import AppKit
import Combine

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google
    case bing
    case duckDuckGo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckDuckGo: return "DuckDuckGo"
        }
    }

    func searchURL(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        switch self {
        case .google:
            components.host = "www.google.com"
            components.path = "/search"
        case .bing:
            components.host = "www.bing.com"
            components.path = "/search"
        case .duckDuckGo:
            components.host = "duckduckgo.com"
            components.path = "/"
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let panelSide = "panelSide"
        static let panelWidth = "panelWidth"
        static let panelHeightRatio = "panelHeightRatio"
        static let panelTopInsetRatio = "panelTopInsetRatio"
        static let autoHide = "autoHide"
        static let alwaysOnTop = "alwaysOnTop"
        static let isPinned = "isPinned"
        static let lastSiteID = "lastSiteID"
        static let searchEngine = "searchEngine"
        static let keepAliveLimit = "keepAliveLimit"
        static let toggleHotKey = "toggleHotKey"
    }

    private let defaults: UserDefaults

    @Published var panelSide: PanelSide {
        didSet { defaults.set(panelSide.rawValue, forKey: Key.panelSide) }
    }

    @Published var panelWidth: CGFloat {
        didSet { defaults.set(Double(panelWidth), forKey: Key.panelWidth) }
    }

    @Published var panelHeightRatio: CGFloat {
        didSet { defaults.set(Double(panelHeightRatio), forKey: Key.panelHeightRatio) }
    }

    @Published var panelTopInsetRatio: CGFloat {
        didSet { defaults.set(Double(panelTopInsetRatio), forKey: Key.panelTopInsetRatio) }
    }

    @Published var autoHide: Bool {
        didSet { defaults.set(autoHide, forKey: Key.autoHide) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: Key.isPinned) }
    }

    @Published var searchEngine: SearchEngine {
        didSet { defaults.set(searchEngine.rawValue, forKey: Key.searchEngine) }
    }

    @Published var keepAliveLimit: Int {
        didSet { defaults.set(keepAliveLimit, forKey: Key.keepAliveLimit) }
    }

    @Published var toggleHotKey: HotKeyCombo {
        didSet {
            guard let data = try? JSONEncoder().encode(toggleHotKey) else { return }
            defaults.set(data, forKey: Key.toggleHotKey)
        }
    }

    var lastSiteID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Key.lastSiteID) else { return nil }
            return UUID(uuidString: raw)
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.lastSiteID) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.panelWidth: Double(PanelGeometry.defaultWidth),
            Key.panelHeightRatio: 1.0,
            Key.panelTopInsetRatio: 0.0,
            Key.autoHide: true,
            Key.alwaysOnTop: true,
            Key.keepAliveLimit: 3
        ])

        panelSide = PanelSide(rawValue: defaults.string(forKey: Key.panelSide) ?? "") ?? .right
        panelWidth = CGFloat(defaults.double(forKey: Key.panelWidth))
        panelHeightRatio = min(max(CGFloat(defaults.double(forKey: Key.panelHeightRatio)), 0.2), 1)
        panelTopInsetRatio = min(max(CGFloat(defaults.double(forKey: Key.panelTopInsetRatio)), 0), 0.8)
        autoHide = defaults.bool(forKey: Key.autoHide)
        alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
        isPinned = defaults.bool(forKey: Key.isPinned)
        searchEngine = SearchEngine(rawValue: defaults.string(forKey: Key.searchEngine) ?? "") ?? .google
        keepAliveLimit = max(1, defaults.integer(forKey: Key.keepAliveLimit))

        if let data = defaults.data(forKey: Key.toggleHotKey),
           let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            toggleHotKey = combo
        } else {
            toggleHotKey = .defaultToggle
        }
    }
}
