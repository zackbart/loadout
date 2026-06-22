import Foundation

/// A single agent reported by `agent.list`, correlated to the pane it runs in.
///
/// This is the typed domain model the app uses to map a pane to its Claude
/// transcript: `agentSession?.value` is the session UUID and `agentSession?.kind`
/// is `"id"`. `cwd` / `foregroundCwd` locate the project on disk.
public struct AgentInfo: Sendable, Equatable {
    /// The pane this agent runs in.
    public let paneID: PaneID
    /// The agent name (e.g. `"claude"`), if reported.
    public let agent: String?
    /// The agent's current status; `.unknown` when absent/unrecognized.
    public let status: AgentStatus
    /// The pane's working directory at launch.
    public let cwd: String?
    /// The foreground process's working directory (may differ in a worktree).
    public let foregroundCwd: String?
    /// The session pointer used to resolve the transcript.
    public let agentSession: AgentSession?
    /// The tab the pane belongs to, if reported.
    public let tabID: TabID?
    /// The workspace the pane belongs to, if reported.
    public let workspaceID: WorkspaceID?
    /// The backing terminal id, if reported.
    public let terminalID: String?
    /// Whether the pane is focused.
    public let isFocused: Bool

    public init(
        paneID: PaneID,
        agent: String? = nil,
        status: AgentStatus = .unknown,
        cwd: String? = nil,
        foregroundCwd: String? = nil,
        agentSession: AgentSession? = nil,
        tabID: TabID? = nil,
        workspaceID: WorkspaceID? = nil,
        terminalID: String? = nil,
        isFocused: Bool = false
    ) {
        self.paneID = paneID
        self.agent = agent
        self.status = status
        self.cwd = cwd
        self.foregroundCwd = foregroundCwd
        self.agentSession = agentSession
        self.tabID = tabID
        self.workspaceID = workspaceID
        self.terminalID = terminalID
        self.isFocused = isFocused
    }
}
