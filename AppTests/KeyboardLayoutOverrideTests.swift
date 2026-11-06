import Carbon
import XCTest
@testable import VietTelex

// KeyboardLayoutOverride's discoverable surface: which layouts we offer, and whether
// a saved preference still resolves.
//
// `apply` decides whether OUR translation must stand in for the OS's, so the tests
// below assert that decision and the table it builds — not any macOS side effect.
// Two documented ways to make macOS do it were tried and measured inert; see the
// KeyboardLayoutOverride header before reaching for either again.
final class KeyboardLayoutOverrideTests: XCTestCase {

    private let s = AppState.shared
    private var savedLayout = ""

    override func setUp() {
        super.setUp()
        savedLayout = s.keyboardLayoutID
    }

    override func tearDown() {
        s.keyboardLayoutID = savedLayout
        super.tearDown()
    }

    /// Every Mac ships ABC and Colemak, so an empty or ABC-less list means the TIS
    /// filter regressed (wrong type constant, or ASCII-capable dropped).
    func testInstalledListsStockAsciiLayouts() {
        let ids = Set(KeyboardLayoutOverride.installed().map(\.id))
        XCTAssertTrue(ids.contains("com.apple.keylayout.ABC"))
        XCTAssertTrue(ids.contains("com.apple.keylayout.Colemak"))
    }

    /// Non-ASCII layouts can't carry Telex — a Telex key must map to a bare Latin
    /// letter — so they must never reach the picker.
    func testInstalledExcludesNonAsciiLayouts() {
        let ids = Set(KeyboardLayoutOverride.installed().map(\.id))
        XCTAssertFalse(ids.contains("com.apple.keylayout.Thai"))
        XCTAssertFalse(ids.contains("com.apple.keylayout.Hebrew"))
    }

    /// The picker shows names, so a layout with no name would render as a blank row.
    func testEveryOptionHasANonEmptyName() {
        for option in KeyboardLayoutOverride.installed() {
            XCTAssertFalse(option.name.isEmpty, "no display name for \(option.id)")
        }
    }

    /// Guards the Settings fallback: a preference naming a layout that has since been
    /// uninstalled must report false so the picker can drop back to "follow".
    func testIsInstalledDistinguishesRealFromStaleIDs() {
        XCTAssertTrue(KeyboardLayoutOverride.isInstalled(KeyboardLayoutOverride.systemDefault))
        XCTAssertTrue(KeyboardLayoutOverride.isInstalled("com.apple.keylayout.Colemak"))
        XCTAssertFalse(KeyboardLayoutOverride.isInstalled("com.apple.keylayout.NoSuchLayout"))
    }

    /// The sentinel must leave events untouched, not look up a layout named "".
    func testApplyingSystemDefaultRemapsNothing() {
        XCTAssertFalse(KeyboardLayoutOverride.apply(KeyboardLayoutOverride.systemDefault))
        XCTAssertNil(KeyboardLayoutOverride.translator)
    }

    /// Pinning the layout macOS is ALREADY on must not build a translator: that is
    /// what keeps a QWERTY user on the untouched 1.5.7 code path, and what makes the
    /// remapping path reachable only when typing is already wrong.
    func testPinningTheLiveLayoutRemapsNothing() {
        let live = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(live, kTISPropertyInputSourceID) else {
            return XCTFail("no current keyboard layout")
        }
        let liveID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        XCTAssertFalse(KeyboardLayoutOverride.apply(liveID))
        XCTAssertNil(KeyboardLayoutOverride.translator)
    }

    /// Pinning a DIFFERENT layout builds the table — the case the whole feature
    /// exists for.
    func testPinningAnotherLayoutBuildsATranslator() throws {
        let live = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let ptr = try XCTUnwrap(TISGetInputSourceProperty(live, kTISPropertyInputSourceID))
        let liveID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        let other = liveID == "com.apple.keylayout.Colemak"
            ? "com.apple.keylayout.ABC" : "com.apple.keylayout.Colemak"

        XCTAssertTrue(KeyboardLayoutOverride.apply(other))
        let translator = try XCTUnwrap(KeyboardLayoutOverride.translator)
        XCTAssertEqual(translator.layoutID, other)

        // Back to the live layout: the translator must be torn down, not left behind
        // remapping every key by one layout forever.
        XCTAssertFalse(KeyboardLayoutOverride.apply(liveID))
        XCTAssertNil(KeyboardLayoutOverride.translator)
    }

    /// The two layouts disagree on where the letters sit, which is the entire point.
    /// keyCode 1 is QWERTY "s"; Colemak puts "r" on that key.
    func testTranslatorMapsKeyCodesThroughTheChosenLayout() throws {
        let abc = try XCTUnwrap(layoutSource("com.apple.keylayout.ABC"))
        let colemak = try XCTUnwrap(layoutSource("com.apple.keylayout.Colemak"))
        let qwerty = try XCTUnwrap(KeyboardLayoutTranslator(layoutID: "abc", source: abc))
        let cole = try XCTUnwrap(KeyboardLayoutTranslator(layoutID: "cole", source: colemak))

        XCTAssertEqual(qwerty.character(keyCode: 1, shift: false), "s")
        XCTAssertEqual(cole.character(keyCode: 1, shift: false), "r")
        XCTAssertEqual(qwerty.character(keyCode: 1, shift: true), "S")
    }

    /// Control keys are dispatched by keyCode long before translation and must not
    /// come back as text — a Return that translated to "\r" would be typed literally.
    func testTranslatorIgnoresControlAndUnknownKeys() throws {
        let abc = try XCTUnwrap(layoutSource("com.apple.keylayout.ABC"))
        let qwerty = try XCTUnwrap(KeyboardLayoutTranslator(layoutID: "abc", source: abc))
        XCTAssertNil(qwerty.character(keyCode: 36, shift: false))    // Return
        XCTAssertNil(qwerty.character(keyCode: 48, shift: false))    // Tab
        XCTAssertNil(qwerty.character(keyCode: 51, shift: false))    // Backspace
        XCTAssertNil(qwerty.character(keyCode: 9999, shift: false))  // out of range
    }

    /// Caps Lock with a pinned layout used to be dropped: the table was read with the
    /// Shift flag alone, so Caps Lock typed lowercase. Letters capitalise; digits and
    /// punctuation keep their plain symbol; Shift on top still gives a capital (macOS
    /// semantics, unlike Windows).
    func testCapsLockCapitalisesLettersOnly() {
        let a = UInt8(ascii: "a"), one = UInt8(ascii: "1"), semi = UInt8(ascii: ";")
        XCTAssertFalse(KeyboardLayoutTranslator.effectiveShift(shift: false, capsLock: false, plainASCII: a))
        XCTAssertTrue(KeyboardLayoutTranslator.effectiveShift(shift: false, capsLock: true, plainASCII: a))
        XCTAssertTrue(KeyboardLayoutTranslator.effectiveShift(shift: true, capsLock: true, plainASCII: a))
        XCTAssertTrue(KeyboardLayoutTranslator.effectiveShift(shift: true, capsLock: false, plainASCII: a))
        XCTAssertFalse(KeyboardLayoutTranslator.effectiveShift(shift: false, capsLock: true, plainASCII: one))
        XCTAssertFalse(KeyboardLayoutTranslator.effectiveShift(shift: false, capsLock: true, plainASCII: semi))
        XCTAssertTrue(KeyboardLayoutTranslator.effectiveShift(shift: true, capsLock: true, plainASCII: one))
        XCTAssertFalse(KeyboardLayoutTranslator.effectiveShift(shift: false, capsLock: true, plainASCII: nil))
    }

    /// End to end through a real layout table: Colemak keyCode 1 is "r".
    func testTranslatorHonoursCapsLock() throws {
        let colemak = try XCTUnwrap(layoutSource("com.apple.keylayout.Colemak"))
        let cole = try XCTUnwrap(KeyboardLayoutTranslator(layoutID: "cole", source: colemak))
        XCTAssertEqual(cole.character(keyCode: 1, shift: false, capsLock: true), "R")
        XCTAssertEqual(cole.character(keyCode: 1, shift: true, capsLock: true), "R")
        XCTAssertEqual(cole.character(keyCode: 1, shift: false, capsLock: false), "r")
        XCTAssertEqual(cole.character(keyCode: 18, shift: false, capsLock: true), "1")   // digit row
        XCTAssertEqual(cole.character(keyCode: 18, shift: true, capsLock: true), "!")
    }

    private func layoutSource(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return (TISCreateInputSourceList(filter, true)?.takeRetainedValue()
            as? [TISInputSource])?.first
    }

    /// A chosen layout survives a settings round trip, and clearing it returns to
    /// "follow" — the value an upgrade from 1.5.7 starts on, so the QWERTY majority
    /// sees no behaviour change.
    func testPreferenceRoundTrips() {
        s.keyboardLayoutID = "com.apple.keylayout.Colemak"
        XCTAssertEqual(s.keyboardLayoutID, "com.apple.keylayout.Colemak")
        XCTAssertEqual(s.defaults.string(forKey: "keyboardLayoutID"),
                       "com.apple.keylayout.Colemak")

        s.keyboardLayoutID = KeyboardLayoutOverride.systemDefault
        XCTAssertEqual(s.keyboardLayoutID, KeyboardLayoutOverride.systemDefault)
    }

    /// A stale saved layout must not leave the Picker with an unmatched tag (SwiftUI
    /// renders that as an empty control).
    func testSettingsModelFallsBackWhenSavedLayoutIsGone() {
        s.keyboardLayoutID = "com.apple.keylayout.NoSuchLayout"
        let model = SettingsModel(selected: .general)
        XCTAssertEqual(model.keyboardLayoutID, KeyboardLayoutOverride.systemDefault)
    }
}
