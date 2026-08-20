import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let siteStore: SiteStore
    private let sessionManager: WebSessionManager
    private let launchAtLogin: LaunchAtLoginManager
    private let onOpen: () -> Void
    private let onOpenSettings: () -> Void

    init(
        siteStore: SiteStore,
        sessionManager: WebSessionManager,
        launchAtLogin: LaunchAtLoginManager,
        onOpen: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.siteStore = siteStore
        self.sessionManager = sessionManager
        self.launchAtLogin = launchAtLogin
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sidebar.trailing",
                accessibilityDescription: "SlideBrowser"
            )
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = menuDelegate
        return menu
    }

    private lazy var menuDelegate: StatusMenuDelegate = {
        StatusMenuDelegate { [weak self] menu in
            self?.rebuild(menu)
        }
    }()

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        launchAtLogin.refresh()

        let toggleItem = NSMenuItem(
            title: "Open SlideBrowser",
            action: #selector(StatusMenuActions.toggle),
            keyEquivalent: ""
        )
        toggleItem.target = actions
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let sitesItem = NSMenuItem(title: "Sites", action: nil, keyEquivalent: "")
        let sitesMenu = NSMenu()
        for (index, site) in siteStore.orderedSites.enumerated() {
            let item = NSMenuItem(
                title: site.name,
                action: #selector(StatusMenuActions.openSite(_:)),
                keyEquivalent: ""
            )
            item.target = actions
            item.tag = index
            sitesMenu.addItem(item)
        }
        if sitesMenu.items.isEmpty {
            sitesMenu.addItem(NSMenuItem(title: "No sites yet", action: nil, keyEquivalent: ""))
        }
        sitesItem.submenu = sitesMenu
        menu.addItem(sitesItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(StatusMenuActions.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = actions
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(StatusMenuActions.toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = actions
        launchItem.state = launchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit SlideBrowser",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    private lazy var actions: StatusMenuActions = {
        StatusMenuActions(
            onOpen: onOpen,
            onOpenSettings: onOpenSettings,
            onOpenSite: { [weak self] index in
                guard let self else { return }
                let sites = self.siteStore.orderedSites
                guard index >= 0, index < sites.count else { return }
                self.sessionManager.activate(site: sites[index])
                self.onOpen()
            },
            onToggleLaunchAtLogin: { [weak self] in
                guard let self else { return }
                self.launchAtLogin.isEnabled.toggle()
            }
        )
    }()
}

private final class StatusMenuDelegate: NSObject, NSMenuDelegate {
    private let onUpdate: (NSMenu) -> Void

    init(onUpdate: @escaping (NSMenu) -> Void) {
        self.onUpdate = onUpdate
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        onUpdate(menu)
    }
}

private final class StatusMenuActions: NSObject {
    private let onOpen: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenSite: (Int) -> Void
    private let onToggleLaunchAtLogin: () -> Void

    init(
        onOpen: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenSite: @escaping (Int) -> Void,
        onToggleLaunchAtLogin: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
        self.onOpenSite = onOpenSite
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
    }

    @objc func toggle() { onOpen() }
    @objc func openSettings() { onOpenSettings() }
    @objc func toggleLaunchAtLogin() { onToggleLaunchAtLogin() }
    @objc func openSite(_ sender: NSMenuItem) { onOpenSite(sender.tag) }
}
