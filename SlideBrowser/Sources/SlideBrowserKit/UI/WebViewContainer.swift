import SwiftUI
import WebKit

/// Bridges an existing WKWebView into SwiftUI. The web view is owned by its WebSession, so this
/// wrapper only ever re-parents it — it must never construct one.
struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        attach(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard webView.superview !== nsView else { return }
        attach(to: nsView)
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
