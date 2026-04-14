import Foundation

public enum DriftlyPaths {
    public static let directoryName = "Driftly"
    private static let legacyDirectoryNames = ["Logbook", "Daylog"]
    private static let databaseFileName = "driftly.sqlite"
    private static let legacyDatabaseFileNames = ["logbook.sqlite"]
    
    public static var appSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)

        legacyDirectoryNames.forEach { legacyDirectoryName in
            let legacyDirectory = baseDirectory.appendingPathComponent(legacyDirectoryName, isDirectory: true)
            migrateLegacyDirectoryIfNeeded(from: legacyDirectory, to: directory)
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    
    public static var databaseURL: URL {
        let newURL = appSupportDirectory.appendingPathComponent(databaseFileName)
        migrateLegacyDatabaseIfNeeded(to: newURL)
        return newURL
    }
    
    public static var shellInboxURL: URL {
        appSupportDirectory.appendingPathComponent("inbox/terminal.tsv")
    }

    public static var reviewDebugLogURL: URL {
        appSupportDirectory.appendingPathComponent("review-debug.log")
    }
    
    private static func migrateLegacyDirectoryIfNeeded(from legacyDirectory: URL, to directory: URL) {
        guard FileManager.default.fileExists(atPath: legacyDirectory.path) else {
            return
        }
        
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        
        try? FileManager.default.moveItem(at: legacyDirectory, to: directory)
    }

    private static func migrateLegacyDatabaseIfNeeded(to databaseURL: URL) {
        guard !FileManager.default.fileExists(atPath: databaseURL.path) else {
            return
        }

        for legacyFileName in legacyDatabaseFileNames {
            let legacyURL = appSupportDirectory.appendingPathComponent(legacyFileName)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.moveItem(at: legacyURL, to: databaseURL)
                return
            }
        }
    }
}
