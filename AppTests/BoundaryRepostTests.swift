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

    func testMarkedWebEditorDelaysTheRepost() {
        // Web editor ở lớp marked (Docs canvas, comment box TikTok) áp commit vào
        // model JS BẤT ĐỒNG BỘ → Enter re-post ngay lập tức "gửi" với text cũ.
        // Hoãn một nhịp; native app (insertText đồng bộ) thì KHÔNG hoãn.
        XCTAssertEqual(TelexInputController.boundaryRepostDelayMs(markedWebField: true), 60)
        XCTAssertNil(TelexInputController.boundaryRepostDelayMs(markedWebField: false))
        // Hoãn phải đủ nhỏ để không cảm nhận được khi bấm gửi, đủ lớn cho một vòng
        // render — nếu ai đổi số, hai biên này buộc phải cân nhắc lại.
        let ms = TelexInputController.boundaryRepostDelayMs(markedWebField: true) ?? 0
        XCTAssertGreaterThanOrEqual(ms, 30, "dưới 30ms không đủ cho React/Lexical")
        XCTAssertLessThanOrEqual(ms, 120, "trên 120ms user bắt đầu cảm nhận được độ trễ")
    }

    func testRepostIsABalancedPair() {
        guard let (down, up) = SyntheticKeyboard.makeBoundaryRepost(key: 48, flags: []) else {
            return XCTFail("pair must be constructible")
        }
        XCTAssertEqual(down.type, .keyDown)
        XCTAssertEqual(up.type, .keyUp)
    }
}
