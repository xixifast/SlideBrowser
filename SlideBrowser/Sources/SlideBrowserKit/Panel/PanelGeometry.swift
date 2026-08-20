import AppKit

/// Pure geometry math for the slide panel. Kept free of window/state so it can be reasoned
/// about (and unit tested) independently of AppKit window behaviour.
struct PanelGeometry {
    static let defaultWidth: CGFloat = 460
    static let minWidth: CGFloat = 320
    static let minHeight: CGFloat = 200
    static let maxWidthRatio: CGFloat = 0.7
    static let edgeInset: CGFloat = 8

    let screenFrame: CGRect
    let side: PanelSide
    let requestedWidth: CGFloat
    /// Panel height as a fraction of the screen's visible height, so a custom size carries
    /// across displays of different sizes.
    let heightRatio: CGFloat
    /// Gap between the top of the visible area and the panel's top edge, same units as above.
    let topInsetRatio: CGFloat

    init(
        visibleFrame: CGRect,
        side: PanelSide,
        requestedWidth: CGFloat,
        heightRatio: CGFloat = 1,
        topInsetRatio: CGFloat = 0
    ) {
        self.screenFrame = visibleFrame
        self.side = side
        self.requestedWidth = requestedWidth
        self.heightRatio = heightRatio
        self.topInsetRatio = topInsetRatio
    }

    var width: CGFloat {
        let maxWidth = max(Self.minWidth, screenFrame.width * Self.maxWidthRatio)
        return min(max(requestedWidth, Self.minWidth), maxWidth)
    }

    var height: CGFloat {
        let requested = screenFrame.height * heightRatio
        return min(max(requested, min(Self.minHeight, screenFrame.height)), screenFrame.height)
    }

    var topInset: CGFloat {
        let requested = screenFrame.height * topInsetRatio
        return min(max(requested, 0), screenFrame.height - height)
    }

    var visibleFrame: CGRect {
        let x: CGFloat
        switch side {
        case .right: x = screenFrame.maxX - width - Self.edgeInset
        case .left: x = screenFrame.minX + Self.edgeInset
        }
        let y = screenFrame.maxY - topInset - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Off-screen resting frame used as the start/end point of the slide animation.
    var hiddenFrame: CGRect {
        let x: CGFloat
        switch side {
        case .right: x = screenFrame.maxX
        case .left: x = screenFrame.minX - width
        }
        return CGRect(x: x, y: visibleFrame.minY, width: width, height: height)
    }

    static func clampWidth(_ value: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let maxWidth = max(minWidth, screenWidth * maxWidthRatio)
        return min(max(value, minWidth), maxWidth)
    }
}
