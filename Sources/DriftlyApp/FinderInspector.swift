import Foundation

enum FinderInspector {
    static func currentPath() -> String? {
        let script = """
        tell application "Finder"
            try
                if (count of selection) > 0 then
                    return POSIX path of (item 1 of (get selection) as alias)
                end if
            end try
            try
                if (count of Finder windows) > 0 then
                    return POSIX path of (target of front window as alias)
                end if
            end try
            return ""
        end tell
        """

        return AppleScriptRunner.run(script, timeout: 0.8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
