import Foundation
import os

/// Diagnostics channels.
///
/// Coarse events go to the unified log and never contain URLs or hosts — SlideBrowser promises
/// not to record browsing history, and the system log is persistent shared storage.
/// Host-level detail is only emitted when the user opts in with:
///
///     defaults write app.slidebrowser.mac verboseDiagnostics -bool true
///
/// and is mirrored to stderr so launching the binary from a terminal shows the same trail.
enum Diagnostics {
    private static let subsystem = "app.slidebrowser.mac"

    static let navigation = Logger(subsystem: subsystem, category: "navigation")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let panel = Logger(subsystem: subsystem, category: "panel")

    static let isVerbose = UserDefaults.standard.bool(forKey: "verboseDiagnostics")

    static func trace(_ category: String, _ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        let line = "[SlideBrowser/\(category)] \(message())\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
