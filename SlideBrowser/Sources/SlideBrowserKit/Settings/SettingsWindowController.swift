import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(makeContent: @escaping () -> AnyView) {
        self.makeContent = makeContent
    }

    var onWillShow: (() -> Void)?

    func show() {
        onWillShow?()
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: makeContent())
        let created = NSWindow(contentViewController: hosting)
        created.title = "SlideBrowser Settings"
        created.styleMask = [.titled, .closable, .miniaturizable]
        created.isReleasedWhenClosed = false
        created.center()
        created.level = .normal
        window = created

        NSApp.activate()
        created.makeKeyAndOrderFront(nil)
    }
}
