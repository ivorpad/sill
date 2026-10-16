import SwiftUI
import Combine
import StreamProtocol

/// The Aa control: a bar button that opens into a ruler while the finger is down, the way the
/// camera's zoom button opens into its dial and the Dynamic Island timer scrubs. The thumb stays
/// put at the button's centre and the ruler slides under it: five detents, 0.5× to 1.5× in 0.25
/// steps, a tick of haptic at each. The bar fades the buttons next to it while `open` and brings
/// them back on release, when the chosen value is applied once (every change restarts the stream,
/// so nothing is sent mid-drag). A nil scale means the Mac window has never been asked to fit; it
/// shows 1×.
struct TextScaleControl: View {
    @Binding var scale: Double?
    @Binding var open: Bool
    var width: CGFloat = 66
    var height: CGFloat = 66
    var radius: CGFloat = 16
    /// Finger travel (and ruler spacing) per detent; smaller in the tighter bars so the ruler,
    /// centred on the button, stays inside the screen.
    var pointsPerStep: CGFloat = 44
    /// A fixed height for "Aa", and the space under it, so its value lines up with the labels of
    /// bar buttons whose symbols sit in a box of that height (a phone's row 1); nil: as tall as the
    /// text, 2 pt over the value (every bar that has always had it).
    var iconBox: CGFloat? = nil
    var iconSpacing: CGFloat = 2

    static let steps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]
    /// Padding either side of the visible ruler; two detents show each side of the thumb.
    static let sliderInset: CGFloat = 30
    var sliderWidth: CGFloat { pointsPerStep * CGFloat(Self.steps.count - 1) + Self.sliderInset * 2 }

    @State private var live: Double = 1.0
    @State private var startValue: Double = 1.0
    @State private var startX: CGFloat = 0

    var body: some View {
        VStack(spacing: iconBox == nil ? 2 : iconSpacing) {
            if let iconBox {
                Text("Aa")
                    .font(.system(size: height >= 60 ? 19 : 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(height: iconBox)
            } else {
                Text("Aa")
                    .font(.system(size: height >= 60 ? 19 : 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
            Text(Self.label(scale ?? 1.0) + "×")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.barLabel)
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.control))
        .opacity(open ? 0 : 1)
        .overlay {
            // Centred on the button: the thumb is where the finger came down.
            slider
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.6)
                .allowsHitTesting(false)
        }
        .zIndex(open ? 1 : 0)
        .onChange(of: open, initial: true) { _, isOpen in if isOpen { live = scale ?? 1.0 } }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    if !open {
                        startValue = scale ?? 1.0
                        live = startValue
                        startX = g.location.x
                        withAnimation(.spring(duration: 0.22, bounce: 0.15)) { open = true }
                    }
                    // The ruler follows the finger: dragging right raises the value, and the ticks
                    // slide left under the fixed thumb.
                    let dx = g.location.x - startX
                    let snapped = Self.snap(startValue + Double(dx / pointsPerStep) * 0.25)
                    if snapped != live {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.1)) { live = snapped }
                    }
                }
                .onEnded { _ in
                    if (scale ?? 1.0) != live { scale = live }     // a plain tap on an untouched control changes nothing
                    withAnimation(.easeOut(duration: 0.2)) { open = false }
                }
        )
        .onDisappear { open = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text size")
        .accessibilityValue("\(Self.label(scale ?? 1.0)) times")
        .accessibilityAdjustableAction { direction in
            let i = Self.steps.firstIndex(of: scale ?? 1.0) ?? 2
            switch direction {
            case .increment: scale = Self.steps[min(i + 1, Self.steps.count - 1)]
            case .decrement: scale = Self.steps[max(i - 1, 0)]
            @unknown default: break
            }
        }
    }

    /// The ruler: a track with five ticks and labels that slides so the live value sits under the
    /// fixed thumb; the ends fade out where they run past the panel.
    private var slider: some View {
        let w = sliderWidth
        let step = pointsPerStep
        let midX = w / 2
        let midY = height / 2 + 4
        func x(_ value: Double) -> CGFloat { midX + CGFloat((value - live) / 0.25) * step }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.controlOpen)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.barLabel.opacity(0.35))
                    .frame(width: step * CGFloat(Self.steps.count - 1), height: 3)
                    .offset(x: x(Self.steps[0]), y: midY - 1.5)
                ForEach(Self.steps, id: \.self) { value in
                    Rectangle().fill(Palette.barLabel.opacity(0.6))
                        .frame(width: 2, height: 9)
                        .offset(x: x(value) - 1, y: midY - 4.5)
                    Text(Self.label(value))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(value == live ? Palette.text : Palette.barLabel)
                        .frame(width: step, alignment: .center)
                        .offset(x: x(value) - step / 2, y: midY + 9)
                }
            }
            .frame(width: w, height: height, alignment: .topLeading)   // the mask below is sized to this
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            Circle().fill(Palette.accent)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .offset(x: midX - 11, y: midY - 11)
            // The live value over the thumb, where the finger does not cover it. In a 50 pt ruler
            // (a phone's row 1, the compact window bar) `midY - 34` put the top of its digits 2 pt
            // outside the clip; it sits where the 58 pt bars put it (1 pt above the frame's top,
            // the digits 2 pt inside), and in the taller bars as it always has.
            Text(Self.label(live) + "×")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 60, alignment: .center)
                .offset(x: midX - 30, y: max(midY - 34, -1))
        }
        .frame(width: w, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Nearest detent, clamped to the ends.
    static func snap(_ value: Double) -> Double {
        let clamped = min(max(value, steps[0]), steps[steps.count - 1])
        return steps.min { abs($0 - clamped) < abs($1 - clamped) } ?? 1.0
    }

    /// 0.5, 0.75, 1, 1.25, 1.5: trailing zeros dropped, and "1" rather than "1.0".
    static func label(_ scale: Double) -> String {
        var text = String(format: "%.2f", scale)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
