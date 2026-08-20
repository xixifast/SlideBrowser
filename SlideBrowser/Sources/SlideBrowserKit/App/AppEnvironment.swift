import AppKit
import Combine
import SwiftUI

/// Wires every service together and owns the app-level object graph.
@MainActor
final class AppEnvironment {
    let settings = SettingsStore()
    let siteStore = SiteStore()
    let favicons = FaviconService()
    let launchAtLogin = LaunchAtLoginManager()
    let screenResolver = ScreenResolver()
    let focusManager = FocusManager()
    let hotKeys: HotKeyProviding = HotKeyManager.shared

    let sessionManager: WebSessionManager
    let panelController: PanelController

    private var registeredSiteHotKeys: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []

    private(set) var settingsWindow: SettingsWindowController!
    private(set) var menuBar: MenuBarController!

    init() {
        sessionManager = WebSessionManager(siteStore: siteStore, settings: settings)
        panelController = PanelController(
            settings: settings,
            screenResolver: screenResolver,
            focusManager: focusManager
        )

        settingsWindow = SettingsWindowController { [unowned self] in
            AnyView(
                SettingsView(
                    settings: settings,
                    siteStore: siteStore,
                    launchAtLogin: launchAtLogin,
                    favicons: favicons,
                    onHotKeyChange: { [unowned self] combo in self.registerToggleHotKey(combo) },
                    onSideChange: { [unowned self] side in self.panelController.move(to: side) },
                    onWidthChange: { [unowned self] width in self.panelController.resize(width: width) },
                    onAlwaysOnTopChange: { [unowned self] in self.panelController.applyLevel() },
                    onResetSize: { [unowned self] in self.panelController.resetVerticalGeometry() }
                )
            )
        }

        settingsWindow.onWillShow = { [unowned self] in self.launchAtLogin.refresh() }

        menuBar = MenuBarController(
            siteStore: siteStore,
            sessionManager: sessionManager,
            launchAtLogin: launchAtLogin,
            onOpen: { [unowned self] in self.panelController.show() },
            onOpenSettings: { [unowned self] in self.settingsWindow.show() }
        )
    }

    func start() {
        let root = RootView(
            siteStore: siteStore,
            sessionManager: sessionManager,
            settings: settings,
            favicons: favicons,
            onHidePanel: { [unowned self] in self.panelController.hide(restoringFocus: true) },
            onOpenSettings: { [unowned self] in self.settingsWindow.show() },
            onTogglePin: { [unowned self] in self.panelController.togglePinned() },
            isPinned: panelController.isPinned
        )
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panelController.attach(contentView: hosting)

        sessionManager.restoreLastSite()
        registerToggleHotKey(settings.toggleHotKey)
        refreshSiteHotKeys()
        siteStore.$sites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSiteHotKeys() }
            .store(in: &cancellables)
        scheduleWarmUp()
    }

    /// Pays WebKit's process-launch cost while the app is idle, then hands the warmed processes to
    /// the session the user is most likely to open first.
    private func scheduleWarmUp() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            WebViewFactory.warmUp()
            try? await Task.sleep(for: .seconds(1))
            self.sessionManager.activeSession?.activate()
            WebViewFactory.releaseWarmUp()
        }
    }

    func registerToggleHotKey(_ combo: HotKeyCombo) {
        hotKeys.register(action: .togglePanel, combo: combo) { [weak self] in
            Task { @MainActor in self?.panelController.toggle() }
        }
        // A site shortcut may have just collided with (or been freed from) the toggle key.
        refreshSiteHotKeys()
    }

    /// Re-registers every per-site shortcut. The toggle key always wins a conflict, and the
    /// first site in rail order wins a duplicate.
    private func refreshSiteHotKeys() {
        for id in registeredSiteHotKeys {
            hotKeys.unregister(action: .openSite(id))
        }
        registeredSiteHotKeys = []

        var taken: Set<HotKeyCombo> = [settings.toggleHotKey]
        for site in siteStore.orderedSites {
            guard let combo = site.hotKey else { continue }
            guard !taken.contains(combo) else {
                Diagnostics.panel.warning("event=siteHotKeyConflictSkipped")
                continue
            }
            taken.insert(combo)
            Diagnostics.trace("hotkey", "register site=\(site.name) combo=\(combo.keyCode)/\(combo.modifierFlags)")
            let siteID = site.id
            hotKeys.register(action: .openSite(siteID), combo: combo) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    Diagnostics.trace("hotkey", "fired site=\(siteID)")
                    self.sessionManager.activateSite(id: siteID)
                    self.panelController.show()
                }
            }
            registeredSiteHotKeys.insert(siteID)
        }
    }
}
