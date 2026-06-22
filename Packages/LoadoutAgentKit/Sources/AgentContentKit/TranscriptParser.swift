import Foundation

/// Parses a Claude `.jsonl` transcript into structured ``TranscriptBlock``s
/// for the agent thread UI.
///
/// Robustness rules (verified against real transcripts):
/// - Each line is decoded independently; un-parseable lines are skipped.
/// - Only top-level records with `type` of `user` or `assistant` are
///   considered. Every other record type (`ai-title`, `permission-mode`,
///   `mode`, `system`, `last-prompt`, …) is skipped silently.
/// - `message.content` may be a plain `String` (user messages) or an array of
///   typed blocks.
/// - `tool_result.content` may be a plain `String` or an array of
///   `{type:"text", text:…}` objects.
/// - `thinking` blocks are dropped this cycle.
public enum TranscriptParser {
    public static func parse(jsonl: String) -> [TranscriptBlock] {
        let lines = jsonl
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return parse(lines: lines)
    }

    public static func parse(lines: [String]) -> [TranscriptBlock] {
        var blocks: [TranscriptBlock] = []
        // Maps a `tool_use` id → the index of the `.toolCall` block it produced,
        // so a later `tool_result` (which arrives in a *following* user message,
        // referenced by `tool_use_id`) attaches to the right call — not whatever
        // happens to be `blocks.last`.
        var toolIndexByID: [String: Int] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let record = object as? [String: Any] else { continue }

            guard let type = record["type"] as? String,
                  type == "user" || type == "assistant" else { continue }
            guard let message = record["message"] as? [String: Any] else { continue }

            let role = (message["role"] as? String) ?? type

            // Content is either a string or an array of typed blocks.
            if let text = message["content"] as? String {
                appendMessage(role: role, text: text, into: &blocks)
                continue
            }
            guard let contentBlocks = message["content"] as? [[String: Any]] else { continue }

            for block in contentBlocks {
                handle(block: block, role: role, into: &blocks, toolIndexByID: &toolIndexByID)
            }
        }
        return blocks
    }

    // MARK: - Block handling

    private static func handle(
        block: [String: Any],
        role: String,
        into blocks: inout [TranscriptBlock],
        toolIndexByID: inout [String: Int]
    ) {
        guard let blockType = block["type"] as? String else { return }

        switch blockType {
        case "text":
            if let text = block["text"] as? String {
                appendMessage(role: role, text: text, into: &blocks)
            }

        case "thinking":
            // Dropped this cycle.
            return

        case "tool_use":
            handleToolUse(block, into: &blocks, toolIndexByID: &toolIndexByID)

        case "tool_result":
            handleToolResult(block, into: &blocks, toolIndexByID: toolIndexByID)

        default:
            return
        }
    }

    private static func handleToolUse(
        _ block: [String: Any],
        into blocks: inout [TranscriptBlock],
        toolIndexByID: inout [String: Int]
    ) {
        let name = (block["name"] as? String) ?? "tool"
        let input = block["input"] as? [String: Any] ?? [:]

        switch name {
        case "Edit":
            let file = (input["file_path"] as? String) ?? ""
            let old = (input["old_string"] as? String) ?? ""
            let new = (input["new_string"] as? String) ?? ""
            let lines = EditDiff.lines(old: old, new: new)
            blocks.append(.diff(file: file, lines: lines))

        case "Bash":
            let command = (input["command"] as? String) ?? ""
            let description = input["description"] as? String
            blocks.append(.toolCall(name: "Bash", title: command, detail: description))

        case "Write":
            let file = (input["file_path"] as? String) ?? ""
            let content = input["content"] as? String
            blocks.append(.toolCall(name: "Write", title: file, detail: content))

        case "TodoWrite":
            let items = planItems(from: input)
            blocks.append(.plan(items: items))

        default:
            // Skill / Agent / AskUserQuestion / anything else: generic card.
            let title = brief(for: name, input: input)
            blocks.append(.toolCall(name: name, title: title, detail: nil))
        }

        // Register `.toolCall` blocks (which have a detail slot) so a later
        // `tool_result` can attach by id. `.diff`/`.plan` have no slot.
        if let id = block["id"] as? String, case .toolCall = blocks[blocks.count - 1] {
            toolIndexByID[id] = blocks.count - 1
        }
    }

    private static func handleToolResult(
        _ block: [String: Any],
        into blocks: inout [TranscriptBlock],
        toolIndexByID: [String: Int]
    ) {
        let text = flatten(content: block["content"])
        guard !text.isEmpty else { return }

        // Attach the result to the matching tool call (by `tool_use_id`) when it
        // has no detail yet. Unmatched results (e.g. an Edit's, whose `.diff`
        // block has no detail slot) are dropped rather than leaked as messages.
        guard let id = block["tool_use_id"] as? String,
              let index = toolIndexByID[id],
              case let .toolCall(name, title, detail) = blocks[index],
              detail == nil else { return }
        blocks[index] = .toolCall(name: name, title: title, detail: text)
    }

    // MARK: - Helpers

    /// Append a `.message`, skipping empty/whitespace-only text.
    private static func appendMessage(
        role: String,
        text: String,
        into blocks: inout [TranscriptBlock]
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blocks.append(.message(role: role, text: text))
    }

    /// Flatten a polymorphic `tool_result.content` (String OR
    /// `[{type:"text", text:…}]`) into a single string.
    private static func flatten(content: Any?) -> String {
        if let string = content as? String {
            return string
        }
        if let array = content as? [[String: Any]] {
            let texts = array.compactMap { $0["text"] as? String }
            return texts.joined(separator: "\n")
        }
        return ""
    }

    /// Build a short title for a generic tool from its most salient argument.
    private static func brief(for name: String, input: [String: Any]) -> String {
        if name == "Skill", let skill = input["skill"] as? String {
            return skill
        }
        // Prefer a few common single-string fields, else fall back to the name.
        for key in ["description", "prompt", "question", "command", "file_path", "skill"] {
            if let value = input[key] as? String, !value.isEmpty {
                return value
            }
        }
        return name
    }

    /// Leniently extract plan items from a TodoWrite `input`.
    private static func planItems(from input: [String: Any]) -> [PlanItem] {
        guard let todos = input["todos"] as? [[String: Any]] else { return [] }
        return todos.map { todo in
            let text = (todo["content"] as? String)
                ?? (todo["activeForm"] as? String)
                ?? ""
            let status = (todo["status"] as? String) ?? ""
            return PlanItem(text: text, status: status)
        }
    }
}
