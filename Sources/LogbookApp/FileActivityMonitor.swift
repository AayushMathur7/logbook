import CoreServices
import Foundation
import LogbookCore

final class FileActivityMonitor {
    private var stream: FSEventStreamRef?
    private var watchedRoots: [String] = []
    private let queue = DispatchQueue(label: "logbook.file-events")

    var onEvent: ((ActivityEvent) -> Void)?

    func updateWatchedPaths(_ paths: [String]) {
        let normalized = normalizedRoots(from: paths)
        guard normalized != watchedRoots else {
            return
        }

        watchedRoots = normalized
        restartStream()
    }

    func stop() {
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private func restartStream() {
        stop()
        guard !watchedRoots.isEmpty else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, eventCount, eventPathsPointer, eventFlagsPointer, _ in
            guard
                let info,
                let eventPaths = unsafeBitCast(eventPathsPointer, to: NSArray.self) as? [String]
            else {
                return
            }

            let monitor = Unmanaged<FileActivityMonitor>.fromOpaque(info).takeUnretainedValue()
            let flagsBuffer = UnsafeBufferPointer(start: eventFlagsPointer, count: eventCount)

            for (index, path) in eventPaths.enumerated() where index < flagsBuffer.count {
                monitor.handle(path: path, flags: flagsBuffer[index])
            }
        }

        let paths = watchedRoots as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func handle(path: String, flags: FSEventStreamEventFlags) {
        guard !PathNoiseFilter.shouldIgnoreFileActivity(path: path) else {
            return
        }

        let kinds = kinds(for: flags)
        guard !kinds.isEmpty else {
            return
        }

        let pathURL = URL(fileURLWithPath: path)
        let parentDirectory = pathURL.deletingLastPathComponent().path
        let occurredAt = Date()

        for kind in kinds {
            onEvent?(
                ActivityEvent(
                    occurredAt: occurredAt,
                    source: .fileSystem,
                    kind: kind,
                    path: path,
                    workingDirectory: parentDirectory
                )
            )
        }
    }

    private func normalizedRoots(from paths: [String]) -> [String] {
        var seen: Set<String> = []

        return paths
            .compactMap { path -> String? in
                guard !path.isEmpty else { return nil }
                let candidateURL = URL(fileURLWithPath: path).standardizedFileURL
                var isDirectory: ObjCBool = false

                if FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory) {
                    let directoryURL = isDirectory.boolValue
                        ? candidateURL
                        : candidateURL.deletingLastPathComponent()
                    let normalized = directoryURL.path
                    return normalized.isEmpty ? nil : normalized
                }

                let parent = candidateURL.deletingLastPathComponent().path
                return parent.isEmpty ? nil : parent
            }
            .filter { seen.insert($0).inserted }
            .prefix(12)
            .map { $0 }
    }

    private func kinds(for flags: FSEventStreamEventFlags) -> [ActivityKind] {
        var result: [ActivityKind] = []

        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
            result.append(.fileCreated)
        }
        if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            result.append(.fileDeleted)
        }
        if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
            result.append(.fileRenamed)
        }
        if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0
            || flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0
            || flags & UInt32(kFSEventStreamEventFlagItemFinderInfoMod) != 0
            || flags & UInt32(kFSEventStreamEventFlagItemChangeOwner) != 0
            || flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 {
            result.append(.fileModified)
        }

        return result
    }
}
