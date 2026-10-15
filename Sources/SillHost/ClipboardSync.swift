import AppKit
import StreamProtocol

extension HostConfig {
    /// The shared clipboard's two switches as one rule (Clipboard.swift). Here, not in HostConfig.swift,
    /// which the away-quality check compiles without Clipboard.swift.
    package var clipboardPolicy: ClipboardPolicy {
        ClipboardPolicy(share: shareClipboard, shareAway: shareClipboardAway)
    }
}

/// The Mac's half of the shared clipboard (kind 29, Clipboard.swift): each copy made on this Mac
/// goes to the connected devices that share it, and each copy such a device sends goes on this
/// Mac's clipboard. Who shares is the coordinator's (`ClipboardPolicy`, Settings › General).
///
/// NSPasteboard has no change notification, so its change count is read twice a second while a
/// device that shares is connected (`running`), which costs nothing measurable. What was on the
/// clipboard before sharing started is never sent (`ClipboardWatch`), nor what a device put there
/// (`ClipboardEcho`), nor a copy an app marks as concealed or transient (`ClipboardItem.skips`). A
/// device's copy is cleared from this Mac's clipboard after two minutes if nothing was copied since
/// (`ClipboardExpiry`). Main actor, like NSPasteboard.
@MainActor
package final class ClipboardSync {
    /// A copy made on this Mac, to send to every device that shares.
    package var onCopy: (ClipboardItem) -> Void = { _ in }

    private let pasteboard = NSPasteboard.general
    private var watch = ClipboardWatch()
    private var expiry = ClipboardExpiry()
    private var timer: Timer?

    package init() {}

    /// On while at least one connected device shares the clipboard. Turning it on starts from what is
    /// on the clipboard now, which is not sent.
    package private(set) var running = false

    /// Sharing is `on` (some connected device shares) or not. `restart` also starts over when it
    /// stays on: who shares changed, so the copy on the clipboard now reaches none of them. The
    /// caller polls first (`poll`), so a copy made just before goes to whoever shared it then.
    package func set(running on: Bool, restart: Bool = false) {
        guard on != running || (on && restart) else { return }
        running = on
        watch.start(on: on, count: pasteboard.changeCount)
        guard on != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard on else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reads the change count, and sends a new copy made on this Mac.
    package func poll() {
        guard watch.looked(at: pasteboard.changeCount) else { return }
        let types = pasteboard.types?.map(\.rawValue) ?? []
        if ClipboardItem.skips(types: types) {
            print("Clipboard: a private copy (\(types.first { ClipboardItem.privateTypes.contains($0) } ?? "")), kept on the Mac")
            return
        }
        guard let item = currentItem() else { return }
        guard item.fits(toHost: false) else {
            print("Clipboard: a copy of \(item.size / 1024) KB, too large to send")
            return
        }
        print("Clipboard → devices: \(Self.describe(item))")
        onCopy(item)
    }

    /// Text if there is any, else one image as PNG (a JPEG copy as it is).
    private func currentItem() -> ClipboardItem? {
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return ClipboardItem(text: text) }
        if let png = pasteboard.data(forType: .png) { return ClipboardItem(image: png, type: "png") }
        if let jpeg = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            return ClipboardItem(image: jpeg, type: "jpeg")
        }
        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return ClipboardItem(image: png, type: "png")
        }
        return nil
    }

    /// A device's copy (kind 29), put on this Mac's clipboard for two minutes. `device` names it in
    /// the log. The coordinator calls it only for a connection that shares.
    package func received(_ item: ClipboardItem, from device: String) {
        guard item.fits(toHost: true) else { return }
        pasteboard.clearContents()
        if let text = item.text {
            pasteboard.setString(text, forType: .string)
        } else if let image = item.image {
            pasteboard.setData(image, forType: item.imageType == "jpeg" ? NSPasteboard.PasteboardType("public.jpeg") : .png)
        }
        watch.wrote(pasteboard.changeCount)
        expiry.wrote(pasteboard.changeCount, at: CFAbsoluteTimeGetCurrent())
        print("Clipboard ← \(device): \(Self.describe(item))")
        // One timer per write; an earlier one finds a later count or an early time and does nothing.
        let expire = Timer(timeInterval: ClipboardExpiry.lifetime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expire() }
        }
        expire.tolerance = 1
        RunLoop.main.add(expire, forMode: .common)
    }

    /// Clears a device's copy whose two minutes are up, unless something was copied since.
    private func expire() {
        guard expiry.clears(count: pasteboard.changeCount, now: CFAbsoluteTimeGetCurrent()) else { return }
        pasteboard.clearContents()
        watch.wrote(pasteboard.changeCount)        // the clear is not a copy of this Mac's
        print("Clipboard: a device's copy expired after \(Int(ClipboardExpiry.lifetime / 60)) minutes; cleared")
    }

    /// For the log: the kind and size only, never the content.
    static func describe(_ item: ClipboardItem) -> String {
        if let text = item.text { return "text, \(text.count) characters" }
        return "\(item.imageType ?? "image"), \(item.size / 1024) KB"
    }
}
