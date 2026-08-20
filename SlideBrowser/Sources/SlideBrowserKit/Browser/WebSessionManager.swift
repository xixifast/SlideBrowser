import AppKit
import Combine
import WebKit

/// Owns every WebSession and enforces the memory policy: the active session, any keep-alive
/// session, and the N most recently used sessions stay live; everything else drops its WKWebView.
@MainActor
final class WebSessionManager: ObservableObject {
    @Published private(set) var sessions: [UUID: WebSession] = [:]
    @Published private(set) var activeSiteID: UUID?
    @Published var popup: PopupSession?
    @Published var isAddressBarVisible = false
    /// Bumped by ⌘L while the home screen is showing so the search field takes focus.
    @Published var homeSearchFocusRequests = 0

    let downloads = DownloadManager()

    private let siteStore: SiteStore
    private let settings: SettingsStore
    private var cancellables: Set<AnyCancellable> = []
    /// Site ids the store held on the previous change, so a deletion can be told apart from a
    /// scratch session that was never in the store.
    private var knownSiteIDs: Set<UUID> = []

    var activeSession: WebSession? {
        guard let activeSiteID else { return nil }
        return sessions[activeSiteID]
    }

    var isShowingHome: Bool { activeSiteID == nil }

    init(siteStore: SiteStore, settings: SettingsStore) {
        self.siteStore = siteStore
        self.settings = settings

        siteStore.$sites
            .sink { [weak self] sites in
                self?.pruneSessions(for: sites)
            }
            .store(in: &cancellables)
    }

    // MARK: - Activation

    func restoreLastSite() {
        guard let id = settings.lastSiteID, let site = siteStore.site(id: id) else { return }
        activate(site: site, loadImmediately: false)
    }

    func activate(site: Site, loadImmediately: Bool = true) {
        let session = session(for: site)
        session.touch()
        activeSiteID = site.id
        settings.lastSiteID = site.id
        isAddressBarVisible = false
        if loadImmediately {
            session.activate()
        }
        enforceMemoryPolicy()
    }

    func activateSite(id: UUID) {
        guard let site = siteStore.site(id: id) else { return }
        activate(site: site)
    }

    func activateSite(atPinnedIndex index: Int) {
        let pinned = siteStore.pinnedSites
        guard index >= 0, index < pinned.count else { return }
        activate(site: pinned[index])
    }

    func showHome() {
        activeSiteID = nil
        settings.lastSiteID = nil
        isAddressBarVisible = false
    }

    func session(for site: Site) -> WebSession {
        if let existing = sessions[site.id] { return existing }
        let session = WebSession(site: site, host: self)
        sessions[site.id] = session
        return session
    }

    /// Opens an ad-hoc query from the home search field in the active session, or in the first
    /// site if nothing is active yet.
    func open(input: String) {
        guard let classified = URLClassifier.classify(input) else { return }
        let url: URL?
        switch classified {
        case .navigate(let target): url = target
        case .search(let query): url = settings.searchEngine.searchURL(for: query)
        }
        guard let url else { return }

        if let session = activeSession {
            session.load(url)
            return
        }
        let scratch = Site(name: url.host ?? "Web", urlString: url.absoluteString)
        let session = session(for: scratch)
        activeSiteID = scratch.id
        session.load(url)
        enforceMemoryPolicy()
    }

    func closePopup() {
        guard let popup else { return }
        Diagnostics.session.notice("event=popupClose")
        Diagnostics.trace("popup", "close host=\(popup.currentURL?.host ?? "nil")")
        popup.close()
        self.popup = nil
    }

    // MARK: - Memory policy

    private func enforceMemoryPolicy() {
        let limit = max(1, settings.keepAliveLimit)
        let liveOrdinary = sessions.values
            .filter { $0.isLive && !$0.keepAlive && $0.id != activeSiteID }
            .sorted { $0.lastAccessDate > $1.lastAccessDate }

        // Active session occupies one slot of the budget.
        let allowance = max(0, limit - 1)
        guard liveOrdinary.count > allowance else { return }
        for session in liveOrdinary.dropFirst(allowance) {
            session.suspend()
        }
    }

    private func pruneSessions(for sites: [Site]) {
        let validIDs = Set(sites.map(\.id))
        for (id, session) in sessions where !validIDs.contains(id) && id != activeSiteID {
            session.suspend()
            sessions.removeValue(forKey: id)
        }
        // A scratch session from the address bar is absent from the store too, so fall back home
        // only for a site the store actually dropped.
        if let activeSiteID, knownSiteIDs.contains(activeSiteID), !validIDs.contains(activeSiteID) {
            sessions.removeValue(forKey: activeSiteID)?.suspend()
            showHome()
        }
        knownSiteIDs = validIDs
    }
}

// MARK: - WebSessionHost

extension WebSessionManager: WebSessionHost {
    func session(
        _ session: WebSession,
        createPopupWith configuration: WKWebViewConfiguration,
        navigationAction: WKNavigationAction
    ) -> WKWebView? {
        // Popups stay inside the single side panel instead of spawning macOS windows.
        closePopup()
        let popup = PopupSession(configuration: configuration)
        popup.onClose = { [weak self] in self?.closePopup() }
        popup.onDownload = { [weak self] download in self?.downloads.begin(download) }
        self.popup = popup

        Diagnostics.session.notice("event=popupOpen")
        Diagnostics.trace(
            "popup",
            "open from=\(session.site.name) host=\(navigationAction.request.url?.host ?? "nil")"
        )
        // WebKit loads the request into the returned web view itself; loading it here as well
        // races the two navigations and can leave the popup blank.
        return popup.webView
    }

    func sessionRequestsClosePopup(_ session: WebSession) {
        closePopup()
    }

    func sessionDidBecomeActive(_ session: WebSession) {
        enforceMemoryPolicy()
    }

    func session(_ session: WebSession, didStartDownload download: WKDownload) {
        downloads.begin(download)
    }
}
