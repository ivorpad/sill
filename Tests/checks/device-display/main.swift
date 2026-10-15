import CoreGraphics
import Foundation

// DeviceDisplayGeometry (Sources/SillHost/DeviceDisplayGeometry.swift), compiled on its own:
//   swiftc -O -package-name sill Sources/SillHost/DeviceDisplayGeometry.swift Tests/checks/device-display/main.swift -o check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias G = DeviceDisplayGeometry
func g(_ w: Double, _ h: Double, ps: Double? = 2, aa: Double? = nil) -> G? {
    G(panelWidth: w, panelHeight: h, pixelScale: ps, textScale: aa)
}
func size(_ x: G?) -> String { x.map { "\($0)" } ?? "nil" }
func pts(_ x: G?) -> [Int] { x.map { [$0.widthPt, $0.heightPt] } ?? [] }
func px(_ x: G?) -> [Int] { x.map { [$0.pixelWidth, $0.pixelHeight] } ?? [] }
func enc(_ x: G?) -> [Int] { x.map { [$0.encodeWidth, $0.encodeHeight] } ?? [] }

// MARK: The plan's table (docs/sidecar-desktop-plan.md), at Default

// The iPad Pro 12.9" under the bar: its own points, 2× pixels, encoded 1:1.
let ipad = g(1366, 940)
check(pts(ipad) == [1366, 940], "iPad Pro: 1366×940 pt (\(size(ipad)))")
check(px(ipad) == [2732, 1880], "iPad Pro: 2732×1880 px (\(size(ipad)))")
check(enc(ipad) == [2732, 1880], "iPad Pro: encoded at the panel's pixels (\(size(ipad)))")
check(ipad?.panelPixelWidth == 2732 && ipad?.panelPixelHeight == 1880, "iPad Pro: the panel's pixels (\(size(ipad)))")
check(G.scale == 2, "every device display is 2×")
// The iPad mini.
check(pts(g(1133, 660)) == [1133, 660] && enc(g(1133, 660)) == [2266, 1320], "iPad mini: 1133×660 pt, 2266×1320 (\(size(g(1133, 660))))")
// A 3× iPhone: a 2× display at the panel's pixels ÷ 2, so 1.5× the iPhone's points, still 1:1.
let phone = g(956, 360, ps: 3)
check(pts(phone) == [1434, 540], "iPhone 3×: 1434×540 pt (\(size(phone)))")
check(px(phone) == [2868, 1080] && enc(phone) == [2868, 1080], "iPhone 3×: 2868×1080 px, encoded 1:1 (\(size(phone)))")
check(phone?.panelPixelWidth == 2868 && phone?.panelPixelHeight == 1080, "iPhone 3×: the panel's pixels (\(size(phone)))")
// A 2× iPhone (an iPhone 11): its own points.
check(pts(g(896, 360, ps: 2)) == [896, 360], "iPhone 2×: its own points (\(size(g(896, 360, ps: 2))))")
// Portrait: the same rule, the other way round.
check(pts(g(940, 1366)) == [940, 1366] && enc(g(940, 1366)) == [1880, 2732], "portrait iPad (\(size(g(940, 1366))))")
check(pts(g(360, 956, ps: 3)) == [540, 1434], "portrait iPhone (\(size(g(360, 956, ps: 3))))")

// MARK: Default is nil or 1

check(g(1366, 940, aa: 1) == ipad, "Aa 1 is Default")
check(g(1366, 940, aa: nil) == ipad, "Aa nil (Off) is Default")
check(g(1366, 940, aa: 0) == ipad && g(1366, 940, aa: -1) == ipad, "Aa 0 or below is Default")
check(g(1366, 940, aa: .nan) == ipad && g(1366, 940, aa: .infinity) == ipad, "Aa not a number is Default")

// MARK: More Space: a larger display, scaled down to the panel's pixels

let half = g(1366, 940, aa: 0.5)
check(pts(half) == [2732, 1880], "More Space 0.5: twice the points (\(size(half)))")
check(px(half) == [5464, 3760], "More Space 0.5: 5464×3760 px (\(size(half)))")
check(enc(half) == [2732, 1880], "More Space 0.5: encoded at the panel's pixels (\(size(half)))")
let threeQ = g(1366, 940, aa: 0.75)
check(pts(threeQ) == [1821, 1253], "More Space 0.75: points ÷ 0.75, rounded down (\(size(threeQ)))")
check(enc(threeQ) == [2732, 1878], "More Space 0.75: one factor for both sides, even (\(size(threeQ)))")
let phoneHalf = g(956, 360, ps: 3, aa: 0.5)
check(pts(phoneHalf) == [2868, 1080] && enc(phoneHalf) == [2868, 1080], "iPhone More Space 0.5 (\(size(phoneHalf)))")

// MARK: Larger Text: a smaller display, sent at its own pixels

let big = g(1366, 940, aa: 1.5)
check(pts(big) == [910, 626], "Larger Text 1.5: points ÷ 1.5, rounded down (\(size(big)))")
check(enc(big) == [1820, 1252], "Larger Text 1.5: the display's own pixels, not scaled up (\(size(big)))")
let bigQ = g(1366, 940, aa: 1.25)
check(pts(bigQ) == [1092, 752] && enc(bigQ) == [2184, 1504], "Larger Text 1.25 (\(size(bigQ)))")
// Aa is clamped to 0.5…2.
check(g(1366, 940, aa: 0.1) == half, "Aa 0.1 is clamped to 0.5")
check(pts(g(1366, 940, aa: 5)) == [683, 470], "Aa 5 is clamped to 2 (\(size(g(1366, 940, aa: 5))))")
check(pts(g(1366, 940, aa: 2)) == [683, 470], "Aa 2 (\(size(g(1366, 940, aa: 2))))")

// MARK: The pixel scale

check(g(1366, 940, ps: nil) == ipad, "no pixel scale counts as 2")
check(g(1366, 940, ps: .nan) == ipad, "a pixel scale not a number counts as 2")
check(pts(g(1366, 940, ps: 1)) == [683, 470], "1×: a 2× display at the panel's pixels ÷ 2 (\(size(g(1366, 940, ps: 1))))")
check(g(1366, 940, ps: 0.5) == g(1366, 940, ps: 1), "a pixel scale under 1 is clamped to 1")
check(g(1000, 700, ps: 10) == g(1000, 700, ps: 4), "a pixel scale over 4 is clamped to 4")
check(pts(g(1000, 700, ps: 4)) == [2000, 1400], "4×: 2000×1400 pt (\(size(g(1000, 700, ps: 4))))")

// MARK: Rounding

// A panel measured a hair under a whole point rounds to its pixels, not down a pixel.
check(pts(g(693.99, 500)) == [694, 500], "693.99 pt at 2× is 1388 px, 694 pt (\(size(g(693.99, 500))))")
// An odd pixel count: the display's points are rounded down, never past the panel.
let odd = g(1366.5, 940.5)
check(pts(odd) == [1366, 940] && enc(odd) == [2732, 1880], "an odd 2733×1881 px panel (\(size(odd)))")
check(odd?.panelPixelWidth == 2733 && odd?.panelPixelHeight == 1881, "its panel pixels (\(size(odd)))")

// MARK: Bounds

// The longest side at most 4096 pt (8192 px), the shape kept.
let huge = g(5000, 3000)
check(pts(huge) == [4096, 2457], "a 10000×6000 px panel: 4096×2457 pt (\(size(huge)))")
check(enc(huge) == [8192, 4914], "and its pixels (\(size(huge)))")
check(pts(g(3000, 5000)) == [2457, 4096], "the same, portrait (\(size(g(3000, 5000))))")
check(pts(g(4096, 1000)) == [4096, 1000], "exactly 4096 pt is kept (\(size(g(4096, 1000))))")
// The floor, 320×240, the shape kept, encoded no larger than the panel.
let tiny = g(100, 80)
check(pts(tiny) == [320, 256], "a 200×160 px panel: up to 320×256 pt (\(size(tiny)))")
check(enc(tiny) == [200, 160], "encoded at the panel's pixels (\(size(tiny)))")
check(pts(g(320, 240)) == [320, 240], "exactly the floor is kept (\(size(g(320, 240))))")
check(pts(g(80, 100)) == [320, 400], "a narrow one: width to the floor (\(size(g(80, 100))))")
// Too long for both: side by side.
check(pts(g(8000, 50, ps: 1)) == [4096, 240], "8000×50 at 1×: 4096×240 (\(size(g(8000, 50, ps: 1))))")
check(pts(g(50, 8000, ps: 1)) == [320, 4096], "50×8000 at 1×: 320×4096 (\(size(g(50, 8000, ps: 1))))")

// MARK: No size, no display

check(g(0, 940) == nil && g(1366, 0) == nil, "a zero side")
check(g(-1366, 940) == nil && g(1366, -940) == nil, "a negative side")
check(g(.nan, 940) == nil && g(1366, .infinity) == nil, "a side not a number")

// MARK: Every size on a grid: bounds, even, never past the panel or the display

var gridProblems = 0
for w in stride(from: 50.0, through: 6000, by: 97.3) {
    for h in stride(from: 40.0, through: 6000, by: 131.7) {
        for ps in [1.0, 2.0, 3.0] {
            for aa in [nil, 0.5, 0.75, 1.0, 1.25, 1.5] as [Double?] {
                guard let x = g(w, h, ps: ps, aa: aa) else { gridProblems += 1; continue }
                let bad = x.widthPt < G.minWidth || x.heightPt < G.minHeight || x.widthPt > G.maxSide || x.heightPt > G.maxSide
                    || x.encodeWidth % 2 != 0 || x.encodeHeight % 2 != 0
                    || x.encodeWidth > x.pixelWidth || x.encodeHeight > x.pixelHeight
                    || x.encodeWidth > max(2, x.panelPixelWidth) || x.encodeHeight > max(2, x.panelPixelHeight)
                if bad {
                    gridProblems += 1
                    if gridProblems < 4 { print("  grid: \(w)×\(h) @\(ps) Aa \(aa.map { "\($0)" } ?? "nil"): \(x)") }
                }
            }
        }
    }
}
check(gridProblems == 0, "a grid of panels: \(gridProblems) out of bounds, odd or past the panel")

// MARK: Capacity: one display for every rotation and Aa step

check(G.capacitySide(panelWidth: 1366, panelHeight: 940, pixelScale: 2) == 2732, "iPad Pro: a 2732 pt square (More Space 0.5)")
check(G.capacitySide(panelWidth: 940, panelHeight: 1366, pixelScale: 2) == 2732, "iPad Pro held upright: the same square")
check(G.capacitySide(panelWidth: 956, panelHeight: 360, pixelScale: 3) == 2868, "iPhone 3×: 2868 pt")
check(G.capacitySide(panelWidth: 5000, panelHeight: 3000, pixelScale: 2) == 4096, "never past the longest side")
check(G.capacitySide(panelWidth: 0, panelHeight: 3000, pixelScale: 2) == nil, "no size, no capacity")
let side = G.capacitySide(panelWidth: 1366, panelHeight: 940, pixelScale: 2) ?? 0
var fitsAll = true
for aa in [nil, 0.5, 0.75, 1.0, 1.25, 1.5] as [Double?] {
    for (w, h) in [(1366.0, 940.0), (940.0, 1366.0)] {
        if let x = g(w, h, aa: aa), !x.fits(side: side) { fitsAll = false; print("  does not fit \(side): \(x)") }
    }
}
check(fitsAll, "every Aa step, either way round, fits the iPad's capacity")
check(ipad?.fits(side: 1366) == true && ipad?.fits(side: 1365) == false, "fits: up to the side, not past it")
check(g(940, 1366)?.fits(side: 1366) == true && g(940, 1366)?.fits(side: 1365) == false, "fits: either side counts")

// MARK: The serial

let fpA = Data((0..<32).map { UInt8($0) }), fpB = Data((0..<32).map { UInt8(255 - $0) })
check(G.serial(fingerprint: nil) == G.unpairedSerial, "no key: the unpaired serial")
check(G.serial(fingerprint: Data()) == G.unpairedSerial, "an empty key: the unpaired serial")
check(G.unpairedSerial == 1, "the unpaired serial is 1")
check(G.serial(fingerprint: fpA) == G.serial(fingerprint: fpA), "the same key, the same serial")
check(G.serial(fingerprint: fpA) != G.serial(fingerprint: fpB), "two keys, two serials")
// FNV-1a 32 of these bytes is 0 and 1 (found by working back from the end): moved past both.
let zero = Data([204, 36, 49, 196, 0]), one = Data([252, 24, 187, 95, 0])
check(G.serial(fingerprint: zero) == 2, "a key hashing to 0 gets 2, never 0 (\(G.serial(fingerprint: zero)))")
check(G.serial(fingerprint: one) == 3, "a key hashing to 1 gets 3, never the unpaired serial (\(G.serial(fingerprint: one)))")
// FNV-1a's own value for one byte, so the hash stays the one shipped (macOS remembers by it).
check(G.serial(fingerprint: Data([0x61])) == 0xE40C_292C, "FNV-1a of \"a\" (\(String(G.serial(fingerprint: Data([0x61])), radix: 16)))")
var serialProblems = 0
for i in 0..<5000 {
    let s = G.serial(fingerprint: Data([UInt8(i & 0xFF), UInt8(i >> 8), 7]))
    if s == 0 || s == G.unpairedSerial { serialProblems += 1 }
}
check(serialProblems == 0, "5,000 keys: \(serialProblems) with 0 or the unpaired serial")

print(failures == 0 ? "ok: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
