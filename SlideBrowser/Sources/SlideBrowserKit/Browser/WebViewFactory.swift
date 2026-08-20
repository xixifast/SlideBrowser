import WebKit

/// Single place where every WKWebView is born, so persistence and preference choices stay
/// consistent across sessions and popups.
@MainActor
enum WebViewFactory {
    /// WKWebView's stock user agent stops after "(KHTML, like Gecko)", which is the signature
    /// login providers and bot-management services use to reject embedded browsers. Reporting the
    /// Safari version we genuinely run fixes that without pretending to be a different browser.
    private static let safariVersion: String = {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
           let version = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            return version
        }
        // Safari's major version tracks the OS major from macOS 26 onwards.
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major >= 26 ? "\(major).0" : "18.6"
    }()

    /// The tail WebKit appends to its own stock prefix. Also the part login providers look for.
    private static var safariSuffix: String { "Version/\(safariVersion) Safari/605.1.15" }

    /// The complete user agent the web views report, reused for favicon requests.
    static var browserUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) " + safariSuffix
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // The default data store persists cookies / local storage to disk, which is what keeps
        // logins alive across restarts. We never touch cookie storage ourselves.
        configuration.websiteDataStore = .default()
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.applicationNameForUserAgent = safariSuffix
        return configuration
    }

    /// Spinning up the first WKWebView pays for launching the WebKit content and networking
    /// processes. Doing it once while the app is idle moves that cost off the first ⌘E.
    private static var warmUpWebView: WKWebView?

    static func warmUp() {
        guard warmUpWebView == nil else { return }
        let webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        warmUpWebView = webView
        Diagnostics.session.notice("event=webKitWarmUp")
    }

    /// Releases the warm-up view once a real session exists to inherit the warmed processes.
    static func releaseWarmUp() {
        warmUpWebView = nil
    }

    static func makeWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration ?? makeConfiguration())
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        return webView
    }
}
