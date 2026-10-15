// TouchTrace (Tests/evidence/README.md): every raw UITouch the glass reports, one JSONL record per
// touch per event, labelled with the gesture the owner is performing from a fixed script (G1...).
// Evidence only: never linked into Sill. One full-screen view, portrait, the home indicator hidden
// and the system's edge gestures deferred, so the bottom-edge gestures reach the app where iOS
// allows it (a touch iOS takes anyway arrives as `cancelled`, which is itself evidence).
//
// Records (Documents/touchtrace-<wall time>.jsonl, `latest.txt` names the newest):
//   {"k":"session", ...}   once: view size, scale, model, OS, the script, uptime and wall clock
//   {"k":"gesture", ...}   each time the label changes (the hold buttons at the top)
//   {"k":"touch", ...}     one per touch per touch event, plus `coalesced: true` records for the
//                          samples UIKit coalesced into that event (the 120 Hz ones)
// `t` is UITouch.timestamp (seconds of system uptime, monotonic); `id` is this app's counter, given
// at `began` and dropped at `ended`/`cancelled`, since UITouch objects are reused.
import UIKit

let script: [(String, String)] = [
    ("G1", "Pointer: one finger, slow, across the middle"),
    ("G2", "Pointer: one finger, fast, across the middle"),
    ("G3", "Pointer: one finger to the TOP edge"),
    ("G4", "Pointer: one finger to the BOTTOM edge"),
    ("G5", "Pointer: one finger to the LEFT edge"),
    ("G6", "Pointer: one finger to the RIGHT edge"),
    ("G7", "One-finger tap, 5 times, 1 s apart"),
    ("G8", "Pinch IN, slow"),
    ("G9", "Pinch OUT, slow"),
    ("G10", "Pinch IN, fast"),
    ("G11", "Pinch OUT, fast"),
    ("G12", "Pinch, then pan with both fingers down"),
    ("G13", "Two-finger double tap, 5 times"),
    ("G14", "Near miss: SLOW two-finger double tap (about 0.6 s between)"),
    ("G15", "Near miss: two-finger double tap, fingers FAR apart"),
    ("G16", "Near miss: two-finger SINGLE tap, 5 times"),
    ("G17", "Near miss: two-finger scroll, up and down"),
    ("G18", "Bottom edge: rest one finger there 1 s, lift"),
    ("G19", "Bottom edge: pass along it without stopping"),
    ("G20", "Bottom edge: drag down off the bottom"),
    ("G21", "Palm or edge graze: brush the side of the screen"),
]

final class TraceLog {
    static let shared = TraceLog()
    private var handle: FileHandle?
    private(set) var fileName = ""
    private var nextID = 1
    private var ids: [ObjectIdentifier: Int] = [:]
    private(set) var gesture = 0

    func open(view: UIView) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        fileName = "touchtrace-\(stamp).jsonl"
        let url = docs.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        try? fileName.write(to: docs.appendingPathComponent("latest.txt"), atomically: true, encoding: .utf8)
        var sys = utsname(); uname(&sys)
        let model = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let screen = view.window?.screen ?? UIScreen.main
        write([
            "k": "session", "uptime": ProcessInfo.processInfo.systemUptime,
            "wall": ISO8601DateFormatter().string(from: Date()), "wallEpoch": Date().timeIntervalSince1970,
            "viewW": view.bounds.width, "viewH": view.bounds.height,
            "scale": screen.scale, "nativeScale": screen.nativeScale,
            "maxFPS": screen.maximumFramesPerSecond,
            "model": model, "os": UIDevice.current.systemVersion,
            "script": script.map { ["id": $0.0, "text": $0.1] },
        ])
    }

    func setGesture(_ index: Int) {
        gesture = index
        write(["k": "gesture", "uptime": ProcessInfo.processInfo.systemUptime,
               "g": script[index].0, "text": script[index].1])
    }

    func log(_ touch: UITouch, in view: UIView, coalesced: Bool, ownerID: Int) {
        let p = touch.location(in: view), q = touch.previousLocation(in: view)
        var r: [String: Any] = [
            "k": "touch", "t": touch.timestamp, "g": script[gesture].0, "id": ownerID,
            "phase": Self.phase(touch.phase), "type": Self.kind(touch.type),
            "x": p.x, "y": p.y, "px": q.x, "py": q.y,
            "r": touch.majorRadius, "rTol": touch.majorRadiusTolerance,
            "force": touch.force, "maxForce": touch.maximumPossibleForce, "taps": touch.tapCount,
        ]
        if coalesced { r["coalesced"] = true }
        write(r)
    }

    /// The app's id for a touch: new at `began`, forgotten after `ended` or `cancelled`.
    func id(for touch: UITouch) -> Int {
        let key = ObjectIdentifier(touch)
        if touch.phase == .began || ids[key] == nil { ids[key] = nextID; nextID += 1 }
        return ids[key]!
    }

    func forget(_ touch: UITouch) {
        if touch.phase == .ended || touch.phase == .cancelled { ids[ObjectIdentifier(touch)] = nil }
    }

    func write(_ record: [String: Any]) {
        guard let handle, var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        handle.write(data)
    }

    func flush() { try? handle?.synchronize() }

    static func phase(_ p: UITouch.Phase) -> String {
        switch p {
        case .began: return "began"
        case .moved: return "moved"
        case .stationary: return "stationary"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .regionEntered: return "regionEntered"
        case .regionMoved: return "regionMoved"
        case .regionExited: return "regionExited"
        @unknown default: return "unknown\(p.rawValue)"
        }
    }

    static func kind(_ t: UITouch.TouchType) -> String {
        switch t {
        case .direct: return "direct"
        case .indirect: return "indirect"
        case .pencil: return "pencil"
        case .indirectPointer: return "indirectPointer"
        @unknown default: return "unknown\(t.rawValue)"
        }
    }
}

/// Sees every touch before any view does. Touches on the top bar (the gesture buttons) are left out.
final class TraceWindow: UIWindow {
    weak var canvas: UIView?
    weak var excluded: UIView?

    override func sendEvent(_ event: UIEvent) {
        if event.type == .touches, let canvas, let touches = event.allTouches {
            let log = TraceLog.shared
            for touch in touches {
                if let v = touch.view, let excluded, v.isDescendant(of: excluded) { continue }
                let id = log.id(for: touch)
                let samples = event.coalescedTouches(for: touch) ?? []
                for sample in samples.dropLast() { log.log(sample, in: canvas, coalesced: true, ownerID: id) }
                log.log(touch, in: canvas, coalesced: false, ownerID: id)
                log.forget(touch)
            }
        }
        super.sendEvent(event)
    }
}

final class TraceController: UIViewController {
    private let label = UILabel()
    private let bar = UIView()
    private let counter = UILabel()

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true

        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 34, weight: .bold)
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        let prev = holdButton("◀ hold", action: #selector(previous(_:)))
        let next = holdButton("hold ▶", action: #selector(advance(_:)))
        counter.textColor = .lightGray
        counter.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        counter.textAlignment = .center
        counter.translatesAutoresizingMaskIntoConstraints = false
        [prev, next, counter].forEach(bar.addSubview)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 56),
            prev.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            prev.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            prev.widthAnchor.constraint(equalToConstant: 88), prev.heightAnchor.constraint(equalToConstant: 44),
            next.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            next.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            next.widthAnchor.constraint(equalToConstant: 88), next.heightAnchor.constraint(equalToConstant: 44),
            counter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            counter.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
        ])
    }

    private var opened = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !opened else { return }
        opened = true
        UIApplication.shared.isIdleTimerDisabled = true
        if let window = view.window as? TraceWindow { window.canvas = view; window.excluded = bar }
        TraceLog.shared.open(view: view)
        show(0)
    }

    private func holdButton(_ title: String, action: Selector) -> UIView {
        let b = UILabel()
        b.text = title
        b.textAlignment = .center
        b.textColor = .white
        b.backgroundColor = UIColor(white: 0.25, alpha: 1)
        b.layer.cornerRadius = 10
        b.clipsToBounds = true
        b.isUserInteractionEnabled = true
        b.translatesAutoresizingMaskIntoConstraints = false
        let hold = UILongPressGestureRecognizer(target: self, action: action)
        hold.minimumPressDuration = 1
        b.addGestureRecognizer(hold)
        return b
    }

    private func show(_ index: Int) {
        TraceLog.shared.setGesture(index)
        TraceLog.shared.flush()
        label.text = "\(script[index].0)\n\(script[index].1)"
        counter.text = "\(index + 1)/\(script.count)  \(TraceLog.shared.fileName.dropFirst(11).prefix(15))"
    }

    @objc private func advance(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        show(min(TraceLog.shared.gesture + 1, script.count - 1))
    }

    @objc private func previous(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        show(max(TraceLog.shared.gesture - 1, 0))
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = TraceWindow(windowScene: scene)
        window.rootViewController = TraceController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidEnterBackground(_ scene: UIScene) { TraceLog.shared.flush() }
    func sceneWillResignActive(_ scene: UIScene) { TraceLog.shared.flush() }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
