import Foundation

struct PagePlugin: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImageName: String
    let help: String
    let privacyNote: String
}

@MainActor
enum PagePluginRegistry {
    static let plugins: [PagePlugin] = [TranslatePagePlugin.metadata]

    static func availablePlugins(for session: WebSession) -> [PagePlugin] {
        plugins.filter { isAvailable($0.id, for: session) }
    }

    static func isAvailable(_ id: String, for session: WebSession) -> Bool {
        switch id {
        case TranslatePagePlugin.metadata.id:
            return TranslatePagePlugin.canRun(on: session)
        default:
            return false
        }
    }

    static func run(_ id: String, on session: WebSession) {
        switch id {
        case TranslatePagePlugin.metadata.id:
            TranslatePagePlugin.run(on: session)
        default:
            break
        }
    }
}
