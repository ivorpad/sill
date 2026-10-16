import Foundation
import SillHostCore
import StreamProtocol

// The canned states -SillRenderPreviews draws for the update check and for Remote Access and pairing
// (DebugHooks.swift keeps the hooks and the rest of the previews). Moved here unchanged.

// MARK: Update check previews

extension DebugHooks {
    /// Sill 0.4, found by a check, against a running 0.3.
    static let previewOffer = UpdatePolicy.Offer(version: SillVersion("0.4.0")!, tag: "v0.4.0",
                                                 url: URL(string: "https://github.com/Saffsanity/sill/releases/tag/v0.4.0")!)

    struct UpdatePaneSample {
        var name: String
        var pane: UpdatePolicy.Pane
        var automatic = true
    }

    /// pane-updates-{never,last,checking,uptodate,available,norelease,limited,offline,noversion,
    /// testpattern}: the section in each state, at the previews' clock (`previewNow`).
    static func updatePaneSamples() -> [UpdatePaneSample] {
        func pane(checking: Bool = false, result: UpdatePolicy.Outcome? = nil, offer: UpdatePolicy.Offer? = nil,
                  lastCheck: Date? = nil, hasVersion: Bool = true, testPatternOnly: Bool = false) -> UpdatePolicy.Pane {
            UpdatePolicy.pane(checking: checking, result: result, resultID: result == nil ? 0 : 1, offer: offer, lastCheck: lastCheck,
                              hasVersion: hasVersion, testPatternOnly: testPatternOnly,
                              time: UpdateChecker.time, date: UpdateChecker.date)
        }
        let lastCheck = previewNow.addingTimeInterval(-3 * 3600)
        return [
            UpdatePaneSample(name: "never", pane: pane()),
            UpdatePaneSample(name: "last", pane: pane(lastCheck: lastCheck)),
            UpdatePaneSample(name: "checking", pane: pane(checking: true, lastCheck: lastCheck)),
            UpdatePaneSample(name: "uptodate", pane: pane(result: .upToDate(tag: "v0.3.0"), lastCheck: previewNow)),
            UpdatePaneSample(name: "available", pane: pane(offer: previewOffer, lastCheck: lastCheck)),
            UpdatePaneSample(name: "norelease", pane: pane(result: .noRelease, lastCheck: previewNow)),
            UpdatePaneSample(name: "limited", pane: pane(result: .limited(status: 403, reset: previewNow.addingTimeInterval(42 * 60)), lastCheck: previewNow)),
            UpdatePaneSample(name: "offline", pane: pane(result: .noConnection(code: -1009, description: "The Internet connection appears to be offline."),
                                                         lastCheck: lastCheck), automatic: false),
            UpdatePaneSample(name: "noversion", pane: pane(hasVersion: false)),
            UpdatePaneSample(name: "testpattern", pane: pane(testPatternOnly: true)),
        ]
    }
}

// MARK: Remote access previews

extension DebugHooks {
    /// The previews' clock: 2026-09-24 16:00 UTC, so "last connected 2 minutes ago" and the
    /// countdown come out the same every run.
    static let previewNow = Date(timeIntervalSince1970: 1_790_265_600)

    static let tailscaleAddresses = [
        MacAddress(host: "mac-mini.tail1234.ts.net", kind: MacAddress.vpn, via: "Tailscale"),
        MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale"),
        MacAddress(host: "fd7a:115c:a1e0::1234", kind: MacAddress.vpn, via: "Tailscale"),
        MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi\u{2011}Fi"),
    ]

    /// The keychain's refusal the unusable samples show.
    static let keychainProblem = "the key couldn’t be read: The user name or passphrase you entered is not correct."

    struct DevicesPaneSample {
        var name: String
        var status: RemoteStatus
        var requirePairing = true
    }

    /// pane-devices-{required,off,empty,unavailable}: three devices, one paired over the USB cable
    /// and seen over Wi-Fi at home, one by QR code and seen through Tailscale yesterday, one by
    /// code and never connected; Require pairing off (its warning); nothing paired yet; the
    /// keychain unusable (no home door).
    static func devicesPaneSamples() -> [DevicesPaneSample] {
        let now = previewNow
        let ipad = PairedDeviceSummary(id: "ipad", keyPrefix: "5KD2Q7", name: "iPad (iPad14,1)", model: "iPad14,1",
                                       pairedAt: now.addingTimeInterval(-2 * 86_400), method: PairResult.cable,
                                       lastSeen: now.addingTimeInterval(-120), lastRoute: "over Wi\u{2011}Fi")
        let iphone = PairedDeviceSummary(id: "iphone", keyPrefix: "9XQ3M1", name: "iPhone (iPhone17,1)", model: "iPhone17,1",
                                         pairedAt: now.addingTimeInterval(-3 * 86_400), method: PairRequest.qr,
                                         lastSeen: now.addingTimeInterval(-86_400), lastRoute: "through Tailscale")
        let pro = PairedDeviceSummary(id: "ipadpro", keyPrefix: "H4MZ8T", name: "iPad (iPad17,4)", model: "iPad17,4",
                                      pairedAt: now.addingTimeInterval(-3_600), method: PairRequest.code)
        return [
            DevicesPaneSample(name: "required", status: RemoteStatus(paired: [ipad, iphone, pro], homeDoor: .pairingRequired)),
            DevicesPaneSample(name: "off", status: RemoteStatus(paired: [ipad, iphone], homeDoor: .open), requirePairing: false),
            DevicesPaneSample(name: "empty", status: RemoteStatus(homeDoor: .pairingRequired)),
            DevicesPaneSample(name: "unavailable",
                              status: RemoteStatus(identityProblem: keychainProblem,
                                                   homeDoor: .unavailable("Sill couldn’t use its key in the keychain (\(keychainProblem))"))),
        ]
    }

    struct RemotePaneSample {
        var name: String
        var status: RemoteStatus
    }

    /// pane-remote-{off,tailscale,notconnected,novpn,internet,cgnat,doublenat,inuse,keychain}.
    static func remotePaneSamples() -> [RemotePaneSample] {
        let now = previewNow
        let ipad = PairedDeviceSummary(id: "ipad", keyPrefix: "5KD2Q7", name: "iPad (iPad14,1)", model: "iPad14,1",
                                       pairedAt: now.addingTimeInterval(-3 * 86_400), method: PairRequest.qr,
                                       lastSeen: now.addingTimeInterval(-120), lastRoute: "through Tailscale")
        let iphone = PairedDeviceSummary(id: "iphone", keyPrefix: "9XQ3M1", name: "iPhone (iPhone17,1)", model: "iPhone17,1",
                                         pairedAt: now.addingTimeInterval(-86_400), method: PairRequest.code)
        let wifi = [MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi\u{2011}Fi")]
        let internetAddresses = tailscaleAddresses + [
            MacAddress(host: "home.example.net", port: 17455, kind: MacAddress.internet, via: "Address name"),
            MacAddress(host: "203.0.113.9", kind: MacAddress.internet, via: "Router"),
            MacAddress(host: "2001:db8::20", kind: MacAddress.internet, via: "IPv6"),
        ]
        func on(_ addresses: [MacAddress], listener: RemoteStatus.Listener = .listening(7455), vpnDown: [String] = [],
                paired: [PairedDeviceSummary] = [ipad, iphone]) -> RemoteStatus {
            RemoteStatus(remoteAccess: true, listener: listener, addresses: addresses, vpnDown: vpnDown,
                         lanAddress: "192.168.1.20", paired: paired)
        }
        func internet(_ router: RemoteStatus.Router, _ addresses: [MacAddress]) -> RemoteStatus {
            var s = on(addresses)
            s.internetAccess = true
            s.router = router
            s.addressName = "home.example.net:17455"
            return s
        }
        return [
            RemotePaneSample(name: "off", status: RemoteStatus(lanAddress: "192.168.1.20", paired: [ipad])),
            RemotePaneSample(name: "tailscale", status: on(tailscaleAddresses)),
            RemotePaneSample(name: "notconnected", status: on(wifi, vpnDown: ["Tailscale"], paired: [ipad])),
            RemotePaneSample(name: "novpn", status: on(wifi, paired: [])),
            RemotePaneSample(name: "internet", status: internet(.address("203.0.113.9"), internetAddresses)),
            RemotePaneSample(name: "cgnat", status: internet(.carrierNAT("100.72.14.3"), tailscaleAddresses)),
            RemotePaneSample(name: "doublenat", status: internet(.doubleNAT, tailscaleAddresses)),
            RemotePaneSample(name: "inuse", status: on(tailscaleAddresses, listener: .portInUse(7455))),
            RemotePaneSample(name: "keychain",
                             status: RemoteStatus(identityProblem: "the key couldn’t be read: The user name or passphrase you entered is not correct.")),
        ]
    }

    struct PairingSample {
        var name: String
        var offer: RemoteAccess.PairingOffer
        var status: RemoteStatus
        var remoteAccess = true
    }

    /// pairing-{waiting,requested,wrong,paired,stopped,expired,remoteoff,novpn,othervpn,longname,asked,
    /// askednearby} (pairing-cablenotice is drawn on its own). A stand-in Mac key (the plan's
    /// SHA-256("mac") vector) and the plan's example code: nothing here pairs anything. The address to
    /// type is Tailscale's name with its IPv4 under it; `novpn` has no VPN, so this network's address;
    /// `othervpn` has a VPN that is not Tailscale, so this network's address with that VPN's IPv4
    /// under it; `longname` has a long MagicDNS name, 40 characters, on a port other than 7455. Not the
    /// longest there can be: LocalHostName allows 63 characters, and from about 46 with a port (52
    /// without) a name wraps after a hyphen, never cut. `asked` and `askednearby` are windows a device
    /// opened by asking at the home door.
    static func pairingSamples() -> [PairingSample] {
        let fingerprint = Data((0..<32).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
        func makeLink(port: Int, _ addresses: [String]) -> PairLink {
            let parsed = addresses.compactMap { text -> ParsedAddress? in
                if case .success(let a) = AddressParser.parse(text) { return a }
                return nil
            }
            return PairLink(fingerprint: fingerprint, secret: Data(repeating: 0x16, count: 16), name: "Mac mini", port: port, addresses: parsed)
        }
        let standard = makeLink(port: 7455, ["192.168.1.20", "mac-mini.tail1234.ts.net", "100.101.102.103"])
        let expires = previewNow.addingTimeInterval(298)
        func offer(_ requestedBy: String? = nil, link: PairLink? = nil) -> RemoteAccess.PairingOffer {
            let link = link ?? standard
            return RemoteAccess.PairingOffer(url: link.url, code: "482913557208", expiresAt: expires, requestedBy: requestedBy,
                                             port: link.port, again: false)
        }
        func status(_ pairing: RemoteStatus.Pairing, addresses: [MacAddress]? = nil, port: Int = 7455) -> RemoteStatus {
            RemoteStatus(remoteAccess: true, listener: .listening(port), addresses: addresses ?? tailscaleAddresses,
                         lanAddress: "192.168.1.20", pairing: pairing)
        }
        let open = RemoteStatus.Pairing.open(requestedBy: nil, expiresAt: expires, triesLeft: 5, lastWrongFrom: nil, byDevice: false)
        let wifi = [MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi\u{2011}Fi")]
        let otherVPN = [MacAddress(host: "10.8.0.6", kind: MacAddress.vpn, via: "WireGuard")] + wifi
        let longName = "studio-macbook-pro-16-in.tail1234.ts.net"
        let long = [MacAddress(host: longName, kind: MacAddress.vpn, via: "Tailscale")] + tailscaleAddresses.dropFirst()
        let longLink = makeLink(port: 17455, [longName, "100.101.102.103", "fd7a:115c:a1e0::1234", "192.168.1.20"])
        // A window a device opened by asking at the home door: its link names no address.
        func askedOffer(_ who: String, from: String) -> RemoteAccess.PairingOffer {
            let link = makeLink(port: 7455, [])
            return RemoteAccess.PairingOffer(url: link.url, code: "482913557208", expiresAt: expires, requestedBy: who,
                                             port: link.port, again: false, byDevice: true, askedFrom: from)
        }
        func askedStatus(_ who: String) -> RemoteStatus {
            RemoteStatus(lanAddress: "192.168.1.20",
                         pairing: .open(requestedBy: who, expiresAt: expires, triesLeft: 5, lastWrongFrom: nil, byDevice: true),
                         homeDoor: .pairingRequired)
        }
        return [
            PairingSample(name: "waiting", offer: offer(), status: status(open)),
            PairingSample(name: "requested", offer: offer("iPad (iPad14,1)"),
                          status: status(.open(requestedBy: "iPad (iPad14,1)", expiresAt: expires, triesLeft: 5, lastWrongFrom: nil, byDevice: false))),
            PairingSample(name: "wrong", offer: offer(),
                          status: status(.open(requestedBy: nil, expiresAt: expires, triesLeft: 4, lastWrongFrom: "203.0.113.9", byDevice: false))),
            PairingSample(name: "paired", offer: offer(), status: status(.paired("iPad (iPad14,1)"))),
            PairingSample(name: "stopped", offer: offer(), status: status(.stopped)),
            PairingSample(name: "expired", offer: offer(), status: status(.expired)),
            PairingSample(name: "remoteoff", offer: offer(), status: status(open), remoteAccess: false),
            PairingSample(name: "novpn", offer: offer(link: makeLink(port: 7455, ["192.168.1.20"])), status: status(open, addresses: wifi)),
            PairingSample(name: "othervpn", offer: offer(link: makeLink(port: 7455, ["10.8.0.6", "192.168.1.20"])),
                          status: status(open, addresses: otherVPN)),
            PairingSample(name: "longname", offer: offer(link: longLink), status: status(open, addresses: long, port: 17455)),
            // Windows a device opened by asking at the home door: its link has no address, the
            // window no Address row and no Remote Access line (Remote Access off here, as it is at
            // most homes); over this network, and nearby (peer-to-peer Wi-Fi).
            PairingSample(name: "asked", offer: askedOffer("iPad (iPad14,1)", from: "on this network"),
                          status: askedStatus("iPad (iPad14,1)"), remoteAccess: false),
            PairingSample(name: "askednearby", offer: askedOffer("iPhone (iPhone17,1)", from: "nearby"),
                          status: askedStatus("iPhone (iPhone17,1)"), remoteAccess: false),
        ]

    }
}
