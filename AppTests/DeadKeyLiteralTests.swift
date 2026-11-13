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
}
