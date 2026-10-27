// Góp ý tester Plus 28/10/2026 (iPhone, App Store 1.2.21):
//  1. "Lỗi không xuất hiện lần đầu khi mở 1 số app như Zalo vẫn chưa khắc phục" — bàn phím đã
//     xé (didDisappear) mà host gắn lại input view không qua willAppear/didAppear ⇒ trống. Chạm
//     vào bàn phím trống ⇒ dựng lại ngay (AppearanceCycle.needsHeal).
//  2. "lag khi gõ trong Gmail" — tiếng vọng TRỄ của web view (trạng thái cũ của chính mình) làm
//     reset từ đang gõ giữa chừng ⇒ EchoGuard.
//  4. Trackpad: ngón thứ hai chạm bàn phím không được gõ ra chữ (TrackpadTouch).
import XCTest
import UIKit

final class Feedback1028Tests: XCTestCase {

    // MARK: 2. Gmail: tiếng vọng trễ

    /// Gõ nhanh trong web view: tiếng vọng của phím TRƯỚC tới SAU khi phím này đã áp cục bộ ⇒
    /// context host báo thiếu phím vừa gõ. `stale` false = host vọng đúng lúc (như Feedback1016).
    @MainActor private func runEcho(stale: Bool) -> (text: String, ctx: Double, passes: Double) {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("B")
        defer { UserDefaultsProvider.shared = saved }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        KeyboardBenchTests.spin(0.05)
        rig.proxy.contextReads = 0
        rig.vc.debugSuggestionPasses = 0
        let keys = Array("vieejt tooi ddi hocj cas caf car cax caj nam tieengs vieetj ")
        var prev = rig.proxy.text
        for c in keys {
            _ = rig.key(c, index: 1, drain: 0)
            let now = rig.proxy.text
            if stale { rig.proxy.text = prev }     // host còn ở trạng thái trước phím này
            rig.vc.textWillChange(nil); rig.vc.selectionWillChange(nil)
            rig.vc.selectionDidChange(nil); rig.vc.textDidChange(nil)
            rig.proxy.text = now
            prev = now
            KeyboardBenchTests.spin(0.045)
        }
        let n = Double(keys.count)
        return (rig.proxy.text, Double(rig.proxy.contextReads) / n, Double(rig.vc.debugSuggestionPasses) / n)
    }

    /// Hồi quy: trước sửa "Vieẹt tooi ddi học … tieengs vieetj", 3,4 lượt đọc context/phím.
    @MainActor func testLateEchoKeepsComposition() {
        let fresh = runEcho(stale: false)
        let late = runEcho(stale: true)
        print(String(format: "LATEECHO fresh ctx=%.2f passes=%.2f | late ctx=%.2f passes=%.2f text=%@",
                     fresh.ctx, fresh.passes, late.ctx, late.passes, late.text))
        let want = "việt tôi đi học cá cà cả cã cạ nam tiếng việt"
        XCTAssertTrue(fresh.text.lowercased().hasPrefix(want), fresh.text)
        // Phím đầu ô: chưa biết host vọng trễ (chưa có ảnh chụp) ⇒ từ đầu có thể đi đường với lại;
        // từ đó trở đi phải đúng hết.
        XCTAssertTrue(late.text.lowercased().hasSuffix(String(want.dropFirst(4)) + " "), late.text)
        XCTAssertLessThanOrEqual(late.ctx, fresh.ctx + 1.2, "bù tiếng vọng: ≤ ~1 lượt đọc thêm mỗi phím")
        XCTAssertLessThanOrEqual(late.passes, fresh.passes + 0.15, "không tính lại thanh gợi ý thêm")
    }

    func testEchoGuardPure() {
        var g = EchoGuard()
        g.record("xin chào bạn ơi hôm nay", now: 0)
        XCTAssertNil(g.settled("xin chào bạn ơi hôm na", now: 0.1), "chưa armed ⇒ không đụng")
        g.arm()
        g.record("xin chào bạn ơi hôm nay t", now: 1)
        g.record("xin chào bạn ơi hôm nay tr", now: 1.05)
        g.record("xin chào bạn ơi hôm nay trờ", now: 1.1)
        XCTAssertEqual(g.settled("xin chào bạn ơi hôm nay tr", now: 1.2), "xin chào bạn ơi hôm nay trờ",
                       "trạng thái cũ của mình ⇒ trạng thái mới nhất")
        XCTAssertNil(g.settled("xin chào bạn ơi hôm nay trờ", now: 1.2), "đã cập nhật")
        XCTAssertNil(g.settled("đoạn khác hẳn", now: 1.2), "thay đổi thật")
        XCTAssertNil(g.settled("xin chào bạn ơi hôm nay tr", now: 3), "quá cửa sổ thời gian")
        XCTAssertNil(g.settled(nil, now: 1.2))
        // Context host cắt đầu khác (cửa sổ trượt) vẫn khớp theo đuôi.
        XCTAssertEqual(g.settled("ào bạn ơi hôm nay tr", now: 1.2), "xin chào bạn ơi hôm nay trờ")
        g.clear()
        XCTAssertNil(g.settled("xin chào bạn ơi hôm nay tr", now: 1.2))
    }

    /// Ô trống / đầu ô: host xoá ô (gửi tin) là thay đổi THẬT, không phải tiếng vọng.
    func testEchoGuardEmptyFieldIsRealChange() {
        var g = EchoGuard()
        g.arm()
        g.record("", now: 0)
        g.record("A", now: 0.05)
        g.record("Ab", now: 0.1)
        XCTAssertNil(g.settled("", now: 0.2))
        XCTAssertEqual(g.settled("A", now: 0.2), "Ab", "đầu ô: khớp hẳn chuỗi")
        XCTAssertNil(g.settled("xA", now: 0.2), "ảnh chụp ngắn chỉ khớp bằng hẳn")
    }

    // MARK: 1. bàn phím trống sau khi xé

    /// Host gắn lại input view đã xé mà không gọi willAppear/didAppear: chạm vào ⇒ dựng lại.
    @MainActor func testTouchOnTornDownKeyboardRebuilds() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("B")
        defer { UserDefaultsProvider.shared = saved }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        let vc = rig.vc
        vc.viewWillDisappear(false)
        vc.viewDidDisappear(false)
        XCTAssertTrue(vc.debugKeyboard.isTornDown)
        XCTAssertTrue(AppearanceCycle.needsHeal(tornDown: true, inWindow: true))
        XCTAssertFalse(AppearanceCycle.needsHeal(tornDown: true, inWindow: false), "đang ẩn: không dựng")
        XCTAssertFalse(AppearanceCycle.needsHeal(tornDown: false, inWindow: true))
        vc.debugTouchRoot()
        XCTAssertFalse(vc.debugKeyboard.isTornDown)
        XCTAssertNotNil(vc.debugKeyboard.debugLetterFrame("a"))
        XCTAssertTrue(vc.debugKeyboard.suggestionsShownState, "thanh gợi ý phải hiện")
        _ = rig.key("a", index: 1, drain: 0.01)
        XCTAssertEqual(rig.proxy.text, "A")
        // Đang hiện bình thường: chạm vào view gốc không dựng lại gì.
        let installs = KeyboardViewController.debugKeyboardInstalls
        vc.debugTouchRoot()
        XCTAssertEqual(KeyboardViewController.debugKeyboardInstalls, installs)
    }

    // MARK: 4. trackpad: ngón thứ hai

    func testTrackpadTouchPolicy() {
        XCTAssertTrue(TrackpadTouch.swallows(trackpadActive: true, isTrackpadFinger: false))
        XCTAssertFalse(TrackpadTouch.swallows(trackpadActive: true, isTrackpadFinger: true))
        XCTAssertFalse(TrackpadTouch.swallows(trackpadActive: false, isTrackpadFinger: false))
    }

    /// Hồi quy: giữ phím cách (trackpad) rồi ngón thứ hai chạm phím chữ ⇒ trước đây ra chữ lạc.
    @MainActor func testSecondFingerDuringTrackpadTypesNothing() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("B")
        defer { UserDefaultsProvider.shared = saved }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        let kb = rig.vc.debugKeyboard
        _ = rig.key("x", index: 1, drain: 0.01)
        XCTAssertEqual(rig.proxy.text, "X")
        kb.debugTrackpadBegin()
        _ = rig.key("a", index: 2, drain: 0.01)
        XCTAssertEqual(rig.proxy.text, "X", "ngón thứ hai lúc trackpad không gõ")
        kb.debugTrackpadEnd()
        _ = rig.key("a", index: 3, drain: 0.01)
        XCTAssertEqual(rig.proxy.text.lowercased(), "xa")
    }
}
