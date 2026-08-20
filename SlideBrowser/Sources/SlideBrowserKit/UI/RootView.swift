import SwiftUI

struct RootView: View {
    @ObservedObject var siteStore: SiteStore
    @ObservedObject var sessionManager: WebSessionManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject var favicons: FaviconService

    let onHidePanel: () -> Void
    let onOpenSettings: () -> Void
    let onTogglePin: () -> Void
    let isPinned: Bool

    @State private var isRailCollapsed = false
    @State private var editorTarget: SiteEditorTarget?

    var body: some View {
        HStack(spacing: 0) {
            SiteRailView(
                siteStore: siteStore,
                sessionManager: sessionManager,
                settings: settings,
                favicons: favicons,
                isCollapsed: $isRailCollapsed,
                onHidePanel: onHidePanel,
                onOpenSettings: onOpenSettings,
                onAddSite: { editorTarget = .new },
                onTogglePin: onTogglePin,
                isPinned: isPinned
            )

            Divider()

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Palette.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Palette.panelCornerRadius, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        )
        .sheet(item: $editorTarget) { target in
            SiteEditorView(target: target, siteStore: siteStore) { editorTarget = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if let popup = sessionManager.popup {
                PopupPane(popup: popup) { sessionManager.closePopup() }
            } else if let session = sessionManager.activeSession {
                BrowserPane(session: session, sessionManager: sessionManager, settings: settings)
            } else {
                HomeView(
                    siteStore: siteStore,
                    sessionManager: sessionManager,
                    settings: settings,
                    favicons: favicons,
                    onAddSite: { editorTarget = .new },
                    onEditSite: { editorTarget = .existing($0) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum SiteEditorTarget: Identifiable {
    case new
    case existing(Site)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let site): return site.id.uuidString
        }
    }
}

struct SiteEditorView: View {
    let target: SiteEditorTarget
    @ObservedObject var siteStore: SiteStore
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var urlString = ""
    @State private var keepAlive = false
    @State private var isPinned = true
    @State private var hotKey: HotKeyCombo?

    private var isExisting: Bool {
        if case .existing = target { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && URLClassifier.classify(urlString) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isExisting ? "Edit Site" : "Add Site")
                .font(.system(size: 15, weight: .semibold))

            Form {
                TextField("Name", text: $name)
                TextField("URL", text: $urlString)
                Toggle("Pin to sidebar", isOn: $isPinned)
                Toggle("Keep page alive in background", isOn: $keepAlive)
                LabeledContent("Global shortcut") {
                    HStack(spacing: 6) {
                        HotKeyRecorderView(combo: hotKey) { hotKey = $0 }
                        if hotKey != nil {
                            Button {
                                hotKey = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Remove shortcut")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if case .existing(let site) = target {
                    Button("Remove", role: .destructive) {
                        siteStore.remove(id: site.id)
                        onDismiss()
                    }
                }
                Spacer()
                Button("Cancel", action: onDismiss)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear(perform: populate)
    }

    private func populate() {
        guard case .existing(let site) = target else { return }
        name = site.name
        urlString = site.urlString
        keepAlive = site.keepAlive
        isPinned = site.isPinned
        hotKey = site.hotKey
    }

    private func save() {
        let normalized: String
        switch URLClassifier.classify(urlString) {
        case .navigate(let url): normalized = url.absoluteString
        default: normalized = urlString
        }

        switch target {
        case .new:
            siteStore.add(
                Site(
                    name: name,
                    urlString: normalized,
                    isPinned: isPinned,
                    keepAlive: keepAlive,
                    hotKey: hotKey
                )
            )
        case .existing(let site):
            var updated = site
            updated.name = name
            updated.urlString = normalized
            updated.isPinned = isPinned
            updated.keepAlive = keepAlive
            updated.hotKey = hotKey
            siteStore.update(updated)
        }
        onDismiss()
    }
}

private extension View {
    func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            if let value = item.wrappedValue {
                content(value)
            }
        }
    }
}
