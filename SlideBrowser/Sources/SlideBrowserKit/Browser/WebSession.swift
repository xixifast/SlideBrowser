import AppKit
import WebKit

struct WebLoadFailure: Identifiable {
    let id = UUID()
    let url: URL?
    let code: String
    let message: String
}

/// Shown when the page being loaded belongs to a login provider that often refuses to work
/// inside an embedded web view.
struct EmbeddedAuthNotice: Identifiable {
    let id = UUID()
    let provider: String
    let url: URL
}

@MainActor
protocol WebSessionHost: AnyObject {
    func session(
        _ session: WebSession,
        createPopupWith configuration: WKWebViewConfiguration,
        navigationAction: WKNavigationAction
    ) -> WKWebView?
    func sessionRequestsClosePopup(_ session: WebSession)
    func sessionDidBecomeActive(_ session: WebSession)
    func session(_ session: WebSession, didStartDownload download: WKDownload)
}

/// One WebSession per site. The WKWebView belongs to the session, never to a SwiftUI view,
/// so redraws can't reload the page.
@MainActor
final class WebSession: NSObject, ObservableObject, Identifiable {
    let site: Site
    nonisolated let id: UUID

    @Published private(set) var webView: WKWebView?
    @Published private(set) var title: String
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published var loadFailure: WebLoadFailure?
    @Published var authNotice: EmbeddedAuthNotice?

    private(set) var lastURL: URL?
    private(set) var lastAccessDate = Date()

    /// Opaque WebKit snapshot of the whole session: back/forward list and scroll position. Lets a
    /// suspended session come back where the user left it instead of reloading the bare URL.
    private var interactionState: Any?

    private weak var host: WebSessionHost?
    private var observations: [NSKeyValueObservation] = []

    /// Redraw threshold for the progress bar. Publishing every WebKit tick re-renders the pane
    /// dozens of times per load for no visible benefit.
    private static let progressPublishStep = 0.05

    var keepAlive: Bool { site.keepAlive }
    var isLive: Bool { webView != nil }

    init(site: Site, host: WebSessionHost?) {
        self.site = site
        self.id = site.id
        self.host = host
        self.title = site.name
        self.lastURL = site.url
        self.currentURL = site.url
        super.init()
    }

    // MARK: - Lifecycle

    @discardableResult
    func activate() -> WKWebView {
        lastAccessDate = Date()
        if let webView { return webView }

        let webView = WebViewFactory.makeWebView()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        observe(webView)

        if let interactionState {
            // Restores history and scroll offset, and reloads the current entry itself.
            webView.interactionState = interactionState
        } else if let url = lastURL ?? site.url {
            webView.load(URLRequest(url: url))
        }
        host?.sessionDidBecomeActive(self)
        return webView
    }

    /// Releases the WKWebView (and its web content process) but keeps everything needed to
    /// restore the page later. Cookies and logins live in the shared data store.
    func suspend() {
        guard let webView else { return }
        lastURL = webView.url ?? lastURL
        interactionState = webView.interactionState
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        self.webView = nil
        isLoading = false
        estimatedProgress = 0
        canGoBack = false
        canGoForward = false
        Diagnostics.session.notice("event=suspend restorable=\(self.interactionState != nil, privacy: .public)")
    }

    func touch() {
        lastAccessDate = Date()
    }

    // MARK: - Navigation

    func load(_ url: URL) {
        loadFailure = nil
        lastURL = url
        // An explicit navigation supersedes any stored snapshot.
        interactionState = nil
        activate().load(URLRequest(url: url))
    }

    func reload() {
        loadFailure = nil
        guard let webView else {
            _ = activate()
            return
        }
        if webView.url == nil, let url = lastURL {
            webView.load(URLRequest(url: url))
        } else {
            webView.reloadFromOrigin()
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func stopLoading() { webView?.stopLoading() }

    // MARK: - Observation

    private func observe(_ webView: WKWebView) {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    let value = webView.title
                    self?.title = (value?.isEmpty == false ? value! : self?.site.name) ?? ""
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    self?.currentURL = webView.url
                    if let url = webView.url { self?.lastURL = url }
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.publishProgress(webView.estimatedProgress) }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            }
        ]
    }

    private func publishProgress(_ value: Double) {
        let isBoundary = value >= 1 || value == 0
        guard isBoundary || abs(value - estimatedProgress) >= Self.progressPublishStep else { return }
        estimatedProgress = value
    }
}

// MARK: - WKNavigationDelegate

extension WebSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        Diagnostics.trace(
            "navigation",
            """
            site=\(site.name) scheme=\(navigationAction.request.url?.scheme ?? "nil") \
            host=\(navigationAction.request.url?.host ?? "nil") \
            path=\(navigationAction.request.url?.path ?? "") \
            type=\(navigationAction.navigationType.rawValue) mainFrame=\(isMainFrame)
            """
        )

        let decision = NavigationPolicy.decide(for: navigationAction)
        if decision == .allow, isMainFrame, let url = navigationAction.request.url {
            updateAuthNotice(for: url)
        }
        NavigationPolicy.apply(decision, context: "site", decisionHandler: decisionHandler)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        Diagnostics.trace(
            "response",
            """
            host=\(navigationResponse.response.url?.host ?? "nil") \
            status=\((navigationResponse.response as? HTTPURLResponse)?.statusCode ?? -1) \
            mime=\(navigationResponse.response.mimeType ?? "nil") \
            canShow=\(navigationResponse.canShowMIMEType) mainFrame=\(navigationResponse.isForMainFrame)
            """
        )
        decisionHandler(NavigationPolicy.decide(for: navigationResponse) == .download ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        host?.session(self, didStartDownload: download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        host?.session(self, didStartDownload: download)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Diagnostics.trace(
            "navigation",
            "event=finish site=\(self.site.name) host=\(webView.url?.host ?? "nil")"
        )
        loadFailure = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        recordFailure(error, phase: "didFail")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        recordFailure(error, phase: "didFailProvisional")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The web content process died; bring the page back instead of leaving a blank panel.
        Diagnostics.session.error(
            "event=webContentProcessTerminated site=\(self.site.name, privacy: .public)"
        )
        if let url = lastURL {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    private func updateAuthNotice(for url: URL) {
        guard let provider = EmbeddedAuthProvider.providerName(for: url) else {
            authNotice = nil
            return
        }
        authNotice = EmbeddedAuthNotice(provider: provider, url: url)
        Diagnostics.navigation.notice(
            "event=embeddedAuthDetected provider=\(provider, privacy: .public)"
        )
    }

    private func recordFailure(_ error: Error, phase: String) {
        let nsError = error as NSError
        // Cancellations are normal during fast navigation and must not surface as an error page.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        Diagnostics.navigation.error(
            """
            event=\(phase, privacy: .public) site=\(self.site.name, privacy: .public) \
            domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)
            """
        )
        loadFailure = WebLoadFailure(
            url: lastURL,
            code: "\(nsError.domain) \(nsError.code)",
            message: nsError.localizedDescription
        )
    }
}

// MARK: - WKUIDelegate

extension WebSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        host?.session(self, createPopupWith: configuration, navigationAction: navigationAction)
    }

    func webViewDidClose(_ webView: WKWebView) {
        host?.sessionRequestsClosePopup(self)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        WebDialogPresenter.alert(
            message: message,
            origin: frame.securityOrigin.host,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        WebDialogPresenter.confirm(
            message: message,
            origin: frame.securityOrigin.host,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        WebDialogPresenter.prompt(
            message: prompt,
            defaultText: defaultText,
            origin: frame.securityOrigin.host,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        WebDialogPresenter.chooseFiles(parameters: parameters, completion: completionHandler)
    }
}
