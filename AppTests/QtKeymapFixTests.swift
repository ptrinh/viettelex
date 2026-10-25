import XCTest
@testable import VietTelex

// Issue #131 — ⌫/⌦ shortcuts dead in Qt 5 apps (DaVinci Resolve Media Pool) while an
// IMKit input method is selected. See the QtKeymapFix header for the Qt source trace.
final class QtKeymapFixTests: XCTestCase {

    func testQtCoreNamesAsAppsShipThem() {
        XCTAssertTrue(QtKeymapFix.isQtCoreName("QtCore.framework"))     // macdeployqt
        XCTAssertTrue(QtKeymapFix.isQtCoreName("libQt5Core.5.dylib"))
        XCTAssertTrue(QtKeymapFix.isQtCoreName("libQt5Core.dylib"))
        XCTAssertTrue(QtKeymapFix.isQtCoreName("libQt6Core.6.dylib"))
        XCTAssertFalse(QtKeymapFix.isQtCoreName("QtGui.framework"))
        XCTAssertFalse(QtKeymapFix.isQtCoreName("Sparkle.framework"))
        XCTAssertFalse(QtKeymapFix.isQtCoreName("Electron Framework.framework"))
        XCTAssertFalse(QtKeymapFix.isQtCoreName("libcrypto.3.dylib"))
    }

    func testBundleListingDetection() {
        XCTAssertTrue(QtKeymapFix.looksLikeQt(entries: ["QtGui.framework", "QtCore.framework", "QtWidgets.framework"]))
        XCTAssertTrue(QtKeymapFix.looksLikeQt(entries: ["libavcodec.dylib", "libQt5Core.5.dylib"]))
        XCTAssertFalse(QtKeymapFix.looksLikeQt(entries: ["Electron Framework.framework", "Squirrel.framework"]))
        XCTAssertFalse(QtKeymapFix.looksLikeQt(entries: []))
    }

    /// The reporter's client id must be covered even if its bundle can't be read.
    func testBlackmagicAppsAreKnownQt() {
        XCTAssertTrue(QtKeymapFix.isKnownQtBundle("com.blackmagic-design.DaVinciResolve"))
        XCTAssertTrue(QtKeymapFix.isKnownQtBundle("com.blackmagic-design.Fusion"))
        XCTAssertFalse(QtKeymapFix.isKnownQtBundle("com.apple.TextEdit"))
        XCTAssertFalse(QtKeymapFix.isKnownQtBundle("com.blackmagic"))
    }

    /// Only Qt clients get an override, and only with the layout macOS already
    /// translates with — typing must not change, an unknown live layout means no-op.
    func testOverrideDecision() {
        XCTAssertEqual(QtKeymapFix.overrideLayout(isQt: true, live: "com.apple.keylayout.ABC"),
                       "com.apple.keylayout.ABC")
        XCTAssertEqual(QtKeymapFix.overrideLayout(isQt: true, live: "com.apple.keylayout.Colemak"),
                       "com.apple.keylayout.Colemak")
        XCTAssertNil(QtKeymapFix.overrideLayout(isQt: false, live: "com.apple.keylayout.ABC"))
        XCTAssertNil(QtKeymapFix.overrideLayout(isQt: true, live: "?"))
        XCTAssertNil(QtKeymapFix.overrideLayout(isQt: true, live: ""))
        XCTAssertNil(QtKeymapFix.overrideLayout(isQt: true, live: nil))
    }

    /// The live layout reported by TIS is always a real keyboard layout (has uchr),
    /// never our input mode — otherwise the override would hand Qt the same NullMode.
    func testLiveLayoutIsAKeyboardLayout() {
        let live = KeyboardLayoutOverride.liveLayoutID()
        XCTAssertNotEqual(live, "?")
        XCTAssertFalse(live.hasPrefix("com.viettelex"), live)
    }
}
