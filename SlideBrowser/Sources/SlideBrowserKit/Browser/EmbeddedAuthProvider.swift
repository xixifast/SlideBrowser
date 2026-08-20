import Foundation

/// Login providers that are known to reject, degrade, or blank out inside embedded web views.
/// We still allow the navigation — some of these work some of the time — but we surface an
/// "open in default browser" escape hatch so a blank page is never a dead end.
enum EmbeddedAuthProvider {
    private static let hosts: [String: String] = [
        "accounts.google.com": "Google",
        "appleid.apple.com": "Apple",
        "login.microsoftonline.com": "Microsoft",
        "login.live.com": "Microsoft",
        "login.yahoo.com": "Yahoo",
        "auth.services.adobe.com": "Adobe"
    ]

    static func providerName(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if let exact = hosts[host] { return exact }
        // Cover regional and tenant subdomains such as accounts.google.co.jp.
        return hosts.first { host.hasSuffix($0.key) || host.hasPrefix("accounts.google.") }?.value
    }
}
