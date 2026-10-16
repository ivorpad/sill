import Foundation
import Network
import QuartzCore
import UIKit
import StreamProtocol

// The Mac's menus on the device (docs/menu-bar-plan.md): the subscription, the fetches and presses and
// their answers. Moved out of StreamClient.swift whole; the stored properties they use stay there, as
// stored properties must (menuCompletions, menuKey, menuToken, menusExpiry, menuAsked, menuPressArgumentDone).
extension StreamClient {
    /// The subscription: a kind 27 without an id, once per connection at its first window list (and
    /// on a move's new connection). The Mac then sends its top level and every later one; a Mac from
    /// before the menus skips it and sends nothing, so no Menus button shows. Main thread.
    func subscribeToMenus() {
        send(.fetchMenu, payload: Wire.encode(FetchMenu(token: nextMenuToken())))
    }

    /// A menu of the top level opened, in the iPad's bar or the Menus button's pull-down: built as
    /// `id` under `title` from the top level of `builtVersion` (another session's, perhaps), it asks
    /// by its title when the current top level's menu there has another (MacMenuState rule 11),
    /// since UIKit rebuilds the bar lazily. With no menu of that title now, the menus changed, and
    /// the bar is asked for a rebuild again. `completion` runs once, on the main queue. Main thread.
    func fetchTopMenu(id: String, title: String, builtVersion: Int, completion: @escaping (MacMenuState.Content) -> Void) {
        guard let current = menus.version else { completion(.message(MacMenuState.notConnected)); return }
        guard let asked = menus.barMenuID(builtID: id, title: title) else {
            #if DEBUG
            print("menubar: \(title) was built from version \(builtVersion); version \(current) has none")
            #endif
            completion(.message(MacMenuState.changedNote))
            MacMenuHub.shared.menusChanged(self)
            return
        }
        #if DEBUG
        if builtVersion != current || asked != id { print("menubar: \(title) was built from version \(builtVersion) as \(id); asked as \(asked) in version \(current)") }
        #endif
        fetchMenu(id: asked, version: current, title: title, completion: completion)
    }

    /// A submenu of a fetched menu opened: asked in the version its row came in. Main thread.
    func fetchMenu(_ row: MacMenuState.Row, completion: @escaping (MacMenuState.Content) -> Void) {
        guard let id = row.id else { completion(.message(MacMenuState.changedNote)); return }
        fetchMenu(id: id, version: row.version, title: row.title, completion: completion)
    }

    private func fetchMenu(id: String, version: Int?, title: String, completion: @escaping (MacMenuState.Content) -> Void) {
        menuKey += 1
        let key = menuKey
        let token = menuToken
        let now = ProcessInfo.processInfo.systemUptime
        switch menus.fetch(id, title: title, version: version, key: key, token: token, now: now) {
        case .send(let request):
            menuToken += 1
            menuCompletions[key] = completion
            #if DEBUG
            menuAsked[key] = (title, id, now)
            #endif
            send(.fetchMenu, payload: Wire.encode(request))
            scheduleMenusExpiry()
            #if DEBUG
            if connection == nil { mockAnswer(request) }
            #endif
        case .joined:
            menuCompletions[key] = completion
            #if DEBUG
            menuAsked[key] = (title, id, now)
            #endif
        case .settled(let content):
            completion(content)
        }
    }

    /// An item chosen in a menu: a kind 25 with the version its row came in and the title shown, or
    /// a refusal told at once (the app not answering on the Mac). Main thread.
    func pressMenuItem(_ row: MacMenuState.Row) {
        switch menus.press(row, token: menuToken) {
        case .send(let request)?:
            menuToken += 1
            send(.pressMenuItem, payload: Wire.encode(request))
            #if DEBUG
            print("menus: chose \(row.title) (\(request.id ?? ""))")
            if connection == nil { mockAnswer(request) }
            #endif
        case .refused(let refusal)?:
            menuRefused(refusal)
        case nil:
            break
        }
    }

    /// A kind 24 from the Mac, on this connection. Main thread.
    func receiveMenus(_ m: MacMenu) {
        let (done, topChanged, refusal) = menus.receive(m, now: ProcessInfo.processInfo.systemUptime)
        finishMenus(done)
        if topChanged {
            #if DEBUG
            let count = menus.menus.count
            let what = count == 0 && menus.app == nil ? "none" : "\(menus.app ?? "?"), \(count) menu\(count == 1 ? "" : "s")"
            print("menus: \(what) (version \(menus.version.map(String.init) ?? "?"))"
                  + (menus.stale ? ", stale" : "") + (menus.note.map { ": \($0)" } ?? ""))
            pressFromLaunchArgument()
            #endif
            MacMenuHub.shared.menusChanged(self)
        }
        if let refusal { menuRefused(refusal) }
        scheduleMenusExpiry()
    }

    /// A choice not made: the warning haptic (iPhones; an iPad has no Taptic Engine) and VoiceOver's
    /// announcement. Nothing on screen: the Mac's picture says what happened (plan's Q9).
    private func menuRefused(_ refusal: MacMenuState.Refusal) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIAccessibility.post(notification: .announcement, argument: refusal.announcement)
        #if DEBUG
        print(refusal.byMac ? "menus: the Mac refused \(refusal.title) (\(refusal.id)): \(refusal.note)"
                            : "menus: not sent: \(refusal.title) (\(refusal.id)): \(refusal.note)")
        #endif
    }

    /// Runs the completions `menus` settled, each once.
    private func finishMenus(_ done: [MacMenuState.Done]) {
        for d in done {
            #if DEBUG
            if let asked = menuAsked.removeValue(forKey: d.key) {
                let ms = Int(((ProcessInfo.processInfo.systemUptime - asked.at) * 1000).rounded())
                switch d.content {
                case .sections(let sections, let more):
                    let items = sections.flatMap { $0 }.filter { $0.kind != .note }.count
                    print("menus: \(asked.title) (\(asked.id)) in \(ms) ms, \(items) item\(items == 1 ? "" : "s")" + (more > 0 ? ", \(more) more" : ""))
                case .message(let text):
                    print("menus: \(asked.title) (\(asked.id)) after \(ms) ms: \(text)")
                }
            }
            #endif
            menuCompletions.removeValue(forKey: d.key)?(d.content)
        }
    }

    /// How long an opened menu waits for the Mac: 4 s, or four of the worst recent round trips on a
    /// slow link, as a settings pick does.
    private var menusTimeout: Double { settingsTimeout }

    /// Arms the timeout check for the oldest waiting fetch, replacing any armed one.
    private func scheduleMenusExpiry() {
        menusExpiry?.cancel()
        menusExpiry = nil
        guard let oldest = menus.oldestWait else { return }
        let work = DispatchWorkItem { [weak self] in self?.expireMenus() }
        menusExpiry = work
        let due = oldest + menusTimeout + 0.05 - ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, due), execute: work)
    }

    /// Menus the Mac never answered: "‹Mac› didn’t answer. Open the menu again."
    private func expireMenus() {
        finishMenus(menus.expire(now: ProcessInfo.processInfo.systemUptime, timeout: menusTimeout, mac: macName))
        scheduleMenusExpiry()
    }

    /// The connection ended: every open menu says "Not connected.", and nothing of the Mac's menus is
    /// kept. From `tearDown`. Main thread.
    func resetMenus() {
        finishMenus(menus.reset())
        // Every completion is the state's, so none is left; one that were would wait for ever.
        let left = menuCompletions
        menuCompletions = [:]
        for (_, completion) in left { completion(.message(MacMenuState.notConnected)) }
        menusExpiry?.cancel()
        menusExpiry = nil
        #if DEBUG
        menuAsked = [:]
        #endif
        MacMenuHub.shared.menusChanged(self)
    }

    /// A move handed the session to its new connection (`finishMove`): what waits settles, and the
    /// new connection subscribes. Main thread.
    func menusMoved() {
        finishMenus(menus.connectionReplaced())
        scheduleMenusExpiry()
        subscribeToMenus()
    }

    private func nextMenuToken() -> Int {
        defer { menuToken += 1 }
        return menuToken
    }

    #if DEBUG
    /// The harness's menus: the mock Mac's top level, as if the Mac had sent it on this connection.
    func showMockMenus(_ mock: MockCatalog.MacMenus) {
        mockMenus = mock
        receiveMenus(mock.topLevel)
    }

    /// The mock Mac answers a fetch after its delay (never, for `timeout`), as a host would.
    private func mockAnswer(_ request: FetchMenu) {
        guard let mock = mockMenus, let delay = mock.fetchDelay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.connection == nil, self.mockMenus != nil else { return }
            self.receiveMenus(mock.answer(request))
        }
    }

    /// …and a choice after 0.2 s: pressed, or refused (`refuse`).
    private func mockAnswer(_ request: PressMenuItem) {
        guard let mock = mockMenus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.connection == nil, self.mockMenus != nil else { return }
            self.receiveMenus(mock.answer(request))
        }
    }

    /// A menu or item by its titles from the top level ("File/Save"), each level fetched as a tap on
    /// it would fetch it: the harness's way to open a submenu or choose an item without a tap. The
    /// row, and the top level's version when it is one of the Mac's menus; nil when a title is not
    /// there.
    func resolveMenuPath(_ titles: [String], completion: @escaping ((row: MacMenuState.Row, topLevelVersion: Int?)?) -> Void) {
        guard let first = titles.first, let version = menus.version,
              let top = menus.menus.first(where: { $0.title == first }) else { completion(nil); return }
        var found: (row: MacMenuState.Row, topLevelVersion: Int?) = (top, version)
        func step(_ rest: ArraySlice<String>) {
            guard let next = rest.first else { completion(found); return }
            let open: (MacMenuState.Content) -> Void = { content in
                guard case .sections(let sections, _) = content,
                      let row = sections.flatMap({ $0 }).first(where: { $0.title == next }) else { completion(nil); return }
                found = (row, nil)
                step(rest.dropFirst())
            }
            if let v = found.topLevelVersion, let id = found.row.id {
                fetchTopMenu(id: id, title: found.row.title, builtVersion: v, completion: open)
            } else {
                fetchMenu(found.row, completion: open)
            }
        }
        step(titles.dropFirst())
    }

    /// Why the harness must not open menus by their path or choose an item in this session
    /// (`-SillMenusOpen 'File/…'`, `-SillMenuPress`), or nil when it may: the mock's menus, or the
    /// test app's (Scripts/menufixture.swift) through a test host, a session dialled to a loopback
    /// address whose Mac's window list gives no version (SillHost; Sill.app always gives one) and
    /// whose top level is menufixture's. Never a real Mac's menus: a choice there is made in whatever
    /// app it streams, and each menu opened is validated by that app.
    var menuHarnessRefusal: String? {
        guard connection != nil else { return nil }
        if let why = InputScript.refusal(endpoint: connection?.endpoint, hostVersion: hostVersion) {
            return why.replacingOccurrences(of: ", which posts input to this Mac", with: "")
        }
        guard menus.app == "menufixture" else { return "the menus are \(menus.app ?? "no app")'s, not the test app's (menufixture)" }
        return nil
    }

    /// `-SillMenuPress 'File/Save'`: once the first top level is in, the item at that path is chosen
    /// as a tap on it would choose it (the menus on the way fetched, the kind 25 sent), once per
    /// client. The harness cannot tap; against a synthetic host with SILL_TEST_MENU_PID this is the
    /// fixture's item pressed through the host. Only where `menuHarnessRefusal` lets it.
    private func pressFromLaunchArgument() {
        guard !menuPressArgumentDone, menus.version != nil, !menus.menus.isEmpty,
              let raw = UserDefaults.standard.string(forKey: "SillMenuPress"), !raw.isEmpty else { return }
        menuPressArgumentDone = true
        if let why = menuHarnessRefusal {
            print("menus: harness: -SillMenuPress \(raw) refused: \(why)")
            return
        }
        let path = raw.split(separator: "/").map { String($0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.resolveMenuPath(path) { [weak self] found in
                guard let self else { return }
                guard let found, found.row.kind == .item else { print("menus: harness: nothing to choose at \(path.joined(separator: " › "))"); return }
                self.pressMenuItem(found.row)
            }
        }
    }
    #endif
}
