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
        // Google signs in on regional domains too: accounts.google.co.jp, .de, and friends.
        if host.hasPrefix("accounts.google.") { return hosts["accounts.google.com"] }
        // Anchored on a label boundary, so notlogin.live.com is not read as login.live.com.
        return hosts.first { host.hasSuffix(".\($0.key)") }?.value
    }
}
