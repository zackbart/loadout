import Foundation

/// A single line in a computed edit diff.
public struct DiffLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case add
        case del
        case context
    }

    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// A single item in a plan (TodoWrite) block.
public struct PlanItem: Sendable, Equatable {
    public var text: String
    public var status: String

    public init(text: String, status: String) {
        self.text = text
        self.status = status
    }
}

/// A structured unit the agent thread UI can switch over to render a
/// transcript like the T3 Code view. Produced by ``TranscriptParser``.
public enum TranscriptBlock: Sendable, Equatable {
    /// A plain text message from a role (`user` / `assistant`).
    case message(role: String, text: String)

    /// A generic tool invocation rendered as a card.
    /// `title` is the most salient argument (e.g. a Bash command),
    /// `detail` is supplementary (e.g. a description or tool result).
    case toolCall(name: String, title: String, detail: String?)

    /// An inline diff computed from an Edit tool call's old/new strings.
    case diff(file: String, lines: [DiffLine])

    /// A plan / todo list (TodoWrite).
    case plan(items: [PlanItem])
}
