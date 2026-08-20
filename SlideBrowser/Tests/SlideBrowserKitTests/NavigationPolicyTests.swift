import Foundation
import Testing
@testable import SlideBrowserKit

@Suite("NavigationPolicy")
struct NavigationPolicyTests {
    private func request(
        _ url: String,
        mainFrame: Bool = true,
        userInitiated: Bool = true,
        download: Bool = false
    ) -> NavigationRequest {
        NavigationRequest(
            url: URL(string: url),
            isMainFrame: mainFrame,
            isUserInitiated: userInitiated,
            shouldPerformDownload: download
        )
    }

    @Test func httpsIsAllowed() {
        #expect(NavigationPolicy.decide(request("https://github.com/apple")) == .allow)
    }

    @Test func downloadRequestsShortCircuit() {
        #expect(NavigationPolicy.decide(request("https://example.com/a.zip", download: true)) == .download)
    }

    @Test func userInitiatedExternalSchemeIsHandedToTheSystem() {
        let decision = NavigationPolicy.decide(request("mailto:someone@example.com"))
        #expect(decision == .openExternally(URL(string: "mailto:someone@example.com")!))
    }

    /// A page must not be able to launch another app without the user acting.
    @Test func scriptedExternalSchemeIsBlocked() {
        let decision = NavigationPolicy.decide(request("mailto:someone@example.com", userInitiated: false))
        #expect(decision == .block(scheme: "mailto"))
    }

    @Test func unknownSchemesAreBlockedEvenWhenUserInitiated() {
        #expect(NavigationPolicy.decide(request("weirdscheme://payload")) == .block(scheme: "weirdscheme"))
    }

    @Test func fileSchemeIsAlwaysBlocked() {
        #expect(NavigationPolicy.decide(request("file:///etc/passwd")) == .block(scheme: "file"))
    }

    @Test func topLevelBlobIsBlocked() {
        let decision = NavigationPolicy.decide(request("blob:https://chatgpt.com/abc", userInitiated: false))
        #expect(decision == .block(scheme: "blob"))
    }

    /// Regression guard: cancelling blob:/data: subframes silently breaks single-page apps.
    @Test func subframeBlobIsAllowed() {
        let decision = NavigationPolicy.decide(
            request("blob:https://chatgpt.com/abc", mainFrame: false, userInitiated: false)
        )
        #expect(decision == .allow)
    }

    @Test func subframeDataURLIsAllowed() {
        let decision = NavigationPolicy.decide(
            request("data:text/html,<p>x</p>", mainFrame: false, userInitiated: false)
        )
        #expect(decision == .allow)
    }

    @Test func nilURLIsAllowedThrough() {
        #expect(NavigationPolicy.decide(NavigationRequest(url: nil)) == .allow)
    }
}
