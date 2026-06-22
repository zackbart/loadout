import Foundation
import HerdrKit

#if canImport(Glibc)
import Glibc
#endif

/// A `HerdrTransport` that talks directly to the **local** Herdr Unix domain
/// socket (no SSH). This is the macOS app's default transport.
///
/// Herdr's wire protocol is one-request-per-connection: you open a fresh
/// `AF_UNIX` `SOCK_STREAM` socket, write one NDJSON-framed request, then read
/// until the server sends its reply and **closes** the connection (there is no
/// length prefix). Only `events.subscribe` keeps a connection open to stream
/// pushed messages.
///
/// All socket syscalls are blocking, so every call is hopped off the
/// cooperative pool onto a `Task.detached` and surfaced through a continuation —
/// the async executor is never blocked. The type is a stateless `final class`
/// (only the immutable socket path is stored), so it is trivially `Sendable`
/// and safe to call concurrently from `HerdrClient` (an actor).
public final class LocalSocketTransport: HerdrTransport {
    private let path: String

    /// Resolve the socket path: explicit argument → `HERDR_SOCKET_PATH` env →
    /// `~/.config/herdr/herdr.sock`.
    public init(path: String? = nil) {
        if let path {
            self.path = path
        } else if let env = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"],
                  !env.isEmpty {
            self.path = env
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.path = home + "/.config/herdr/herdr.sock"
        }
    }

    // MARK: HerdrTransport

    /// No persistent connection to establish — each `request` opens its own
    /// socket. We do a cheap reachability probe so callers get an early, clear
    /// error if the socket is missing.
    public func connect() async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw HerdrError.connectionFailed("Herdr socket not found at \(path)")
        }
    }

    public func disconnect() async {}

    /// One-shot round-trip: open a fresh connection, write the framed request,
    /// read every byte until EOF (the server closes after replying), reassemble
    /// lines, and decode the single reply.
    public func request(_ request: RPCRequest) async throws -> RPCResponse {
        let frame = try NDJSON.frame(request)
        let path = self.path
        let bytes: Data = try await runBlocking {
            let fd = try Self.openConnection(to: path)
            defer { close(fd) }
            try Self.writeAll(fd, frame)
            return try Self.readToEOF(fd)
        }

        var lineBuffer = LineBuffer()
        let lines = lineBuffer.append(bytes)
        guard let first = lines.first else {
            throw HerdrError.connectionFailed("Herdr closed the connection without a reply")
        }
        let message = try IncomingMessage.decode(line: first)
        switch message {
        case .response(let response):
            return response
        case .event:
            // A reply line that decoded as an event is malformed for a request.
            throw HerdrError.connectionFailed("Expected a reply, got an event")
        }
    }

    /// Persistent subscription: open a connection, write the subscribe request,
    /// then stream every NDJSON line as an `IncomingMessage` until the socket
    /// hits EOF, errors, or the stream is cancelled.
    public func events(_ subscribeRequest: RPCRequest) -> AsyncStream<IncomingMessage> {
        let path = self.path
        return AsyncStream { continuation in
            // A detached task owns the blocking socket loop. Cancelling the
            // stream cancels the task, which closes the fd and unblocks read().
            let task = Task.detached {
                let fd: Int32
                do {
                    let frame = try NDJSON.frame(subscribeRequest)
                    fd = try Self.openConnection(to: path)
                    try Self.writeAll(fd, frame)
                } catch {
                    continuation.finish()
                    return
                }
                defer { close(fd) }

                var lineBuffer = LineBuffer()
                var chunk = [UInt8](repeating: 0, count: 64 * 1024)
                while !Task.isCancelled {
                    let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                    if n > 0 {
                        let data = Data(chunk[0..<n])
                        for line in lineBuffer.append(data) {
                            if let message = try? IncomingMessage.decode(line: line) {
                                continuation.yield(message)
                            }
                        }
                    } else if n == 0 {
                        break // EOF: server closed the subscription.
                    } else {
                        if errno == EINTR { continue }
                        break // read error.
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Blocking-I/O hop

    /// Run a blocking socket operation on a detached task so the cooperative
    /// executor is never blocked, bridging its result/throw back via a
    /// continuation.
    private func runBlocking<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: POSIX socket primitives

    /// Open and connect an `AF_UNIX` `SOCK_STREAM` socket to `path`.
    private static func openConnection(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HerdrError.connectionFailed("socket() failed: \(errnoString())")
        }

        // Build the sockaddr_un. `sun_path` is a fixed-size C char array; we must
        // copy the NUL-terminated path bytes into it and bail if the path is too
        // long to fit (108 bytes on macOS/Linux, including the trailing NUL).
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString // includes trailing NUL
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= capacity else {
            close(fd)
            throw HerdrError.connectionFailed("Socket path too long: \(path)")
        }
        // Copy bytes into the tuple via a raw pointer over sun_path's storage.
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            sunPath.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, byte) in pathBytes.enumerated() { dst[i] = byte }
            }
        }

        // connect() wants a `sockaddr *`; rebind our `sockaddr_un` to that type.
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(fd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let message = errnoString()
            close(fd)
            throw HerdrError.connectionFailed("connect(\(path)) failed: \(message)")
        }
        return fd
    }

    /// Write every byte of `data`, looping over partial writes and retrying on
    /// `EINTR`.
    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n > 0 {
                    offset += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    throw HerdrError.connectionFailed("write() failed: \(errnoString())")
                }
            }
        }
    }

    /// Read until EOF (the server closes after sending its reply). Retries on
    /// `EINTR`; a genuine read error throws rather than returning a partial
    /// (and likely malformed-JSON) buffer.
    private static func readToEOF(_ fd: Int32) throws -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                data.append(contentsOf: chunk[0..<n])
            } else if n == 0 {
                break // EOF.
            } else if errno == EINTR {
                continue
            } else {
                throw HerdrError.connectionFailed("read() failed: \(errnoString())")
            }
        }
        return data
    }

    private static func errnoString() -> String {
        String(cString: strerror(errno))
    }
}
