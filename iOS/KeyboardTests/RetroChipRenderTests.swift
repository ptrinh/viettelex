// "Tự sửa từ phía trước" (docs/SETTINGS-CLEANUP-SPEC.md §2): chip MỜI (công tắc tắt) và chip
// "↩︎ Khôi phục" (công tắc bật, vừa tự sửa) phải thực sự lên thanh gợi ý của bàn phím — đi hết
// đường thật KeyboardViewController → updateSuggestions → KeyboardView.showSuggestions, không chỉ
// bridge (RetroEnglishBridgeTests). Chạm chip áp / trả lại đúng chữ.
import XCTest
import UIKit

@MainActor
final class RetroChipRenderTests: XCTestCase {

    private func withRig(retroAuto: Bool, _ body: (KeyboardBenchTests.Rig) throws -> Void) rethrows {
        let saved = UserDefaultsProvider.shared
        let d = KeyboardBenchTests.makeDefaults("retro-chip")
        d.set(retroAuto, forKey: RetroEnglishUI.autoKey)
        d.set(false, forKey: "autoCapitalize")        // chữ ra đúng như gõ, không phụ thuộc shift tự bật
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        KeyboardBenchTests.spin(0.05)
        try body(rig)
    }

    private func type(_ s: String, _ rig: KeyboardBenchTests.Rig) {
        for c in s {
            rig.vc.debugHandle(c == " " ? .space : .letter(c))
            KeyboardBenchTests.spin(0.01)
        }
        KeyboardBenchTests.spin(0.08)                   // lượt gợi ý hoãn của phím cuối
        rig.vc.debugUpdateSuggestions()
    }

    func testInviteChipRendersAndApplies() {
        withRig(retroAuto: false) { rig in
            type("his car is very fast ", rig)
            XCTAssertEqual(rig.proxy.text, "hí cả í very fast ", "công tắc tắt: không tự viết lại")
            let kb = rig.vc.debugKeyboard
            XCTAssertEqual(kb.debugLastShownSet?.actionPayload, KeyboardView.retroOfferToken)
            XCTAssertEqual(kb.debugVisibleSlotTexts.first, "his car is", "chip mời ở ô đầu thanh gợi ý")
            kb.onSuggestion?(KeyboardView.retroOfferToken)          // đường chạm ô thật
            KeyboardBenchTests.spin(0.05)
            XCTAssertEqual(rig.proxy.text, "his car is very fast ")
            XCTAssertNotEqual(kb.debugLastShownSet?.actionPayload, KeyboardView.retroOfferToken, "chip mời chỉ một lần")
        }
    }

    func testUndoChipRendersAndRestores() {
        withRig(retroAuto: true) { rig in
            type("his car is fast ", rig)
            XCTAssertEqual(rig.proxy.text, "his car is fast ", "công tắc bật: tự sửa")
            let kb = rig.vc.debugKeyboard
            XCTAssertEqual(kb.debugLastShownSet?.actionPayload, KeyboardView.undoRetroToken)
            XCTAssertEqual(kb.debugVisibleSlotTexts.first, RetroEnglishUI.undoChipLabel)
            kb.onSuggestion?(KeyboardView.undoRetroToken)
            KeyboardBenchTests.spin(0.05)
            XCTAssertEqual(rig.proxy.text, "hí cả í fast ")
        }
    }

    /// "Quyết định theo ngữ cảnh" tắt ⇒ không chip nào (mục phụ thuộc mờ trong cài đặt).
    func testNoChipWhenContextualOff() {
        for auto in [false, true] {
            let saved = UserDefaultsProvider.shared
            let d = KeyboardBenchTests.makeDefaults("retro-chip-off")
            d.set(auto, forKey: RetroEnglishUI.autoKey)
            d.set(false, forKey: "contextualEnglish")
            d.set(false, forKey: "autoCapitalize")
            UserDefaultsProvider.shared = d
            let rig = KeyboardBenchTests.Rig()
            KeyboardBenchTests.spin(0.05)
            type("his car is very fast ", rig)
            let p = rig.vc.debugKeyboard.debugLastShownSet?.actionPayload
            XCTAssertNotEqual(p, KeyboardView.retroOfferToken)
            XCTAssertNotEqual(p, KeyboardView.undoRetroToken)
            rig.close()
            UserDefaultsProvider.shared = saved
        }
    }
}
