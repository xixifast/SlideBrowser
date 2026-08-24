import SwiftUI

struct SiteRailView: View {
    @ObservedObject var siteStore: SiteStore
    @ObservedObject var sessionManager: WebSessionManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject var favicons: FaviconService

    @Binding var isCollapsed: Bool
    let onHidePanel: () -> Void
    let onOpenSettings: () -> Void
    let onAddSite: () -> Void
    let onTogglePin: () -> Void
    let isPinned: Bool

    var body: some View {
        VStack(spacing: 10) {
            Button(action: { isCollapsed.toggle() }) {
                Image(systemName: isCollapsed ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")

            if !isCollapsed {
                Button(action: onHidePanel) {
                    Image(systemName: settings.panelSide == .right ? "arrow.right.to.line" : "arrow.left.to.line")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Hide panel (Esc)")

                menuButton

                Divider().padding(.horizontal, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        Button(action: { sessionManager.showHome() }) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(
                                    sessionManager.isShowingHome
                                        ? Palette.primaryText
                                        : Palette.secondaryText
                                )
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .help("Favourites")

                        ForEach(siteStore.pinnedSites) { site in
                            railItem(site)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Spacer(minLength: 0)

            if !isCollapsed {
                Button(action: onAddSite) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Add site")
            }
        }
        .padding(.vertical, 12)
        .frame(width: isCollapsed ? Palette.railCollapsedWidth : Palette.railWidth)
        .frame(maxHeight: .infinity)
        .background(Palette.railBackground)
        .foregroundStyle(Palette.primaryText)
    }

    private var menuButton: some View {
        Menu {
            if let session = sessionManager.activeSession {
                Button("Reload Page") { session.reload() }
                Button("Open in Default Browser") {
                    if let url = session.currentURL ?? session.site.url {
                        NSWorkspace.shared.open(url)
                    }
                }
                let plugins = PagePluginRegistry.availablePlugins(for: session)
                Menu("Plugins") {
                    if plugins.isEmpty {
                        Button("No plugins available") {}
                            .disabled(true)
                    } else {
                        ForEach(plugins) { plugin in
                            Button {
                                PagePluginRegistry.run(plugin.id, on: session)
                            } label: {
                                Label(plugin.title, systemImage: plugin.systemImageName)
                            }
                            .help("\(plugin.help). \(plugin.privacyNote)")
                        }
                    }
                }
                Divider()
            }

            if !sessionManager.downloads.items.isEmpty {
                Menu("Downloads") {
                    ForEach(sessionManager.downloads.items) { item in
                        Button(downloadTitle(item)) {
                            guard let destination = item.destination else { return }
                            NSWorkspace.shared.activateFileViewerSelecting([destination])
                        }
                        .disabled(item.destination == nil)
                    }
                    Divider()
                    Button("Clear Finished") { sessionManager.downloads.clearFinished() }
                }
                Divider()
            }

            Button("Settings…") { onOpenSettings() }
            Button(isPinned ? "Unpin Panel" : "Pin Panel") { onTogglePin() }
            Picker("Side", selection: Binding(
                get: { settings.panelSide },
                set: { settings.panelSide = $0 }
            )) {
                ForEach(PanelSide.allCases) { side in
                    Text(side.displayName).tag(side)
                }
            }
            Divider()
            Button("Quit SlideBrowser") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 22)
        .help("More")
    }

    private func downloadTitle(_ item: DownloadManager.Item) -> String {
        if let error = item.errorMessage { return "\(item.filename) — \(error)" }
        return item.isFinished ? item.filename : "\(item.filename) — downloading…"
    }

    private func railItem(_ site: Site) -> some View {
        let isActive = sessionManager.activeSiteID == site.id
        return Button(action: { sessionManager.activate(site: site) }) {
            SiteIconView(site: site, size: 20, favicons: favicons)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? Palette.primaryText.opacity(0.1) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(site.hotKey.map { "\(site.name)  \($0.displayString)" } ?? site.name)
        .contextMenu {
            Button("Reload") { sessionManager.session(for: site).reload() }
            Button("Open in Default Browser") {
                if let url = sessionManager.session(for: site).currentURL ?? site.url {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Button("Unpin from Sidebar") { siteStore.togglePinned(id: site.id) }
        }
    }
}
