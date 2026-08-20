import Foundation

struct Site: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var urlString: String
    var isPinned: Bool
    var order: Int
    var keepAlive: Bool
    /// Optional global shortcut that summons the panel with this site active.
    var hotKey: HotKeyCombo?

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        isPinned: Bool = false,
        order: Int = 0,
        keepAlive: Bool = false,
        hotKey: HotKeyCombo? = nil
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.isPinned = isPinned
        self.order = order
        self.keepAlive = keepAlive
        self.hotKey = hotKey
    }

    var url: URL? { URL(string: urlString) }

    var host: String {
        url?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? name
    }

    var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    static let defaults: [Site] = [
        Site(name: "ChatGPT", urlString: "https://chatgpt.com", isPinned: true, order: 0, keepAlive: true),
        Site(name: "Claude", urlString: "https://claude.ai", isPinned: true, order: 1, keepAlive: true),
        Site(name: "GitHub", urlString: "https://github.com", isPinned: true, order: 2),
        Site(name: "Gmail", urlString: "https://mail.google.com", isPinned: true, order: 3),
        Site(name: "Slack", urlString: "https://app.slack.com/client", order: 4),
        Site(name: "YouTube", urlString: "https://www.youtube.com", order: 5),
        Site(name: "WhatsApp", urlString: "https://web.whatsapp.com", order: 6),
        Site(name: "Notion", urlString: "https://www.notion.so", order: 7),
        Site(name: "Google Calendar", urlString: "https://calendar.google.com", order: 8)
    ]
}
