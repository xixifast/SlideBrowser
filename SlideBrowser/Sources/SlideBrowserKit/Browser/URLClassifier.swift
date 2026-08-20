import Foundation

enum AddressBarInput {
    case navigate(URL)
    case search(String)
}

/// Decides whether what the user typed is a location or a search query.
struct URLClassifier {
    /// Schemes we are willing to load as a top-level document. Deliberately excludes data: so the
    /// address bar can never display a spoofed origin.
    static let topLevelSchemes: Set<String> = ["http", "https", "about"]

    /// Subframes legitimately use blob: and data: documents (SPA iframes, generated previews,
    /// worker documents), so cancelling them breaks real pages.
    static let subframeSchemes: Set<String> = ["http", "https", "about", "blob", "data"]

    /// Schemes we are willing to hand to the system, and only for user-initiated navigation.
    static let allowedExternalSchemes: Set<String> = [
        "mailto", "tel", "facetime", "facetime-audio", "sms", "maps",
        "itms-apps", "itms-appss", "macappstore", "x-apple.systempreferences",
        "zoommtg", "slack", "msteams", "vscode", "cursor", "notion", "figma", "spotify"
    ]

    static func classify(_ rawInput: String) -> AddressBarInput? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let url = URL(string: input),
           let scheme = url.scheme?.lowercased(),
           topLevelSchemes.contains(scheme),
           url.host != nil || scheme == "about" {
            return .navigate(url)
        }

        // A scheme we refuse to load inline is never treated as a location.
        if hasExplicitScheme(input) {
            return .search(input)
        }

        if looksLikeHost(input), let url = URL(string: "https://\(input)") {
            return .navigate(url)
        }

        return .search(input)
    }

    /// True when the text starts with a real URL scheme. `URL(string:)` cannot be used for this:
    /// it reads "localhost:3000" as scheme "localhost", which would misfile a common dev address
    /// as a search query.
    private static func hasExplicitScheme(_ input: String) -> Bool {
        guard let colon = input.firstIndex(of: ":") else { return false }
        let candidate = input[input.startIndex..<colon]
        guard let first = candidate.first, first.isLetter else { return false }
        let isSchemeShaped = candidate.allSatisfy { $0.isLetter || $0.isNumber || "+-.".contains($0) }
        guard isSchemeShaped else { return false }

        // "host:8080" and "host:8080/path" are an authority with a port, not a scheme.
        let remainder = input[input.index(after: colon)...]
        let digits = remainder.prefix { $0.isNumber }
        if !digits.isEmpty {
            let afterDigits = remainder.dropFirst(digits.count)
            if afterDigits.isEmpty || "/?#".contains(afterDigits.first!) { return false }
        }
        return true
    }

    private static func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(" ") else { return false }
        let head = input.split(separator: "/", maxSplits: 1).first.map(String.init) ?? input
        let hostOnly = head.split(separator: "?", maxSplits: 1).first.map(String.init) ?? head
        if hostOnly == "localhost" || hostOnly.hasPrefix("localhost:") { return true }
        guard hostOnly.contains(".") else { return false }
        let labels = hostOnly.split(separator: ".")
        guard labels.count >= 2, let last = labels.last else { return false }
        let tld = stripPort(String(last))

        if tld.allSatisfy(\.isNumber) {
            // A numeric final label is only a host if the whole thing is a dotted-quad address.
            return labels.count == 4 && labels.allSatisfy { label in
                let octet = stripPort(String(label))
                return !octet.isEmpty && octet.allSatisfy(\.isNumber) && (Int(octet) ?? 256) <= 255
            }
        }
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }

    private static func stripPort(_ label: String) -> String {
        label.split(separator: ":").first.map(String.init) ?? label
    }

    static func isInlineLoadable(_ url: URL, isMainFrame: Bool) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return isMainFrame ? topLevelSchemes.contains(scheme) : subframeSchemes.contains(scheme)
    }

    static func isAllowedExternal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedExternalSchemes.contains(scheme)
    }
}
