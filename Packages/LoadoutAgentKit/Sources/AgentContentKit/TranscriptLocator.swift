import Foundation

/// Resolves the on-disk path of a Claude transcript (`.jsonl`) from a
/// session UUID and the cwd the pane was launched in.
///
/// Claude stores transcripts at
/// `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl`, where the encoded cwd is
/// the absolute path with both `/` and `.` replaced by `-`.
public enum TranscriptLocator {
    /// The directory-name encoding Claude uses for a cwd: replace `/` and `.`
    /// with `-`. Exposed for testing.
    public static func encode(cwd: String) -> String {
        var encoded = cwd.replacingOccurrences(of: "/", with: "-")
        encoded = encoded.replacingOccurrences(of: ".", with: "-")
        return encoded
    }

    /// Resolve the transcript path. Tries the derived
    /// `~/.claude/projects/<enc>/<uuid>.jsonl` first; if that file does not
    /// exist, globs `~/.claude/projects/*/<uuid>.jsonl` (the UUID is globally
    /// unique) and returns the first existing match. Returns `nil` if nothing
    /// is found.
    public static func path(
        sessionUUID: String,
        cwd: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let fm = FileManager.default
        let projects = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)

        let fileName = "\(sessionUUID).jsonl"

        // 1. Derived candidate from the encoded cwd.
        let derived = projects
            .appendingPathComponent(encode(cwd: cwd), isDirectory: true)
            .appendingPathComponent(fileName)
        if fm.fileExists(atPath: derived.path) {
            return derived
        }

        // 2. Glob fallback: scan every project dir for <uuid>.jsonl.
        guard let entries = try? fm.contentsOfDirectory(
            at: projects,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for dir in entries {
            let candidate = dir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}
