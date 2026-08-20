import AppKit
import WebKit

@MainActor
final class PopupSession: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published private(set) var title: String = "Loading…"
    @Published private(set) var currentURL: URL?

    var onClose: (() -> Void)?
    var onDownload: ((WKDownload) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration) {
        webView = WebViewFactory.makeWebView(configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    if let value = webView.title, !value.isEmpty { self?.title = value }
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.currentURL = webView.url }
            }
        ]
    }

    func close() {
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}

extension PopupSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        Diagnostics.trace(
            "popupNavigation",
            """
            scheme=\(navigationAction.request.url?.scheme ?? "nil") \
            host=\(navigationAction.request.url?.host ?? "nil")
            """
        )
        NavigationPolicy.apply(
            NavigationPolicy.decide(for: navigationAction),
            context: "popup",
            decisionHandler: decisionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(NavigationPolicy.decide(for: navigationResponse) == .download ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        onDownload?(download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        onDownload?(download)
    }
}

extension PopupSession: WKUIDelegate {
    func webViewDidClose(_ webView: WKWebView) {
        onClose?()
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        WebDialogPresenter.chooseFiles(parameters: parameters, completion: completionHandler)
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
}
