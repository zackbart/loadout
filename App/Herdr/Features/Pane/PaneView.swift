import Foundation
import SwiftUI
import HerdrKit

/// Screen 3: read a pane's output and send input, rendered as a real terminal —
/// a dark scrollback surface and a prompt-style input bar. Scrollback comes from
/// `pane read` plus live `output` events; the input bar sends text + Enter (or
/// individual keys).
struct PaneView: View {
    @Environment(SessionModel.self) private var session
    let paneID: PaneID

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    private var pane: Pane? { session.pane(paneID) }
    private var lines: [String] { session.outputs[paneID] ?? [] }

    private let quickKeys = ["Enter", "Esc", "Ctrl-C", "Tab", "Up", "Down"]

    var body: some View {
        VStack(spacing: 0) {
            scrollback
            Rectangle()
                .fill(Theme.terminalDim.opacity(0.18))
                .frame(height: 1)
            inputBar
        }
        .background(Theme.terminalBG, ignoresSafeAreaEdges: .bottom)
        .navigationTitle(pane?.title ?? paneID.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let pane, pane.isAgent {
                    StatusTag(status: pane.status)
                }
            }
        }
        .task(id: paneID) { await session.loadOutput(for: paneID) }
    }

    private var scrollback: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty {
                        Text("— no output yet —")
                            .font(Theme.monospaced)
                            .foregroundStyle(Theme.terminalDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.strippingANSI())
                            .font(Theme.monospaced)
                            .foregroundStyle(Theme.terminalText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(14)
            }
            .background(Theme.terminalBG)
            .onChange(of: lines.count) {
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            // Quick keys for common control sequences.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickKeys, id: \.self) { key in
                        Button(key) { Task { await session.sendKeys(key, to: paneID) } }
                            .font(Theme.mono(12, .medium))
                            .foregroundStyle(Theme.terminalText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Theme.terminalSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.terminalDim.opacity(0.25)))
                    }
                }
                .padding(.horizontal, 1)
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Text(">")
                        .font(Theme.mono(15, .bold))
                        .foregroundStyle(Theme.prompt)
                    TextField("", text: $input,
                              prompt: Text("send input…").foregroundColor(Theme.terminalDim),
                              axis: .vertical)
                        .font(Theme.monospaced)
                        .foregroundStyle(Theme.terminalText)
                        .focused($inputFocused)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .tint(Theme.prompt)
                        .onSubmit(send)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.terminalSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.terminalBG)
                        .frame(width: 38, height: 38)
                        .background(canSend ? Theme.prompt : Theme.terminalDim, in: Circle())
                }
                .disabled(!canSend)
            }
        }
        .padding(14)
        .background(Theme.terminalBG)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private let bottomAnchor = "herdr.pane.bottom"

    private func send() {
        let text = input
        input = ""
        Task { await session.submit(text, to: paneID) }
    }
}

extension String {
    /// Remove ANSI/VT escape sequences so terminal output renders as plain text.
    func strippingANSI() -> String {
        guard contains("\u{1B}") else { return self }
        let pattern = "\u{1B}\\[[0-9;?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }
}
