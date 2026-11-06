// FeatureRegressionTests — chốt hành vi của batch 24/07/2026: emoji blob,
// settings mới, hợp đồng peek/restore của bridge, cache topWords, và một
// memory-budget test chạy được trên CI (GitHub Actions macOS runner) làm
// regression guard cho RAM của các cấu trúc dữ liệu.
//
// Những phần KHÔNG unit-test được ở đây (cần UIInputViewController + host):
// strip 36/0 + burger hit-area, animation toggle, template plane,
// backspace-undo sau auto-restore, double-space guard, email-gating XPC —
// các mục đó verify tay trên máy (đã đi qua đủ vòng bug 24/07).
import XCTest
import TelexCore

final class EmojiBlobTests: XCTestCase {

    // Bug 24/07: gõ "cứt"/"shit" phải ra 💩 (data từng thiếu + bị filter chặn).
    func testPoopEmoji() {
        XCTAssertEqual(EmojiSuggest.emojis(for: "cứt"), ["💩"])
        XCTAssertEqual(EmojiSuggest.emojis(for: "shit"), ["💩"])
    }

    // Blob mới phải giữ nguyên semantics bảng dictionary cũ.
    func testKnownKeysSurviveBlobification() {
        XCTAssertEqual(EmojiSuggest.emojis(for: "cut"), ["✂️"])   // không lẫn với "cứt"
        XCTAssertEqual(EmojiSuggest.emojis(for: "apple"), ["🍎"])
        XCTAssertFalse(EmojiSuggest.emojis(for: "anh trai").isEmpty)  // khóa 2 token
    }

    // Dictionary cũ so khóa canonical-equivalent + lowercased — blob phải giữ.
    func testCaseAndUnicodeNormalization() {
        XCTAssertEqual(EmojiSuggest.emojis(for: "SHIT"), ["💩"])
        let nfd = "cứt".decomposedStringWithCanonicalMapping
        XCTAssertEqual(EmojiSuggest.emojis(for: nfd), ["💩"])
    }

    func testMisses() {
        XCTAssertEqual(EmojiSuggest.emojis(for: ""), [])
        XCTAssertEqual(EmojiSuggest.emojis(for: "zzzkhongco"), [])
        XCTAssertEqual(EmojiSuggest.emojis(for: "cứ"), [])   // prefix ≠ khóa
    }
}

final class SettingsRegressionTests: XCTestCase {

    private func withDefaults(_ pairs: [String: Any], _ body: () -> Void) {
        let d = UserDefaults(suiteName: "vt-feature-tests")!
        d.removePersistentDomain(forName: "vt-feature-tests")
        for (k, v) in pairs { d.set(v, forKey: k) }
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved }
        body()
    }

    // Rung phím: default TẮT (tính năng đang ẩn — RequestsOpenAccess=false),
    // nhưng key vẫn được đọc để sẵn sàng bật lại.
    func testHapticDefaultOffAndReadable() {
        withDefaults([:]) {
            XCTAssertFalse(KeyboardSettings.load().hapticFeedback)
        }
        withDefaults(["hapticFeedback": true]) {
            XCTAssertTrue(KeyboardSettings.load().hapticFeedback)
        }
    }

    // Sửa dấu từ đã gõ: default BẬT, tắt được qua App Group (user 26/09/2026).
    func testReEditWordDefaultOnAndReadable() {
        withDefaults([:]) { XCTAssertTrue(KeyboardSettings.load().reEditWord) }
        withDefaults(["reEditWord": false]) { XCTAssertFalse(KeyboardSettings.load().reEditWord) }
    }

    // learnWords đi theo showSuggestions (quyết định 24/07).
    func testLearnFollowsSuggestions() {
        withDefaults(["showSuggestions": false]) {
            let s = KeyboardSettings.load()
            XCTAssertFalse(s.showSuggestions)
            XCTAssertFalse(s.learnWords)
        }
    }
}

final class BridgeContractTests: XCTestCase {

    // predictedCommit (peek, không mutate) phải đúng bằng thứ boundary chốt —
    // hợp đồng cho slot literal + backspace-undo sau auto-restore.
    func testPredictedCommitMatchesBoundary() {
        for word in ["his", "vieejt", "google", "loss", "ddaayj", "toans"] {
            let proxy = MockProxy()
            let bridge = EngineBridge(settings: KeyboardSettings())
            for ch in word { bridge.letter(ch, proxy: proxy) }
            let predicted = bridge.predictedCommit
            let committed = bridge.boundary(" ", proxy: proxy)
            XCTAssertEqual(predicted, committed, "peek lệch commit cho \(word)")
        }
    }

    // Nền của trust-fix "his≡hí": composed ≠ committed khi restore xảy ra —
    // controller dựa vào cặp (raw, composed) này để chào undo.
    func testRestorePairForUndo() {
        let proxy = MockProxy()
        let bridge = EngineBridge(settings: KeyboardSettings())
        for ch in "his" { bridge.letter(ch, proxy: proxy) }
        let composed = bridge.composedWord
        let committed = bridge.boundary(" ", proxy: proxy)
        XCTAssertEqual(composed, "hí")
        XCTAssertEqual(committed, "hí")   // chính sách: collision thật → Việt thắng
        // và một ca restore thật (từ Anh thuần). Không dùng "loss": POLICY V2
        // (31/07/2026) cho gõ đúp cuối từ giữ composed (loss→los).
        // "test" ("tét" hợp lệ, không đóng băng ⇒ restore ở boundary). "google" không còn
        // là ca này từ 18/10/2026: eager English restore đưa nó về raw ngay lúc đóng băng.
        let p2 = MockProxy()
        let b2 = EngineBridge(settings: KeyboardSettings())
        for ch in "test" { b2.letter(ch, proxy: p2) }
        XCTAssertNotEqual(b2.composedWord, b2.boundary(" ", proxy: p2))
        let p3 = MockProxy()
        let b3 = EngineBridge(settings: KeyboardSettings())
        for ch in "google" { b3.letter(ch, proxy: p3) }
        XCTAssertEqual(b3.composedWord, "google")
        XCTAssertEqual(b3.boundary(" ", proxy: p3), "google")
    }
}

final class TopWordsCacheTests: XCTestCase {

    // topWords có cache — record() phải invalidate để từ mới nổi lên ngay.
    func testTopWordsCacheInvalidatesOnRecord() {
        let m = UserLangModel(appGroup: nil)
        m.isKnownWord = { _ in true }
        m.record(word: "một", after: nil, prev2: nil, weight: 5)
        _ = m.topWords(limit: 3)                        // mồi cache
        m.record(word: "hai", after: nil, prev2: nil, weight: 50)
        XCTAssertEqual(m.topWords(limit: 1).first, "hai")
    }

    func testEraseAllClearsTopWords() {
        let m = UserLangModel(appGroup: nil)
        m.isKnownWord = { _ in true }
        m.record(word: "xin", after: nil, prev2: nil, weight: 9)
        _ = m.topWords(limit: 3)
        m.eraseAll()
        XCTAssertTrue(m.topWords(limit: 3).isEmpty)
    }
}

// Batch 25/07: thanh gợi ý LUÔN đủ 3 (SuggestionFill.pad) + double-space →
// ". " (TypingHeuristics). Logic thuần rút khỏi KeyboardViewController để
// test được; controller chỉ còn nối proxy/model vào 2 hàm này.
final class SuggestionFillTests: XCTestCase {

    // Đủ sẵn ≥ need → cắt đúng need, không đụng candidates.
    func testAlreadyEnoughTruncates() {
        let r = SuggestionFill.pad(["a", "b", "c", "d"], with: ["x"], need: 3)
        XCTAssertEqual(r, ["a", "b", "c"])
    }

    // Thiếu → đệm từ candidates cho đủ, giữ thứ tự base trước.
    func testPadsToNeed() {
        let r = SuggestionFill.pad(["em"], with: ["anh", "là", "một"], need: 3)
        XCTAssertEqual(r, ["em", "anh", "là"])
    }

    // Loại trùng (case-insensitive) giữa base và candidates.
    func testDedupCaseInsensitive() {
        let r = SuggestionFill.pad(["Em"], with: ["em", "anh", "ANH", "là"], need: 3)
        XCTAssertEqual(r, ["Em", "anh", "là"])
    }

    // Loại từ đang gõ (excluding) khỏi phần đệm.
    func testExcludesTypedWord() {
        let r = SuggestionFill.pad([], with: ["xin", "chào", "bạn"], need: 3, excluding: "Chào")
        XCTAssertEqual(r, ["xin", "bạn"])   // "chào" bị loại vì trùng typed
    }

    // Không đủ candidates → trả những gì có, không nhồi rỗng/nil.
    func testUnderfilledReturnsWhatExists() {
        let r = SuggestionFill.pad(["a"], with: ["b"], need: 3)
        XCTAssertEqual(r, ["a", "b"])
    }

    // Base rỗng + đủ candidates → đúng 3 (ca "chưa gõ / hết gợi ý").
    func testEmptyBaseFillsThree() {
        let r = SuggestionFill.pad([], with: ["một", "hai", "ba", "bốn"], need: 3)
        XCTAssertEqual(r, ["một", "hai", "ba"])
    }
}

final class DoubleSpacePeriodTests: XCTestCase {

    // Có chữ trước space → thành ". ".
    func testAfterWord() {
        XCTAssertTrue(TypingHeuristics.doubleSpaceMakesPeriod(
            context: "xin chào ", lastWasSpace: true))
    }

    // Phím trước KHÔNG phải space → không đổi (double-space đến từ timing space).
    func testRequiresLastWasSpace() {
        XCTAssertFalse(TypingHeuristics.doubleSpaceMakesPeriod(
            context: "xin chào ", lastWasSpace: false))
    }

    // Đầu ô "␣␣" → không biến thành ". ".
    func testNoPeriodAtStart() {
        XCTAssertFalse(TypingHeuristics.doubleSpaceMakesPeriod(
            context: " ", lastWasSpace: true))
    }

    // Trước space đã là dấu câu → không nhân đôi ". .".
    func testNoDoublePunctuation() {
        for c in [".", "!", "?", ","] {
            XCTAssertFalse(TypingHeuristics.doubleSpaceMakesPeriod(
                context: "hết\(c) ", lastWasSpace: true), "sau '\(c)' không được thành . .")
        }
    }

    // Cuối ô không phải space (chưa có space nào) → false.
    func testNeedsTrailingSpace() {
        XCTAssertFalse(TypingHeuristics.doubleSpaceMakesPeriod(
            context: "chào", lastWasSpace: true))
    }

    // Chữ có dấu tiếng Việt trước space vẫn tính là chữ.
    func testVietnameseLetterCounts() {
        XCTAssertTrue(TypingHeuristics.doubleSpaceMakesPeriod(
            context: "việt ", lastWasSpace: true))
    }
}

/// "Tự thêm dấu cách sau dấu câu" (AutoSpace) — số liệu y hệt Android AutoSpaceTests.
/// Nhận gợi ý rồi gõ dấu câu (luồng controller thật, BenchProxy).
final class SuggestionSnapFlowTests: XCTestCase {
    @MainActor private func accept(_ word: String, typing keys: String, then punct: String) -> KeyboardBenchTests.Rig {
        let rig = KeyboardBenchTests.Rig()
        for c in keys { rig.vc.debugHandle(.letter(c)) }
        rig.vc.debugAcceptSuggestion(word)
        rig.vc.debugHandle(.text(punct))
        return rig
    }

    @MainActor func testPeriodAfterAcceptedSuggestionSnapsSpaceAndBackspaceDeletesOnlyIt() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("snap")
        defer { UserDefaultsProvider.shared = saved }
        let rig = accept("người", typing: "nguoi", then: ".")
        defer { rig.close() }
        var t = rig.proxy.text
        while t.hasSuffix(" ") { rig.vc.debugHandle(.backspace); t = rig.proxy.text }   // dấu cách tự thêm (nếu bật)
        XCTAssertEqual(t, "người.")
        rig.vc.debugHandle(.backspace)
        XCTAssertEqual(rig.proxy.text, "người")
    }

    @MainActor func testColonKeepsSuggestionSpace() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("snap")
        defer { UserDefaultsProvider.shared = saved }
        let rig = accept("người", typing: "nguoi", then: ":")
        defer { rig.close() }
        XCTAssertTrue(rig.proxy.text.hasPrefix("người :"), rig.proxy.text)
    }

    @MainActor func testUserTypedSpaceIsNotSnapped() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("snap")
        defer { UserDefaultsProvider.shared = saved }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        for c in "nguowif" { rig.vc.debugHandle(.letter(c)) }
        rig.vc.debugHandle(.space)
        rig.vc.debugHandle(.text("."))
        XCTAssertTrue(rig.proxy.text.hasPrefix("người ."), rig.proxy.text)
    }
}

final class AutoSpaceTests: XCTestCase {

    /// Gợi ý vừa chèn "từ " + . , ? ! ) / nháy đóng ⇒ hút dấu cách ("từ ." → "từ.").
    func testSuggestionSpaceSnapsBeforeClosingPunctuation() {
        for p in [".", ",", "?", "!", ")", "\u{201D}", "\u{2019}", "\u{00BB}"] {
            XCTAssertTrue(AutoSpace.snapsSuggestionSpace(p, before: "xin chào ", inserted: "chào "), p)
        }
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace(":", before: "xin chào ", inserted: "chào "))
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace(";", before: "xin chào ", inserted: "chào "))
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace("(", before: "xin chào ", inserted: "chào "))
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace("a", before: "xin chào ", inserted: "chào "))
        // con trỏ đã dời / không đọc được
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace(".", before: "xin chào", inserted: "chào "))
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace(".", before: nil, inserted: "chào "))
        // " thẳng chỉ khi là nháy ĐÓNG
        XCTAssertTrue(AutoSpace.snapsSuggestionSpace("\"", before: "nói \"xin chào ", inserted: "chào "))
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace("\"", before: "nói xin chào ", inserted: "chào "))
        XCTAssertFalse(AutoSpace.snapsSuggestionSpace("\"", before: "\"a\nnói chào ", inserted: "chào "))
    }

    func testAddsAfterWord() {
        for p in [".", ",", "?", "!", ";", ":"] {
            XCTAssertTrue(AutoSpace.shouldAdd(punct: p, before: "xin chào" + p, after: ""), p)
            XCTAssertTrue(AutoSpace.shouldAdd(punct: p, before: "chào" + p, after: nil), p)
        }
    }

    func testNotInsideNumbers() {
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "giá 3.", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ",", before: "1,", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ":", before: "lúc 10:", after: ""))
        XCTAssertTrue(AutoSpace.shouldAdd(punct: "?", before: "số 3?", after: ""))   // ? ! ; sau số vẫn thêm
    }

    func testNotInUrlsEmailsPaths() {
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "mail ban@gmail.", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "xem https://vnexpress.", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "mở ~/Documents/a.", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "vào www.", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "vào www.google.", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "trang vnexpress.net.", after: ""))
        XCTAssertTrue(AutoSpace.shouldAdd(punct: ".", before: "vd e.g.", after: ""))      // viết tắt
        XCTAssertTrue(AutoSpace.shouldAdd(punct: ".", before: "ờ..", after: ""))          // dấu ba chấm
    }

    func testNotForLoneOrMidText() {
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ":", before: "cười :", after: ""))     // ":)" sắp gõ
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: ".", after: ""))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ",", before: "a,", after: " b"))        // đã có dấu cách sau
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "(hi.", after: ")"))
        XCTAssertTrue(AutoSpace.shouldAdd(punct: ",", before: "hello,", after: "world"))
        XCTAssertFalse(AutoSpace.shouldAdd(punct: "-", before: "a-", after: ""))          // không phải dấu câu
        XCTAssertFalse(AutoSpace.shouldAdd(punct: ".", before: "hi", after: ""))          // host chưa có dấu
    }

    func testReactions() {
        XCTAssertEqual(AutoSpace.reaction(toText: ")"), .carry)
        XCTAssertEqual(AutoSpace.reaction(toText: "\""), .carry)
        XCTAssertEqual(AutoSpace.reaction(toText: "”"), .carry)
        XCTAssertEqual(AutoSpace.reaction(toText: "."), .remove)
        XCTAssertEqual(AutoSpace.reaction(toText: "?"), .remove)
        XCTAssertEqual(AutoSpace.reaction(toText: "/"), .remove)
        XCTAssertEqual(AutoSpace.reaction(toText: "("), .keep)
        XCTAssertEqual(AutoSpace.reaction(toText: "5"), .keep)
        XCTAssertEqual(AutoSpace.reaction(toText: "😀"), .keep)
    }

    func testFieldGate() {
        XCTAssertTrue(FieldTraits().allowsAutoSpace)
        XCTAssertFalse(FieldTraits(keyboardType: .emailAddress).allowsAutoSpace)
        XCTAssertFalse(FieldTraits(keyboardType: .URL).allowsAutoSpace)
        XCTAssertFalse(FieldTraits(keyboardType: .webSearch).allowsAutoSpace)
        XCTAssertFalse(FieldTraits(keyboardType: .decimalPad).allowsAutoSpace)
        XCTAssertFalse(FieldTraits(contentType: .password).allowsAutoSpace)
        XCTAssertFalse(FieldTraits(secure: true).allowsAutoSpace)
    }

    func testSettingDefaultOffAndLoads() {
        XCTAssertFalse(KeyboardSettings().autoSpaceAfterPunct)
        let d = UserDefaults(suiteName: "vt-autospace")!
        d.removePersistentDomain(forName: "vt-autospace")
        d.set(true, forKey: "autoSpaceAfterPunct")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved }
        XCTAssertTrue(KeyboardSettings.load().autoSpaceAfterPunct)
    }

    // MARK: controller thật + proxy giả

    @MainActor private func rig(on: Bool) -> KeyboardBenchTests.Rig {
        let d = KeyboardBenchTests.makeDefaults("C")
        d.set(on, forKey: "autoSpaceAfterPunct")
        UserDefaultsProvider.shared = d
        return KeyboardBenchTests.Rig()
    }

    @MainActor private func run(_ on: Bool, _ keys: [KeyboardView.Key]) -> String {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let r = rig(on: on)
        defer { r.close() }
        for k in keys { r.vc.debugHandle(k); KeyboardBenchTests.spin(0.02) }
        return r.proxy.text
    }

    private func word(_ s: String) -> [KeyboardView.Key] { s.map { .letter($0) } }

    @MainActor func testOffIsUnchanged() {
        XCTAssertEqual(run(false, word("hi") + [.text("."), .space]), "hi. ")
        XCTAssertEqual(run(false, word("hi") + [.text(",")]), "hi,")
    }

    /// Tắt: dấu câu không đọc context thêm (như phím ký hiệu thường "(").
    @MainActor func testOffReadsNoExtraContext() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        func reads(_ on: Bool, _ s: String) -> Int {
            let r = rig(on: on)
            defer { r.close() }
            for k in word("hi") { r.vc.debugHandle(k) }
            KeyboardBenchTests.spin(0.05)
            r.proxy.contextReads = 0
            r.vc.debugHandle(.text(s))
            return r.proxy.contextReads
        }
        XCTAssertEqual(reads(false, ";"), reads(false, "("))
        XCTAssertEqual(reads(true, "("), reads(false, "("))
        XCTAssertGreaterThan(reads(true, ";"), reads(false, ";"))
    }

    @MainActor func testAddsSpaceAndSwallowsNext() {
        XCTAssertEqual(run(true, word("hi") + [.text(",")]), "hi, ")
        XCTAssertEqual(run(true, word("hi") + [.text("."), .space]), "hi. ")
        XCTAssertEqual(run(true, word("hi") + [.text("."), .doubleSpacePeriod]), "hi. ")
        XCTAssertEqual(run(true, word("hi") + [.text("."), .space, .space]), "hi.  ")   // chỉ nuốt 1
        XCTAssertEqual(run(true, word("hi") + [.text(","), .letter("b")]), "hi, b")
    }

    @MainActor func testBackspaceRemovesOnlyAutoSpace() {
        XCTAssertEqual(run(true, word("hi") + [.text("."), .backspace]), "hi.")
        XCTAssertEqual(run(true, word("hi") + [.text("."), .backspace, .backspace]), "hi")
    }

    @MainActor func testPunctAndClosersAfterAutoSpace() {
        XCTAssertEqual(run(true, word("hi") + [.text("."), .text("."), .text(".")]), "hi... ")
        XCTAssertEqual(run(true, word("hi") + [.text("?"), .text("!")]), "hi?! ")
        XCTAssertEqual(run(true, word("hi") + [.text("."), .text(")")]), "hi.) ")
        XCTAssertEqual(run(true, word("hi") + [.text("."), .text("\""), .space]), "hi.\" ")
        XCTAssertEqual(run(true, word("hi") + [.text("."), .newline]), "hi.\n")
        XCTAssertEqual(run(true, word("http") + [.text(":"), .text("/"), .text("/")]), "http://")
    }

    @MainActor func testNumbersStayTight() {
        XCTAssertEqual(run(true, [.text("3"), .text("."), .text("5")]), "3.5")
        XCTAssertEqual(run(true, [.text("1"), .text(","), .text("0")]), "1,0")
    }

    /// Không tự thêm ở ô email / URL / mật khẩu.
    @MainActor func testFieldGateInController() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        for type in [UIKeyboardType.emailAddress, .URL, .webSearch] {
            let r = rig(on: true)
            r.proxy.keyboardType = type
            r.vc.textDidChange(nil)                    // đọc lại trait ô
            for k in word("hi") + [.text(".")] { r.vc.debugHandle(k) }
            XCTAssertEqual(r.proxy.text, "hi.", "\(type.rawValue)")
            r.close()
        }
    }

    /// ". " tự thêm vẫn viết hoa chữ kế; double-space → ". " vẫn chạy.
    @MainActor func testAutoCapAndDoubleSpace() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let r = rig(on: true)
        defer { r.close() }
        for (i, c) in "chao".enumerated() { _ = r.key(c, index: i + 1, drain: 0.03) }
        r.vc.debugHandle(.text("."))
        KeyboardBenchTests.spin(0.05)
        _ = r.key("a", index: 5, drain: 0.03)
        XCTAssertEqual(r.proxy.text, "Chao. A")
        r.vc.debugHandle(.space); r.vc.debugHandle(.doubleSpacePeriod)
        XCTAssertEqual(r.proxy.text, "Chao. A. ")
    }
}

/// Dấu hiệu phím cách: VI/EN khi bật vuốt đổi ngôn ngữ, logo Vᴛ khi tắt.
final class SpaceMarkTests: XCTestCase {
    func testChoice() {
        XCTAssertEqual(SpaceMark.choose(flickEnabled: true, showLogo: true, language: .vi), .code("VI"))
        XCTAssertEqual(SpaceMark.choose(flickEnabled: true, showLogo: false, language: .en), .code("EN"))
        XCTAssertEqual(SpaceMark.choose(flickEnabled: false, showLogo: true, language: .vi), .logo(.vi))
        XCTAssertEqual(SpaceMark.choose(flickEnabled: false, showLogo: false, language: .vi), .none)
    }

    @MainActor func testSpaceBarShowsCodeAndFollowsLanguage() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let d = KeyboardBenchTests.makeDefaults("C")
        d.set(true, forKey: "spaceSwipeLanguage")
        UserDefaultsProvider.shared = d
        let r = KeyboardBenchTests.Rig()
        defer { r.close() }
        let kb = r.vc.debugKeyboard
        XCTAssertEqual(kb.debugSpaceMark(), "VI")
        kb.spaceLanguage = .en
        XCTAssertEqual(kb.debugSpaceMark(), "EN")
        kb.configureSpaceFlick(enabled: false, language: .vi)
        XCTAssertEqual(kb.debugSpaceMark(), "logo")
        kb.configureSpaceFlick(enabled: true, language: .vi)
        XCTAssertEqual(kb.debugSpaceMark(), "VI")
        kb.debugSetPlane(numbers: true)                 // plane số dựng mới cũng có mã
        XCTAssertEqual(kb.debugSpaceMark(), "VI")
    }

    @MainActor func testLogoWhenFlickOff() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("C")
        let r = KeyboardBenchTests.Rig()
        defer { r.close() }
        XCTAssertEqual(r.vc.debugKeyboard.debugSpaceMark(), "logo")
    }
}

final class MemoryBudgetTests: XCTestCase {

    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<Int32>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    // Regression guard chạy được trên CI: delta footprint khi ép load toàn bộ
    // cấu trúc dữ liệu (emoji blob + lexicon + seed model). Không phải RAM
    // tuyệt đối trên iPhone (đó là log "VTKB mem" trên máy) — nhưng blob mà
    // thoái hoá về Dictionary ~1MB+ là test này ĐỎ.
    func testDataStructuresStayUnderBudget() {
        let before = footprintMB()
        _ = EmojiSuggest.emojis(for: "yêu")            // ép decode blob emoji
        _ = VNSuggest.matches("nguoi")                 // ép decode lexicon
        let m = UserLangModel(appGroup: nil)
        m.seedIfEmpty(unigrams: SeedData.unigrams, bigrams: SeedData.bigrams)
        _ = m.topWords(limit: 6)
        let delta = footprintMB() - before
        print("MemoryBudget: data structures delta = \(String(format: "%.2f", delta)) MB")
        XCTAssertLessThan(delta, 8.0, "cấu trúc dữ liệu phình bất thường (\(delta) MB)")
    }
}

// perf-appear 25/09/2026: saveNow() ở viewWillDisappear từng là ioQueue.sync (chặn
// main lúc ẩn bàn phím) và ghi cả file dù không có gì đổi. Giờ async + expiring
// activity, bỏ qua khi không có thay đổi chờ ghi, giữ thứ tự FIFO với save().
final class UserLangModelSaveNowTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("userlm-\(UUID().uuidString).plist")
    }
    override func tearDown() { UserLangModel.removeStore(at: url) }
    /// File thật trên đĩa (userlm.bin — url là tên gốc .plist).
    private var disk: URL { UserLangModel.compactURL(for: url) }

    private func loadedModel() -> UserLangModel {
        let m = UserLangModel(fileURL: url)
        m.isKnownWord = { _ in true }
        let e = expectation(description: "load")
        m.onReady = { e.fulfill() }
        wait(for: [e], timeout: 5)
        return m
    }

    private func waitForFile(_ check: @escaping (UserLangModel) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: disk.path), check(loadedModel()) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    func testSaveNowPersistsAsync() {
        let m = loadedModel()
        m.record(word: "việt", after: nil, prev2: nil, weight: 7)
        m.saveNow()
        XCTAssertTrue(waitForFile { $0.count(of: "việt") == 7 })
    }

    func testSaveNowSkipsWhenNothingPending() {
        let m = loadedModel()
        m.record(word: "nam", after: nil, prev2: nil, weight: 3)
        m.saveNow()
        XCTAssertTrue(waitForFile { $0.count(of: "nam") == 3 })
        try? FileManager.default.removeItem(at: disk)
        m.saveNow()                       // không có gì đổi → không ghi lại
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.path))
    }

    func testSaveNowThenSaveKeepsNewestSnapshot() {
        let m = loadedModel()
        m.record(word: "một", after: nil, prev2: nil, weight: 1)
        m.saveNow()
        m.record(word: "một", after: nil, prev2: nil, weight: 4)
        m.save()                          // cùng ioQueue FIFO → bản mới thắng
        XCTAssertTrue(waitForFile { $0.count(of: "một") == 5 })
    }
}
