import Foundation

/// Computes a simple, deterministic line diff between an Edit tool call's
/// `old_string` and `new_string`. Not a general LCS diff — it strips the
/// common leading and trailing runs of equal lines (emitted as `.context`)
/// and reports the remaining old lines as `.del` and new lines as `.add`.
public enum EditDiff {
    public static func lines(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        // Length of the common prefix of equal lines.
        var prefix = 0
        while prefix < oldLines.count,
              prefix < newLines.count,
              oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }

        // Length of the common suffix of equal lines, not overlapping the prefix.
        var suffix = 0
        while suffix < (oldLines.count - prefix),
              suffix < (newLines.count - prefix),
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }

        var result: [DiffLine] = []

        for i in 0..<prefix {
            result.append(DiffLine(kind: .context, text: oldLines[i]))
        }

        let oldMiddle = oldLines[prefix..<(oldLines.count - suffix)]
        for line in oldMiddle {
            result.append(DiffLine(kind: .del, text: line))
        }

        let newMiddle = newLines[prefix..<(newLines.count - suffix)]
        for line in newMiddle {
            result.append(DiffLine(kind: .add, text: line))
        }

        for i in (oldLines.count - suffix)..<oldLines.count {
            result.append(DiffLine(kind: .context, text: oldLines[i]))
        }

        return result
    }
}
