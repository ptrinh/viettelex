// KeyboardLayoutTranslator.swift
// Ported from the VTX fork (github.com/xkhanhs/vtx, MIT) — credit: xkhanhs.
// Physical key → character, through a keyboard layout WE choose rather than the one
// macOS happens to have bound to the input method.
//
// Needed because macOS gives an input method no say in its own layout: see
// KeyboardLayoutOverride for the measurements that ruled out both documented routes
// (TISSetInputMethodKeyboardLayoutOverride is inert; a selection bounce is ignored).
// Translating the keycode ourselves is the only mechanism left that does not depend
// on the OS cooperating.
//
// PRECOMPUTED, because this sits on the keystroke path. UCKeyTranslate itself is not
// free (it walks the layout's tables and can allocate), and the engine budget is
// ~0.15 µs/key. So the whole layout is resolved ONCE when the user picks it — 128
// keycodes × {plain, shift} — into a flat array the hot path indexes. Building the
// table costs a few hundred UCKeyTranslate calls at settings-change time, which is
// free at that cadence.
//
// ASCII ONLY. A Telex key must be a bare Latin letter, digit or punctuation mark;
// a dead key is stored as the character it types on its own (' on U.S. International
// – PC), and anything else outside ASCII (accented output, multi-char sequences, a
// dead key whose own character is ´ or ¨) is stored as nil and the caller falls back to the OS's own characters.
// That keeps exotic layouts from silently mangling input instead of degrading to
// today's behaviour.

import Carbon
import Foundation

struct KeyboardLayoutTranslator {
    /// kTISPropertyInputSourceID of the layout this table was built from.
    let layoutID: String

    /// [keyCode * 2 + (shift ? 1 : 0)] → ASCII value, 0 when the key produces
    /// something we deliberately don't handle (see ASCII ONLY above).
    private let table: [UInt8]

    /// The inverse: [ascii * 2 + (shift ? 1 : 0)] → keyCode + 1, 0 when no key on this
    /// layout produces that character. Needed to rewrite a ⌘/⌃/⌥ chord, which the app
    /// resolves through the LIVE layout and so has to be handed a DIFFERENT keycode
    /// rather than a different character. First writer wins, which keeps the main row
    /// ahead of the numeric keypad (keycodes 82…92).
    private let reverse: [UInt16]

    /// [keyCode * 2 + (shift ? 1 : 0)] → true when that key is a DEAD key on this
    /// layout (' " ` ~ ^ on U.S. International – PC). Spotlight (#161 follow-up) does
    /// not hand the input method an empty event for it, so "empty characters" alone
    /// cannot identify a dead key there — the layout itself has to say.
    private let dead: [Bool]

    /// [keyCode * 2 + (shift ? 1 : 0)] → the UTF-16 unit a DEAD key types on its own
    /// when that character is NOT ASCII (´ ¨ on German / French layouts), 0 otherwise.
    /// Kept out of `table` on purpose: it must never become a Telex key nor a chord
    /// remap target — it is only what the dead-key rescue inserts (#161).
    private let deadLiteral: [UInt16]

    /// [keyCode * 2 + (shift ? 1 : 0)] → true when ⌥(+Shift)+key is a DEAD key on this
    /// layout (⌥e ´, ⌥u ¨, ⌥i ˆ, ⌥n ˜, ⌥` ` on ABC). The composition that follows is
    /// done by `compose`, on demand — only after such a key.
    private let optionDead: [Bool]

    /// The layout's raw `uchr` bytes (immutable copy) + keyboard type, for `compose`.
    private let layoutData: Data
    private let kbdType: UInt32

    private static let keyCodeCount = 128
    private static let asciiCount = 128

    /// Builds the table, or returns nil when the layout carries no `uchr` data —
    /// true of old-style 'KCHR' resources and of input methods, neither of which can
    /// back a Telex keyboard.
    init?(layoutID: String, source: TISInputSource) {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let kbdType = UInt32(LMGetKbdType())

        var built = [UInt8](repeating: 0, count: Self.keyCodeCount * 2)
        var inverse = [UInt16](repeating: 0, count: Self.asciiCount * 2)
        var deadKeys = [Bool](repeating: false, count: Self.keyCodeCount * 2)
        var deadLits = [UInt16](repeating: 0, count: Self.keyCodeCount * 2)
        var optDead = [Bool](repeating: false, count: Self.keyCodeCount * 2)
        let ok = data.withUnsafeBytes { buf -> Bool in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return false }
            for code in 0..<Self.keyCodeCount {
                for shift in 0...1 {
                    // UCKeyTranslate wants the modifiers in the high byte's format —
                    // the same shift the Carbon docs specify (`modifierKeyState =
                    // (EventRecord.modifiers >> 8) & 0xFF`).
                    let modifiers = UInt32(shift == 1 ? (shiftKey >> 8) : 0)
                    optDead[code * 2 + shift] = Self.deadState(
                        layout, code: UInt16(code),
                        modifiers: modifiers | UInt32(optionKey >> 8), kbdType: kbdType) != 0
                    guard let r = Self.resolve(layout, code: UInt16(code),
                                               modifiers: modifiers, kbdType: kbdType)
                    else { continue }
                    deadKeys[code * 2 + shift] = r.isDead
                    guard let ascii = r.ascii else {
                        deadLits[code * 2 + shift] = r.deadLiteral ?? 0
                        continue
                    }
                    built[code * 2 + shift] = ascii
                    let slot = Int(ascii) * 2 + shift
                    if inverse[slot] == 0 { inverse[slot] = UInt16(code) + 1 }
                }
            }
            return true
        }
        guard ok else { return nil }
        self.layoutID = layoutID
        self.table = built
        self.reverse = inverse
        self.dead = deadKeys
        self.deadLiteral = deadLits
        self.optionDead = optDead
        self.layoutData = data
        self.kbdType = kbdType
    }

    /// One key, one plane → its ASCII character, or nil.
    ///
    /// Dead keys OFF first: a layout where a Telex key is dead (´ on some European
    /// layouts) cannot carry Telex anyway, and asking for the resolved character keeps
    /// the table one-to-one. MASK, not BIT: kUCKeyTranslateNoDeadKeysBit is the bit
    /// INDEX (0), so passing it (as this did until #161) asked for dead-key processing
    /// and every dead key (' " ` ~ ^ on U.S. International – PC) came out nil.
    ///
    /// A dead key whose own character is not ASCII (˜ ˆ on U.S. International – PC)
    /// gets a second try: the dead key followed by Space, i.e. what typing it alone
    /// produces on that layout (~ ^). When even that is not ASCII (´ ¨) the key comes
    /// back with `ascii` nil and its own (non-ASCII) character in `deadLiteral`.
    private static func resolve(_ layout: UnsafePointer<UCKeyboardLayout>, code: UInt16,
                                modifiers: UInt32, kbdType: UInt32)
        -> (ascii: UInt8?, isDead: Bool, deadLiteral: UniChar?)? {
        func translate(_ key: UInt16, _ mods: UInt32, _ options: OptionBits,
                       _ state: inout UInt32) -> UniChar? {
            var length = 0
            var chars: (UniChar, UniChar, UniChar, UniChar) = (0, 0, 0, 0)
            let status = withUnsafeMutableBytes(of: &chars) { raw in
                UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), mods, kbdType, options,
                               &state, 4, &length, raw.bindMemory(to: UniChar.self).baseAddress)
            }
            return status == noErr && length == 1 ? chars.0 : nil
        }
        func printable(_ c: UniChar?) -> UInt8? {
            // Control characters (Return, Tab, Esc, ⌫) are handled by keyCode upstream
            // of any translation and must not be re-derived here.
            guard let c, c >= 0x20, c < 0x7F else { return nil }
            return UInt8(c)
        }
        var state: UInt32 = 0
        let plain = translate(code, modifiers, OptionBits(kUCKeyTranslateNoDeadKeysMask), &state)
        guard plain != nil else { return nil }   // nothing at all: not a dead-key question
        // Was it a dead key? With dead keys ON it produces nothing and sets a state.
        var deadState: UInt32 = 0
        let isDead = translate(code, modifiers, 0, &deadState) == nil && deadState != 0
        if let ascii = printable(plain) { return (ascii, isDead, nil) }
        guard isDead else { return nil }
        let spaced = translate(UInt16(kVK_Space), 0, 0, &deadState)
        if let ascii = printable(spaced) { return (ascii, true, nil) }
        // Neither is ASCII (´ ¨): keep the key's own character for the rescue —
        // dead key + Space first (what typing it alone gives), else the plain one.
        return (nil, true, [spaced, plain].lazy.compactMap { $0 }.first(where: Self.isLiteralUnit))
    }

    /// The dead-key state `code` leaves behind with dead keys ON, 0 when the key is
    /// not dead (it produced output, or nothing at all).
    private static func deadState(_ layout: UnsafePointer<UCKeyboardLayout>, code: UInt16,
                                  modifiers: UInt32, kbdType: UInt32) -> UInt32 {
        var state: UInt32 = 0
        var length = 0
        var chars: (UniChar, UniChar, UniChar, UniChar) = (0, 0, 0, 0)
        let status = withUnsafeMutableBytes(of: &chars) { raw in
            UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, kbdType, 0,
                           &state, 4, &length, raw.bindMemory(to: UniChar.self).baseAddress)
        }
        return status == noErr && length == 0 ? state : 0
    }

    /// Carbon modifier byte (UCKeyTranslate's format) for a key event.
    static func carbonModifiers(shift: Bool, option: Bool, capsLock: Bool) -> UInt32 {
        var m = 0
        if shift { m |= shiftKey }
        if option { m |= optionKey }
        if capsLock { m |= alphaLock }
        return UInt32(m >> 8)
    }

    /// Is ⌥(+Shift)+keyCode a dead key on this layout (⌥e ⌥u ⌥i ⌥n ⌥` on ABC)?
    /// One array read — the only cost an ⌥ chord pays.
    func isOptionDeadKey(keyCode: UInt16, shift: Bool) -> Bool {
        let index = Int(keyCode) * 2 + (shift ? 1 : 0)
        return index < optionDead.count && optionDead[index]
    }

    /// The dead-key state ⌥(+Shift)+keyCode starts, 0 when it is not a dead key.
    func optionDeadState(keyCode: UInt16, shift: Bool, capsLock: Bool) -> UInt32 {
        guard isOptionDeadKey(keyCode: keyCode, shift: shift) else { return 0 }
        let mods = Self.carbonModifiers(shift: shift, option: true, capsLock: capsLock)
        return layoutData.withUnsafeBytes { buf -> UInt32 in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return 0 }
            return Self.deadState(layout, code: keyCode, modifiers: mods, kbdType: kbdType)
        }
    }

    /// Finish a pending dead key with the next key, exactly as the layout would:
    /// ⌥e then e → "é"; ⌥e then Space → "´"; ⌥e then x (no composition) → "´x".
    /// `state` stays non-zero in the result when the key chained another dead state.
    /// Empty text = the layout produced nothing.
    func compose(state: UInt32, keyCode: UInt16, modifiers: UInt32) -> (text: String, state: UInt32) {
        layoutData.withUnsafeBytes { buf -> (String, UInt32) in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return ("", 0) }
            var st = state
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers, kbdType, 0,
                                        &st, chars.count, &length, &chars)
            guard status == noErr else { return ("", 0) }
            return (String(utf16CodeUnits: chars, count: length), st)
        }
    }

    /// A UTF-16 unit the rescue may insert as a dead key's own character: printable,
    /// not a control, not a private-use function-key code, not a lone surrogate.
    static func isLiteralUnit(_ u: UniChar) -> Bool {
        u >= 0x20 && u != 0x7F && !(0x80..<0xA0).contains(u)
            && !(0xD800...0xDFFF).contains(u) && !(0xE000...0xF8FF).contains(u)
    }

    /// The character `keyCode` produces on this layout, or nil to defer to whatever
    /// macOS already decided.
    ///
    /// One bounds check and one array read — no allocation, no Carbon call.
    func character(keyCode: UInt16, shift: Bool) -> Character? {
        guard let ascii = ascii(keyCode: keyCode, shift: shift) else { return nil }
        return Character(UnicodeScalar(ascii))
    }

    /// Same lookup with Caps Lock taken into account. The table only holds the plain
    /// and Shift planes, so Caps Lock has to be folded into the shift bit here —
    /// otherwise a pinned layout types lowercase with Caps Lock on.
    func character(keyCode: UInt16, shift: Bool, capsLock: Bool) -> Character? {
        let effective = Self.effectiveShift(
            shift: shift, capsLock: capsLock, plainASCII: ascii(keyCode: keyCode, shift: false))
        return character(keyCode: keyCode, shift: effective)
    }

    /// Which plane a key reads from. macOS Caps Lock capitalises LETTERS only (digits
    /// and punctuation keep their unshifted symbol), and on a Mac Shift does not undo
    /// it: Caps Lock + Shift + a still types "A". So it is an OR restricted to keys
    /// whose plain character is a letter, not an XOR. Pure so the rule is pinned by
    /// tests.
    static func effectiveShift(shift: Bool, capsLock: Bool, plainASCII: UInt8?) -> Bool {
        if shift { return true }
        guard capsLock, let plain = plainASCII else { return false }
        return (plain >= 0x61 && plain <= 0x7A) || (plain >= 0x41 && plain <= 0x5A)
    }

    /// Same lookup, undecoded — the chord remap compares and re-looks-up raw bytes and
    /// has no use for a Character.
    func ascii(keyCode: UInt16, shift: Bool) -> UInt8? {
        let index = Int(keyCode) * 2 + (shift ? 1 : 0)
        guard index < table.count else { return nil }
        let ascii = table[index]
        return ascii == 0 ? nil : ascii
    }

    /// Is `keyCode` a dead key on this layout (in the plane Shift / Caps Lock select)?
    /// True for ASCII dead keys (' " ` ~ ^) and non-ASCII ones (´ ¨). One array read.
    func isDeadKey(keyCode: UInt16, shift: Bool, capsLock: Bool) -> Bool {
        let effective = Self.effectiveShift(
            shift: shift, capsLock: capsLock, plainASCII: ascii(keyCode: keyCode, shift: false))
        let index = Int(keyCode) * 2 + (effective ? 1 : 0)
        return index < dead.count && dead[index]
    }

    /// What a DEAD key types on its own, ASCII (' " ` ~ ^) or not (´ ¨), or nil when the
    /// key is not dead on this layout. Two array reads. This is the rescue's literal
    /// (#161) — never a Telex key: non-ASCII literals go to the engine as punctuation.
    func deadLiteral(keyCode: UInt16, shift: Bool, capsLock: Bool) -> Character? {
        guard isDeadKey(keyCode: keyCode, shift: shift, capsLock: capsLock) else { return nil }
        let effective = Self.effectiveShift(
            shift: shift, capsLock: capsLock, plainASCII: ascii(keyCode: keyCode, shift: false))
        if let a = ascii(keyCode: keyCode, shift: effective) { return Character(UnicodeScalar(a)) }
        let index = Int(keyCode) * 2 + (effective ? 1 : 0)
        guard index < deadLiteral.count, deadLiteral[index] != 0,
              let scalar = UnicodeScalar(deadLiteral[index]) else { return nil }
        return Character(scalar)
    }

    /// The keyCode that produces `ascii` on this layout, or nil when none does.
    func keyCode(forASCII ascii: UInt8, shift: Bool) -> UInt16? {
        let index = Int(ascii) * 2 + (shift ? 1 : 0)
        guard index < reverse.count else { return nil }
        let code = reverse[index]
        return code == 0 ? nil : code - 1
    }
}

/// Dead keys while VietTelex is the input source (#161).
///
/// On a layout where ' " ` ~ ^ are dead keys (U.S. International – PC, several
/// European and Brazilian layouts) macOS hands the input method an event with EMPTY
/// characters for them: the dead-key composition ("'" then "e" → "é") is the work of
/// the layout's own input source, which is not running while an input method is.
/// Passing such a key through therefore typed nothing — the reporter's "không viết
/// được dấu ' và \"". Vietnamese typing has no use for that composition, so the key
/// types its own character, literally, the way it would on ABC.
///
/// Pure, so the rule is pinned by tests; `live` is the dead-keys-off lookup of the
/// same key on the live layout (KeyboardLayoutOverride.liveCharacter), evaluated only
/// when needed.
enum DeadKeyLiteral {
    /// The text this key should count as.
    /// - eventCharacters: what macOS put in the event ("" for a dead key).
    /// - afterDeadKey: the PREVIOUS key was a dead key. If macOS kept the dead state
    ///   anyway, this key arrives composed ("é", or "'x" for a key with no
    ///   composition) although its ' was already typed — so it reads as the plain
    ///   key instead.
    /// - deadOnLayout: the live layout says THIS key is a dead key. Spotlight's search
    ///   field (com.apple.campo / com.apple.Spotlight) does not deliver it as an empty
    ///   event, so the key resolves to its own character whatever macOS put in it.
    static func resolve(eventCharacters: String?, afterDeadKey: Bool, deadOnLayout: Bool = false,
                        live: () -> Character?) -> String? {
        let empty = eventCharacters?.isEmpty ?? true
        guard empty || afterDeadKey || deadOnLayout, let c = live() else { return eventCharacters }
        return String(c)
    }

    /// Is this the empty-characters event of a dead key? (Modifier chords never get
    /// here; a function key carries U+F7xx, never "".)
    static func isDeadKeyEvent(_ characters: String?) -> Bool {
        characters?.isEmpty ?? false
    }

    /// Worth asking the layout whether this key is dead? Letters and digits never are
    /// on any layout Telex can run on, so the common keystroke skips the table read;
    /// "" (the usual dead-key event), punctuation and accents (´ ¨ ˆ) are asked.
    static func mayBeDeadKey(_ characters: String?) -> Bool {
        guard let c = characters?.first else { return true }
        if let a = c.asciiValue {
            return !((a >= 0x30 && a <= 0x39) || (a | 0x20 >= 0x61 && a | 0x20 <= 0x7A))
        }
        return true
    }

    /// What a non-word key must be INSERTED as by VietTelex (handle() returns true),
    /// or nil to let macOS type the event itself.
    /// - ours: effectiveCharacters (already resolved through `resolve`).
    /// - deadOnLayout: a layout dead key is ALWAYS inserted, even when the event
    ///   already carries that very character: handed back to the client, Spotlight
    ///   runs the layout's dead-key composition on it and types nothing (#161,
    ///   reporter: ' " work everywhere after 1.9.9 except the Spotlight field).
    /// - A dead key whose own character is not ASCII (´ ¨, German / French) is
    ///   inserted too — it counts as punctuation, never as a Telex key.
    static func insertion(ours: String?, eventCharacters: String?, deadOnLayout: Bool) -> String? {
        guard let ours, ours != eventCharacters || deadOnLayout else { return nil }
        if TelexInputController.insertsOneCharacter(ours) { return ours }
        let deadKey = deadOnLayout || isDeadKeyEvent(eventCharacters)
        return deadKey && isLiteral(ours) ? ours : nil
    }

    /// One printable character a dead key may type on its own (' or ´ alike): not
    /// empty, not a control, not a function-key code (U+F7xx).
    static func isLiteral(_ text: String?) -> Bool {
        guard let text, text.count == 1, text.utf16.count <= 2,
              let u = text.utf16.first else { return false }
        return KeyboardLayoutTranslator.isLiteralUnit(u) || (0xD800...0xDBFF).contains(u)
    }

    /// Same prefilter as `mayBeDeadKey`, for the tap (first UTF-16 unit of the event;
    /// nil = empty event).
    @inline(__always)
    static func mayBeDeadKey(unit: UniChar?) -> Bool {
        guard let u = unit else { return true }
        if u < 0x80 {
            let a = UInt8(u)
            return !((a >= 0x30 && a <= 0x39) || (a | 0x20 >= 0x61 && a | 0x20 <= 0x7A))
        }
        return true
    }

    // MARK: - Rescue invariant (#161)

    /// THE INVARIANT: while VietTelex is the input source, a plain (no ⌘⌃⌥) keyDown
    /// that is a dead key on the live layout puts EXACTLY ONE character on screen —
    /// never zero (the layout's own dead-key composition does not run while an input
    /// method is selected, so a key handed back to the app types nothing), never two.
    ///
    /// The IMK controller enforces it in ONE place, after its whole decision tree
    /// ran: whatever branch let the key go (`handled == false` — secure field,
    /// tap-defer while the tap is tripped/quarantined/dead, manual Off, a game in
    /// passthrough, stall breaker, machine typing…), the literal is inserted here and
    /// the key consumed. The text to insert, or nil to keep the verdict.
    ///
    /// - handled: the decision tree already returned true (it inserted / composed).
    /// - deadKey: this keyDown is a dead key (empty characters, or the live layout
    ///   says so) without ⌘⌃⌥.
    /// - keepRaw: the key must reach the app as a raw keycode — remote desktop / VM
    ///   (the GUEST composes from the scancode), our own synthetic echoes.
    /// - tapOwned: the event tap already typed this very keystroke (it rewrote the
    ///   physical event in place — DeadKeyHandoff). A tap that swallows a key and
    ///   re-posts the literal never reaches here with the physical event at all, and
    ///   its re-post is keycode 0 + our magic, so it is not a dead key either.
    /// - literal: the key's own character (evaluated only when everything else says
    ///   rescue).
    static func rescue(handled: Bool, deadKey: Bool, keepRaw: Bool, tapOwned: @autoclosure () -> Bool,
                       literal: () -> String?) -> String? {
        guard !handled, deadKey, !keepRaw, !tapOwned(), let text = literal(), isLiteral(text)
        else { return nil }
        return text
    }

    /// Passthrough apps whose dead keys must stay RAW: a remote desktop / VM forwards
    /// the scancode and the guest's own layout composes it — inserting a literal here
    /// would type it twice (or type it on the host). Other passthrough apps (a game's
    /// chat box, a manual "Off" pin on an ordinary app) read TEXT, and there a dead
    /// key passed through types nothing, so they get the rescue.
    static func passthroughKeepsRaw(remoteDesktop: Bool, builtInPassthrough: Bool,
                                    bundleID: String?) -> Bool {
        if remoteDesktop { return true }
        guard builtInPassthrough else { return false }
        guard let id = bundleID else { return true }
        return !textPassthroughPrefixes.contains { id.hasPrefix($0) }
    }

    /// Built-in passthrough entries that are NOT scancode tunnels (typing-modes.yml:
    /// games are there to keep their keys unconverted, not to forward keycodes).
    static let textPassthroughPrefixes = ["com.valvesoftware."]
}

/// Which keystroke the event TAP already typed itself while letting the physical
/// event pass (the in-place rewrite, TerminalTap.modifyInPlace). The rescue must not
/// type it again. Exact match on (keyCode, CGEvent timestamp): the IMK controller
/// receives that same event, so there is no time window to go stale.
/// Written on the tap thread, read on main — guarded.
enum DeadKeyHandoff {
    private static let lock = NSLock()
    private static var owned: (keyCode: UInt16, timestamp: UInt64)?

    static func markTapOwned(keyCode: UInt16, timestamp: UInt64) {
        lock.withLock { owned = (keyCode, timestamp) }
    }

    /// Consumes the mark when it names this keystroke.
    static func consumeTapOwned(keyCode: UInt16, timestamp: UInt64) -> Bool {
        lock.withLock {
            guard let o = owned, o.keyCode == keyCode, o.timestamp == timestamp else { return false }
            owned = nil
            return true
        }
    }
}
