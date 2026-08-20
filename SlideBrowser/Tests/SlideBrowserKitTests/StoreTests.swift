import AppKit
import Foundation
import Testing
@testable import SlideBrowserKit

@MainActor
@Suite("SiteStore")
struct SiteStoreTests {
    private func makeStore() -> (SiteStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidebrowser-tests-\(UUID().uuidString)")
            .appendingPathComponent("sites.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return (SiteStore(fileURL: url), url)
    }

    @Test func seedsDefaultsOnFirstRun() {
        let (store, url) = makeStore()
        #expect(store.sites.count == Site.defaults.count)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func addAppendsToTheEndOfTheOrder() throws {
        let (store, _) = makeStore()
        let highestBefore = store.sites.map(\.order).max() ?? -1
        store.add(Site(name: "Linear", urlString: "https://linear.app"))
        let added = try #require(store.sites.first { $0.name == "Linear" })
        #expect(added.order == highestBefore + 1)
    }

    @Test func updateReplacesMatchingSite() throws {
        let (store, _) = makeStore()
        var site = try #require(store.orderedSites.first)
        site.name = "Renamed"
        site.keepAlive = true
        store.update(site)

        let reloaded = try #require(store.site(id: site.id))
        #expect(reloaded.name == "Renamed")
        #expect(reloaded.keepAlive)
        #expect(store.sites.count == Site.defaults.count)
    }

    @Test func removeCompactsTheOrder() throws {
        let (store, _) = makeStore()
        let target = try #require(store.orderedSites.first)
        store.remove(id: target.id)

        #expect(store.site(id: target.id) == nil)
        #expect(store.orderedSites.map(\.order) == Array(0..<store.sites.count))
    }

    @Test func moveReordersAndRenumbers() throws {
        let (store, _) = makeStore()
        let originalSecond = store.orderedSites[1]
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        #expect(store.orderedSites.first?.id == originalSecond.id)
        #expect(store.orderedSites.map(\.order) == Array(0..<store.sites.count))
    }

    @Test func pinnedSitesFollowOrder() {
        let (store, _) = makeStore()
        let pinned = store.pinnedSites
        let allPinned = pinned.allSatisfy { $0.isPinned }
        #expect(allPinned)
        #expect(pinned.map(\.order) == pinned.map(\.order).sorted())
    }

    @Test func togglePinnedFlipsTheFlag() throws {
        let (store, _) = makeStore()
        let target = try #require(store.orderedSites.first)
        let before = target.isPinned
        store.togglePinned(id: target.id)
        #expect(store.site(id: target.id)?.isPinned == !before)
    }

    @Test func changesSurviveReload() throws {
        let (store, url) = makeStore()
        store.add(Site(name: "Linear", urlString: "https://linear.app", keepAlive: true))

        let reopened = SiteStore(fileURL: url)
        let restored = try #require(reopened.sites.first { $0.name == "Linear" })
        #expect(restored.keepAlive)
        #expect(reopened.sites.count == Site.defaults.count + 1)
    }

    @Test func corruptFileFallsBackToDefaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidebrowser-tests-\(UUID().uuidString)")
            .appendingPathComponent("sites.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not json".utf8).write(to: url)

        let store = SiteStore(fileURL: url)
        #expect(store.sites.count == Site.defaults.count)
    }
}

@MainActor
@Suite("SettingsStore")
struct SettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "slidebrowser.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func startsFromDocumentedDefaults() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.panelSide == .right)
        #expect(store.panelWidth == PanelGeometry.defaultWidth)
        #expect(store.panelHeightRatio == 1)
        #expect(store.panelTopInsetRatio == 0)
        #expect(store.autoHide)
        #expect(store.alwaysOnTop)
        #expect(!store.isPinned)
        #expect(store.searchEngine == .google)
        #expect(store.keepAliveLimit == 3)
        #expect(store.toggleHotKey == .defaultToggle)
    }

    @Test func writesSurviveANewStoreOverTheSameDefaults() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.panelSide = .left
        first.panelWidth = 620
        first.panelHeightRatio = 0.5
        first.panelTopInsetRatio = 0.1
        first.autoHide = false
        first.searchEngine = .duckDuckGo
        first.keepAliveLimit = 6

        let second = SettingsStore(defaults: defaults)
        #expect(second.panelSide == .left)
        #expect(second.panelWidth == 620)
        #expect(second.panelHeightRatio == 0.5)
        #expect(second.panelTopInsetRatio == 0.1)
        #expect(!second.autoHide)
        #expect(second.searchEngine == .duckDuckGo)
        #expect(second.keepAliveLimit == 6)
    }

    @Test func hotKeyRoundTrips() {
        let defaults = makeDefaults()
        let combo = HotKeyCombo(keyCode: 49, modifierFlags: 1_048_576 | 131_072)
        SettingsStore(defaults: defaults).toggleHotKey = combo
        #expect(SettingsStore(defaults: defaults).toggleHotKey == combo)
    }

    /// Out-of-range persisted values must be tamed rather than producing an unusable panel.
    @Test func absurdStoredRatiosAreClamped() {
        let defaults = makeDefaults()
        defaults.set(9.0, forKey: "panelHeightRatio")
        defaults.set(-4.0, forKey: "panelTopInsetRatio")

        let store = SettingsStore(defaults: defaults)
        #expect(store.panelHeightRatio == 1)
        #expect(store.panelTopInsetRatio == 0)
    }

    @Test func keepAliveLimitNeverDropsBelowOne() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "keepAliveLimit")
        #expect(SettingsStore(defaults: defaults).keepAliveLimit == 1)
    }

    @Test func lastSiteIDRoundTrips() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let id = UUID()
        store.lastSiteID = id
        #expect(SettingsStore(defaults: defaults).lastSiteID == id)

        store.lastSiteID = nil
        #expect(SettingsStore(defaults: defaults).lastSiteID == nil)
    }
}

@MainActor
@Suite("Site hotKey")
struct SiteHotKeyTests {
    /// sites.json written before the feature existed has no hotKey field and must keep loading.
    @Test func legacyJSONWithoutHotKeyDecodes() throws {
        let legacy = """
        [{"id":"3A3008B9-214E-479C-9FCD-8FC2F6B41EC3","isPinned":true,"keepAlive":true,
          "name":"ChatGPT","order":0,"urlString":"https://chatgpt.com"}]
        """
        let sites = try JSONDecoder().decode([Site].self, from: Data(legacy.utf8))
        #expect(sites.count == 1)
        #expect(sites[0].hotKey == nil)
    }

    @Test func hotKeyRoundTripsThroughTheStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidebrowser-tests-\(UUID().uuidString)/sites.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = SiteStore(fileURL: url)
        let combo = HotKeyCombo(keyCode: 5, modifierFlags: 1_179_648)
        store.add(Site(name: "GitHub2", urlString: "https://github.com", hotKey: combo))

        let reopened = SiteStore(fileURL: url)
        let restored = try #require(reopened.sites.first { $0.name == "GitHub2" })
        #expect(restored.hotKey == combo)
    }

    @Test func hotKeyCanBeCleared() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidebrowser-tests-\(UUID().uuidString)/sites.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = SiteStore(fileURL: url)
        store.add(Site(name: "X", urlString: "https://x.com", hotKey: HotKeyCombo(keyCode: 7, modifierFlags: 1_179_648)))
        var site = try #require(store.sites.first { $0.name == "X" })
        site.hotKey = nil
        store.update(site)
        #expect(SiteStore(fileURL: url).sites.first { $0.name == "X" }?.hotKey == nil)
    }

    @Test func combosAreHashable() {
        let a = HotKeyCombo(keyCode: 5, modifierFlags: 1_179_648)
        let b = HotKeyCombo(keyCode: 5, modifierFlags: 1_179_648)
        #expect(Set([a, b]).count == 1)
    }
}

@MainActor
@Suite("HotKeyCombo")
struct HotKeyComboTests {
    @Test func defaultToggleIsCommandE() {
        #expect(HotKeyCombo.defaultToggle.displayString == "⌘E")
    }

    @Test func carbonModifiersMapFromCocoaFlags() {
        let combo = HotKeyCombo(
            keyCode: 0,
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
        )
        // cmdKey = 256, shiftKey = 512
        #expect(combo.carbonModifiers == 256 | 512)
    }

    @Test func displayStringOrdersModifiersLikeMacOS() {
        let combo = HotKeyCombo(
            keyCode: 0,
            modifierFlags: NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue
        )
        #expect(combo.displayString.hasPrefix("⌃⌥⇧⌘"))
    }
}
