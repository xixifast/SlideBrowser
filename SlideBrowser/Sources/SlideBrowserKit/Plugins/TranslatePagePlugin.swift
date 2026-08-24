import Foundation

@MainActor
enum TranslatePagePlugin {
    static let metadata = PagePlugin(
        id: "translate-page",
        title: "Translate Page",
        systemImageName: "character.book.closed",
        help: "Translate this page with Google Translate",
        privacyNote: "Sends the current page URL to Google Translate when you choose it."
    )

    static func canRun(on session: WebSession) -> Bool {
        guard let url = pageURL(for: session) else { return false }
        return translatedURL(for: url, targetLanguage: targetLanguageCode()) != nil
    }

    static func run(on session: WebSession) {
        guard let url = pageURL(for: session),
              let translated = translatedURL(for: url, targetLanguage: targetLanguageCode())
        else { return }
        session.load(translated)
    }

    static func translatedURL(for pageURL: URL, targetLanguage: String) -> URL? {
        guard let scheme = pageURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        guard var components = URLComponents(string: "https://translate.google.com/translate") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLanguage),
            URLQueryItem(name: "u", value: pageURL.absoluteString)
        ]
        return components.url
    }

    static func targetLanguageCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard let preferred = preferredLanguages.first else { return "en" }
        let normalized = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh-hans") || normalized == "zh" { return "zh-CN" }
        if normalized.hasPrefix("zh-hant") { return "zh-TW" }
        if let code = normalized.split(separator: "-").first, !code.isEmpty {
            return String(code)
        }
        return "en"
    }

    private static func pageURL(for session: WebSession) -> URL? {
        session.currentURL ?? session.site.url
    }
}
