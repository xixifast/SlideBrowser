import Foundation

@MainActor
final class SiteStore: ObservableObject {
    @Published private(set) var sites: [Site] = []

    private let fileURL: URL

    var pinnedSites: [Site] {
        sites.filter(\.isPinned).sorted { $0.order < $1.order }
    }

    var orderedSites: [Site] {
        sites.sorted { $0.order < $1.order }
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func site(id: UUID) -> Site? {
        sites.first { $0.id == id }
    }

    func add(_ site: Site) {
        var new = site
        new.order = (sites.map(\.order).max() ?? -1) + 1
        sites.append(new)
        save()
    }

    func update(_ site: Site) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }
        sites[index] = site
        save()
    }

    func remove(id: UUID) {
        sites.removeAll { $0.id == id }
        normalizeOrder()
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = orderedSites
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, var site) in ordered.enumerated() {
            site.order = index
            ordered[index] = site
        }
        sites = ordered
        save()
    }

    func togglePinned(id: UUID) {
        guard var site = site(id: id) else { return }
        site.isPinned.toggle()
        update(site)
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent("SlideBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sites.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Site].self, from: data),
              !decoded.isEmpty
        else {
            sites = Site.defaults
            save()
            return
        }
        sites = decoded
    }

    private func normalizeOrder() {
        var ordered = orderedSites
        for (index, var site) in ordered.enumerated() {
            site.order = index
            ordered[index] = site
        }
        sites = ordered
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(orderedSites) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
