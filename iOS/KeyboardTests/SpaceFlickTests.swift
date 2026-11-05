// Vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh: phân loại flick (SpaceFlick), trạng thái
// ngôn ngữ, chế độ Tiếng Anh của EngineBridge, gợi ý tiếng Anh, lọc gõ vuốt.
// Bản Kotlin song sinh: android/keyboard/src/test/.../SpaceFlickTests.kt (cùng số liệu).
import XCTest
import TelexCore

final class SpaceFlickTests: XCTestCase {

    // MARK: phân loại

    func testFlickDirections() {
        XCTAssertEqual(SpaceFlick.classify(dx: 50, dy: 4, duration: 0.15, keyWidth: 37), .right)
        XCTAssertEqual(SpaceFlick.classify(dx: -45, dy: -10, duration: 0.2, keyWidth: 37), .left)
    }

    func testTooShortSlowOrVerticalIsNotFlick() {
        XCTAssertNil(SpaceFlick.classify(dx: 30, dy: 0, duration: 0.1, keyWidth: 37))    // < 1 phím
        XCTAssertNil(SpaceFlick.classify(dx: 80, dy: 0, duration: 0.3, keyWidth: 37))    // tới ngưỡng trackpad
        XCTAssertNil(SpaceFlick.classify(dx: 60, dy: 31, duration: 0.1, keyWidth: 37))   // dốc quá
        XCTAssertNil(SpaceFlick.classify(dx: 0, dy: 0, duration: 0.05, keyWidth: 37))    // chạm thường
    }

    func testDistanceFloorAndSpeed() {
        // phím hẹp: sàn 24 pt
        XCTAssertNil(SpaceFlick.classify(dx: 20, dy: 0, duration: 0.05, keyWidth: 10))
        XCTAssertEqual(SpaceFlick.classify(dx: 25, dy: 0, duration: 0.05, keyWidth: 10), .right)
        // 25 pt trong 290 ms = 0,086 pt/ms < 0,1
        XCTAssertNil(SpaceFlick.classify(dx: 25, dy: 0, duration: 0.29, keyWidth: 10))
    }

    func testPreviewProgress() {
        let span = SpaceFlick.previewSpan(keyWidth: 37)
        XCTAssertEqual(span, 74)
        XCTAssertEqual(SpaceFlick.progress(dx: 5, dy: 0, elapsed: 0.05, span: span), 0)     // dưới slop
        XCTAssertEqual(SpaceFlick.progress(dx: 37, dy: 0, elapsed: 0.1, span: span), 0.5)
        XCTAssertEqual(SpaceFlick.progress(dx: -200, dy: 0, elapsed: 0.1, span: span), -1)
        XCTAssertEqual(SpaceFlick.progress(dx: 37, dy: 0, elapsed: 0.31, span: span), 0)    // sắp trackpad
        XCTAssertEqual(SpaceFlick.progress(dx: 20, dy: 30, elapsed: 0.1, span: span), 0)    // kéo dọc
    }

    /// #147: kéo chậm sau khi đã trượt quá ngưỡng (trackpad không thể bật) vẫn đổi ngôn ngữ.
    func testSlowDragAfterSlopToggles() {
        XCTAssertNil(SpaceFlick.classify(dx: 50, dy: 4, duration: 1.2, keyWidth: 37))   // trước đây: quá giờ
        XCTAssertEqual(SpaceFlick.classify(dx: 50, dy: 4, duration: 1.2, keyWidth: 37, trackpadPossible: false), .right)
        XCTAssertEqual(SpaceFlick.classify(dx: -40, dy: 10, duration: 0.8, keyWidth: 37, trackpadPossible: false), .left)
        XCTAssertEqual(SpaceFlick.classify(dx: 25, dy: 0, duration: 0.29, keyWidth: 10, trackpadPossible: false), .right)
        // vẫn cần đủ quãng + chủ yếu ngang
        XCTAssertNil(SpaceFlick.classify(dx: 30, dy: 0, duration: 1.2, keyWidth: 37, trackpadPossible: false))
        XCTAssertNil(SpaceFlick.classify(dx: 60, dy: 31, duration: 1.2, keyWidth: 37, trackpadPossible: false))
        XCTAssertNil(SpaceFlick.classify(dx: 0, dy: 0, duration: 1.2, keyWidth: 37, trackpadPossible: false))
        // nhanh: không đổi hành vi
        XCTAssertEqual(SpaceFlick.classify(dx: 50, dy: 4, duration: 0.15, keyWidth: 37, trackpadPossible: false), .right)
    }

    func testSlowDragPreviewKeepsTracking() {
        let span = SpaceFlick.previewSpan(keyWidth: 37)
        XCTAssertEqual(SpaceFlick.progress(dx: 37, dy: 0, elapsed: 1, span: span), 0)
        XCTAssertEqual(SpaceFlick.progress(dx: 37, dy: 0, elapsed: 1, span: span, trackpadPossible: false), 0.5)
        XCTAssertEqual(SpaceFlick.progress(dx: -200, dy: 0, elapsed: 2, span: span, trackpadPossible: false), -1)
        XCTAssertEqual(SpaceFlick.progress(dx: 5, dy: 0, elapsed: 1, span: span, trackpadPossible: false), 0)
        XCTAssertEqual(SpaceFlick.progress(dx: 20, dy: 30, elapsed: 1, span: span, trackpadPossible: false), 0)
    }

    // MARK: trạng thái ngôn ngữ

    func testLanguageStateForcedVietnameseWhenOff() {
        XCTAssertEqual(KeyboardLanguage.effective(stored: "en", flickEnabled: false), .vi)
        XCTAssertEqual(KeyboardLanguage.effective(stored: "en", flickEnabled: true), .en)
        XCTAssertEqual(KeyboardLanguage.effective(stored: nil, flickEnabled: true), .vi)
        XCTAssertEqual(KeyboardLanguage.effective(stored: "xx", flickEnabled: true), .vi)
        XCTAssertEqual(KeyboardLanguage.vi.toggled, .en)
        XCTAssertEqual(KeyboardLanguage.en.toggled, .vi)
        XCTAssertEqual(KeyboardLanguage.en.displayName, "English")
        XCTAssertEqual(KeyboardLanguage.vi.displayName, "Tiếng Việt")
    }

    func testSettingDefaultsOff() {
        XCTAssertFalse(KeyboardSettings().spaceSwipeLanguage)
        XCTAssertEqual(BackupSettings.byKey["spaceSwipeLanguage"]?.kind, .bool(false))
    }

    // MARK: EngineBridge chế độ Tiếng Anh

    private func run(_ keys: String, bridge: EngineBridge, proxy: MockProxy) {
        for ch in keys {
            if ch == " " { bridge.boundary(" ", proxy: proxy) }
            else if ch == "⌫" { bridge.backspace(proxy: proxy) }
            else { bridge.letter(ch, proxy: proxy) }
        }
    }

    private func english(_ settings: KeyboardSettings = KeyboardSettings()) -> (EngineBridge, MockProxy) {
        let b = EngineBridge(settings: settings), p = MockProxy()
        b.setEnglish(true, proxy: p)
        return (b, p)
    }

    func testEnglishModeTypesRawKeys() {
        let (b, p) = english()
        run("vieetj hows ", bridge: b, proxy: p)
        XCTAssertEqual(p.text, "vieetj hows ")
        run("wordd", bridge: b, proxy: p)
        XCTAssertEqual(b.composedWord, "wordd")
        XCTAssertEqual(b.rawWord, "wordd")
        XCTAssertEqual(b.predictedCommit, "wordd")
        XCTAssertTrue(b.isComposing)
        XCTAssertEqual(b.boundary(".", proxy: p), "wordd")
        XCTAssertEqual(p.text, "vieetj hows wordd.")
        XCTAssertFalse(b.isComposing)
    }

    func testEnglishBackspace() {
        let (b, p) = english()
        run("cat⌫⌫", bridge: b, proxy: p)
        XCTAssertEqual(p.text, "c")
        XCTAssertEqual(b.composedWord, "c")
        run("⌫⌫", bridge: b, proxy: p)
        XCTAssertEqual(p.text, "")
        XCTAssertFalse(b.isComposing)
    }

    func testEnglishShortcutsStillExpand() {
        var s = KeyboardSettings()
        s.shortcuts = ShortcutTable(["brb": "be right back"])
        let (b, p) = english(s)
        XCTAssertEqual(b.shortcutPreview, nil)
        run("brb", bridge: b, proxy: p)
        XCTAssertEqual(b.shortcutPreview, "be right back")
        XCTAssertEqual(b.boundary(" ", proxy: p), "be right back")
        XCTAssertEqual(p.text, "be right back ")
        XCTAssertTrue(b.expandedAtLastBoundary)
        run("⌫", bridge: b, proxy: p)                 // ⌫ ngay sau = trả lại chữ tắt
        XCTAssertEqual(p.text, "brb ")
    }

    func testEnglishIgnoresVNIDigits() {
        var s = KeyboardSettings()
        s.vniMode = true
        let (b, p) = english(s)
        run("viet", bridge: b, proxy: p)
        XCTAssertFalse(b.vniDigit("5", proxy: p))
    }

    func testEnglishUndoLastLetter() {
        let (b, p) = english()
        run("ab", bridge: b, proxy: p)
        XCTAssertTrue(b.undoLastLetter(proxy: p))
        XCTAssertEqual(p.text, "a")
        XCTAssertEqual(b.composedWord, "a")
    }

    func testSwitchCommitsHalfComposedWord() {
        let b = EngineBridge(), p = MockProxy()
        run("vieetj", bridge: b, proxy: p)
        XCTAssertEqual(b.setEnglish(true, proxy: p), "việt")   // chốt, không chèn ký tự nào
        XCTAssertEqual(p.text, "việt")
        XCTAssertFalse(b.isComposing)
        run("s", bridge: b, proxy: p)                          // Tiếng Anh: không sửa dấu từ cũ
        XCTAssertEqual(p.text, "việts")
        XCTAssertEqual(b.setEnglish(false, proxy: p), "s")
        run("s", bridge: b, proxy: p)                          // Tiếng Việt: từ mới, không nạp lại "việts"
        XCTAssertEqual(p.text, "việtss")
        XCTAssertEqual(b.setEnglish(false, proxy: p), "")      // đã là Tiếng Việt: không làm gì
    }

    func testSwitchAutoRestoresEnglishWord() {
        let b = EngineBridge(), p = MockProxy()
        run("google", bridge: b, proxy: p)
        XCTAssertEqual(b.setEnglish(true, proxy: p), "google")
        XCTAssertEqual(p.text, "google")
    }

    func testVietnameseUnchangedWhenNotEnglish() {
        let b = EngineBridge(), p = MockProxy()
        run("vieetj ", bridge: b, proxy: p)
        XCTAssertEqual(p.text, "việt ")
        XCTAssertFalse(b.englishMode)
    }

    // MARK: §7 vuốt khi đang gõ dở một từ — chuyển luôn từ đó (ONBOARDING-SPEC §7)

    /// Gõ phím; số ⇒ vniDigit (VNI), không xử lý được ⇒ ranh giới như controller.
    private func typeKeys(_ keys: String, _ b: EngineBridge, _ p: MockProxy) {
        for ch in keys {
            if ch.isNumber { if !b.vniDigit(ch, proxy: p) { b.boundary(String(ch), proxy: p) } }
            else if ch == " " { b.boundary(" ", proxy: p) }
            else { b.letter(ch, proxy: p) }
        }
    }

    private func flickBridge(vni: Bool = false, strict: Bool = true) -> (EngineBridge, MockProxy) {
        var s = KeyboardSettings()
        s.vniMode = vni
        s.autoRestore = strict
        s.liveSpellCheck = strict
        return (EngineBridge(settings: s), MockProxy())
    }

    /// Gõ `keys` ở VI, vuốt EN ⇒ `en`; vuốt VI ⇒ `vi` (khứ hồi). Từ vẫn đang soạn.
    private func roundTrip(_ keys: String, vi: String, en: String, vni: Bool = false, strict: Bool = true,
                           file: StaticString = #filePath, line: UInt = #line) {
        let (b, p) = flickBridge(vni: vni, strict: strict)
        typeKeys(keys, b, p)
        XCTAssertEqual(p.text, vi, file: file, line: line)
        XCTAssertEqual(b.flickLanguage(toEnglish: true, convertWord: true, proxy: p), "", file: file, line: line)
        XCTAssertEqual(p.text, en, file: file, line: line)
        XCTAssertTrue(b.englishMode, file: file, line: line)
        XCTAssertEqual(b.composedWord, en, file: file, line: line)
        XCTAssertEqual(b.flickLanguage(toEnglish: false, convertWord: true, proxy: p), "", file: file, line: line)
        XCTAssertEqual(p.text, vi, file: file, line: line)
        XCTAssertFalse(b.englishMode, file: file, line: line)
        XCTAssertEqual(b.composedWord, vi, file: file, line: line)
        XCTAssertEqual(b.rawWord, keys, file: file, line: line)
    }

    func testConvertHis() { roundTrip("His", vi: "Hí", en: "His") }
    /// Mặc định (tự khôi phục + kiểm tra chính tả) "very" đã hiện "very" giữa từ; tắt hai công
    /// tắc đó mới thấy "vẻy" như bảng spec.
    func testConvertVery() { roundTrip("very", vi: "vẻy", en: "very", strict: false) }
    func testConvertVeryDefaultSettings() { roundTrip("very", vi: "very", en: "very") }
    func testConvertKeepsCaps() { roundTrip("HIS", vi: "HÍ", en: "HIS") }
    func testConvertHornsAndBreve() { roundTrip("dduwowcj", vi: "được", en: "dduwowcj") }
    func testConvertVNI() { roundTrip("hi1", vi: "hí", en: "hi1", vni: true) }

    func testConvertEnglishFirstThenVietnamese() {
        let (b, p) = flickBridge()
        b.flickLanguage(toEnglish: true, convertWord: true, proxy: p)   // EN, chưa có từ
        typeKeys("His", b, p)
        XCTAssertEqual(p.text, "His")
        b.flickLanguage(toEnglish: false, convertWord: true, proxy: p)
        XCTAssertEqual(p.text, "Hí")
        XCTAssertEqual(b.boundary(" ", proxy: p), "Hí")                 // chốt như gõ tay
        XCTAssertEqual(p.text, "Hí ")
    }

    func testConvertedWordKeepsComposingInTarget() {
        let (b, p) = flickBridge()
        typeKeys("vie", b, p)
        b.flickLanguage(toEnglish: true, convertWord: true, proxy: p)
        typeKeys("ws", b, p)                                             // EN: không Telex
        XCTAssertEqual(p.text, "views")
        b.flickLanguage(toEnglish: false, convertWord: true, proxy: p)   // VI: chạy lại "views"
        XCTAssertEqual(p.text, b.composeTrial("views"))
    }

    func testConvertEmptyWordIsOldBehavior() {
        let (b, p) = flickBridge()
        XCTAssertFalse(b.convertComposing(toEnglish: true, proxy: p))
        XCTAssertEqual(b.flickLanguage(toEnglish: true, convertWord: true, proxy: p), "")
        XCTAssertTrue(b.englishMode)
        XCTAssertEqual(p.text, "")
        XCTAssertFalse(b.isComposing)
    }

    func testConvertAfterSpaceLeavesCommittedWord() {
        let (b, p) = flickBridge()
        typeKeys("His ", b, p)
        let before = p.text
        b.flickLanguage(toEnglish: true, convertWord: true, proxy: p)
        XCTAssertEqual(p.text, before)
        b.flickLanguage(toEnglish: false, convertWord: true, proxy: p)
        XCTAssertEqual(p.text, before)
    }

    func testConvertOnlyTouchesComposingWord() {
        let (b, p) = flickBridge()
        typeKeys("vieetj His", b, p)
        b.flickLanguage(toEnglish: true, convertWord: true, proxy: p)
        XCTAssertEqual(p.text, "việt His")
        b.flickLanguage(toEnglish: false, convertWord: true, proxy: p)
        XCTAssertEqual(p.text, "việt Hí")
    }

    /// Bảng số/emoji ⇒ không chuyển: chốt từ rồi đổi như cũ.
    func testConvertNotOnNumberOrEmojiPlane() {
        let (b, p) = flickBridge()
        typeKeys("His", b, p)
        XCTAssertEqual(b.flickLanguage(toEnglish: true, convertWord: false, proxy: p), "Hí")
        XCTAssertEqual(p.text, "Hí")
        XCTAssertFalse(b.isComposing)
        XCTAssertTrue(b.englishMode)
    }

    /// Engine đã đóng băng tiếng Anh giữa từ: sang EN là phím gốc, về VI chạy lại toàn bộ phím.
    func testConvertEnglishFrozenPrefix() {
        let (b, p) = flickBridge()
        typeKeys("google", b, p)
        let vi = p.text
        b.flickLanguage(toEnglish: true, convertWord: true, proxy: p)
        XCTAssertEqual(p.text, "google")
        b.flickLanguage(toEnglish: false, convertWord: true, proxy: p)
        XCTAssertEqual(p.text, vi)
        XCTAssertEqual(b.rawWord, "google")
    }

    /// Chữ trước con trỏ không còn là từ đang soạn ⇒ không xoá mù, đổi như cũ.
    func testConvertTailMismatchFallsBack() {
        let (b, p) = flickBridge()
        typeKeys("His", b, p)
        p.fakeContext = .some("Hix")
        XCTAssertFalse(b.convertComposing(toEnglish: true, proxy: p))
        XCTAssertEqual(p.text, "Hí")
        XCTAssertFalse(b.englishMode)
    }

    /// Gõ vuốt: từ vuốt còn mở là từ từ điển (phím gốc tổng hợp) ⇒ không chuyển, chốt như cũ.
    func testConvertSkipsOpenSwipeWord() {
        let (b, p) = flickBridge()
        _ = b.insertSwipeWord("viết", proxy: p)
        XCTAssertTrue(b.isSwipeWordOpen)
        XCTAssertEqual(b.flickLanguage(toEnglish: true, convertWord: true, proxy: p), "viết")
        XCTAssertEqual(p.text, "viết")
        XCTAssertFalse(b.isComposing)
        XCTAssertTrue(b.englishMode)
    }

    // MARK: gợi ý tiếng Anh

    private func lexicon(_ entries: [(String, UInt8)]) -> SwipeEnglish.Lexicon {
        var d = Data("VTE1".utf8)
        let n = UInt32(entries.count)
        d.append(contentsOf: [UInt8(n & 0xff), UInt8(n >> 8 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 24)])
        for (w, f) in entries.sorted(by: { $0.0 < $1.0 }) {
            d.append(UInt8(w.utf8.count)); d.append(f); d.append(contentsOf: Array(w.utf8))
        }
        return SwipeEnglish.parse(d)!
    }

    func testEnglishCompletions() {
        let lex = lexicon([("hello", 200), ("help", 220), ("he", 250), ("helm", 90), ("world", 240)])
        XCTAssertEqual(SwipeEnglish.completions("hel", in: lex).map(\.word), ["help", "hello", "helm"])
        XCTAssertEqual(SwipeEnglish.completions("he", limit: 2, in: lex).map(\.word), ["help", "hello"])
        XCTAssertEqual(SwipeEnglish.completions("Hel", in: lex).first?.word, "Help")
        XCTAssertEqual(SwipeEnglish.completions("HEL", in: lex).first?.word, "HELP")
        XCTAssertEqual(SwipeEnglish.completions("hel", in: lex).first?.freq, 220)
        XCTAssertEqual(SwipeEnglish.completions("việt", in: lex), [])
        XCTAssertEqual(SwipeEnglish.completions("", in: lex), [])
        XCTAssertEqual(SwipeEnglish.completions("xyz", in: lex), [])
        XCTAssertEqual(SwipeEnglish.topWords(limit: 2, in: lex), ["he", "world"])
    }

    func testRealLexiconHasCompletions() {
        XCTAssertFalse(SwipeEnglish.completions("th").isEmpty)
        XCTAssertEqual(SwipeEnglish.top.count, 12)
    }

    func testSwipeEnglishOnlyFilter() {
        let c = [SwipeCandidate(folded: "the", score: 1, lang: .vi),
                 SwipeCandidate(folded: "the", score: 0.9, lang: .en),
                 SwipeCandidate(folded: "then", score: 0.5, lang: .en)]
        XCTAssertEqual(SwipeTyping.englishOnly(c).map(\.folded), ["the", "then"])
        XCTAssertTrue(SwipeTyping.englishOnly(c).allSatisfy { $0.lang == .en })
    }
}
