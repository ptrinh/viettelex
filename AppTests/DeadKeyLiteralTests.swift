import Carbon
import XCTest
@testable import VietTelex

// Issue #161: on a layout where ' and " are dead keys (U.S. International – PC) the
// key typed NOTHING while VietTelex was the input source. Two halves:
//  - the layout table must resolve a dead key to its own character (the
//    kUCKeyTranslateNoDeadKeysBit-vs-Mask bug left every dead key nil);
//  - an event with empty characters must count as that character (DeadKeyLiteral),
//    not as a no-text key passed through to a composition that never runs.
final class DeadKeyLiteralTests: XCTestCase {

    private static let usIntlPC = "com.apple.keylayout.USInternational-PC"

    private func layoutSource(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
    }

    private func translator(_ id: String) throws -> KeyboardLayoutTranslator {
        guard let src = layoutSource(id) else { throw XCTSkip("\(id) not installed on this Mac") }
        return try XCTUnwrap(KeyboardLayoutTranslator(layoutID: id, source: src))
    }

    // MARK: - Table (UCKeyTranslate with dead keys OFF)

    func testDeadKeysResolveToTheirOwnCharacterOnUSInternational() throws {
        let t = try translator(Self.usIntlPC)
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_Quote), shift: false), "'")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_Quote), shift: true), "\"")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_Grave), shift: false), "`")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_Grave), shift: true), "~")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_6), shift: true), "^")
        // Ordinary keys unchanged — Telex letters still come out as themselves.
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_S), shift: false), "s")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_W), shift: true), "W")
        // And the reverse table can find them (chord remap).
        XCTAssertEqual(t.keyCode(forASCII: UInt8(ascii: "'"), shift: false), UInt16(kVK_ANSI_Quote))
    }

    func testABCQuoteKeysUnchanged() throws {
        let t = try translator("com.apple.keylayout.ABC")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_Quote), shift: false), "'")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_Quote), shift: true), "\"")
        XCTAssertEqual(t.character(keyCode: UInt16(kVK_ANSI_A), shift: false), "a")
    }

    /// The live-layout cache the key handlers read (any thread).
    func testLiveTableAnswersForTheLiveLayout() throws {
        _ = try translator(Self.usIntlPC)
        let live = KeyboardLayoutOverride.liveLayoutID()
        defer { KeyboardLayoutOverride.refreshLiveTable(live) }
        KeyboardLayoutOverride.refreshLiveTable(Self.usIntlPC)
        XCTAssertEqual(KeyboardLayoutOverride.liveTable?.layoutID, Self.usIntlPC)
        XCTAssertEqual(KeyboardLayoutOverride.liveCharacter(keyCode: UInt16(kVK_ANSI_Quote),
                                                            shift: true, capsLock: false), "\"")
    }

    // MARK: - Handler decision (pure)

    func testEmptyCharactersBecomeTheKeysOwnCharacter() {
        XCTAssertEqual(DeadKeyLiteral.resolve(eventCharacters: "", afterDeadKey: false) { "'" }, "'")
        XCTAssertEqual(DeadKeyLiteral.resolve(eventCharacters: nil, afterDeadKey: false) { "\"" }, "\"")
    }

    func testOrdinaryKeyNeverConsultsTheLayout() {
        var asked = false
        let r = DeadKeyLiteral.resolve(eventCharacters: "a", afterDeadKey: false) { asked = true; return "x" }
        XCTAssertEqual(r, "a")
        XCTAssertFalse(asked, "hot path: no table read for a key that carries characters")
    }

    func testKeyAfterDeadKeyReadsAsThePlainKey() {
        // macOS composed "'" + "e" → "é", but the ' was already typed literally.
        XCTAssertEqual(DeadKeyLiteral.resolve(eventCharacters: "é", afterDeadKey: true) { "e" }, "e")
        // No composition for that pair: the dead char rides along ("'s") — drop it.
        XCTAssertEqual(DeadKeyLiteral.resolve(eventCharacters: "'s", afterDeadKey: true) { "s" }, "s")
    }

    func testUnknownKeyFallsBackToTheEvent() {
        XCTAssertEqual(DeadKeyLiteral.resolve(eventCharacters: "", afterDeadKey: false) { nil }, "")
        XCTAssertEqual(DeadKeyLiteral.resolve(eventCharacters: "é", afterDeadKey: true) { nil }, "é")
    }

    func testDeadKeyEventDetection() {
        XCTAssertTrue(DeadKeyLiteral.isDeadKeyEvent(""))
        XCTAssertFalse(DeadKeyLiteral.isDeadKeyEvent(nil))
        XCTAssertFalse(DeadKeyLiteral.isDeadKeyEvent("'"))
    }

    /// The literal must go through the boundary path as a one-character insert.
    func testLiteralCountsAsOneInsertedCharacter() {
        XCTAssertTrue(TelexInputController.insertsOneCharacter("'"))
        XCTAssertTrue(TelexInputController.insertsOneCharacter("\""))
        XCTAssertFalse(TelexInputController.insertsOneCharacter(""))
    }

    // MARK: - Spotlight (#161 follow-up): dead key NOT delivered as an empty event

    /// The layout table itself must know which keys are dead — Spotlight's event does
    /// not say so.
    func testTableFlagsDeadKeysOnUSInternational() throws {
        let t = try translator(Self.usIntlPC)
        XCTAssertTrue(t.isDeadKey(keyCode: UInt16(kVK_ANSI_Quote), shift: false, capsLock: false))
        XCTAssertTrue(t.isDeadKey(keyCode: UInt16(kVK_ANSI_Quote), shift: true, capsLock: false))
        XCTAssertTrue(t.isDeadKey(keyCode: UInt16(kVK_ANSI_Grave), shift: false, capsLock: false))
        XCTAssertTrue(t.isDeadKey(keyCode: UInt16(kVK_ANSI_6), shift: true, capsLock: false))
        XCTAssertFalse(t.isDeadKey(keyCode: UInt16(kVK_ANSI_6), shift: false, capsLock: false))
        XCTAssertFalse(t.isDeadKey(keyCode: UInt16(kVK_ANSI_S), shift: false, capsLock: false))
        XCTAssertFalse(t.isDeadKey(keyCode: UInt16(kVK_ANSI_Semicolon), shift: false, capsLock: false))
    }

    func testABCHasNoDeadQuote() throws {
        let t = try translator("com.apple.keylayout.ABC")
        XCTAssertFalse(t.isDeadKey(keyCode: UInt16(kVK_ANSI_Quote), shift: false, capsLock: false))
        XCTAssertFalse(t.isDeadKey(keyCode: UInt16(kVK_ANSI_Quote), shift: true, capsLock: false))
    }

    /// Spotlight hands the input method ' WITH its character. The old rule ("insert
    /// only when ours differs from the event") passed it back, and Spotlight then ran
    /// the layout's dead-key composition on it → nothing typed. A layout dead key must
    /// always be inserted by VietTelex.
    func testSpotlightDeadKeyWithCharactersIsStillInserted() {
        let ours = DeadKeyLiteral.resolve(eventCharacters: "'", afterDeadKey: false, deadOnLayout: true) { "'" }
        XCTAssertEqual(ours, "'")
        XCTAssertEqual(DeadKeyLiteral.insertion(ours: ours, eventCharacters: "'", deadOnLayout: true), "'")
        let dq = DeadKeyLiteral.resolve(eventCharacters: "\"", afterDeadKey: false, deadOnLayout: true) { "\"" }
        XCTAssertEqual(DeadKeyLiteral.insertion(ours: dq, eventCharacters: "\"", deadOnLayout: true), "\"")
    }

    /// Spotlight variant carrying the layout's spacing accent (´ ¨) instead: the key
    /// still types its own ASCII character.
    func testSpotlightDeadKeyWithAccentResolvesToLiteral() {
        let ours = DeadKeyLiteral.resolve(eventCharacters: "\u{B4}", afterDeadKey: false, deadOnLayout: true) { "'" }
        XCTAssertEqual(ours, "'")
        XCTAssertEqual(DeadKeyLiteral.insertion(ours: ours, eventCharacters: "\u{B4}", deadOnLayout: true), "'")
    }

    /// Empty-event apps keep the 1.9.9 behaviour.
    func testEmptyEventStillInserted() {
        let ours = DeadKeyLiteral.resolve(eventCharacters: "", afterDeadKey: false, deadOnLayout: true) { "'" }
        XCTAssertEqual(DeadKeyLiteral.insertion(ours: ours, eventCharacters: "", deadOnLayout: true), "'")
        XCTAssertEqual(DeadKeyLiteral.insertion(ours: "'", eventCharacters: "", deadOnLayout: false), "'")
    }

    /// ABC (no dead keys): ' carries "'" and is NOT dead → passthrough, as always.
    func testNonDeadQuotePassesThrough() {
        XCTAssertNil(DeadKeyLiteral.insertion(ours: "'", eventCharacters: "'", deadOnLayout: false))
        XCTAssertNil(DeadKeyLiteral.insertion(ours: nil, eventCharacters: "", deadOnLayout: true))
        XCTAssertNil(DeadKeyLiteral.insertion(ours: "", eventCharacters: "", deadOnLayout: true))
    }

    /// Hot path: letters and digits never read the layout table.
    func testMayBeDeadKeyPrefilter() {
        for c in ["a", "Z", "s", "5", "0"] { XCTAssertFalse(DeadKeyLiteral.mayBeDeadKey(c), c) }
        for c in ["", "'", "\"", "`", "~", "^", "\u{B4}", "\u{A8}"] {
            XCTAssertTrue(DeadKeyLiteral.mayBeDeadKey(c), c)
        }
        XCTAssertTrue(DeadKeyLiteral.mayBeDeadKey(nil))
    }

    // MARK: - Rescue invariant (#161, every branch): exactly one character

    private func rescue(handled: Bool = false, deadKey: Bool = true, keepRaw: Bool = false,
                        tapOwned: Bool = false, literal: String? = "'") -> String? {
        DeadKeyLiteral.rescue(handled: handled, deadKey: deadKey, keepRaw: keepRaw,
                              tapOwned: tapOwned, literal: { literal })
    }

    /// Any branch that let a dead key go (secure field, tap-defer with the tap dead,
    /// manual Off, game passthrough, stall, machine typing): VietTelex inserts it once.
    func testPassedDeadKeyIsInsertedOnce() {
        XCTAssertEqual(rescue(), "'")
        XCTAssertEqual(rescue(literal: "\""), "\"")
    }

    /// Handled already (inserted / composed by the decision tree): never a second copy.
    func testHandledDeadKeyIsNotInsertedAgain() {
        XCTAssertNil(rescue(handled: true))
    }

    /// The tap typed this very keystroke (in-place rewrite): IMK must not add one.
    func testTapOwnedKeyIsNotInsertedByIMK() {
        XCTAssertNil(rescue(tapOwned: true))
        DeadKeyHandoff.markTapOwned(keyCode: 39, timestamp: 12345)
        XCTAssertFalse(DeadKeyHandoff.consumeTapOwned(keyCode: 39, timestamp: 999), "other keystroke")
        XCTAssertTrue(DeadKeyHandoff.consumeTapOwned(keyCode: 39, timestamp: 12345))
        XCTAssertFalse(DeadKeyHandoff.consumeTapOwned(keyCode: 39, timestamp: 12345), "consumed once")
    }

    /// Remote desktop / VM / our own echo: raw, untouched.
    func testRawPassthroughIsNeverRescued() {
        XCTAssertNil(rescue(keepRaw: true))
    }

    /// ABC (no dead key): nothing changes, nothing is even looked up.
    func testOrdinaryKeyIsNeverRescued() {
        var asked = false
        XCTAssertNil(DeadKeyLiteral.rescue(handled: false, deadKey: false, keepRaw: false, tapOwned: false,
                                           literal: { asked = true; return "'" }))
        XCTAssertFalse(asked)
    }

    func testUnknownOrControlLiteralIsNotInserted() {
        XCTAssertNil(rescue(literal: nil))
        XCTAssertNil(rescue(literal: ""))
        XCTAssertNil(rescue(literal: "\r"))
        XCTAssertNil(rescue(literal: "\u{F702}"))
        XCTAssertNil(rescue(literal: "ab"))
    }

    func testPassthroughClassification() {
        XCTAssertTrue(DeadKeyLiteral.passthroughKeepsRaw(remoteDesktop: true, builtInPassthrough: false, bundleID: "x"))
        XCTAssertTrue(DeadKeyLiteral.passthroughKeepsRaw(remoteDesktop: false, builtInPassthrough: true,
                                                         bundleID: "com.vmware.fusion"))
        XCTAssertFalse(DeadKeyLiteral.passthroughKeepsRaw(remoteDesktop: false, builtInPassthrough: true,
                                                          bundleID: "com.valvesoftware.dota2"))
        // Manual "Off" on an ordinary app reads text → rescued.
        XCTAssertFalse(DeadKeyLiteral.passthroughKeepsRaw(remoteDesktop: false, builtInPassthrough: false,
                                                          bundleID: "com.apple.TextEdit"))
        XCTAssertTrue(TelexInputController.deadKeyStaysRaw("com.microsoft.rdc.macos"))
        XCTAssertTrue(TelexInputController.deadKeyStaysRaw("com.vmware.fusion"))
        XCTAssertFalse(TelexInputController.deadKeyStaysRaw("com.valvesoftware.dota2"))
        XCTAssertFalse(TelexInputController.deadKeyStaysRaw("com.apple.TextEdit"))
    }

    func testTapPrefilterByUnit() {
        XCTAssertTrue(DeadKeyLiteral.mayBeDeadKey(unit: nil))
        XCTAssertTrue(DeadKeyLiteral.mayBeDeadKey(unit: UniChar(UInt8(ascii: "'"))))
        XCTAssertTrue(DeadKeyLiteral.mayBeDeadKey(unit: 0xB4))
        XCTAssertFalse(DeadKeyLiteral.mayBeDeadKey(unit: UniChar(UInt8(ascii: "a"))))
        XCTAssertFalse(DeadKeyLiteral.mayBeDeadKey(unit: UniChar(UInt8(ascii: "Z"))))
        XCTAssertFalse(DeadKeyLiteral.mayBeDeadKey(unit: UniChar(UInt8(ascii: "7"))))
    }

    // MARK: - Non-ASCII dead keys (´ ¨ on German / French)

    private func deadLiteralKeys(_ t: KeyboardLayoutTranslator, _ want: Character) -> [(UInt16, Bool)] {
        var hits: [(UInt16, Bool)] = []
        for code in 0..<128 {
            for shift in [false, true]
            where t.deadLiteral(keyCode: UInt16(code), shift: shift, capsLock: false) == want {
                hits.append((UInt16(code), shift))
            }
        }
        return hits
    }

    func testGermanAcuteDeadKeyHasItsOwnLiteral() throws {
        let t = try translator("com.apple.keylayout.German")
        let keys = deadLiteralKeys(t, "\u{B4}")
        XCTAssertFalse(keys.isEmpty, "German ´ dead key must resolve to ´")
        for (code, shift) in keys {
            XCTAssertTrue(t.isDeadKey(keyCode: code, shift: shift, capsLock: false))
            // Never a Telex key / chord target: the ASCII table stays empty for it.
            XCTAssertNil(t.character(keyCode: code, shift: shift))
        }
    }

    func testFrenchDiaeresisDeadKeyHasItsOwnLiteral() throws {
        let t = try translator("com.apple.keylayout.French")
        XCTAssertFalse(deadLiteralKeys(t, "\u{A8}").isEmpty, "French ¨ dead key must resolve to ¨")
    }

    func testNonASCIILiteralIsInsertedAsPunctuation() {
        XCTAssertEqual(DeadKeyLiteral.insertion(ours: "\u{B4}", eventCharacters: "", deadOnLayout: true), "\u{B4}")
        XCTAssertEqual(DeadKeyLiteral.insertion(ours: "\u{A8}", eventCharacters: "", deadOnLayout: false), "\u{A8}")
        // A non-dead key's non-ASCII character still goes through macOS.
        XCTAssertNil(DeadKeyLiteral.insertion(ours: "\u{F6}", eventCharacters: "\u{F6}", deadOnLayout: false))
        XCTAssertEqual(rescue(literal: "\u{B4}"), "\u{B4}")
    }

    // MARK: - Live table freshness

    func testLiveTableStaleness() {
        XCTAssertTrue(KeyboardLayoutOverride.liveTableStale(cachedLayoutID: nil, attempted: false, live: "a"))
        XCTAssertTrue(KeyboardLayoutOverride.liveTableStale(cachedLayoutID: "a", attempted: true, live: "b"))
        XCTAssertFalse(KeyboardLayoutOverride.liveTableStale(cachedLayoutID: "a", attempted: true, live: "a"))
    }

    /// The input-source-changed notification rebuilds the table for the CURRENT layout.
    func testInputSourceChangedRebuildsForLiveLayout() throws {
        _ = try translator(Self.usIntlPC)
        let live = KeyboardLayoutOverride.liveLayoutID()
        defer { KeyboardLayoutOverride.refreshLiveTable(live) }
        KeyboardLayoutOverride.refreshLiveTable(
            live == Self.usIntlPC ? "com.apple.keylayout.ABC" : Self.usIntlPC)
        KeyboardLayoutOverride.inputSourceChanged()
        XCTAssertEqual(KeyboardLayoutOverride.liveTable?.layoutID, live)
    }

    // MARK: - ⌥ dead keys on ABC (⌥e ⌥u ⌥i ⌥n ⌥`)

    private func optionCompose(_ t: KeyboardLayoutTranslator, _ dead: Int, _ next: Int,
                               shift: Bool = false) -> String {
        let st = t.optionDeadState(keyCode: UInt16(dead), shift: false, capsLock: false)
        XCTAssertNotEqual(st, 0, "keyCode \(dead) must be an ⌥ dead key")
        return t.compose(state: st, keyCode: UInt16(next),
                         modifiers: KeyboardLayoutTranslator.carbonModifiers(shift: shift, option: false,
                                                                             capsLock: false)).text
    }

    func testOptionDeadKeysComposeOnABC() throws {
        let t = try translator("com.apple.keylayout.ABC")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_E, kVK_ANSI_E), "é")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_E, kVK_ANSI_E, shift: true), "É")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_U, kVK_ANSI_U), "ü")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_U, kVK_ANSI_I), "ï")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_I, kVK_ANSI_I), "î")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_N, kVK_ANSI_N), "ñ")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_Grave, kVK_ANSI_E), "è")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_E, kVK_Space), "\u{B4}")
        XCTAssertEqual(optionCompose(t, kVK_ANSI_E, kVK_ANSI_X), "\u{B4}x")
    }

    func testOrdinaryOptionChordIsNotDead() throws {
        let t = try translator("com.apple.keylayout.ABC")
        XCTAssertFalse(t.isOptionDeadKey(keyCode: UInt16(kVK_ANSI_S), shift: false))   // ⌥s = ß
        XCTAssertNil(TelexInputController.optionDeadStart(table: t, keyCode: UInt16(kVK_ANSI_S),
                                                          shift: false, capsLock: false))
        XCTAssertNotNil(TelexInputController.optionDeadStart(table: t, keyCode: UInt16(kVK_ANSI_E),
                                                             shift: false, capsLock: false))
        XCTAssertNil(TelexInputController.optionDeadStart(table: nil, keyCode: UInt16(kVK_ANSI_E),
                                                          shift: false, capsLock: false))
    }

    func testOptionDeadOutcome() {
        typealias O = TelexInputController.OptionDeadOutcome
        var asked = false
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 53, commandOrControl: false) {
            asked = true; return ("", 0) }, O.cancel)                                    // Esc
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 51, commandOrControl: false) {
            asked = true; return ("", 0) }, O.cancelConsume)                             // ⌫
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 0, commandOrControl: true) {
            asked = true; return ("", 0) }, O.cancel)                                    // ⌘/⌃
        XCTAssertFalse(asked)
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 14, commandOrControl: false) {
            ("é", 0) }, O.insert("é", state: 0))
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 7, commandOrControl: false) {
            ("\u{B4}x", 0) }, O.insert("\u{B4}x", state: 0))
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 36, commandOrControl: false) {
            ("\u{B4}\r", 0) }, O.insertThenContinue("\u{B4}"))                          // Return
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 123, commandOrControl: false) {
            ("\u{F702}", 0) }, O.cancel)                                                // ←
        XCTAssertEqual(TelexInputController.optionDeadOutcome(keyCode: 14, commandOrControl: false) {
            ("", 7) }, O.insert("", state: 7))                                          // chained
    }
}
