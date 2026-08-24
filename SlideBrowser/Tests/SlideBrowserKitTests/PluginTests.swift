import Foundation
import Testing
@testable import SlideBrowserKit

@MainActor
@Suite("PagePlugins")
struct PagePluginTests {
    @Test func translatePluginBuildsGoogleTranslateURL() throws {
        let page = try #require(URL(string: "https://example.com/path?q=hello world"))
        let translated = try #require(TranslatePagePlugin.translatedURL(for: page, targetLanguage: "zh-CN"))
        let components = try #require(URLComponents(url: translated, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "translate.google.com")
        #expect(components.path == "/translate")
        #expect(components.queryItems?.first { $0.name == "sl" }?.value == "auto")
        #expect(components.queryItems?.first { $0.name == "tl" }?.value == "zh-CN")
        #expect(components.queryItems?.first { $0.name == "u" }?.value == page.absoluteString)
    }

    @Test func translatePluginOnlyAcceptsWebPages() throws {
        #expect(TranslatePagePlugin.translatedURL(
            for: URL(string: "https://example.com")!,
            targetLanguage: "en"
        ) != nil)
        #expect(TranslatePagePlugin.translatedURL(
            for: URL(string: "http://example.com")!,
            targetLanguage: "en"
        ) != nil)
        #expect(TranslatePagePlugin.translatedURL(
            for: URL(string: "about:blank")!,
            targetLanguage: "en"
        ) == nil)
        #expect(TranslatePagePlugin.translatedURL(
            for: URL(fileURLWithPath: "/tmp/example.html"),
            targetLanguage: "en"
        ) == nil)
    }

    @Test func targetLanguageFollowsSystemLanguageShape() {
        #expect(TranslatePagePlugin.targetLanguageCode(preferredLanguages: ["zh-Hans-CN"]) == "zh-CN")
        #expect(TranslatePagePlugin.targetLanguageCode(preferredLanguages: ["zh-Hant-TW"]) == "zh-TW")
        #expect(TranslatePagePlugin.targetLanguageCode(preferredLanguages: ["ja-JP"]) == "ja")
        #expect(TranslatePagePlugin.targetLanguageCode(preferredLanguages: []) == "en")
    }

    @Test func registryExposesTranslateOnlyForWebSessions() {
        let webSession = WebSession(site: Site(name: "Example", urlString: "https://example.com"), host: nil)
        let fileSession = WebSession(site: Site(name: "Local", urlString: "file:///tmp/example.html"), host: nil)

        #expect(PagePluginRegistry.availablePlugins(for: webSession).map(\.id) == ["translate-page"])
        #expect(PagePluginRegistry.availablePlugins(for: fileSession).isEmpty)
    }
}
