import AppKit

/// Remembers which app the user came from so Esc / hotkey can hand focus back.
/// Restore only happens when the panel was the key window at hide time, otherwise the user
/// has already moved on and yanking them back would be hostile.
@MainActor
final class FocusManager {
    private var previousApplication: NSRunningApplication?

    func captureFrontmostApplication() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApplication = frontmost
    }

    func restorePreviousApplication() {
        guard let app = previousApplication, !app.isTerminated else { return }
        previousApplication = nil
        app.activate()
    }

    func forgetPreviousApplication() {
        previousApplication = nil
    }
}
