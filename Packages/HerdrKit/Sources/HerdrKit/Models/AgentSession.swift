import Foundation

/// The agent's session pointer, as reported in `agent.list` (`agent_session`).
///
/// For Claude, this is `{agent:"claude", kind:"id", source:"herdr:claude",
/// value:"<uuid>"}` — `value` is the transcript session UUID and `kind == "id"`.
/// Every field is optional and unknown keys are tolerated (Codable ignores keys
/// it doesn't model), so a partial or future-extended `agent_session` still
/// decodes — this is enrichment, not correctness.
public struct AgentSession: Codable, Sendable, Equatable {
    /// The agent name the session belongs to (e.g. `"claude"`).
    public let agent: String?
    /// How `value` should be interpreted (e.g. `"id"`).
    public let kind: String?
    /// Provenance of the session (e.g. `"herdr:claude"`).
    public let source: String?
    /// The session payload — for `kind == "id"`, the transcript UUID.
    public let value: String?

    public init(agent: String? = nil, kind: String? = nil, source: String? = nil, value: String? = nil) {
        self.agent = agent
        self.kind = kind
        self.source = source
        self.value = value
    }
}
