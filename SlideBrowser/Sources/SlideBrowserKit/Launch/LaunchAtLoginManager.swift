import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != wasEnabled else { return }
            apply(isEnabled)
        }
    }

    private var wasEnabled: Bool

    init() {
        // Deliberately not querying SMAppService here: its status is an XPC round trip and the
        // value is only needed once Settings or the menu bar is opened.
        isEnabled = false
        wasEnabled = false
    }

    /// Syncs with the system's registration state. Call before showing the toggle.
    func refresh() {
        let enabled = SMAppService.mainApp.status == .enabled
        guard enabled != isEnabled else { return }
        wasEnabled = enabled
        isEnabled = enabled
    }

    private func apply(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            wasEnabled = enabled
        } catch {
            NSLog("SlideBrowser: launch at login change failed: \(error.localizedDescription)")
            // Roll back so the UI never claims a state the system rejected. Writing wasEnabled
            // first makes the didSet guard short-circuit instead of recursing.
            wasEnabled = !enabled
            isEnabled = !enabled
        }
    }
}
