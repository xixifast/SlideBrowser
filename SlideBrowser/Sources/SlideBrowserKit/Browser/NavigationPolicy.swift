import AppKit
import WebKit

enum NavigationDecision: Equatable {
    case allow
    case download
    /// Hand the URL to the system and cancel the in-panel navigation.
    case openExternally(URL)
    /// Refuse silently; the scheme is one we will not load or delegate.
    case block(scheme: String)
}

/// The parts of a navigation the policy actually reasons about. Keeping this separate from
/// WKNavigationAction makes the rules testable: WebKit's delegate objects cannot be constructed.
struct NavigationRequest: Equatable {
    let url: URL?
    let isMainFrame: Bool
    let isUserInitiated: Bool
    let shouldPerformDownload: Bool

    init(
        url: URL?,
        isMainFrame: Bool = true,
        isUserInitiated: Bool = true,
        shouldPerformDownload: Bool = false
    ) {
        self.url = url
        self.isMainFrame = isMainFrame
        self.isUserInitiated = isUserInitiated
        self.shouldPerformDownload = shouldPerformDownload
    }

    init(_ action: WKNavigationAction) {
        url = action.request.url
        isMainFrame = action.targetFrame?.isMainFrame ?? true
        isUserInitiated = action.navigationType != .other
        shouldPerformDownload = action.shouldPerformDownload
    }
}

/// Single source of truth for what a web view is allowed to navigate to. Shared by site sessions
/// and popups so the two can't drift apart.
enum NavigationPolicy {
    static func decide(_ request: NavigationRequest) -> NavigationDecision {
        if request.shouldPerformDownload { return .download }
        guard let url = request.url else { return .allow }

        if URLClassifier.isInlineLoadable(url, isMainFrame: request.isMainFrame) { return .allow }

        // Only a deliberate user action may hand a URL to another app.
        if request.isUserInitiated, URLClassifier.isAllowedExternal(url) {
            return .openExternally(url)
        }
        return .block(scheme: url.scheme ?? "nil")
    }

    static func decide(for action: WKNavigationAction) -> NavigationDecision {
        decide(NavigationRequest(action))
    }

    static func decide(for response: WKNavigationResponse) -> NavigationDecision {
        response.canShowMIMEType ? .allow : .download
    }

    /// Applies the decision and reports what happened for diagnostics.
    @MainActor
    static func apply(
        _ decision: NavigationDecision,
        context: String,
        decisionHandler: (WKNavigationActionPolicy) -> Void
    ) {
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .download:
            decisionHandler(.download)
        case .openExternally(let url):
            Diagnostics.navigation.notice(
                "event=openExternally scheme=\(url.scheme ?? "nil", privacy: .public)"
            )
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .block(let scheme):
            Diagnostics.navigation.warning(
                "event=blocked context=\(context, privacy: .public) scheme=\(scheme, privacy: .public)"
            )
            decisionHandler(.cancel)
        }
    }
}
