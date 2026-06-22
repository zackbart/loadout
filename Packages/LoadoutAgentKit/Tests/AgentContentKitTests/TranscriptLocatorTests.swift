import XCTest
@testable import AgentContentKit

final class TranscriptLocatorTests: XCTestCase {
    func testEncodeReplacesSlashAndDot() {
        let encoded = TranscriptLocator.encode(cwd: "/Users/zackbart/Dev/projects/tooling/loadout")
        XCTAssertEqual(encoded, "-Users-zackbart-Dev-projects-tooling-loadout")
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("."))
    }

    func testEncodeHandlesDotsInPath() {
        let encoded = TranscriptLocator.encode(cwd: "/Users/me/.claude/worktrees/feat.x")
        XCTAssertEqual(encoded, "-Users-me--claude-worktrees-feat-x")
    }

    func testDerivedPathResolvesWhenFileExists() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cwd = "/Users/me/Dev/proj"
        let uuid = "11111111-2222-3333-4444-555555555555"
        let dir = home
            .appendingPathComponent(".claude/projects", isDirectory: true)
            .appendingPathComponent(TranscriptLocator.encode(cwd: cwd), isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(uuid).jsonl")
        try Data("{}".utf8).write(to: file)
        defer { try? fm.removeItem(at: home) }

        let resolved = TranscriptLocator.path(sessionUUID: uuid, cwd: cwd, home: home)
        XCTAssertEqual(resolved?.standardizedFileURL, file.standardizedFileURL)
    }

    func testGlobFallbackFindsByUUID() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        // File lives under a DIFFERENT encoded dir than the cwd would derive.
        let dir = home
            .appendingPathComponent(".claude/projects", isDirectory: true)
            .appendingPathComponent("-some-other-encoded-dir", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(uuid).jsonl")
        try Data("{}".utf8).write(to: file)
        defer { try? fm.removeItem(at: home) }

        let resolved = TranscriptLocator.path(sessionUUID: uuid, cwd: "/Users/me/elsewhere", home: home)
        XCTAssertEqual(resolved?.standardizedFileURL, file.standardizedFileURL)
    }

    func testReturnsNilWhenNotFound() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolved = TranscriptLocator.path(
            sessionUUID: "00000000-0000-0000-0000-000000000000",
            cwd: "/nope",
            home: home
        )
        XCTAssertNil(resolved)
    }
}
