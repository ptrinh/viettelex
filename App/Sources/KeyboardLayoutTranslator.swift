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
        let ok = data.withUnsafeBytes { buf -> Bool in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return false }
            for code in 0..<Self.keyCodeCount {
                for shift in 0...1 {
                    // UCKeyTranslate wants the modifiers in the high byte's format —
                    // the same shift the Carbon docs specify (`modifierKeyState =
                    // (EventRecord.modifiers >> 8) & 0xFF`).
                    let modifiers = UInt32(shift == 1 ? (shiftKey >> 8) : 0)
                    guard let ascii = Self.resolve(layout, code: UInt16(code), modifiers: modifiers,
                                                   kbdType: kbdType)
                    else { continue }
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
    /// produces on that layout (~ ^). Still nil when even that is not ASCII (´ ¨).
    private static func resolve(_ layout: UnsafePointer<UCKeyboardLayout>, code: UInt16,
                                modifiers: UInt32, kbdType: UInt32) -> UInt8? {
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
        if let ascii = printable(plain) { return ascii }
        guard plain != nil else { return nil }   // nothing at all: not a dead-key question
        // Was it a dead key? With dead keys ON it produces nothing and sets a state.
        state = 0
        guard translate(code, modifiers, 0, &state) == nil, state != 0 else { return nil }
        return printable(translate(UInt16(kVK_Space), 0, 0, &state))
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
    static func resolve(eventCharacters: String?, afterDeadKey: Bool,
                        live: () -> Character?) -> String? {
        let empty = eventCharacters?.isEmpty ?? true
        guard empty || afterDeadKey, let c = live() else { return eventCharacters }
        return String(c)
    }

    /// Is this the empty-characters event of a dead key? (Modifier chords never get
    /// here; a function key carries U+F7xx, never "".)
    static func isDeadKeyEvent(_ characters: String?) -> Bool {
        characters?.isEmpty ?? false
    }
}
