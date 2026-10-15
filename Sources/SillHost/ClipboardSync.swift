import AppKit
import StreamProtocol

/// The Mac's half of the shared clipboard (kind 29, Clipboard.swift): each copy made on this Mac
/// goes to the connected devices, and each copy a device sends goes on this Mac's clipboard.
///
/// NSPasteboard has no change notification, so its change count is read twice a second while a
/// device is connected (`running`), which costs nothing measurable. What was on the clipboard
/// before is never sent, nor what a device put there (`ClipboardEcho`), nor a copy an app marks as
/// concealed or transient (`ClipboardItem.skips`). Main actor, like NSPasteboard.
@MainActor
package final class ClipboardSync {
    /// A copy made on this Mac, to send to every device.
    package var onCopy: (ClipboardItem) -> Void = { _ in }

    private let pasteboard = NSPasteboard.general
    private var echo = ClipboardEcho()
    private var timer: Timer?

    package init() {}

    /// On while at least one device is connected. Turning it on starts from what is on the
    /// clipboard now, which is not sent.
    package var running = false {
        didSet {
            guard running != oldValue else { return }
            timer?.invalidate()
            timer = nil
            echo = ClipboardEcho()
            guard running else { return }
            _ = echo.looked(at: pasteboard.changeCount)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func poll() {
        guard echo.looked(at: pasteboard.changeCount) else { return }
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

    /// A device's copy (kind 29), put on this Mac's clipboard. `device` names it in the log.
    package func received(_ item: ClipboardItem, from device: String) {
        guard item.fits(toHost: true) else { return }
        pasteboard.clearContents()
        if let text = item.text {
            pasteboard.setString(text, forType: .string)
        } else if let image = item.image {
            pasteboard.setData(image, forType: item.imageType == "jpeg" ? NSPasteboard.PasteboardType("public.jpeg") : .png)
        }
        echo.wrote(pasteboard.changeCount)
        print("Clipboard ← \(device): \(Self.describe(item))")
    }

    /// For the log: the kind and size only, never the content.
    static func describe(_ item: ClipboardItem) -> String {
        if let text = item.text { return "text, \(text.count) characters" }
        return "\(item.imageType ?? "image"), \(item.size / 1024) KB"
    }
}
