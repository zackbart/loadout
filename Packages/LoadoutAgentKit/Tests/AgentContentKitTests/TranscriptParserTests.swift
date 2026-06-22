import XCTest
@testable import AgentContentKit

/// JSONL lines modeled on the exact shapes in
/// `.motif/fixtures/transcript-sample.jsonl` and the live transcript.
/// Embedded inline so no Package resource wiring is needed.
private enum Fixture {
    // Unknown record types that MUST be skipped.
    static let lastPrompt = #"{"type":"last-prompt","leafUuid":"437e6683","sessionId":"7671f37d"}"#
    static let mode = #"{"type":"mode","mode":"normal","sessionId":"7671f37d"}"#
    static let permissionMode = #"{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"7671f37d"}"#
    static let aiTitle = #"{"type":"ai-title","aiTitle":"Create Loadout unified design mockups","sessionId":"7671f37d"}"#
    static let system = #"{"type":"system","subtype":"info","sessionId":"7671f37d"}"#

    // Assistant text block.
    static let assistantText = #"{"type":"assistant","message":{"role":"assistant","type":"message","content":[{"type":"text","text":"I read the whole doc. Quick read-back so we're aligned."}]}}"#

    // Assistant thinking block (must be dropped).
    static let assistantThinking = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"let me reason about this"}]}}"#

    // Assistant Bash tool_use.
    static let bash = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_bash1","name":"Bash","input":{"command":"swift build && swift test","description":"Build and test the package"}}]}}"#

    // Assistant Edit tool_use (real shape from live transcript).
    static let edit = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_edit1","name":"Edit","input":{"replace_all":false,"file_path":"/tmp/a.css","old_string":"line one\nold middle\nline three","new_string":"line one\nnew middle\nline three"}}]}}"#

    // User message with a STRING content (not array).
    static let userString = #"{"type":"user","message":{"role":"user","content":"can you look at this doc for me"}}"#

    // User tool_result with ARRAY content [{type:text,text:...}].
    static let toolResultArray = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_bash1","type":"tool_result","content":[{"type":"text","text":"Build succeeded"}]}]}}"#

    // User tool_result with plain STRING content.
    static let toolResultString = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_x","type":"tool_result","content":"plain string result"}]}}"#

    // Skill tool_use (generic card).
    static let skill = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_s1","name":"Skill","input":{"skill":"scratch-html"}}]}}"#

    // TodoWrite tool_use (modeled from documented shape; not in fixture).
    static let todoWrite = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_t1","name":"TodoWrite","input":{"todos":[{"content":"Write parser","activeForm":"Writing parser","status":"completed"},{"content":"Run tests","activeForm":"Running tests","status":"in_progress"}]}}]}}"#

    // Array-form result matching the Skill call (which has no detail → folds in).
    static let skillResult = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_s1","type":"tool_result","content":[{"type":"text","text":"skill output"}]}]}}"#

    // ONE assistant message with TWO tool_use blocks (both generic → nil detail),
    // followed by their results out of order — exercises id-matching across the
    // message boundary (the bug: results folding into `blocks.last`).
    static let twoReads = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a","name":"Read","input":{"file_path":"/a"}},{"type":"tool_use","id":"toolu_b","name":"Read","input":{"file_path":"/b"}}]}}"#
    static let resultA = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_a","type":"tool_result","content":"AAA"}]}}"#
    static let resultB = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_b","type":"tool_result","content":[{"type":"text","text":"BBB"}]}]}}"#
}

final class TranscriptParserTests: XCTestCase {
    func testYieldsAtLeastOneMessage() {
        let blocks = TranscriptParser.parse(lines: [Fixture.assistantText])
        let messages = blocks.compactMap { block -> String? in
            if case let .message(_, text) = block { return text }
            return nil
        }
        XCTAssertGreaterThanOrEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("read the whole doc"))
    }

    func testBashToolCallTitleIsCommand() {
        let blocks = TranscriptParser.parse(lines: [Fixture.bash])
        guard case let .toolCall(name, title, detail)? = blocks.first else {
            return XCTFail("expected a toolCall block, got \(blocks)")
        }
        XCTAssertEqual(name, "Bash")
        XCTAssertEqual(title, "swift build && swift test")
        XCTAssertEqual(detail, "Build and test the package")
    }

    func testEditProducesDiffWithAddAndDel() {
        let blocks = TranscriptParser.parse(lines: [Fixture.edit])
        guard case let .diff(file, lines)? = blocks.first else {
            return XCTFail("expected a diff block, got \(blocks)")
        }
        XCTAssertEqual(file, "/tmp/a.css")
        XCTAssertTrue(lines.contains { $0.kind == .add })
        XCTAssertTrue(lines.contains { $0.kind == .del })
        XCTAssertTrue(lines.contains { $0.kind == .context })
    }

    func testUnknownRecordTypesAreSkipped() {
        let blocks = TranscriptParser.parse(lines: [
            Fixture.lastPrompt,
            Fixture.mode,
            Fixture.permissionMode,
            Fixture.aiTitle,
            Fixture.system,
        ])
        XCTAssertTrue(blocks.isEmpty, "unknown record types must not emit blocks")
    }

    func testThinkingBlocksAreDropped() {
        let blocks = TranscriptParser.parse(lines: [Fixture.assistantThinking])
        XCTAssertTrue(blocks.isEmpty)
    }

    func testUserStringContentBecomesMessage() {
        let blocks = TranscriptParser.parse(lines: [Fixture.userString])
        guard case let .message(role, text)? = blocks.first else {
            return XCTFail("expected a message block, got \(blocks)")
        }
        XCTAssertEqual(role, "user")
        XCTAssertTrue(text.contains("look at this doc"))
    }

    func testArrayResultDoesNotOverwriteFilledDetail() {
        // Bash already carries a detail (its description), so the matching
        // array-form result does NOT overwrite it — and must not crash on the
        // array content. One block, detail unchanged.
        let blocks = TranscriptParser.parse(lines: [Fixture.bash, Fixture.toolResultArray])
        XCTAssertEqual(blocks.count, 1)
        guard case let .toolCall(_, _, detail)? = blocks.first else {
            return XCTFail("expected a toolCall block, got \(blocks)")
        }
        XCTAssertEqual(detail, "Build and test the package")
    }

    func testArrayResultFoldsIntoMatchingEmptyCall() {
        // The Skill call has no detail, so its matching array result folds in.
        let blocks = TranscriptParser.parse(lines: [Fixture.skill, Fixture.skillResult])
        XCTAssertEqual(blocks.count, 1)
        guard case let .toolCall(name, _, detail)? = blocks.first else {
            return XCTFail("expected a toolCall block, got \(blocks)")
        }
        XCTAssertEqual(name, "Skill")
        XCTAssertEqual(detail, "skill output")
    }

    func testUnmatchedToolResultIsDropped() {
        // A result whose tool_use_id matches no call is dropped, not leaked as a
        // message (regression: results used to fall through to `appendMessage`).
        let blocks = TranscriptParser.parse(lines: [Fixture.toolResultString])
        XCTAssertTrue(blocks.isEmpty)
    }

    func testToolResultsMatchByID() {
        // Two tool calls in one message; results attach to the RIGHT call by id,
        // not to whatever is `blocks.last`.
        let blocks = TranscriptParser.parse(lines: [Fixture.twoReads, Fixture.resultA, Fixture.resultB])
        XCTAssertEqual(blocks.count, 2)
        guard case let .toolCall(_, titleA, detailA)? = blocks.first,
              case let .toolCall(_, titleB, detailB) = blocks[1] else {
            return XCTFail("expected two toolCall blocks, got \(blocks)")
        }
        XCTAssertEqual(titleA, "/a")
        XCTAssertEqual(detailA, "AAA")
        XCTAssertEqual(titleB, "/b")
        XCTAssertEqual(detailB, "BBB")
    }

    func testMismatchedIDDoesNotFold() {
        // The result's tool_use_id (toolu_bash1) doesn't match the Skill call
        // (toolu_s1), so it must NOT fold into it — Skill keeps a nil detail.
        let blocks = TranscriptParser.parse(lines: [Fixture.skill, Fixture.toolResultArray])
        XCTAssertEqual(blocks.count, 1)
        guard case let .toolCall(name, title, detail)? = blocks.first else {
            return XCTFail("expected one toolCall, got \(blocks)")
        }
        XCTAssertEqual(name, "Skill")
        XCTAssertEqual(title, "scratch-html")
        XCTAssertNil(detail)
    }

    func testTodoWriteBecomesPlan() {
        let blocks = TranscriptParser.parse(lines: [Fixture.todoWrite])
        guard case let .plan(items)? = blocks.first else {
            return XCTFail("expected a plan block, got \(blocks)")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].text, "Write parser")
        XCTAssertEqual(items[0].status, "completed")
        XCTAssertEqual(items[1].status, "in_progress")
    }

    func testUnparseableLinesAreSkipped() {
        let blocks = TranscriptParser.parse(lines: ["not json at all", "", Fixture.assistantText])
        XCTAssertEqual(blocks.count, 1)
    }

    func testParseJSONLConvenienceSplitsOnNewlines() {
        let jsonl = [Fixture.assistantText, Fixture.bash].joined(separator: "\n")
        let blocks = TranscriptParser.parse(jsonl: jsonl)
        XCTAssertEqual(blocks.count, 2)
    }
}
