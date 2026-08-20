import AppKit
import Foundation
import Testing
@testable import SlideBrowserKit

@Suite("PanelGeometry")
struct PanelGeometryTests {
    /// Stand-in for a 1512x982pt display with the menu bar removed.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)

    private func geometry(
        side: PanelSide = .right,
        width: CGFloat = 460,
        heightRatio: CGFloat = 1,
        topInsetRatio: CGFloat = 0,
        screen: CGRect? = nil
    ) -> PanelGeometry {
        PanelGeometry(
            visibleFrame: screen ?? self.screen,
            side: side,
            requestedWidth: width,
            heightRatio: heightRatio,
            topInsetRatio: topInsetRatio
        )
    }

    @Test func rightSideSitsInsideTheTrailingEdge() {
        let frame = geometry().visibleFrame
        #expect(frame.maxX == screen.maxX - PanelGeometry.edgeInset)
        #expect(frame.width == 460)
    }

    @Test func leftSideSitsInsideTheLeadingEdge() {
        let frame = geometry(side: .left).visibleFrame
        #expect(frame.minX == screen.minX + PanelGeometry.edgeInset)
    }

    @Test func hiddenFrameRestsFullyOffScreen() {
        let right = geometry()
        #expect(right.hiddenFrame.minX >= screen.maxX)

        let left = geometry(side: .left)
        #expect(left.hiddenFrame.maxX <= screen.minX)
    }

    @Test func hiddenFrameKeepsVerticalPlacement() {
        let subject = geometry(heightRatio: 0.5, topInsetRatio: 0.1)
        #expect(subject.hiddenFrame.minY == subject.visibleFrame.minY)
        #expect(subject.hiddenFrame.height == subject.visibleFrame.height)
    }

    @Test func widthIsClampedToTheMinimum() {
        #expect(geometry(width: 100).width == PanelGeometry.minWidth)
    }

    @Test func widthIsClampedToTheScreenRatio() {
        let expected = screen.width * PanelGeometry.maxWidthRatio
        #expect(geometry(width: 5000).width == expected)
    }

    @Test func fullHeightSpansTheVisibleArea() {
        let frame = geometry().visibleFrame
        #expect(frame.height == screen.height)
        #expect(frame.maxY == screen.maxY)
    }

    @Test func heightRatioIsAppliedFromTheTop() {
        let frame = geometry(heightRatio: 0.5).visibleFrame
        #expect(frame.height == screen.height * 0.5)
        #expect(frame.maxY == screen.maxY)
    }

    @Test func topInsetPushesThePanelDown() {
        let subject = geometry(heightRatio: 0.5, topInsetRatio: 0.2)
        #expect(subject.visibleFrame.maxY == screen.maxY - screen.height * 0.2)
    }

    @Test func topInsetCannotPushThePanelOffTheBottom() {
        let subject = geometry(heightRatio: 0.9, topInsetRatio: 0.9)
        #expect(subject.visibleFrame.minY >= screen.minY)
        #expect(subject.topInset == screen.height - subject.height)
    }

    @Test func heightNeverExceedsTheVisibleArea() {
        #expect(geometry(heightRatio: 3).height == screen.height)
    }

    @Test func heightRespectsTheMinimum() {
        #expect(geometry(heightRatio: 0.01).height == PanelGeometry.minHeight)
    }

    /// A stored ratio must reproduce the same proportion on a differently sized display, which is
    /// what lets a custom size survive moving between the built-in screen and an external one.
    @Test func ratiosTranslateAcrossDisplays() {
        let external = CGRect(x: -1920, y: 0, width: 1920, height: 1046)
        let builtIn = geometry(heightRatio: 0.65)
        let moved = geometry(heightRatio: 0.65, screen: external)

        #expect(abs(builtIn.height / screen.height - moved.height / external.height) < 0.0001)
        #expect(moved.visibleFrame.maxX == external.maxX - PanelGeometry.edgeInset)
    }

    @Test func clampWidthMatchesInstanceBehaviour() {
        #expect(PanelGeometry.clampWidth(100, screenWidth: 1512) == PanelGeometry.minWidth)
        #expect(PanelGeometry.clampWidth(5000, screenWidth: 1512) == 1512 * PanelGeometry.maxWidthRatio)
        #expect(PanelGeometry.clampWidth(460, screenWidth: 1512) == 460)
    }

    /// Narrow displays must not be able to clamp below the usable minimum.
    @Test func minimumWinsOnVeryNarrowDisplays() {
        #expect(PanelGeometry.clampWidth(460, screenWidth: 400) == PanelGeometry.minWidth)
    }
}

@Suite("PanelState")
struct PanelStateTests {
    @Test func onScreenStatesAreShowingAndVisible() {
        #expect(PanelState.showing.isOnScreen)
        #expect(PanelState.visible.isOnScreen)
        #expect(!PanelState.hiding.isOnScreen)
        #expect(!PanelState.hidden.isOnScreen)
    }

    @Test func sidesRoundTripThroughRawValues() throws {
        for side in PanelSide.allCases {
            #expect(PanelSide(rawValue: side.rawValue) == side)
        }
        #expect(PanelSide(rawValue: "diagonal") == nil)
    }
}

@Suite("EmbeddedAuthProvider")
struct EmbeddedAuthProviderTests {
    @Test func recognisesKnownProviders() {
        #expect(EmbeddedAuthProvider.providerName(for: URL(string: "https://appleid.apple.com/auth/authorize")!) == "Apple")
        #expect(EmbeddedAuthProvider.providerName(for: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!) == "Google")
        #expect(EmbeddedAuthProvider.providerName(for: URL(string: "https://login.microsoftonline.com/common")!) == "Microsoft")
    }

    @Test func ignoresUnrelatedHosts() {
        #expect(EmbeddedAuthProvider.providerName(for: URL(string: "https://github.com/login")!) == nil)
        #expect(EmbeddedAuthProvider.providerName(for: URL(string: "https://chatgpt.com/")!) == nil)
    }
}

@Suite("Site")
struct SiteTests {
    @Test func hostDropsTheWWWPrefix() {
        #expect(Site(name: "YouTube", urlString: "https://www.youtube.com").host == "youtube.com")
        #expect(Site(name: "GitHub", urlString: "https://github.com").host == "github.com")
    }

    @Test func hostFallsBackToTheNameWhenTheURLIsUnusable() {
        #expect(Site(name: "Broken", urlString: "not a url").host == "Broken")
    }

    @Test func initialsUseTheFirstCharacter() {
        #expect(Site(name: "claude", urlString: "https://claude.ai").initials == "C")
        #expect(Site(name: "", urlString: "https://x.com").initials == "?")
    }

    @Test func defaultsAreOrderedAndContainPinnedEntries() {
        let defaults = Site.defaults
        #expect(defaults.map(\.order) == Array(0..<defaults.count))
        #expect(defaults.contains { $0.isPinned })
        #expect(defaults.allSatisfy { $0.url != nil })
    }
}
