import Foundation

public enum LogbookPaths {
    public static let directoryName = "Logbook"
    private static let legacyDirectoryName = "Daylog"
    
    public static var appSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        let legacyDirectory = baseDirectory.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        
        migrateLegacyDirectoryIfNeeded(from: legacyDirectory, to: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    
    public static var databaseURL: URL {
        appSupportDirectory.appendingPathComponent("logbook.sqlite")
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
}
