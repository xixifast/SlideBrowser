import AppKit

final class SlidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc arrives here when the panel itself holds focus; WebView-focused Esc is caught by
    /// the local key monitor in AppDelegate.
    var onCancel: (() -> Void)?

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        minSize = CGSize(width: PanelGeometry.minWidth, height: 200)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
