import Foundation

enum PanelState {
    case hidden
    case showing
    case visible
    case hiding

    var isOnScreen: Bool {
        switch self {
        case .showing, .visible: return true
        case .hidden, .hiding: return false
        }
    }
}

enum PanelSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}
