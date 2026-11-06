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
// anything a layout produces outside that (dead keys, accented output, multi-char
// sequences) is stored as nil and the caller falls back to the OS's own characters.
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
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers, kbdType,
                        // No dead keys: a layout where a Telex key is dead (´ on some
                        // European layouts) cannot carry Telex anyway, and asking for
                        // the resolved character keeps the table one-to-one.
                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState, 4, &length, &chars)
                    guard status == noErr, length == 1, chars[0] < 128 else { continue }
                    let ascii = UInt8(chars[0])
                    // Control characters (Return, Tab, Esc, ⌫) are handled by keyCode
                    // upstream of any translation and must not be re-derived here.
                    guard ascii >= 0x20, ascii != 0x7F else { continue }
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
