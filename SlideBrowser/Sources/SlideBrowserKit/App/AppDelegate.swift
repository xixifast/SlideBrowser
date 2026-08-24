import AppKit
import Carbon.HIToolbox

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private var environment: AppEnvironment!
    private var escapeMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let environment = AppEnvironment()
            self.environment = environment
            NSApp.mainMenu = buildMainMenu()
            environment.start()
            installEscapeMonitor()
            observeDeactivation()
            // First launch lands on the panel so the app is not invisible after install.
            if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                environment.panelController.show()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    // MARK: - Esc handling

    /// A local monitor is needed because Esc is usually swallowed by the focused WKWebView.
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let environment = self.environment else { return event }
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            return MainActor.assumeIsolated {
                guard environment.panelController.isVisible else { return event }
                if environment.sessionManager.isAddressBarVisible {
                    environment.sessionManager.isAddressBarVisible = false
                    return nil
                }
                if environment.sessionManager.popup != nil {
                    environment.sessionManager.closePopup()
                    return nil
                }
                environment.panelController.hide(restoringFocus: true)
                return nil
            }
        }
    }

    private func observeDeactivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.environment?.panelController.hideForDeactivation()
            }
        }
    }

    // MARK: - Main menu

    /// The app is an accessory (no Dock icon, no visible menu bar), but the main menu is still
    /// what makes ⌘L / ⌘R / ⌘C etc. work while the panel is focused.
    @MainActor
    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Panel",
            action: #selector(hidePanel),
            keyEquivalent: "h"
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit SlideBrowser",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let browserItem = NSMenuItem()
        let browserMenu = NSMenu(title: "Browser")
        browserMenu.addItem(
            withTitle: "Address Bar",
            action: #selector(focusAddressBar),
            keyEquivalent: "l"
        ).target = self
        browserMenu.addItem(
            withTitle: "Reload",
            action: #selector(reload),
            keyEquivalent: "r"
        ).target = self
        browserMenu.addItem(
            withTitle: "Back",
            action: #selector(goBack),
            keyEquivalent: "["
        ).target = self
        browserMenu.addItem(
            withTitle: "Forward",
            action: #selector(goForward),
            keyEquivalent: "]"
        ).target = self
        let pluginsItem = NSMenuItem(title: "Plugins", action: nil, keyEquivalent: "")
        let pluginsMenu = NSMenu(title: "Plugins")
        for plugin in PagePluginRegistry.plugins {
            let item = pluginsMenu.addItem(
                withTitle: plugin.title,
                action: #selector(runPagePlugin(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = plugin.id
            item.toolTip = plugin.privacyNote
            item.image = NSImage(systemSymbolName: plugin.systemImageName, accessibilityDescription: plugin.title)
        }
        pluginsItem.submenu = pluginsMenu
        browserMenu.addItem(pluginsItem)
        browserMenu.addItem(.separator())
        browserMenu.addItem(
            withTitle: "Favourites",
            action: #selector(showHome),
            keyEquivalent: "0"
        ).target = self
        for index in 1...9 {
            let item = browserMenu.addItem(
                withTitle: "Site \(index)",
                action: #selector(selectSite(_:)),
                keyEquivalent: "\(index)"
            )
            item.target = self
            item.tag = index - 1
        }
        browserMenu.addItem(.separator())
        browserMenu.addItem(
            withTitle: "Close Popup",
            action: #selector(closePopup),
            keyEquivalent: "w"
        ).target = self
        browserItem.submenu = browserMenu
        mainMenu.addItem(browserItem)

        return mainMenu
    }

    // MARK: - Menu actions

    @MainActor @objc private func openSettings() {
        environment.settingsWindow.show()
    }

    @MainActor @objc private func hidePanel() {
        environment.panelController.hide(restoringFocus: true)
    }

    @MainActor @objc private func focusAddressBar() {
        guard environment.sessionManager.activeSession != nil else {
            environment.sessionManager.homeSearchFocusRequests += 1
            return
        }
        environment.sessionManager.isAddressBarVisible = true
    }

    @MainActor @objc private func reload() {
        environment.sessionManager.activeSession?.reload()
    }

    @MainActor @objc private func goBack() {
        environment.sessionManager.activeSession?.goBack()
    }

    @MainActor @objc private func goForward() {
        environment.sessionManager.activeSession?.goForward()
    }

    @MainActor @objc private func runPagePlugin(_ sender: NSMenuItem) {
        guard let pluginID = sender.representedObject as? String,
              let session = environment.sessionManager.activeSession,
              PagePluginRegistry.isAvailable(pluginID, for: session)
        else { return }
        PagePluginRegistry.run(pluginID, on: session)
    }

    @MainActor @objc private func showHome() {
        environment.sessionManager.showHome()
    }

    @MainActor @objc private func selectSite(_ sender: NSMenuItem) {
        environment.sessionManager.activateSite(atPinnedIndex: sender.tag)
    }

    @MainActor @objc private func closePopup() {
        environment.sessionManager.closePopup()
    }
}

extension AppDelegate: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let pluginID = menuItem.representedObject as? String else { return true }
        guard let session = environment.sessionManager.activeSession else { return false }
        return PagePluginRegistry.isAvailable(pluginID, for: session)
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }
}
