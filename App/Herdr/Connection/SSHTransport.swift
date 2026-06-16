import Foundation
import Citadel
import Crypto // `Insecure` namespace (Citadel adds `Insecure.RSA`)
import NIOCore // `ByteBuffer`
import HerdrKit

/// SSH-bridged transport to a remote Herdr Unix socket.
///
/// Herdr exposes no network port: its socket API is a local Unix domain socket
/// (`~/.config/herdr/herdr.sock`). We reach it the same way the official tooling
/// does — over SSH:
///
///  1. Open an SSH connection to `host` (Citadel / SwiftNIO SSH) using
///     `credential` (private key or password).
///  2. Start an exec channel that bridges stdio to the socket with
///     `socat - UNIX-CONNECT:<socketPath>` (falling back to `nc -U <socketPath>`).
///  3. Write request frames to the channel's stdin via `NDJSON.frame`, and feed
///     the channel's stdout through `LineBuffer` → `IncomingMessage.decode` →
///     `continuation.yield(_:)`. The persistent duplex channel makes live event
///     subscriptions work, exactly like a direct socket connection.
///
/// Host-key validation currently accepts any key (TOFU pinning is a follow-up).
public actor SSHTransport: HerdrTransport {
    private let host: Host
    private let credential: Credential

    private let stream: AsyncStream<IncomingMessage>
    private let continuation: AsyncStream<IncomingMessage>.Continuation
    private var lineBuffer = LineBuffer()

    private var client: SSHClient?
    private var channelTask: Task<Void, Never>?
    private var writer: TTYStdinWriter?

    /// Resumed exactly once when the exec channel goes live (success) or when it
    /// fails/closes before ever opening (failure).
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var didSignalConnect = false
    /// Remote stderr captured during connect, surfaced if the bridge dies early
    /// (e.g. neither `socat` nor `nc` is installed, or the socket path is wrong).
    private var capturedStderr = ""

    init(host: Host, credential: Credential) {
        self.host = host
        self.credential = credential
        var continuation: AsyncStream<IncomingMessage>.Continuation!
        self.stream = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
    }

    public nonisolated func messages() -> AsyncStream<IncomingMessage> { stream }

    public func connect() async throws {
        guard client == nil else { return }
        guard !host.hostname.isEmpty, !host.username.isEmpty else {
            throw HerdrError.connectionFailed("This host is missing a hostname or username.")
        }

        let auth = try authenticationMethod()
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: host.hostname,
                port: host.port,
                authenticationMethod: auth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
        } catch {
            throw HerdrError.connectionFailed("Couldn't connect to \(host.displayName): \(error)")
        }
        self.client = client

        // Resolve the socket path: honour an explicit override, otherwise probe
        // the documented locations on the remote host so the user never has to
        // know where Herdr keeps its socket.
        let socketPath: String
        let override = host.socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            socketPath = override
        } else {
            let found = try await discoverSocketPaths(client: client)
            guard let chosen = found.first else {
                throw HerdrError.connectionFailed(
                    "Couldn't find a running Herdr socket on \(host.displayName) (looked under "
                    + "~/.config/herdr). Is Herdr running there?"
                )
            }
            socketPath = chosen
        }

        // Open the bridge exec channel and suspend until it's live (so the first
        // `send` has a writer) or it fails during setup.
        let command = Self.bridgeCommand(socketPath: socketPath)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            self.channelTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await client.withExec(command) { inbound, outbound in
                        await self.channelOpened(writer: outbound)
                        for try await chunk in inbound {
                            if case .stdout(let buffer) = chunk {
                                await self.ingest(buffer)
                            } else if case .stderr(let buffer) = chunk {
                                await self.captureStderr(buffer)
                            }
                        }
                    }
                    await self.channelClosed(error: nil)
                } catch {
                    await self.channelClosed(error: error)
                }
            }
        }
    }

    public func send(_ request: RPCRequest) async throws {
        guard let writer else { throw HerdrError.notConnected }
        let frame = try NDJSON.frame(request)
        try await writer.write(ByteBuffer(bytes: frame))
    }

    public func disconnect() async {
        channelTask?.cancel()
        channelTask = nil
        writer = nil
        if let client {
            try? await client.close()
        }
        client = nil
        continuation.finish()
    }

    // MARK: Channel lifecycle

    private func channelOpened(writer: TTYStdinWriter) {
        self.writer = writer
        signalConnect(.success(()))
    }

    private func channelClosed(error: Error?) {
        // Closed before the bridge ever went live → this *is* the connect failure.
        if !didSignalConnect {
            let stderr = capturedStderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = !stderr.isEmpty ? stderr
                : (error.map { "\($0)" } ?? "the bridge command exited immediately")
            signalConnect(.failure(HerdrError.connectionFailed(
                "Couldn't open the Herdr socket bridge — \(detail). "
                + "Check that `socat` (or `nc`) is installed on the host and that the socket path is correct."
            )))
        }
        writer = nil
        continuation.finish()
    }

    private func signalConnect(_ result: Result<Void, Error>) {
        guard !didSignalConnect else { return }
        didSignalConnect = true
        connectContinuation?.resume(with: result)
        connectContinuation = nil
    }

    // MARK: Byte plumbing

    private func ingest(_ buffer: ByteBuffer) {
        guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else { return }
        for line in lineBuffer.append(Data(bytes)) {
            if let message = try? IncomingMessage.decode(line: line) {
                continuation.yield(message)
            }
        }
    }

    private func captureStderr(_ buffer: ByteBuffer) {
        guard capturedStderr.count < 2_000,
              let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes),
              let text = String(bytes: bytes, encoding: .utf8) else { return }
        capturedStderr += text
    }

    // MARK: Helpers

    private func authenticationMethod() throws -> SSHAuthenticationMethod {
        switch host.authMethod {
        case .password:
            guard let password = credential.password, !password.isEmpty else {
                throw HerdrError.connectionFailed("No password saved for \(host.displayName).")
            }
            return .passwordBased(username: host.username, password: password)

        case .privateKey:
            guard let pem = credential.privateKey, !pem.isEmpty else {
                throw HerdrError.connectionFailed("No private key saved for \(host.displayName).")
            }
            do {
                let key = try Insecure.RSA.PrivateKey(sshRsa: pem)
                return .rsa(username: host.username, privateKey: key)
            } catch {
                throw HerdrError.connectionFailed(
                    "Couldn't read this private key. Key auth currently supports OpenSSH-format "
                    + "RSA keys only — use an RSA key or password auth for now."
                )
            }
        }
    }

    /// Probe the remote host for live Herdr sockets, most-preferred first. Mirrors
    /// Herdr's own resolution order (per the socket-API docs): the
    /// `HERDR_SOCKET_PATH` override, then the default session socket, then any
    /// named session under `~/.config/herdr/sessions/<name>/`. Only paths that are
    /// actually sockets (`test -S`) are returned. Wrapped in `sh -c` so it's POSIX
    /// regardless of the user's login shell.
    private func discoverSocketPaths(client: SSHClient) async throws -> [String] {
        let probe = #"sh -c 'for p in "$HERDR_SOCKET_PATH" "$HOME/.config/herdr/herdr.sock" "$HOME"/.config/herdr/sessions/*/herdr.sock; do [ -S "$p" ] && echo "$p"; done'"#
        let output: ByteBuffer
        do {
            output = try await client.executeCommand(probe)
        } catch {
            throw HerdrError.connectionFailed(
                "Couldn't search for the Herdr socket on \(host.displayName): \(error)"
            )
        }
        let text = output.getString(at: output.readerIndex, length: output.readableBytes) ?? ""
        var seen = Set<String>()
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Shell command run on the remote host to bridge stdio to the Herdr socket.
    /// A leading `~` is rewritten to `$HOME` so the remote shell expands it
    /// (tilde expansion doesn't fire mid-word, but `$HOME` does).
    static func bridgeCommand(socketPath: String) -> String {
        let expanded = socketPath.hasPrefix("~") ? "$HOME" + socketPath.dropFirst() : socketPath
        let quoted = "\"\(expanded)\""
        return "socat - UNIX-CONNECT:\(quoted) || nc -U \(quoted)"
    }
}
