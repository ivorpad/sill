import CoreGraphics

/// Pinch to zoom on the picture: this device's own magnifier over the stream. The Mac's window keeps
/// its size and nothing goes to the Mac (Aa is the control that resizes the window); only where the
/// video is drawn changes, and with it what a touch's fraction of the frame means, since touches,
/// the pointer sprite and the video all go through `rect(fitted:in:)`.
///
/// The state is a scale and the point of the frame, in fractions, at the middle of the fitted rect.
/// Scale 1 is the fitted picture, exactly as before zooming existed. A zoomed picture never leaves a
/// gap at an edge it could cover: it is kept over the view on each axis where it is wider than the
/// view, and centred where it is still narrower (the letterbox stays, smaller).
///
/// Pure value, no UIKit: `HEVCDisplayView` draws through it and `InputOverlayView` changes it.
/// Checked on its own by Tests/checks/picture-zoom.
struct PictureZoom: Equatable {
    /// Five times the fitted picture: a 1280 pt wide Mac window on a 390 pt iPhone is then about
    /// 1.5 device points per Mac point, past the size it has on the Mac.
    static let maximum: CGFloat = 5
    /// A pinch let go below this goes back to the fitted picture, so getting all the way out never
    /// needs a precise pinch.
    static let snapBelow: CGFloat = 1.1
    /// A two-finger double tap's zoom: 2.5 times, enough to read a Mac window's text on a phone.
    static let tapScale: CGFloat = 2.5

    private(set) var scale: CGFloat = 1
    /// The frame point at the fitted rect's middle, each coordinate 0...1.
    private(set) var center = CGPoint(x: 0.5, y: 0.5)

    init() {}

    var isZoomed: Bool { scale > 1 }

    /// Where the frame is drawn, given where it is drawn fitted (`fitted`, aspect-fit inside
    /// `bounds`). `.zero` for a `.zero` fitted rect: no video yet stays no video.
    func rect(fitted: CGRect, in bounds: CGRect) -> CGRect {
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        let width = fitted.width * scale, height = fitted.height * scale
        let x = Self.place(fitted.midX - center.x * width, size: width, in: bounds.minX, bounds.width)
        let y = Self.place(fitted.midY - center.y * height, size: height, in: bounds.minY, bounds.height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The zoom at `scale` (held to 1...maximum) with the frame point `anchor` (fractions) under the
    /// view point `point`, as far as the edges allow: a pinch's step, and a two-finger move's at the
    /// same scale.
    func moved(to scale: CGFloat, anchor: CGPoint, at point: CGPoint, fitted: CGRect, in bounds: CGRect) -> PictureZoom {
        guard fitted.width > 0, fitted.height > 0 else { return self }
        let s = min(max(scale, 1), Self.maximum)
        guard s > 1 else { return PictureZoom() }
        let width = fitted.width * s, height = fitted.height * s
        let x = Self.place(point.x - anchor.x * width, size: width, in: bounds.minX, bounds.width)
        let y = Self.place(point.y - anchor.y * height, size: height, in: bounds.minY, bounds.height)
        var zoom = PictureZoom()
        zoom.scale = s
        // Read back from the placed rect, so `rect(fitted:in:)` gives that same rect.
        zoom.center = CGPoint(x: (fitted.midX - x) / width, y: (fitted.midY - y) / height)
        return zoom
    }

    /// The zoom moved just enough that the frame point `point` (fractions) is drawn at least
    /// `margin` inside the view, as far as the edges allow: the picture follows the Mac's pointer,
    /// as macOS's own Zoom does. Unzoomed, or with the point already inside, it is unchanged.
    func following(_ point: CGPoint, margin: CGFloat, fitted: CGRect, in bounds: CGRect) -> PictureZoom {
        guard isZoomed, fitted.width > 0, fitted.height > 0 else { return self }
        let r = rect(fitted: fitted, in: bounds)
        let at = CGPoint(x: r.minX + point.x * r.width, y: r.minY + point.y * r.height)
        let inner = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
        let target = CGPoint(x: min(max(at.x, inner.minX), inner.maxX), y: min(max(at.y, inner.minY), inner.maxY))
        guard target != at else { return self }
        return moved(to: scale, anchor: point, at: target, fitted: fitted, in: bounds)
    }

    /// The zoom a pinch leaves when it ends: the fitted picture below `snapBelow`, else as it is.
    var settled: PictureZoom { scale < Self.snapBelow ? PictureZoom() : self }

    /// One axis's origin: centred in the view while the picture is narrower than it, else kept so
    /// both edges of the view are covered.
    private static func place(_ origin: CGFloat, size: CGFloat, in start: CGFloat, _ length: CGFloat) -> CGFloat {
        if size <= length { return start + (length - size) / 2 }
        return min(max(origin, start + length - size), start)
    }
}
