import AppKit

/// Decides which display the panel slides in on. Deliberately reads only the mouse location
/// and `NSScreen`, so the app never needs Accessibility permission.
final class ScreenResolver {
    private var lastUsedScreenID: CGDirectDisplayID?

    func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            lastUsedScreenID = hit.displayID
            return hit
        }
        if let id = lastUsedScreenID,
           let remembered = NSScreen.screens.first(where: { $0.displayID == id }) {
            return remembered
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
