import XCTest
@testable import HerdrKit

/// Decodes the real captured `agent.list` response (`.motif/fixtures/agent-list.json`)
/// inlined here so the test needs no SwiftPM resource. Asserts the typed
/// `agent.list` path surfaces `agent_session` and friends.
final class AgentListTests: XCTestCase {
    /// A real `herdr agent list` reply, verbatim (herdr 0.7.0).
    private let fixture = #"""
    {"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"0af0a380-8159-4af4-99aa-82892611e863"},"agent_status":"idle","cwd":"/Users/zackbart/Dev/bepresent/screentox-webunnel","focused":false,"foreground_cwd":"/Users/zackbart/Dev/bepresent/screentox-webunnel","pane_id":"wR:p1","revision":0,"tab_id":"wR:t1","terminal_id":"term_6549e3d9490431c","workspace_id":"wR"},{"agent":"claude","agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"7671f37d-7258-4d2a-a51c-d5674bdb0afc"},"agent_status":"working","cwd":"/Users/zackbart/Dev/projects/tooling/loadout","focused":true,"foreground_cwd":"/Users/zackbart/Dev/projects/tooling/loadout","pane_id":"wZ:p1","revision":0,"tab_id":"wZ:t1","terminal_id":"term_654c61112abdc24","workspace_id":"wZ"}],"type":"agent_list"}}
    """#

    /// Decode the `result` object the way `HerdrClient` does (`decodedSnake`).
    private func decodeAgents() throws -> [AgentInfo] {
        let message = Data(fixture.utf8)
        guard case .response(let response) = try IncomingMessage.decode(line: message),
              let result = response.result else {
            XCTFail("expected a response with a result")
            return []
        }
        return try result.decodedSnake(AgentListResult.self).agents.map {
            AgentInfo(
                paneID: PaneID($0.paneId),
                agent: $0.agent,
                status: $0.agentStatus.flatMap(AgentStatus.init(rawValue:)) ?? .unknown,
                cwd: $0.cwd,
                foregroundCwd: $0.foregroundCwd,
                agentSession: $0.agentSession,
                tabID: $0.tabId.map { TabID($0) },
                workspaceID: $0.workspaceId.map { WorkspaceID($0) },
                terminalID: $0.terminalId,
                isFocused: $0.focused ?? false
            )
        }
    }

    func testDecodesAtLeastOneAgent() throws {
        let agents = try decodeAgents()
        XCTAssertGreaterThanOrEqual(agents.count, 1)
    }

    func testLoadoutPaneSessionIsAUUIDWithKindID() throws {
        let agents = try decodeAgents()
        guard let loadout = agents.first(where: { $0.cwd == "/Users/zackbart/Dev/projects/tooling/loadout" }) else {
            return XCTFail("expected the loadout pane")
        }
        XCTAssertEqual(loadout.agentSession?.kind, "id")
        let value = try XCTUnwrap(loadout.agentSession?.value)
        XCTAssertNotNil(UUID(uuidString: value), "agent_session.value must be a UUID")
        XCTAssertEqual(value, "7671f37d-7258-4d2a-a51c-d5674bdb0afc")
    }

    func testForegroundCwdAndStatusParsed() throws {
        let agents = try decodeAgents()
        let loadout = try XCTUnwrap(agents.first(where: { $0.paneID == PaneID("wZ:p1") }))
        XCTAssertEqual(loadout.foregroundCwd, "/Users/zackbart/Dev/projects/tooling/loadout")
        XCTAssertEqual(loadout.status, .working)

        let other = try XCTUnwrap(agents.first(where: { $0.paneID == PaneID("wR:p1") }))
        XCTAssertEqual(other.status, .idle)
        XCTAssertEqual(other.foregroundCwd, "/Users/zackbart/Dev/bepresent/screentox-webunnel")
    }

    // MARK: Lenient decode

    /// An unknown extra key in `agent_session` must not break decoding.
    func testAgentSessionTitlesExtraUnknownKeyStillDecodes() throws {
        let json = Data(#"{"agent":"claude","kind":"id","source":"herdr:claude","value":"abc","future_field":42}"#.utf8)
        let session = try JSONDecoder().decode(AgentSession.self, from: json)
        XCTAssertEqual(session.value, "abc")
        XCTAssertEqual(session.kind, "id")
    }

    /// A missing `source` (and `agent`) must still decode — every field optional.
    func testAgentSessionMissingSourceStillDecodes() throws {
        let json = Data(#"{"kind":"id","value":"abc"}"#.utf8)
        let session = try JSONDecoder().decode(AgentSession.self, from: json)
        XCTAssertNil(session.source)
        XCTAssertNil(session.agent)
        XCTAssertEqual(session.value, "abc")
    }
}
