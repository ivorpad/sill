import UIKit
import StreamProtocol

/// The device's half of the shared clipboard (kind 29, Clipboard.swift): a copy made on the Mac
/// lands on this device's clipboard for two minutes, and a copy made on this device goes to the Mac
/// the next time Sill comes to the front or connects, only to a Mac whose window list says
/// `clipboard` (which it says only with Settings › General's "Share the clipboard" on, and to a
/// device away from home only with "Also with devices away from home" too). A copy made before the
/// Mac started sharing is never sent (`ClipboardListAction`).
///
/// iOS has no notice of another app's copy, so the device compares the clipboard's change count
/// with the one it saw as Sill went to the background (`clipboardEcho`). Only a new copy is read,
/// which is when iOS asks "Allow Paste" (Settings › Sill › Paste from Other Apps: Allow ends that).
/// What the Mac sent is never sent back. Main thread.
extension StreamClient {
    /// Called once, from init.
    func startClipboardObservers() {
        let center = NotificationCenter.default
        // Leaving: the count as it stands, so a copy made in another app meanwhile shows as new.
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            _ = self.clipboardEcho.looked(at: UIPasteboard.general.changeCount)
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sendClipboardIfNew()
        }
        // A copy made inside Sill itself (the only one iOS announces).
        center.addObserver(forName: UIPasteboard.changedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sendClipboardIfNew()
        }
        _ = clipboardEcho.looked(at: UIPasteboard.general.changeCount)
    }

    /// What a window list's `clipboard` asks (`ClipboardListAction`): send a copy made while there was
    /// no session, or start over from the clipboard as it stands, so a copy made before the Mac
    /// started sharing is never sent. Reads only the change count, which asks nothing of the person.
    func clipboardListed(_ action: ClipboardListAction) {
        switch action {
        case .send: sendClipboardIfNew()
        case .startOver: _ = clipboardEcho.looked(at: UIPasteboard.general.changeCount)
        case .nothing: break
        }
    }

    /// Sends this device's clipboard to the Mac if it changed here since last looked at, and the Mac
    /// takes it. Also on a session's first window list, for a copy made while disconnected.
    func sendClipboardIfNew() {
        guard connected, (hostClipboard ?? 0) >= ClipboardItem.generation else { return }
        let board = UIPasteboard.general
        guard clipboardEcho.looked(at: board.changeCount) else { return }
        // `hasStrings` and `hasImages` ask nothing of the person; reading the value is what iOS
        // asks about, and only happens for a copy that is new.
        let item: ClipboardItem?
        if board.hasStrings, let text = board.string, !text.isEmpty {
            item = ClipboardItem(text: text)
        } else if board.hasImages, let image = board.image {
            item = Self.clipboardImage(image)
        } else {
            item = nil
        }
        guard let item else { return }
        guard item.fits(toHost: true) else {
            print("clipboard: a copy of \(item.size / 1024) KB, too large for the Mac")
            return
        }
        print("clipboard → Mac: " + (item.text != nil ? "text, \(item.text!.count) characters" : "\(item.imageType ?? ""), \(item.size / 1024) KB"))
        let payload = Wire.encode(item)
        queue.async { [weak self] in self?.send(.clipboard, payload: payload) }
    }

    /// A copy from the Mac (kind 29, on the network queue): onto this device's clipboard, for two
    /// minutes (`ClipboardExpiry.lifetime`) and this device only: `localOnly` keeps Universal
    /// Clipboard from carrying it on to the person's other devices.
    func receiveClipboard(_ data: Data) {
        guard let item = Wire.decode(ClipboardItem.self, from: data), item.fits(toHost: false) else { return }
        let from = connection
        DispatchQueue.main.async {
            guard self.connection === from else { return }
            let board = UIPasteboard.general
            let entry: [String: Any]
            if let text = item.text {
                entry = ["public.utf8-plain-text": text]
            } else if let image = item.image {
                entry = [item.imageType == "jpeg" ? "public.jpeg" : "public.png": image]
            } else {
                return
            }
            board.setItems([entry], options: [.expirationDate: Date(timeIntervalSinceNow: ClipboardExpiry.lifetime),
                                              .localOnly: true])
            self.clipboardEcho.wrote(board.changeCount)
            print("clipboard ← Mac: " + (item.text != nil ? "text, \(item.text!.count) characters" : "\(item.imageType ?? ""), \(item.size / 1024) KB"))
        }
    }

    /// An image for the Mac under `ClipboardItem.maxToHostBytes`: PNG when it fits, else JPEG,
    /// scaled down until it does. Nil if even a small one does not.
    static func clipboardImage(_ image: UIImage) -> ClipboardItem? {
        if let png = image.pngData(), png.count <= ClipboardItem.maxToHostBytes { return ClipboardItem(image: png, type: "png") }
        var current = image
        for _ in 0..<6 {
            if let jpeg = current.jpegData(compressionQuality: 0.8), jpeg.count <= ClipboardItem.maxToHostBytes {
                return ClipboardItem(image: jpeg, type: "jpeg")
            }
            let size = CGSize(width: current.size.width * 0.7, height: current.size.height * 0.7)
            guard size.width >= 16, size.height >= 16 else { return nil }
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            current = UIGraphicsImageRenderer(size: size, format: format).image { _ in current.draw(in: CGRect(origin: .zero, size: size)) }
        }
        return nil
    }
}
