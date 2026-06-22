import SwiftUI
import HerdrKit
import AgentContentKit

/// Renders a selected pane's transcript as structured blocks, styled to the v2 mockup:
/// an identity header (agent dot + hash + status pill + chips), structured block cards,
/// and a visual-only input-bar stub. Presentation only — no behavior/data changes.
struct AgentThreadView: View {
    @ObservedObject var model: AgentsSessionModel

    private var selectedPane: AgentInfo? {
        guard let id = model.selectedPaneID else { return nil }
        return model.panes.first { $0.paneID == id }
    }

    var body: some View {
        if let pane = selectedPane {
            VStack(spacing: 0) {
                header(pane)
                Divider()
                thread(pane)
                Divider()
                inputBar(pane)
            }
        } else {
            ContentUnavailableView(
                "Select an agent",
                systemImage: "bubble.left.and.bubble.right",
                description: Text(model.status ?? "\(model.panes.count) live panes")
            )
        }
    }

    // MARK: - Header (identity)

    @ViewBuilder
    private func header(_ pane: AgentInfo) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AgentStyle.identityColor(pane.agent))
                    .frame(width: 13, height: 13)
                Text(pane.agent ?? "agent")
                    .font(.largeTitle).fontWeight(.bold)
                Text("#\(pane.paneID.rawValue)")
                    .font(.largeTitle).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            FlowRow(spacing: 8) {
                statusPill(pane.status)
                if let cwd = pane.cwd ?? pane.foregroundCwd {
                    chip(key: "cwd", value: AgentStyle.shortCwd(cwd))
                }
                if let uuid = pane.agentSession?.value, !uuid.isEmpty {
                    chip(key: "session", value: String(uuid.prefix(8)))
                    chip(key: "transcript", value: "wired ✓")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Status pill: amber for blocked, green for working, gray otherwise (mockup `.pill`).
    private func statusPill(_ status: AgentStatus) -> some View {
        let color = AgentStyle.statusColor(status)
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(AgentStyle.statusLabel(status).capitalized)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }

    /// Mono key/value chip (mockup `.chip`).
    private func chip(key: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(key).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.secondary)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
    }

    // MARK: - Thread (blocks)

    @ViewBuilder
    private func thread(_ pane: AgentInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let status = model.status, model.blocks.isEmpty {
                    ContentUnavailableView(
                        "Nothing to show",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(status)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(Array(model.blocks.enumerated()), id: \.offset) { _, block in
                        BlockView(block: block, agentName: pane.agent)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Input bar (visual stub)

    @ViewBuilder
    private func inputBar(_ pane: AgentInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text("›")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(AgentStyle.identityColor(pane.agent))
                Text("Message \(pane.agent ?? "agent") #\(pane.paneID.rawValue)…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("⏎ send")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary))
            HStack(spacing: 15) {
                keyHint("⌘1–9", "panes")
                keyHint("⌘↑↓", "workspaces")
                keyHint("↵", "accept")
                keyHint("esc", "deny")
                keyHint("⌘K", "command bar")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.bar)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}

/// One transcript block rendered to the mockup's structured language.
private struct BlockView: View {
    let block: TranscriptBlock
    let agentName: String?

    var body: some View {
        switch block {
        case let .message(role, text):
            messageView(role: role, text: text)
        case let .toolCall(name, title, detail):
            toolCard(name: name, title: title, detail: detail)
        case let .diff(file, lines):
            diffCard(file: file, lines: lines)
        case let .plan(items):
            planCard(items: items)
        }
    }

    // MARK: message

    @ViewBuilder
    private func messageView(role: String, text: String) -> some View {
        let user = role.lowercased() == "user"
        let identity = user ? Color(hex: 0x9AA0A6) : AgentStyle.identityColor(agentName)
        let who = user ? "You" : (agentName.map { $0.capitalized } ?? "Agent")
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 5).fill(identity).frame(width: 15, height: 15)
                Text(who.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(user ? AnyShapeStyle(.tertiary) : AnyShapeStyle(identity))
            }
            markdown(text)
                .font(.system(size: 14))
                .foregroundStyle(user ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Render markdown inline, falling back to plain text if it doesn't parse.
    private func markdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    // MARK: tool card

    @ViewBuilder
    private func toolCard(name: String, title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                typeTag(name)
                Text(title)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Color.secondary.opacity(0.03))
            if let detail, !detail.isEmpty {
                Divider()
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11).padding(.vertical, 9)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    private func typeTag(_ name: String) -> some View {
        Text(name.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(AgentStyle.toolTagColor(name), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.white)
    }

    // MARK: diff card

    @ViewBuilder
    private func diffCard(file: String, lines: [DiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                typeTag("Edit")
                Text(file)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1).truncationMode(.head)
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Color.secondary.opacity(0.03))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    diffRow(line)
                }
            }
            .padding(.vertical, 5)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    private func diffRow(_ line: DiffLine) -> some View {
        let (bg, fg, gutter): (Color, Color, String)
        switch line.kind {
        case .add: (bg, fg, gutter) = (Color(hex: 0x2BA160).opacity(0.10), Color(hex: 0x1A7A47), "+")
        case .del: (bg, fg, gutter) = (Color(hex: 0xE5484D).opacity(0.08), Color(hex: 0xC0363A), "-")
        case .context: (bg, fg, gutter) = (.clear, .secondary, " ")
        }
        return HStack(spacing: 0) {
            Text(gutter)
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(fg.opacity(0.6))
            Text(line.text)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 9)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 1)
        .background(bg)
        .textSelection(.enabled)
    }

    // MARK: plan card

    @ViewBuilder
    private func planCard(items: [PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PLAN")
                .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.03))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    planRow(item)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    private func planRow(_ item: PlanItem) -> some View {
        let status = item.status.lowercased()
        let done = status == "completed" || status == "done"
        let active = status == "in_progress" || status == "active"
        let green = Color(hex: 0x2BA160)
        return HStack(spacing: 9) {
            Group {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(green, in: RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(active ? AgentStyle.identityColor(agentName) : Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                }
            }
            Text(item.text)
                .font(.system(size: 13))
                .foregroundStyle(done ? .tertiary : (active ? .primary : .secondary))
                .strikethrough(done, color: Color.secondary.opacity(0.5))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}