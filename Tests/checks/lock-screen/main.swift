import Foundation

// Locking and unlocking the Mac from a device (docs/lock-screen-plan.md): LockScreen.swift's rules, with
// StreamMessage.swift's kind 44 and Switcher.swift's `locked`, `lockScreen` and `unlock`, compiled on their own
// (module.txt names the files; run.sh hands them to ../module.py).
//
// A made-up secret goes through every case. The expectations are written out (a table, a list of faults in the
// plan's order, a few numbers), never taken from the code they check, and a result is read field by field
// where an initializer builds the value it is compared with, so a mutated initializer cannot hide behind itself.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func json(_ text: String) -> Data { Data(text.utf8) }
func keys<T: Encodable>(_ value: T) -> Set<String> {
    (try? JSONSerialization.jsonObject(with: Wire.encode(value)) as? [String: Any]).map { Set($0.keys) } ?? []
}

// MARK: Kind 44

// 44 is this branch's number until it is agreed with upstream (the plan's N). When it moves, these cases, the
// kind tables of `menus` and `pointer-control` and mutant K1 in mutants.py move with it.
func header(_ kind: UInt8) -> StreamHeader? {
    var d = Data([kind]); d.append(Data(count: 8)); d.append(0); d.append(contentsOf: [0, 0, 0, 0])
    return StreamMessage.parseHeader(d)
}
check(StreamMessageKind.lockScreen.rawValue == 44 && StreamMessageKind(rawValue: 44) == .lockScreen, "the lock screen is kind 44")
check(header(44)?.kind == .lockScreen, "a header with kind 44 parses as the lock screen")
check(header(43)?.kind == .unknown && header(45)?.kind == .unknown, "43 and 45 are still unknown")
check(StreamMessageKind(rawValue: 43) == nil && StreamMessageKind(rawValue: 45) == nil, "…and no case of the enum")

let request = LockScreenRequest(action: "unlock", secret: "made-up secret", token: 7)
let requestMessage = StreamMessage(kind: .lockScreen, timestamp: 1_790_000_000.25, isKeyframe: false, payload: Wire.encode(request)).serialized()
let requestHeader = StreamMessage.parseHeader(requestMessage)
check(requestMessage.first == 44 && requestHeader?.kind == .lockScreen && requestHeader?.timestamp == 1_790_000_000.25
      && requestHeader?.isKeyframe == false && requestHeader?.payloadLength == requestMessage.count - StreamMessage.headerLength,
      "a kind 44 request serializes and its header parses")
check(Wire.decode(LockScreenRequest.self, from: requestMessage.subdata(in: StreamMessage.headerLength..<requestMessage.count)) == request,
      "…and its payload is the request")
let outcome = LockScreenOutcome(token: 7, outcome: "refused", message: "Not now.")
let outcomeMessage = StreamMessage(kind: .lockScreen, timestamp: 1, isKeyframe: false, payload: Wire.encode(outcome)).serialized()
check(StreamMessage.parseHeader(outcomeMessage)?.kind == .lockScreen
      && Wire.decode(LockScreenOutcome.self, from: outcomeMessage.subdata(in: StreamMessage.headerLength..<outcomeMessage.count)) == outcome,
      "a kind 44 outcome serializes, parses and decodes")
// The longest secret a device may send (128 characters of four bytes) stays far inside a client message.
let longest = Wire.encode(LockScreenRequest(action: LockScreenAction.unlock,
                                            secret: String(repeating: "😀", count: LockScreenSecret.maxCharacters), token: Int.max))
check(longest.count < 1024 && longest.count < StreamMessage.maxClientPayload, "the longest request is \(longest.count) bytes, well inside a client message")

// MARK: The JSON

func decodeRequest(_ text: String) -> LockScreenRequest? { Wire.decode(LockScreenRequest.self, from: json(text)) }
func decodeOutcome(_ text: String) -> LockScreenOutcome? { Wire.decode(LockScreenOutcome.self, from: json(text)) }

check(keys(LockScreenRequest(action: "lock", token: 3)) == ["action", "token"], "a lock request: action and token")
check(keys(LockScreenRequest(action: "unlock", secret: "s", token: 4)) == ["action", "secret", "token"], "an unlock request: action, secret and token")
let lockText = String(decoding: Wire.encode(LockScreenRequest(action: "lock", token: 3)), as: UTF8.self)
check(!lockText.contains("secret") && !lockText.contains("null"), "a nil secret is left out, not written as null: \(lockText)")
check(keys(LockScreenOutcome(token: 5, outcome: "locked")) == ["token", "outcome"], "an outcome without a message: token and outcome")
check(keys(LockScreenOutcome(token: 5, outcome: "refused", message: "Words.")) == ["token", "outcome", "message"], "an outcome with one: three keys")
// Built by the initializer, then against the JSON written by hand: each field comes from its own argument.
check(LockScreenRequest(action: "a", secret: "b", token: 3) == decodeRequest(#"{"action":"a","secret":"b","token":3}"#),
      "LockScreenRequest's init sets each field from its own argument")
check(LockScreenOutcome(token: 3, outcome: "a", message: "b") == decodeOutcome(#"{"token":3,"outcome":"a","message":"b"}"#),
      "LockScreenOutcome's init sets each field from its own argument")
check(LockScreenRequest(action: "a", token: 3) == decodeRequest(#"{"action":"a","token":3}"#)
      && LockScreenOutcome(token: 3, outcome: "a") == decodeOutcome(#"{"token":3,"outcome":"a"}"#), "no secret and no message by default")
check(decodeRequest(#"{"action":"unlock","secret":"made-up","token":7,"later":{"x":[1,2]}}"#)
      == LockScreenRequest(action: "unlock", secret: "made-up", token: 7), "a request: a later key is ignored")
check(decodeOutcome(#"{"token":5,"outcome":"stillLocked","message":"Try again.","later":true}"#)
      == LockScreenOutcome(token: 5, outcome: "stillLocked", message: "Try again."), "an outcome: a later key is ignored")
check(decodeRequest(#"{"action":"reboot","token":1}"#)?.action == "reboot" && !LockScreenAction.known.contains("reboot"),
      "an action this build does not know decodes as the string it is")
let later = decodeOutcome(#"{"token":9,"outcome":"quarantined","message":"Locked out for a minute."}"#)
check(later?.outcome == "quarantined" && later?.message == "Locked out for a minute." && later?.token == 9
      && !LockScreenOutcome.known.contains("quarantined"), "an outcome this build does not know keeps its word, and its message")
check(decodeOutcome(#"{"token":9,"outcome":"locked"}"#).map { $0.message == nil && $0.outcome == "locked" } == true, "an outcome without a message decodes with none")
for r in [LockScreenRequest(action: "lock", token: 1), LockScreenRequest(action: "unlock", secret: "pässwörd 🔑", token: Int(Int32.max) + 1)] {
    check(Wire.decode(LockScreenRequest.self, from: Wire.encode(r)) == r, "a \(r.action) request round-trips")
}
check(Wire.decode(LockScreenOutcome.self, from: Wire.encode(outcome)) == outcome, "an outcome round-trips")
check(decodeRequest(#"{"action":"lock"}"#) == nil && decodeRequest(#"{"token":1}"#) == nil && decodeRequest("{}") == nil,
      "a request without an action or without a token does not decode: there is nothing to answer")
check(decodeOutcome(#"{"token":1}"#) == nil && decodeOutcome(#"{"outcome":"locked"}"#) == nil && decodeOutcome("[]") == nil,
      "an outcome without a token or an outcome word, or that is no object, does not decode")

// MARK: The window list's three fields

func list(_ extra: String = "") -> WindowList? {
    Wire.decode(WindowList.self, from: json(#"{"macName":"Studio","windows":[],"active":{"desktop":{}}"# + extra + "}"))
}
let before = list(#","launchID":"L","hostVersion":"0.5.1","protocol":1,"gestures":1,"clipboard":1,"deviceDisplay":1,"deviceDisplayLive":true"#)
check(before.map { $0.macName == "Studio" && $0.active == .desktop && $0.clipboard == 1 } == true, "a list from before the lock screen still decodes")
check(before.map { $0.locked == nil && $0.lockScreen == nil && $0.unlock == nil } == true, "…with locked, lockScreen and unlock nil")
check(list().map { $0.locked == nil && $0.lockScreen == nil && $0.unlock == nil } == true, "…and the oldest list too")
check(list(#","locked":"password","lockScreen":1,"unlock":true"#).map { $0.locked == "password" && $0.lockScreen == 1 && $0.unlock == true } == true,
      "a list that says locked, lockScreen 1 and unlock true is read so")
check(list(#","locked":"somethingLater""#).map { $0.locked == "somethingLater" && $0.lockScreen == nil && $0.unlock == nil } == true,
      "a locked this build does not know is kept, and the other two stay nil")
check(list(#","unlock":false"#).map { $0.unlock == false && $0.locked == nil } == true, "unlock false reads as false")
let said = WindowList(macName: "Studio", windows: [], active: .desktop, locked: "pin", lockScreen: 7, unlock: true)
check(Wire.decode(WindowList.self, from: Wire.encode(said)).map { $0.locked == "pin" && $0.lockScreen == 7 && $0.unlock == true
      && $0.macName == "Studio" && $0.active == .desktop } == true, "a list with the three fields round-trips")
check(keys(said).isSuperset(of: ["locked", "lockScreen", "unlock"]), "…written as locked, lockScreen and unlock")
let plain = WindowList(macName: "Studio", windows: [], active: .desktop)
check(plain.locked == nil && plain.lockScreen == nil && plain.unlock == nil, "a list built without them says none")
check(keys(plain).isDisjoint(with: ["locked", "lockScreen", "unlock"]), "…and leaves the three keys out")
check(list(#","locked":"pin","lockScreen":7,"unlock":true"#).map { $0.locked == said.locked && $0.lockScreen == said.lockScreen && $0.unlock == said.unlock
      && said.locked == "pin" && said.lockScreen == 7 && said.unlock == true } == true,
      "WindowList's init sets locked, lockScreen and unlock from their own arguments")

// MARK: Actions, outcomes and asks

check(LockScreenRequest.generation == 1, "the generation `lockScreen` says is 1")
check(LockScreenAction.lock == "lock" && LockScreenAction.unlock == "unlock", "the actions' words")
check(LockScreenAction.known == ["lock", "unlock"], "the known actions")
check(LockScreenOutcome.unlocked == "unlocked" && LockScreenOutcome.stillLocked == "stillLocked" && LockScreenOutcome.refused == "refused"
      && LockScreenOutcome.locked == "locked" && LockScreenOutcome.notLocked == "notLocked", "the outcomes' words")
check(LockScreenOutcome.known == ["unlocked", "stillLocked", "refused", "locked", "notLocked"], "the known outcomes")
check(LockScreenAsk.password == "password" && LockScreenAsk.pin == "pin", "the asks' words")
check(LockScreenAsk.known == ["password", "pin"], "the known asks")
check(LockScreenAsk.label("password") == "Password" && LockScreenAsk.label("pin") == "PIN", "the field is labelled Password or PIN as `locked` says")
for ask in ["", "token", "smartcard"] {
    check(LockScreenAsk.label(ask) == "Password or PIN", "a value this build does not know (\"\(ask)\") is labelled Password or PIN")
}
// The same inside a sentence: the acronym keeps its capitals.
check(LockScreenAsk.word("password") == "password" && LockScreenAsk.word("pin") == "PIN", "in a sentence: password, PIN")
for ask in ["", "token", "smartcard"] {
    check(LockScreenAsk.word(ask) == "password or PIN", "in a sentence, a value this build does not know (\"\(ask)\") is password or PIN")
}
for ask in ["password", "pin", "", "token"] {
    check(LockScreenAsk.word(ask).lowercased() == LockScreenAsk.label(ask).lowercased(), "the word and the label say the same thing (\"\(ask)\")")
}

// MARK: What a host may type

typealias Secret = LockScreenSecret
let oneEmoji = "\u{1F469}\u{200D}\u{1F4BB}"        // a woman technologist: three scalars, one character
let accented = "e\u{301}"                           // an e and a combining acute: two scalars, one character
check(oneEmoji.count == 1 && oneEmoji.unicodeScalars.count == 3 && accented.count == 1 && accented.unicodeScalars.count == 2,
      "the test characters are what they are meant to be")
check(Secret.maxCharacters == 128, "128 characters at most")
check(!Secret.isTypeable(""), "empty: nothing to type")
check(Secret.isTypeable("a") && Secret.isTypeable("1234"), "one character, a PIN")
check(Secret.isTypeable(String(repeating: "a", count: 128)), "128 characters: typed")
check(!Secret.isTypeable(String(repeating: "a", count: 129)), "129 characters: not")
// Characters, not bytes or scalars.
check(Secret.isTypeable(String(repeating: "😀", count: 128)), "128 emoji (four bytes each) are 128 characters")
check(!Secret.isTypeable(String(repeating: "😀", count: 129)), "129 emoji are not")
check(Secret.isTypeable(String(repeating: "a", count: 127) + oneEmoji), "127 letters and a three-scalar emoji are 128 characters")
check(!Secret.isTypeable(String(repeating: "a", count: 128) + oneEmoji), "…and one more is 129")
check(Secret.isTypeable(String(repeating: accented, count: 128)), "128 accented letters of two scalars each are 128 characters")
check(!Secret.isTypeable(String(repeating: accented, count: 129)), "129 are not")
// A control character anywhere: it would press Return part way through, or delete.
let controls: [(String, String)] = [("a newline", "\n"), ("a carriage return", "\r"), ("a tab", "\t"), ("a backspace", "\u{8}"), ("a delete", "\u{7F}"),
                                    ("a NUL", "\u{0}"), ("an escape", "\u{1B}"), ("a C1 control (NEL)", "\u{85}"), ("a CRLF", "\r\n")]
for (name, bad) in controls {
    check(!Secret.isTypeable(bad), "\(name) alone: not typeable")
    check(!Secret.isTypeable("pass" + bad + "word"), "\(name) inside: not typeable")
    check(!Secret.isTypeable(bad + "password"), "\(name) first: not typeable")
    check(!Secret.isTypeable("password" + bad), "\(name) last: not typeable")
}
let typeable: [(String, String)] = [("a space", "pass word"), ("accented text", "pässwörd-é"), ("Cyrillic", "пароль"), ("Chinese", "密码密码"),
                                    ("Arabic", "كلمة السر"), ("an emoji", "🔑key"), ("every symbol", "p@$$ w0rd!~`#%^&*()_+-={}[]|\\:\";'<>?,./")]
for (name, good) in typeable {
    check(Secret.isTypeable(good), "\(name) is typeable")
}

// MARK: The host's waits

check(UnlockTiming.afterFailure == 5, "5 s after a failure")
check(UnlockTiming.verdictWait > 5, "the verdict waits longer than loginwindow's own 5 s for user activity")
check(UnlockTiming.wakeWait > 0 && UnlockTiming.settle > 0 && UnlockTiming.keyGap > 0 && UnlockTiming.lockWait > 0, "every wait is more than none")

// MARK: Who may unlock: the Mac's two switches, by route and door

// allow = "Unlock from devices", allowAway = "Also from devices away from home"; the two results are
// allows(away:) and advertised(away:tls:), which is true or nil and never false. The switches gate the unlock
// card's attempts (kind 44) and nothing else: typing into the lock screen by hand stays open to every paired
// device (the plan's decision 2, Ivor, 2026-10-16), so there is no rule here for key input.
typealias Row = (allow: Bool, allowAway: Bool, away: Bool, tls: Bool, allows: Bool, advertised: Bool?)
let table: [Row] = [
    (false, false, false, false, false, nil), (false, false, false, true, false, nil),
    (false, false, true, false, false, nil), (false, false, true, true, false, nil),
    // The away switch alone lets nobody in.
    (false, true, false, false, false, nil), (false, true, false, true, false, nil),
    (false, true, true, false, false, nil), (false, true, true, true, false, nil),
    // Home only: a connection home, at a TLS door.
    (true, false, false, false, true, nil), (true, false, false, true, true, true),
    (true, false, true, false, false, nil), (true, false, true, true, false, nil),
    // Home and away.
    (true, true, false, false, true, nil), (true, true, false, true, true, true),
    (true, true, true, false, true, nil), (true, true, true, true, true, true),
]
for r in table {
    let p = UnlockPolicy(allow: r.allow, allowAway: r.allowAway)
    let what = "unlock \(r.allow), away switch \(r.allowAway), a connection \(r.away ? "away" : "home") at a \(r.tls ? "TLS" : "plain") door"
    check(p.allows(away: r.away) == r.allows, "allows: \(what)")
    check(p.advertised(away: r.away, tls: r.tls) == r.advertised, "advertised (true or nil, never false): \(what)")
}
let off = UnlockPolicy()
check(!off.allow && !off.allowAway && off == UnlockPolicy(allow: false, allowAway: false), "both switches start off")
check(!off.allows(away: false) && !off.allows(away: true) && off.advertised(away: false, tls: true) == nil, "off: nobody unlocks, nothing is advertised")
check(UnlockPolicy(allow: true).allow && !UnlockPolicy(allow: true).allowAway, "the first switch alone leaves the second off")
check(UnlockPolicy(allow: true, allowAway: false) != UnlockPolicy(allow: false, allowAway: true), "the two switches are not each other")

// MARK: The record of attempts

typealias Attempts = UnlockAttempts
let mac = "Ivor’s Studio"
let inFlightWords = "Ivor’s Studio is already being unlocked."
let pinStopWords = "Two wrong PINs in a row. Unlock Ivor’s Studio at the Mac: a third would block the smart card."
let waitWords = "Wait a few seconds, then try again."
func afterFailures(_ n: Int, from t: Double = 100, every: Double = 10) -> Attempts {
    var a = Attempts()
    for i in 0..<n { a.began(); a.ended(outcome: LockScreenOutcome.stillLocked, now: t + Double(i) * every) }
    return a
}
check(Attempts.pinFailureStop == 2, "the PIN stop is after 2")
let fresh = Attempts()
check(!fresh.inFlight && fresh.failuresInARow == 0 && fresh.lastFailure == nil, "a fresh record: nothing in flight, no failures")
for ask in ["password", "pin"] { check(fresh.refusal(now: 0, ask: ask, mac: mac) == nil, "a fresh record takes an attempt (\(ask))") }

// One at a time, across every device.
var busy = fresh
busy.began()
check(busy.inFlight, "an attempt that began is in flight")
check(busy.refusal(now: 0, ask: "password", mac: mac) == inFlightWords && busy.refusal(now: 0, ask: "pin", mac: mac) == inFlightWords,
      "while one is in flight another is refused, with the Mac's name: \(busy.refusal(now: 0, ask: "password", mac: mac) ?? "nil")")
var busyAfterTwo = afterFailures(2)
busyAfterTwo.began()
check(busyAfterTwo.refusal(now: 111, ask: "pin", mac: mac) == inFlightWords, "in flight comes before the PIN stop and the wait")
for o in LockScreenOutcome.known.sorted() + ["quarantined"] {
    var a = fresh; a.began(); a.ended(outcome: o, now: 50)
    check(!a.inFlight && a.refusal(now: 50, ask: "password", mac: mac) == (o == LockScreenOutcome.stillLocked ? waitWords : nil),
          "an attempt that ended with \(o) is no longer in flight")
}

// 5 s after a failure.
let one = afterFailures(1, from: 100)
check(one.failuresInARow == 1 && one.lastFailure == 100, "a failure is counted and its time kept")
check(one.refusal(now: 100, ask: "password", mac: mac) == waitWords, "the moment after a failure: wait")
check(one.refusal(now: 104.9, ask: "password", mac: mac) == waitWords, "4.9 s after a failure: wait")
check(one.refusal(now: 105, ask: "password", mac: mac) == nil, "5.0 s after: taken")
check(one.refusal(now: 105.1, ask: "password", mac: mac) == nil && one.refusal(now: 10_000, ask: "password", mac: mac) == nil, "later: taken")
check(one.refusal(now: 104.9, ask: "pin", mac: mac) == waitWords && one.refusal(now: 105, ask: "pin", mac: mac) == nil,
      "after one failure a PIN waits the same 5 s and is taken, not stopped")

// The PIN stop: after exactly 2 failures in a row, never for a password.
let two = afterFailures(2, from: 100, every: 10)            // the second failure at 110
check(two.failuresInARow == 2 && two.lastFailure == 110, "two failures: counted, the last one's time kept")
check(two.refusal(now: 200, ask: "pin", mac: mac) == pinStopWords, "two wrong PINs: no third, with the Mac's name and the card's risk")
check(two.refusal(now: 10_000, ask: "pin", mac: mac) == pinStopWords, "…however long it is left")
check(two.refusal(now: 111, ask: "pin", mac: mac) == pinStopWords, "the stop comes before the wait: no \"try again\" for a PIN that must not be tried")
check(two.refusal(now: 111, ask: "password", mac: mac) == waitWords, "a password after two failures waits the 5 s")
check(two.refusal(now: 115, ask: "password", mac: mac) == nil, "…and is taken")
for n in [3, 4, 10] {
    check(afterFailures(n).refusal(now: 10_000, ask: "password", mac: mac) == nil, "a password is never stopped (\(n) failures)")
    check(afterFailures(n).refusal(now: 10_000, ask: "pin", mac: mac) == pinStopWords, "a PIN stays stopped (\(n) failures)")
}

// An unlock starts over, and so does the Mac unlocking by hand.
var unlocked = afterFailures(2); unlocked.began(); unlocked.ended(outcome: LockScreenOutcome.unlocked, now: 300)
check(!unlocked.inFlight && unlocked.failuresInARow == 0 && unlocked.lastFailure == nil, "unlocked: the count and the time start over")
check(unlocked.refusal(now: 300, ask: "pin", mac: mac) == nil, "…so a PIN is taken at once")
unlocked.began(); unlocked.ended(outcome: LockScreenOutcome.stillLocked, now: 310)
check(unlocked.failuresInARow == 1 && unlocked.refusal(now: 320, ask: "pin", mac: mac) == nil, "one failure since: counted from nothing, not stopped")
var byHand = afterFailures(2)
byHand.macUnlocked()
check(byHand.failuresInARow == 0 && byHand.lastFailure == nil, "the Mac unlocked by hand: the count and the time start over")
check(byHand.refusal(now: 111, ask: "pin", mac: mac) == nil, "…so a PIN is taken at once, with the wait gone too")
var byHandOne = afterFailures(1)
byHandOne.macUnlocked()
check(byHandOne.refusal(now: 101, ask: "password", mac: mac) == nil, "one failure, then the Mac unlocked: no wait")
var byHandBusy = afterFailures(2); byHandBusy.began(); byHandBusy.macUnlocked()
check(byHandBusy.failuresInARow == 0 && byHandBusy.refusal(now: 500, ask: "pin", mac: mac) == inFlightWords,
      "unlocking by hand clears the count, not an attempt that is still typing")

// Anything but a wrong entry or an unlock only ends the attempt.
for o in ["refused", "locked", "notLocked", "quarantined"] {
    var a = fresh; a.began(); a.ended(outcome: o, now: 50)
    check(!a.inFlight && a.failuresInARow == 0 && a.lastFailure == nil && a.refusal(now: 50, ask: "pin", mac: mac) == nil, "\(o) ends the flight and counts nothing")
    var b = afterFailures(1); b.began(); b.ended(outcome: o, now: 150)
    check(!b.inFlight && b.failuresInARow == 1 && b.lastFailure == 100, "\(o) after a failure leaves the count and the time as they were")
}

// 3,000 random sessions of attempts, endings and the Mac unlocking, against a model of the plan's three limits.
struct Rng: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
var rng = Rng(state: 0x51_11)
let endings = [LockScreenOutcome.unlocked, LockScreenOutcome.stillLocked, LockScreenOutcome.refused, LockScreenOutcome.locked,
               LockScreenOutcome.notLocked, "quarantined"]
var held = 0
for _ in 0..<3_000 {
    var a = Attempts(), inFlight = false, fails = 0, last: Double? = nil, clock = 0.0, ok = true
    for _ in 0..<40 {
        clock += Double.random(in: 0...4, using: &rng)
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: a.began(); inFlight = true
        case 1:
            let o = endings.randomElement(using: &rng)!
            a.ended(outcome: o, now: clock); inFlight = false
            if o == LockScreenOutcome.stillLocked { fails += 1; last = clock } else if o == LockScreenOutcome.unlocked { fails = 0; last = nil }
        case 2: a.macUnlocked(); fails = 0; last = nil
        default: break
        }
        for ask in [LockScreenAsk.password, LockScreenAsk.pin] {
            let expected: String? = inFlight ? inFlightWords
                : ask == "pin" && fails >= 2 ? pinStopWords
                : (last.map { clock - $0 < 5 } ?? false) ? waitWords : nil
            if a.refusal(now: clock, ask: ask, mac: mac) != expected { ok = false }
        }
        if a.inFlight != inFlight || a.failuresInARow != fails || a.lastFailure != last { ok = false }
    }
    if ok { held += 1 }
}
check(held == 3_000, "random sessions match the model (\(held) of 3000)")

// MARK: The verdict on an unlock request

// What a request is judged on, and the plan's order of what stops it: the door, the switch, the away switch,
// the console, the lock state (the Mac already unlocked: nothing to type), the secret, the attempts.
struct Request {
    var tls = true, away = false, onConsole = true, locked = true
    var policy = UnlockPolicy(allow: true, allowAway: false)
    var secret: String? = "zq7-made-up-secret"
    var ask = LockScreenAsk.password
    var attempts = Attempts()
    var now = 1_000.0
    func verdict() -> UnlockVerdict {
        UnlockJudge.verdict(tls: tls, policy: policy, away: away, onConsole: onConsole, locked: locked, secret: secret, ask: ask,
                            attempts: attempts, now: now, mac: mac)
    }
}
let doorWords = "This connection can’t unlock Ivor’s Studio."
let switchWords = "Unlocking from devices is off on Ivor’s Studio. It can be turned on in Sill on the Mac, in Settings › General."
let awayWords = "Unlocking from devices away from home is off on Ivor’s Studio."
let consoleWords = "Ivor’s Studio is showing another user’s session."
let secretWords = "Sill can’t type that password."
check(Request().verdict() == .go, "everything in order: go")

typealias Fault = (name: String, apply: (inout Request) -> Void, verdict: UnlockVerdict)
let faults: [Fault] = [
    ("the door", { $0.tls = false }, .refuse(doorWords)),
    ("the switch", { $0.policy = UnlockPolicy(allow: false, allowAway: false) }, .refuse(switchWords)),
    ("the away switch", { $0.away = true }, .refuse(awayWords)),
    ("the console", { $0.onConsole = false }, .refuse(consoleWords)),
    ("the lock state", { $0.locked = false }, .alreadyUnlocked),
    ("the secret", { $0.secret = nil }, .refuse(secretWords)),
    ("the attempts", { $0.attempts.began() }, .refuse(inFlightWords)),
]
for f in faults {
    var r = Request(); f.apply(&r)
    check(r.verdict() == f.verdict, "\(f.name) alone: \(f.verdict)")
}
// Every combination of the seven: the first of them in the plan's order is what the answer is, and no
// refusal repeats the secret.
var orderHeld = 0
for mask in 0..<(1 << faults.count) {
    var r = Request()
    for (i, f) in faults.enumerated() where mask & (1 << i) != 0 { f.apply(&r) }
    let want = faults.enumerated().first { mask & (1 << $0.offset) != 0 }?.element.verdict ?? .go
    let got = r.verdict()
    if got == want { orderHeld += 1 } else { check(false, "faults \(String(mask, radix: 2)): \(got), want \(want)") }
    if case .refuse(let words) = got { check(!words.contains("zq7-made-up-secret"), "a refusal never repeats the secret") }
}
check(orderHeld == 1 << faults.count, "all \(1 << faults.count) combinations of faults are judged in the plan's order (\(orderHeld))")

// The secret's refusals, by what the lock screen asks for (LockScreenAsk.word) and by what is wrong with it.
let badSecrets: [(String, String?)] = [("none", nil), ("empty", ""), ("129 characters", String(repeating: "a", count: 129)),
                                       ("a newline in it", "pass\nword"), ("a return in it", "pass\rword")]
for (name, bad) in badSecrets {
    for (ask, words) in [("password", "Sill can’t type that password."), ("pin", "Sill can’t type that PIN."),
                         ("someLaterAsk", "Sill can’t type that password or PIN.")] {
        var r = Request(); r.secret = bad; r.ask = ask
        check(r.verdict() == .refuse(words), "a secret that is \(name), asked for as \(ask): \(words)")
    }
}
// The attempts' refusals through the verdict.
var inFlight = Request(); inFlight.attempts.began()
check(inFlight.verdict() == .refuse(inFlightWords), "an attempt already in flight: refused with the Mac's name")
var pinStop = Request(); pinStop.ask = "pin"; pinStop.attempts = afterFailures(2, from: 100, every: 10); pinStop.now = 500
check(pinStop.verdict() == .refuse(pinStopWords), "two wrong PINs: refused")
pinStop.ask = "password"
check(pinStop.verdict() == .go, "…a password is taken")
var waiting = Request(); waiting.attempts = afterFailures(1, from: 995); waiting.now = 1_000
check(waiting.verdict() == .go, "a failure 5.0 s ago: go")
waiting.now = 999.9
check(waiting.verdict() == .refuse(waitWords), "a failure 4.9 s ago: wait")
// The ways to go.
var awayOK = Request(); awayOK.away = true; awayOK.policy = UnlockPolicy(allow: true, allowAway: true)
check(awayOK.verdict() == .go, "away from home with both switches on: go")
var homeBoth = Request(); homeBoth.policy = UnlockPolicy(allow: true, allowAway: true)
check(homeBoth.verdict() == .go, "at home with both switches on: go")
var pinOK = Request(); pinOK.ask = "pin"; pinOK.attempts = afterFailures(1, from: 900)
check(pinOK.verdict() == .go, "a PIN after one failure, long enough ago: go")
var widest = Request(); widest.secret = String(repeating: "😀", count: 128)
check(widest.verdict() == .go, "128 emoji: go")
var spaced = Request(); spaced.secret = "pässwörd with spaces ’"
check(spaced.verdict() == .go, "a password with spaces and accents: go")

// MARK: Lock again

typealias Again = LockAgain
func locks(enabled: Bool = true, unlockedBySill: Bool = true, leftAt: Double = 1_000, now: Double = 1_030,
           unlockerBack: Bool = false, locked: Bool = false, usedSince: Bool = false) -> Bool {
    Again.locks(enabled: enabled, unlockedBySill: unlockedBySill, leftAt: leftAt, now: now, unlockerBack: unlockerBack, locked: locked, usedSince: usedSince)
}
check(Again.grace == 30, "30 s of grace")
check(locks(), "every condition met, 30 s after the device left: locks")
check(!locks(enabled: false), "the switch off: no")
check(!locks(unlockedBySill: false), "the Mac was not unlocked by Sill's attempt: no")
check(!locks(unlockerBack: true), "the device that unlocked it is back: no")
check(!locks(locked: true), "the Mac is locked already: no")
check(!locks(usedSince: true), "the Mac's own keyboard or mouse, or another device, was used since: no")
check(!locks(enabled: false, unlockedBySill: false, unlockerBack: true, locked: true, usedSince: true), "none of them: no")
check(!locks(now: 1_000), "the moment the device left: no")
check(!locks(now: 1_029.9), "29.9 s after: not yet")
check(locks(now: 1_030), "30 s after: locks")
check(locks(now: 1_030.1) && locks(now: 5_000), "later: locks")
check(!locks(now: 900), "a clock that went back: no")

// MARK: The lock shortcut

typealias Shortcut = LockShortcut
/// Whether `s` is a shortcut for `key` with exactly the modifiers named in `mods` (@ ⌘, ^ ⌃, ~ ⌥, $ ⇧), read field by field.
func isShortcut(_ s: Shortcut?, _ key: Character, _ mods: String) -> Bool {
    s.map { $0.key == key && $0.command == mods.contains("@") && $0.control == mods.contains("^")
        && $0.option == mods.contains("~") && $0.shift == mods.contains("$") } == true
}
check(isShortcut(Shortcut.standard, "q", "@^"), "the standard shortcut is ⌃⌘Q")
check(isShortcut(Shortcut.from(userKeyEquivalent: nil), "q", "@^"), "no key equivalent for Lock Screen: the standard ⌃⌘Q")
check(isShortcut(Shortcut.from(userKeyEquivalent: "@^q"), "q", "@^"), "@^q is ⌃⌘Q")
check(isShortcut(Shortcut.from(userKeyEquivalent: "^@Q"), "q", "@^"), "^@Q: the order does not matter and the key is lowercased")
check(isShortcut(Shortcut.from(userKeyEquivalent: "$@~l"), "l", "$@~"), "$@~l is ⇧⌥⌘L")
check(isShortcut(Shortcut.from(userKeyEquivalent: "@q"), "q", "@"), "⌘ alone with a key counts")
check(isShortcut(Shortcut.from(userKeyEquivalent: "^q"), "q", "^"), "⌃ alone with a key counts")
check(isShortcut(Shortcut.from(userKeyEquivalent: "~q"), "q", "~"), "⌥ alone with a key counts")
check(isShortcut(Shortcut.from(userKeyEquivalent: "@1"), "1", "@") && isShortcut(Shortcut.from(userKeyEquivalent: "@^Ö"), "ö", "@^"), "a digit, a capital with an accent")
check(Shortcut.from(userKeyEquivalent: "q") == nil, "a key alone is not a lock shortcut")
check(Shortcut.from(userKeyEquivalent: "") == nil, "an empty key equivalent: none")
check(Shortcut.from(userKeyEquivalent: "@") == nil && Shortcut.from(userKeyEquivalent: "@^") == nil, "modifiers without a key: none")
check(Shortcut.from(userKeyEquivalent: "@^qq") == nil, "two keys: none")
check(Shortcut.from(userKeyEquivalent: "$q") == nil, "⇧ and a key is no shortcut a lock could use")
check(Shortcut.from(userKeyEquivalent: "@^ ") == nil && Shortcut.from(userKeyEquivalent: "@\t") == nil, "a space or a tab is no key")
let k = Shortcut(key: "k", command: true, control: false, option: true, shift: false)
check(isShortcut(k, "k", "@~"), "LockShortcut's init sets each field from its own argument")
let k2 = Shortcut(key: "j", command: false, control: true, option: false, shift: true)
check(isShortcut(k2, "j", "^$") && k != k2 && k == Shortcut(key: "k", command: true, control: false, option: true, shift: false), "…and another set, and equality")

print(failures == 0 ? "ok: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
