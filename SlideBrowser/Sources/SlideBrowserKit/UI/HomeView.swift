import SwiftUI

/// The panel's landing screen: a search field plus the favourites grid from the design reference.
struct HomeView: View {
    @ObservedObject var siteStore: SiteStore
    @ObservedObject var sessionManager: WebSessionManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject var favicons: FaviconService

    let onAddSite: () -> Void
    let onEditSite: (Site) -> Void

    @State private var query = ""
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                searchField
                    .padding(.top, 26)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Favourites")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Palette.primaryText)

                    grid
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.panelBackground)
        .onChange(of: sessionManager.homeSearchFocusRequests) { _, _ in
            isQueryFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            TextField("Search \(settings.searchEngine.displayName) or enter address", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isQueryFocused)
                .onSubmit(submit)

            if !query.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Go")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.fieldBackground)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        )
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 84, maximum: 140), spacing: 12)],
            spacing: 12
        ) {
            ForEach(siteStore.orderedSites) { site in
                Button(action: { sessionManager.activate(site: site) }) {
                    card(site)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit…") { onEditSite(site) }
                    Button(site.isPinned ? "Unpin from Sidebar" : "Pin to Sidebar") {
                        siteStore.togglePinned(id: site.id)
                    }
                    Divider()
                    Button("Remove", role: .destructive) { siteStore.remove(id: site.id) }
                }
            }

            Button(action: onAddSite) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.cardBackground.opacity(0.6))
                    .frame(height: 96)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Palette.primaryText.opacity(0.7))
                    )
            }
            .buttonStyle(.plain)
            .help("Add site")
        }
    }

    private func card(_ site: Site) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SiteIconView(site: site, size: 26, favicons: favicons)
            Spacer(minLength: 8)
            Text(site.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }

    private func submit() {
        let text = query
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        query = ""
        sessionManager.open(input: text)
    }
}
