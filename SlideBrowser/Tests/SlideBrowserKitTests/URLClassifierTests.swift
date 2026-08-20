import Foundation
import Testing
@testable import SlideBrowserKit

@Suite("URLClassifier")
struct URLClassifierTests {
    @Test func bareHostBecomesHTTPS() throws {
        guard case .navigate(let url)? = URLClassifier.classify("example.com") else {
            throw TestFailure("expected navigate")
        }
        #expect(url.absoluteString == "https://example.com")
    }

    @Test func hostWithPathKeepsPath() throws {
        guard case .navigate(let url)? = URLClassifier.classify("github.com/apple/swift") else {
            throw TestFailure("expected navigate")
        }
        #expect(url.absoluteString == "https://github.com/apple/swift")
    }

    @Test func explicitSchemePassesThrough() throws {
        guard case .navigate(let url)? = URLClassifier.classify("http://localhost:8080/health") else {
            throw TestFailure("expected navigate")
        }
        #expect(url.absoluteString == "http://localhost:8080/health")
    }

    @Test func localhostWithoutSchemeIsAHost() throws {
        guard case .navigate(let url)? = URLClassifier.classify("localhost:3000") else {
            throw TestFailure("expected navigate")
        }
        #expect(url.host == "localhost")
    }

    @Test func ipWithPortIsAHost() throws {
        guard case .navigate(let url)? = URLClassifier.classify("127.0.0.1:8080/api") else {
            throw TestFailure("expected navigate")
        }
        #expect(url.host == "127.0.0.1")
        #expect(url.port == 8080)
    }

    /// mailto: really is a scheme, so it must not be rewritten into an https host.
    @Test func schemesThatAreNotHostPortStaySearches() throws {
        guard case .search(let query)? = URLClassifier.classify("mailto:a@b.com") else {
            throw TestFailure("expected search")
        }
        #expect(query == "mailto:a@b.com")
    }

    @Test(arguments: [
        "hello swift concurrency",
        "what is a wkwebview",
        "swift 6 migration"
    ])
    func sentencesBecomeSearches(_ input: String) throws {
        guard case .search(let query)? = URLClassifier.classify(input) else {
            throw TestFailure("expected search for \(input)")
        }
        #expect(query == input)
    }

    @Test func trailingDotOnlyIsNotAHost() throws {
        guard case .search? = URLClassifier.classify("notes.") else {
            throw TestFailure("expected search")
        }
    }

    @Test func emptyInputIsRejected() {
        #expect(URLClassifier.classify("   ") == nil)
    }

    @Test func whitespaceIsTrimmedBeforeClassifying() throws {
        guard case .navigate(let url)? = URLClassifier.classify("  example.com  ") else {
            throw TestFailure("expected navigate")
        }
        #expect(url.absoluteString == "https://example.com")
    }

    /// A data: URL in the address bar could spoof the displayed origin, so it must never be
    /// treated as a location.
    @Test(arguments: [
        "data:text/html,<h1>hi</h1>",
        "javascript:alert(1)",
        "file:///etc/passwd"
    ])
    func unsafeSchemesAreNeverLocations(_ input: String) throws {
        guard case .search? = URLClassifier.classify(input) else {
            throw TestFailure("expected search for \(input)")
        }
    }

    @Test func topLevelFramesRejectBlobAndData() {
        let blob = URL(string: "blob:https://chatgpt.com/1234")!
        let data = URL(string: "data:text/html,<p>x</p>")!
        #expect(!URLClassifier.isInlineLoadable(blob, isMainFrame: true))
        #expect(!URLClassifier.isInlineLoadable(data, isMainFrame: true))
    }

    /// Single-page apps legitimately load blob:/data: documents into iframes; cancelling those
    /// silently breaks rendering.
    @Test func subframesAcceptBlobAndData() {
        let blob = URL(string: "blob:https://chatgpt.com/1234")!
        let data = URL(string: "data:text/html,<p>x</p>")!
        #expect(URLClassifier.isInlineLoadable(blob, isMainFrame: false))
        #expect(URLClassifier.isInlineLoadable(data, isMainFrame: false))
    }

    @Test func fileSchemeIsBlockedInEveryFrame() {
        let file = URL(string: "file:///etc/passwd")!
        #expect(!URLClassifier.isInlineLoadable(file, isMainFrame: true))
        #expect(!URLClassifier.isInlineLoadable(file, isMainFrame: false))
    }

    @Test func knownExternalSchemesAreAllowed() {
        #expect(URLClassifier.isAllowedExternal(URL(string: "mailto:a@b.com")!))
        #expect(URLClassifier.isAllowedExternal(URL(string: "zoommtg://zoom.us/join?x=1")!))
    }

    @Test func unknownExternalSchemesAreRejected() {
        #expect(!URLClassifier.isAllowedExternal(URL(string: "totallymadeup://do-something")!))
    }

    @Test func searchEnginesBuildQueryURLs() throws {
        let url = try #require(SearchEngine.google.searchURL(for: "hello swift"))
        #expect(url.absoluteString == "https://www.google.com/search?q=hello%20swift")
        #expect(SearchEngine.duckDuckGo.searchURL(for: "x")?.host == "duckduckgo.com")
        #expect(SearchEngine.bing.searchURL(for: "x")?.host == "www.bing.com")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
