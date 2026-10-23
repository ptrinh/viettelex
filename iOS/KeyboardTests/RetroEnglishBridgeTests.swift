// "Tự sửa từ phía trước" — sửa ngược tiếng Anh ở bàn phím iOS (EngineBridge + chip).
// Engine: docs/DESIGN.md "Sửa ngược tiếng Anh". Công tắc TẮT ⇒ chỉ mời qua chip; BẬT ⇒ tự áp +
// chip "Khôi phục" / ⌫ ngay sau trả lại. contextualEnglish TẮT ⇒ không gì cả.
import XCTest
import TelexCore

final class RetroEnglishBridgeTests: XCTestCase {

    private func settings(contextual: Bool = true, auto: Bool) -> KeyboardSettings {
        var s = KeyboardSettings()
        s.contextualEnglish = contextual
        s.retroEnglishAuto = auto
        return s
    }

    /// Gõ `keys` (" " = dấu cách, "⌫" = xoá, "⏎" = Enter, "." = dấu chấm) qua bridge.
    private func type(_ keys: String, _ bridge: EngineBridge, _ proxy: MockProxy) {
        for ch in keys {
            switch ch {
            case " ": bridge.boundary(" ", proxy: proxy)
            case "⏎": bridge.boundary("\n", proxy: proxy)
            case ".", ",": bridge.boundary(String(ch), proxy: proxy)
            case "⌫": bridge.backspace(proxy: proxy)
            default: bridge.letter(ch, proxy: proxy)
            }
        }
    }

    // MARK: cài đặt

    func testSwitchVisibleOnlyWithContextualEnglish() {
        XCTAssertTrue(RetroEnglishUI.switchVisible(contextualEnglish: true))
        XCTAssertFalse(RetroEnglishUI.switchVisible(contextualEnglish: false))
        XCTAssertFalse(RetroEnglishUI.switchVisible(contextualEnglish: true, vniMode: true))
        XCTAssertFalse(RetroEnglishUI.switchVisible(contextualEnglish: false, vniMode: true))
    }

    func testSettingDefaultOffAndLoadsFromAppGroup() {
        XCTAssertFalse(KeyboardSettings().retroEnglishAuto)
        let name = "vt-test-retro"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: name) }
        XCTAssertFalse(KeyboardSettings.load().retroEnglishAuto)
        d.set(true, forKey: RetroEnglishUI.autoKey)
        XCTAssertTrue(KeyboardSettings.load().retroEnglishAuto)
    }

    func testBackupCarriesSwitch() {
        XCTAssertTrue(BackupSettings.all.contains { $0.key == RetroEnglishUI.autoKey })
    }

    // MARK: công tắc TẮT — chỉ mời

    func testOfferChipWhenSwitchOff() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: false))
        type("His car is very fast ", b, p)
        XCTAssertEqual(p.text, "Hí cả í very fast ")          // KHÔNG tự viết lại
        let offer = try? XCTUnwrap(b.retroOffer)
        XCTAssertNotNil(offer)
        XCTAssertFalse(b.retroUndoAvailable)
        XCTAssertEqual(EngineBridge.retroLabel(offer!, context: p.contextBeforeInput), "His car is")
        XCTAssertTrue(b.applyRetroOffer(proxy: p))
        XCTAssertEqual(p.text, "His car is very fast ")
        XCTAssertNil(b.retroOffer)
        XCTAssertFalse(b.applyRetroOffer(proxy: p))             // một lần
        XCTAssertEqual(p.text, "His car is very fast ")
    }

    func testOfferGoneOnNextKey() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: false))
        type("His car is very fast ", b, p)
        XCTAssertNotNil(b.retroOffer)
        type("n", b, p)
        XCTAssertNil(b.retroOffer)
        XCTAssertFalse(b.applyRetroOffer(proxy: p))
        let p2 = MockProxy(), b2 = EngineBridge(settings: settings(auto: false))
        type("His car is very fast ", b2, p2)
        type("⌫", b2, p2)
        XCTAssertNil(b2.retroOffer)
    }

    func testOfferMismatchDoesNotEdit() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: false))
        type("His car is very fast ", b, p)
        XCTAssertNotNil(b.retroOffer)
        p.text = "Hi ca i very fast "                           // host đổi chữ dưới con trỏ
        XCTAssertFalse(b.applyRetroOffer(proxy: p))
        XCTAssertEqual(p.text, "Hi ca i very fast ")
        // context không đọc được ⇒ cũng không sửa
        let p2 = MockProxy(), b2 = EngineBridge(settings: settings(auto: false))
        type("His car is very fast ", b2, p2)
        p2.fakeContext = .some(nil)
        XCTAssertFalse(b2.applyRetroOffer(proxy: p2))
        XCTAssertEqual(p2.text, "Hí cả í very fast ")
    }

    // MARK: công tắc BẬT — tự áp + Khôi phục

    func testAutoApplyAndRestoreChip() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: true))
        type("His car is very fast ", b, p)
        XCTAssertEqual(p.text, "His car is very fast ")
        XCTAssertNil(b.retroOffer)
        XCTAssertTrue(b.retroUndoAvailable)
        XCTAssertTrue(b.revertRetro(proxy: p))
        XCTAssertEqual(p.text, "Hí cả í very fast ")            // đúng chữ trước khi sửa
        XCTAssertFalse(b.retroUndoAvailable)
        XCTAssertFalse(b.revertRetro(proxy: p))
        // gõ tiếp bình thường sau khi khôi phục
        type("now ", b, p)
        XCTAssertTrue(p.text.hasPrefix("Hí cả í very fast "), p.text)
    }

    func testBackspaceRightAfterAutoFixRestores() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: true))
        type("His car is very fast ", b, p)
        XCTAssertEqual(p.text, "His car is very fast ")
        type("⌫", b, p)
        XCTAssertEqual(p.text, "Hí cả í very fast ")            // ⌫ đầu = Khôi phục, không xoá ký tự
        XCTAssertTrue(b.revertedRetro)
        XCTAssertFalse(b.retroUndoAvailable)
        type("⌫", b, p)                                          // ⌫ kế: xoá thường
        XCTAssertEqual(p.text, "Hí cả í very fast")
    }

    func testRestoreGoneOnNextKey() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: true))
        type("His car is very fast ", b, p)
        type("n", b, p)
        XCTAssertFalse(b.retroUndoAvailable)
        type("⌫", b, p)                                          // ⌫ thường, không khôi phục
        XCTAssertEqual(p.text, "His car is very fast ")
    }

    func testBackspaceAfterAutoFixMismatchIsNormalDelete() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: true))
        type("His car is very fast ", b, p)
        p.text = "His car is very fast  "                       // host thêm chữ
        type("⌫", b, p)
        XCTAssertEqual(p.text, "His car is very fast ")
        XCTAssertFalse(b.revertedRetro)
        // chip Khôi phục cũng phải kiểm lại
        let p2 = MockProxy(), b2 = EngineBridge(settings: settings(auto: true))
        type("His car is very fast ", b2, p2)
        p2.text = "x"
        XCTAssertFalse(b2.revertRetro(proxy: p2))
        XCTAssertEqual(p2.text, "x")
    }

    func testAutoApplyMismatchDoesNotEdit() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: true))
        type("His car is very fas", b, p)
        p.fakeContext = .some("khác hẳn very fas")              // host báo chữ khác
        type("t ", b, p)
        XCTAssertEqual(p.text, "Hí cả í very fast ")
        XCTAssertFalse(b.retroUndoAvailable)
        // context nil ⇒ cũng không sửa
        let p2 = MockProxy(), b2 = EngineBridge(settings: settings(auto: true))
        type("His car is very fas", b2, p2)
        p2.fakeContext = .some(nil)
        type("t ", b2, p2)
        XCTAssertEqual(p2.text, "Hí cả í very fast ")
    }

    func testEnterNeverRewrites() {
        for auto in [false, true] {
            let p = MockProxy(), b = EngineBridge(settings: settings(auto: auto))
            type("His car is very fast⏎", b, p)
            XCTAssertEqual(p.text, "Hí cả í very fast\n")
            XCTAssertNil(b.retroOffer)
            XCTAssertFalse(b.retroUndoAvailable)
        }
    }

    // MARK: contextualEnglish TẮT — không gì cả

    func testContextualEnglishOffDoesNothing() {
        for auto in [false, true] {
            let p = MockProxy(), b = EngineBridge(settings: settings(contextual: false, auto: auto))
            type("His car is very fast ", b, p)
            XCTAssertTrue(p.text.hasPrefix("Hí cả í "), p.text)
            XCTAssertNil(b.retroOffer)
            XCTAssertFalse(b.retroUndoAvailable)
            type("⌫", b, p)
            XCTAssertFalse(b.revertedRetro)
        }
    }

    // MARK: thanh gợi ý

    func testChipsLeadTheBar() {
        var s = KeyboardView.SuggestionSet()
        s.nextWords = ["a", "b", "c"]
        s.actionLabel = "His car is"; s.actionPayload = KeyboardView.retroOfferToken
        guard case .slots(let slots, _) = SuggestionSlots.arrange(s) else { return XCTFail() }
        XCTAssertEqual(slots.first??.payload, KeyboardView.retroOfferToken)
        s.actionLabel = RetroEnglishUI.undoChipLabel; s.actionPayload = KeyboardView.undoRetroToken
        guard case .slots(let slots2, _) = SuggestionSlots.arrange(s) else { return XCTFail() }
        XCTAssertEqual(slots2.first??.payload, KeyboardView.undoRetroToken)
        XCTAssertEqual(slots2.first??.label, "\u{21A9}\u{FE0E} Khôi phục")
    }

    func testRetroLabelWithoutContext() {
        let p = MockProxy(), b = EngineBridge(settings: settings(auto: false))
        type("His car is very fast ", b, p)
        guard let c = b.retroOffer else { return XCTFail("no offer") }
        XCTAssertEqual(EngineBridge.retroLabel(c, context: p.text), "His car is")
        // không đọc được context: chỉ phần chèn, vẫn trọn các từ đổi
        XCTAssertFalse(EngineBridge.retroLabel(c, context: nil).isEmpty)
        XCTAssertTrue("His car is".hasSuffix(EngineBridge.retroLabel(c, context: nil)))
    }
}
