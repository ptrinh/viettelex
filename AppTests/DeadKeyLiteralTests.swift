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
}
