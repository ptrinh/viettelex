import XCTest
import CoreGraphics
@testable import VietTelex

// Shortcut word + Enter (WhatsApp, 2026-08-06): "ko"⏎ expanded to "không" but the
// message wasn't sent — one beep, second Enter needed. Root cause: postBoundaryCopy
// re-posted `event.copy()` of the REAL hardware Return, and macOS 26 silently drops
// a re-posted copy of a HID event before app delivery (it passed our own tap, then
// vanished — never reached IMKit). The fix posts a FRESH down/up pair instead.
// These tests pin the properties of that pair that each fix a distinct failure:
final class BoundaryRepostTests: XCTestCase {

    func testRepostCarriesKeycodeAndFlags() {
        guard let (down, up) = SyntheticKeyboard.makeBoundaryRepost(key: 36, flags: .maskShift) else {
            return XCTFail("pair must be constructible")
        }
        XCTAssertEqual(down.getIntegerValueField(.keyboardEventKeycode), 36)
        XCTAssertEqual(up.getIntegerValueField(.keyboardEventKeycode), 36)
        // Shift+Enter in chat apps means "newline, don't send" — the repost must
        // preserve that distinction or a shortcut expansion turns it into a send.
        XCTAssertTrue(down.flags.contains(.maskShift))
        XCTAssertTrue(up.flags.contains(.maskShift))
    }

    /// NO magic: IMKit's handle() drops magic events without processing; this Enter
    /// must re-enter handle() as a REAL key (engine is empty post-boundary, so it
    /// passes through once — no loop) so the app's Enter action fires.
    func testRepostCarriesNoMagicStamp() {
        guard let (down, up) = SyntheticKeyboard.makeBoundaryRepost(key: 36, flags: []) else {
            return XCTFail("pair must be constructible")
        }
        XCTAssertFalse(SyntheticKeyboard.isSyntheticMagic(down),
                       "magic would make IMKit skip the repost — the Enter action would never fire")
        XCTAssertFalse(SyntheticKeyboard.isSyntheticMagic(up))
    }

    /// A keyUp must exist: the user's physical keyUp precedes our posted keyDown,
    /// so without our own up the key stays logically held (key-repeat / stuck-key
    /// semantics in apps that track key state).
    // MARK: Field 19/08/2026 — "thử xem"+Enter trên TikTok post ra mỗi "thử"

    func testMarkedWebEditorNeedsASecondPress() {
        // Web editor ở lớp marked (Docs canvas, comment box TikTok): KHÔNG gửi hộ được
        // phím boundary mà giữ được từ cuối — bốn ngả đã thử và vỡ trên TikTok/Safari
        // 19/08/2026 (re-post ngay / hoãn 60ms / hoãn 300ms / không nuốt / chèn space
        // rồi Enter). Đường duy nhất không mất chữ: chốt từ, user bấm lần hai.
        XCTAssertTrue(TelexInputController.boundaryNeedsSecondPress(markedWebField: true))
        // App native (insertText đồng bộ) vẫn được gửi hộ như cũ — không đụng.
        XCTAssertFalse(TelexInputController.boundaryNeedsSecondPress(markedWebField: false))
    }

    func testRepostIsABalancedPair() {
        guard let (down, up) = SyntheticKeyboard.makeBoundaryRepost(key: 48, flags: []) else {
            return XCTFail("pair must be constructible")
        }
        XCTAssertEqual(down.type, .keyDown)
        XCTAssertEqual(up.type, .keyUp)
    }
}
