import CoreGraphics
import Foundation

/// The size of a display for one device (docs/sidecar-desktop-plan.md): a HiDPI virtual display
/// whose pixels are the pixels of the device's picture panel, so the Desktop streams 1:1.
///
/// From the device's viewport: the panel in device points, the device's pixel scale (2 on iPads, 3
/// on most iPhones) and its Aa text scale. The display is always 2× (macOS offers no 3× mode), at
/// the panel's pixels ÷ 2 in points. On a 2× iPad that is the panel's own points; on a 3× iPhone it
/// is 1.5× the panel's points, so the Mac's UI draws 1.5× bigger than the iPhone's and still 1:1 in
/// pixels.
///
/// Aa: Default (nil or 1) is 1:1. More Space (below 1) divides the points by it, a larger display
/// whose pixels are more than the panel's; Larger Text (above 1) a smaller one. The encoded size is
/// the display's pixels, never more than the panel's: More Space is scaled down on the Mac (what
/// ScreenCaptureKit's output size does), Larger Text is sent at the display's own pixels and the
/// device scales it up as it fits every picture.
///
/// Pure: the coordinator's DeviceDisplay takes its mode from here. Checked by
/// Tests/checks/device-display.
package struct DeviceDisplayGeometry: Equatable, CustomStringConvertible {
    /// The display's size in points: what windows see and what the mode is made of.
    package let widthPt: Int
    package let heightPt: Int
    /// The panel's pixels, as the device draws them.
    package let panelPixelWidth: Int
    package let panelPixelHeight: Int
    /// The encoded frame: the display's pixels, scaled down to the panel's when larger. Even, as
    /// HEVC's 4:2:0 wants.
    package let encodeWidth: Int
    package let encodeHeight: Int

    /// Every device display is HiDPI 2×: `setHiDPI:` is a flag, and no 3× mode exists (probe P1c).
    package static let scale = 2
    /// VirtualDisplay's floor in points (its guard), and the longest side: 4096 pt keeps the 2×
    /// backing store at or under 8192 px, VirtualDisplay's and the encoder's ceiling (VirtualStage's
    /// maxSide, for the same reason).
    package static let minWidth = 320
    package static let minHeight = 240
    package static let maxSide = 4096
    /// A device that sent no pixel scale (none does that asks for a display) counts as an iPad's.
    package static let assumedPixelScale = 2.0
    /// The device's pixel scale is taken within this; anything outside it is clamped.
    package static let pixelScaleRange = 1.0...4.0
    /// The Aa steps the device offers run from 0.5 to 1.5; a value outside this is clamped.
    package static let textScaleRange = 0.5...2.0
    /// The serial of a session with no paired key: one display for every unpaired device.
    package static let unpairedSerial: UInt32 = 1

    package var pixelWidth: Int { widthPt * Self.scale }
    package var pixelHeight: Int { heightPt * Self.scale }

    /// Nil when the panel has no size (zero, negative, not a number).
    package init?(panelWidth: Double, panelHeight: Double, pixelScale: Double?, textScale: Double?) {
        guard panelWidth.isFinite, panelHeight.isFinite, panelWidth > 0, panelHeight > 0 else { return nil }
        let ps = Self.clampedPixelScale(pixelScale)
        let aa = Self.clampedTextScale(textScale)
        let pxW = max(1, Int((panelWidth * ps).rounded()))
        let pxH = max(1, Int((panelHeight * ps).rounded()))
        // The panel's pixels ÷ 2 in points, then Aa: More Space (below 1) a larger display.
        let wantW = Double(pxW) / Double(Self.scale) / aa
        let wantH = Double(pxH) / Double(Self.scale) / aa
        let (w, h) = Self.fit(wantW, wantH)
        widthPt = w
        heightPt = h
        panelPixelWidth = pxW
        panelPixelHeight = pxH
        // Never more than the panel's pixels: one factor for both sides, so the picture keeps its shape.
        let f = min(1, Double(pxW) / Double(w * Self.scale), Double(pxH) / Double(h * Self.scale))
        encodeWidth = Self.even(Double(w * Self.scale) * f)
        encodeHeight = Self.even(Double(h * Self.scale) * f)
    }

    /// The side, in points, of the square that holds every mode this panel can ask for: either way
    /// round and at the smallest Aa. The display's `maxPixels` are made for it, so a rotation or an
    /// Aa step re-modes the display instead of making a new one.
    package static func capacitySide(panelWidth: Double, panelHeight: Double, pixelScale: Double?) -> Int? {
        guard let g = DeviceDisplayGeometry(panelWidth: panelWidth, panelHeight: panelHeight, pixelScale: pixelScale,
                                            textScale: textScaleRange.lowerBound) else { return nil }
        return max(g.widthPt, g.heightPt)
    }

    /// Whether this mode fits a display made for `side` (`capacitySide`) both ways.
    package func fits(side: Int) -> Bool { widthPt <= side && heightPt <= side }

    /// A stable serial per paired key, so macOS remembers where the user put each device's display
    /// (System Settings › Displays keeps one entry per vendor, product and serial). FNV-1a over the
    /// key's fingerprint; never 0, and never the unpaired serial. No key: `unpairedSerial`.
    package static func serial(fingerprint: Data?) -> UInt32 {
        guard let fingerprint, !fingerprint.isEmpty else { return unpairedSerial }
        var h: UInt32 = 0x811C_9DC5
        for byte in fingerprint {
            h ^= UInt32(byte)
            h = h &* 0x0100_0193
        }
        return h <= unpairedSerial ? h &+ 2 : h
    }

    package var description: String {
        "\(widthPt)×\(heightPt) pt @\(Self.scale)× (\(pixelWidth)×\(pixelHeight) px), encoded \(encodeWidth)×\(encodeHeight)"
    }

    // MARK: Rules

    static func clampedPixelScale(_ s: Double?) -> Double {
        guard let s, s.isFinite else { return assumedPixelScale }
        return min(max(s, pixelScaleRange.lowerBound), pixelScaleRange.upperBound)
    }

    /// Nil, zero, negative or not a number: Default (1).
    static func clampedTextScale(_ s: Double?) -> Double {
        guard let s, s.isFinite, s > 0 else { return 1 }
        return min(max(s, textScaleRange.lowerBound), textScaleRange.upperBound)
    }

    /// Whole points within the bounds, the shape kept where it can be: one factor down to fit the
    /// longest side, or up to reach the floor; a shape too long for both is clamped side by side.
    /// Rounded down, so the display never has more pixels than asked.
    static func fit(_ w: Double, _ h: Double) -> (Int, Int) {
        var k = 1.0
        let longest = max(w, h)
        if longest > Double(maxSide) { k = Double(maxSide) / longest }
        if w * k < Double(minWidth) || h * k < Double(minHeight) {
            k = max(Double(minWidth) / w, Double(minHeight) / h)
        }
        let fw = Int((w * k).rounded(.down)), fh = Int((h * k).rounded(.down))
        return (min(max(fw, minWidth), maxSide), min(max(fh, minHeight), maxSide))
    }

    /// Even and at least 2: HEVC 4:2:0 wants even sizes.
    static func even(_ v: Double) -> Int { max(2, Int(v.rounded(.down)) & ~1) }
}
