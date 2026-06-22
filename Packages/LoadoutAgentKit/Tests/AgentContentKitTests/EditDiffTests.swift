import XCTest
@testable import AgentContentKit

final class EditDiffTests: XCTestCase {
    func testIdenticalIsAllContext() {
        let lines = EditDiff.lines(old: "a\nb\nc", new: "a\nb\nc")
        XCTAssertEqual(lines.map(\.kind), [.context, .context, .context])
        XCTAssertFalse(lines.contains { $0.kind == .add || $0.kind == .del })
    }

    func testPureAddition() {
        // Adding a line at the end: common prefix "a\nb", new "c" added.
        let lines = EditDiff.lines(old: "a\nb", new: "a\nb\nc")
        XCTAssertEqual(lines.filter { $0.kind == .del }.count, 0)
        let adds = lines.filter { $0.kind == .add }
        XCTAssertEqual(adds.map(\.text), ["c"])
    }

    func testPureDeletion() {
        let lines = EditDiff.lines(old: "a\nb\nc", new: "a\nc")
        XCTAssertEqual(lines.filter { $0.kind == .add }.count, 0)
        let dels = lines.filter { $0.kind == .del }
        XCTAssertEqual(dels.map(\.text), ["b"])
    }

    func testMixedReplacement() {
        let lines = EditDiff.lines(old: "x\nold\nz", new: "x\nnew\nz")
        let dels = lines.filter { $0.kind == .del }.map(\.text)
        let adds = lines.filter { $0.kind == .add }.map(\.text)
        XCTAssertEqual(dels, ["old"])
        XCTAssertEqual(adds, ["new"])
        // Common prefix/suffix preserved as context.
        XCTAssertEqual(lines.first?.kind, .context)
        XCTAssertEqual(lines.last?.kind, .context)
    }

    func testDeletionsPrecedeAdditions() {
        let lines = EditDiff.lines(old: "p\na\nb\nq", new: "p\nc\nq")
        let kinds = lines.map(\.kind)
        guard let firstAdd = kinds.firstIndex(of: .add),
              let lastDel = kinds.lastIndex(of: .del) else {
            return XCTFail("expected both add and del kinds")
        }
        XCTAssertLessThan(lastDel, firstAdd, "all dels should come before adds")
    }
}
