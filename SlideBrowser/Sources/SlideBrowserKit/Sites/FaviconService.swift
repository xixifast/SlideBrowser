import AppKit

/// Fetches favicons straight from each site (never through a third-party favicon proxy) so the
/// app does not leak the user's site list to anyone.
///
/// Lookups are pure so they are safe to call while rendering; fetching is driven separately by
/// `load(for:)`, which callers invoke from a `.task`.
@MainActor
final class FaviconService: ObservableObject {
    @Published private(set) var icons: [String: NSImage] = [:]

    private var inFlight: Set<String> = []
    /// Hosts that served nothing usable. Without this, all four candidate paths get re-requested
    /// on every launch for every icon-less site.
    private var knownMisses: Set<String> = []
    private let cacheDirectory: URL
    private let session: URLSession

    private static let candidatePaths = [
        "/favicon.ico",
        "/apple-touch-icon.png",
        "/apple-touch-icon-precomposed.png",
        "/favicon.png"
    ]

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = base.appendingPathComponent("SlideBrowser/Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 16 * 1024 * 1024,
            directory: base.appendingPathComponent("SlideBrowser/FaviconHTTPCache", isDirectory: true)
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 8
        configuration.httpMaximumConnectionsPerHost = 2
        // Some CDNs only serve icons to browser-shaped clients.
        configuration.httpAdditionalHeaders = ["User-Agent": WebViewFactory.browserUserAgent]
        session = URLSession(configuration: configuration)
    }

    /// Pure lookup, safe to call from a view body.
    func icon(for site: Site) -> NSImage? {
        icons[site.host]
    }

    func load(for site: Site) async {
        let host = site.host
        guard !host.isEmpty, icons[host] == nil, !knownMisses.contains(host), !inFlight.contains(host)
        else { return }
        inFlight.insert(host)
        defer { inFlight.remove(host) }

        let diskURL = cacheDirectory.appendingPathComponent("\(host).png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            icons[host] = image
            return
        }

        guard let siteURL = site.url,
              var components = URLComponents(url: siteURL, resolvingAgainstBaseURL: false)
        else { return }
        components.query = nil
        components.fragment = nil

        for path in Self.candidatePaths {
            var candidate = components
            candidate.path = path
            guard let url = candidate.url else { continue }
            if let image = await fetchImage(at: url) {
                icons[host] = image
                persist(image, to: diskURL)
                return
            }
        }
        knownMisses.insert(host)
    }

    private func fetchImage(at url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty,
              let image = NSImage(data: data), image.size.width > 0
        else { return nil }
        return image
    }

    private func persist(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url, options: .atomic)
    }
}
