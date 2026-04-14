import AppKit

if ReviewReplayCommand.shouldRun(arguments: CommandLine.arguments) {
    ReviewReplayCommand.runAndExit(arguments: Array(CommandLine.arguments.dropFirst()))
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { LogbookAppController() }
application.delegate = delegate
application.run()
