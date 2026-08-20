import AppKit
import WebKit

/// Asks the user where every file goes, so the app never needs blanket Downloads-folder access.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let filename: String
        var destination: URL?
        var isFinished: Bool = false
        var errorMessage: String?
    }

    @Published private(set) var items: [Item] = []

    private var itemIDsByDownload: [ObjectIdentifier: UUID] = [:]

    func begin(_ download: WKDownload) {
        download.delegate = self
    }

    func clearFinished() {
        items.removeAll { $0.isFinished || $0.errorMessage != nil }
    }

    private func updateItem(for download: WKDownload, _ mutate: (inout Item) -> Void) {
        guard let id = itemIDsByDownload[ObjectIdentifier(download)],
              let index = items.firstIndex(where: { $0.id == id })
        else { return }
        mutate(&items[index])
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.begin { [weak self] result in
            guard let self else {
                completionHandler(nil)
                return
            }
            guard result == .OK, let url = panel.url else {
                completionHandler(nil)
                return
            }
            // WebKit requires the destination not to exist yet.
            try? FileManager.default.removeItem(at: url)
            let item = Item(filename: url.lastPathComponent, destination: url)
            self.items.append(item)
            self.itemIDsByDownload[ObjectIdentifier(download)] = item.id
            completionHandler(url)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        updateItem(for: download) { $0.isFinished = true }
        itemIDsByDownload.removeValue(forKey: ObjectIdentifier(download))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        updateItem(for: download) { $0.errorMessage = error.localizedDescription }
        itemIDsByDownload.removeValue(forKey: ObjectIdentifier(download))
    }
}
