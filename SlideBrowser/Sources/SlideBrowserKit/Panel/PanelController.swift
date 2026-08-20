import AppKit

/// Owns the panel window and the show/hide state machine. Knows nothing about SwiftUI:
/// content is injected as an already-built NSView.
@MainActor
final class PanelController {
    private(set) var state: PanelState = .hidden
    private(set) var isPinned = false

    private let settings: SettingsStore
    private let screenResolver: ScreenResolver
    private let focusManager: FocusManager
    private var panel: SlidePanel?
    private var contentView: NSView?

    /// Visible frame of the screen the current geometry was computed against. Used as the
    /// denominator when turning a user resize back into stored ratios.
    private var geometryScreenFrame: CGRect = .zero
    /// Last frame we set ourselves. AppKit posts a trailing geometry notification once an
    /// animation settles, and echoing that back into settings would let a clamped width
    /// permanently overwrite the user's choice.
    private var lastAppliedFrame: CGRect = .null
    var onVisibilityChange: ((Bool) -> Void)?

    private static let animationDuration: TimeInterval = 0.16

    init(settings: SettingsStore, screenResolver: ScreenResolver, focusManager: FocusManager) {
        self.settings = settings
        self.screenResolver = screenResolver
        self.focusManager = focusManager
        self.isPinned = settings.isPinned
    }

    func attach(contentView view: NSView) {
        contentView = view
        panel?.contentView = view
    }

    func toggle() {
        switch state {
        case .hidden, .hiding: show()
        case .visible, .showing: hide(restoringFocus: true)
        }
    }

    func show() {
        let panel = ensurePanel()
        let geometry = currentGeometry()

        if state == .visible || state == .showing {
            lastAppliedFrame = geometry.visibleFrame
            panel.setFrame(geometry.visibleFrame, display: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        focusManager.captureFrontmostApplication()
        state = .showing
        Diagnostics.panel.notice("event=show side=\(self.settings.panelSide.rawValue, privacy: .public)")

        lastAppliedFrame = geometry.visibleFrame
        panel.setFrame(geometry.hiddenFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(geometry.visibleFrame, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if self.state == .showing {
                self.state = .visible
                self.onVisibilityChange?(true)
            }
        })
    }

    func hide(restoringFocus: Bool) {
        guard let panel, state == .visible || state == .showing else { return }
        let shouldRestoreFocus = restoringFocus && panel.isKeyWindow
        state = .hiding
        let geometry = currentGeometry()

        lastAppliedFrame = geometry.hiddenFrame
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(geometry.hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            guard self.state == .hiding else { return }
            panel.orderOut(nil)
            self.state = .hidden
            self.onVisibilityChange?(false)
            if shouldRestoreFocus {
                self.focusManager.restorePreviousApplication()
            } else {
                self.focusManager.forgetPreviousApplication()
            }
        })
    }

    func hideForDeactivation() {
        guard settings.autoHide, !isPinned else { return }
        guard state == .visible || state == .showing else { return }
        guard let panel else { return }
        // The user clicked another app; drop straight out without stealing focus back.
        panel.orderOut(nil)
        panel.alphaValue = 1
        state = .hidden
        focusManager.forgetPreviousApplication()
        onVisibilityChange?(false)
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        settings.isPinned = pinned
    }

    func togglePinned() {
        setPinned(!isPinned)
    }

    func move(to side: PanelSide) {
        settings.panelSide = side
        applyGeometry(animated: state.isOnScreen)
    }

    func resize(width: CGFloat) {
        let screen = screenResolver.currentScreen()
        settings.panelWidth = PanelGeometry.clampWidth(width, screenWidth: screen.visibleFrame.width)
        applyGeometry(animated: false)
    }

    /// Restores the full-height default after a vertical resize.
    func resetVerticalGeometry() {
        settings.panelHeightRatio = 1
        settings.panelTopInsetRatio = 0
        applyGeometry(animated: true)
    }

    func applyLevel() {
        panel?.level = settings.alwaysOnTop ? .floating : .normal
    }

    var isVisible: Bool { state.isOnScreen }

    // MARK: - Private

    private func ensurePanel() -> SlidePanel {
        if let panel { return panel }
        let geometry = currentGeometry()
        let created = SlidePanel(contentRect: geometry.hiddenFrame)
        created.onCancel = { [weak self] in self?.hide(restoringFocus: true) }
        created.level = settings.alwaysOnTop ? .floating : .normal
        if let contentView { created.contentView = contentView }
        created.delegate = panelDelegate
        panel = created
        return created
    }

    private lazy var panelDelegate: PanelWindowDelegate = {
        PanelWindowDelegate { [weak self] frame in
            self?.persistUserFrame(frame)
        }
    }()

    private func currentGeometry() -> PanelGeometry {
        let screen = screenResolver.currentScreen()
        geometryScreenFrame = screen.visibleFrame
        return PanelGeometry(
            visibleFrame: screen.visibleFrame,
            side: settings.panelSide,
            requestedWidth: settings.panelWidth,
            heightRatio: settings.panelHeightRatio,
            topInsetRatio: settings.panelTopInsetRatio
        )
    }

    private func applyGeometry(animated: Bool) {
        guard let panel, state.isOnScreen else { return }
        let target = currentGeometry().visibleFrame
        lastAppliedFrame = target
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    /// Turns a user-driven resize into a stored width plus vertical ratios, so both survive
    /// restarts and translate across displays of different sizes.
    private func persistUserFrame(_ frame: CGRect) {
        // AppKit rounds the frame it applies, so compare with a tolerance: exact equality lets a
        // sub-point echo through and nudge the stored ratio on every launch.
        let echoesOurFrame = abs(frame.width - lastAppliedFrame.width) <= 1
            && abs(frame.height - lastAppliedFrame.height) <= 1
            && abs(frame.minY - lastAppliedFrame.minY) <= 1
        guard !echoesOurFrame else { return }
        let screen = panel?.screen?.visibleFrame ?? geometryScreenFrame
        guard screen.width > 0, screen.height > 0 else { return }

        settings.panelWidth = PanelGeometry.clampWidth(frame.width, screenWidth: screen.width)
        settings.panelHeightRatio = min(max(frame.height / screen.height, 0.2), 1)
        settings.panelTopInsetRatio = min(max((screen.maxY - frame.maxY) / screen.height, 0), 0.8)
    }
}

private final class PanelWindowDelegate: NSObject, NSWindowDelegate {
    private let onFrameChange: (CGRect) -> Void

    init(onFrameChange: @escaping (CGRect) -> Void) {
        self.onFrameChange = onFrameChange
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onFrameChange(window.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onFrameChange(window.frame)
    }
}
