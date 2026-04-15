import Foundation

public enum DriftlyPaths {
    public static let directoryName = "Driftly"
    private static let databaseFileName = "driftly.sqlite"

    public static var appSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static var databaseURL: URL {
        appSupportDirectory.appendingPathComponent(databaseFileName)
    }

    public static var shellInboxURL: URL {
        appSupportDirectory.appendingPathComponent("inbox/terminal.tsv")
    }

    public static var reviewDebugLogURL: URL {
        appSupportDirectory.appendingPathComponent("review-debug.log")
    }
}
