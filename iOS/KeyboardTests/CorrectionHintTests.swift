import XCTest
import UIKit

/// ONBOARDING-SPEC §8 — tô nền gợi ý sửa khi gõ sai. Parity Android CorrectionHintTests.kt.
/// Ô tô nền và dấu cách dùng CHUNG một quyết định (controller correctionDecision).
final class CorrectionHintTests: XCTestCase {
    private let center = AutoCorrect.Touch(dx: 0, dy: 0)

    private func plan(_ b: EngineBridge, _ raw: String) -> AutoCorrect.Plan? {
        AutoCorrect.plan(raw: raw, compose: { b.composeTrial($0) }, frequency: { VNSuggest.frequency(of: $0) },
                         hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty })
    }

    /// Quyết định như controller: điểm chạm giữa phím, `rejected` = từng hoàn tác tự sửa.
    private func decide(_ b: EngineBridge, _ raw: String, rejected: AutoCorrect.Rejected = .init()) -> String? {
        plan(b, raw).flatMap {
            AutoCorrect.decide($0, touches: Array(repeating: center, count: raw.count),
                               isKnown: { rejected.contains($0) || AutoCorrect.isEnglish($0) })
        }
    }

    private func type(_ b: EngineBridge, _ p: MockProxy, _ keys: String) {
        for ch in keys { if ch == " " { b.boundary(" ", proxy: p) } else { b.letter(ch, proxy: p) } }
    }

    /// Thanh gợi ý như controller dựng cho từ đang soạn (nil = không tô).
    private func bar(_ b: EngineBridge, _ p: MockProxy, rejected: AutoCorrect.Rejected = .init(),
                     others: [String] = ["ánh", "anh"]) -> [BarChip?] {
        var set = KeyboardView.SuggestionSet()
        set.literal = b.composedWord; set.word = others.first; set.word2 = others.dropFirst().first
        if let fix = decide(b, b.rawWord, rejected: rejected),
           let original = b.autoCorrectPreview(fix, context: p.contextBeforeInput) {
            CorrectionHint.apply(&set, typed: original, fix: fix, need: 2)
        }
        guard case .slots(let s, _) = SuggestionSlots.arrange(set) else { XCTFail(); return [] }
        return s
    }

    /// Bridge có tự sửa bằng đúng quyết định của thanh.
    private func acBridge(rejected: AutoCorrect.Rejected = .init()) -> EngineBridge {
        let b = EngineBridge(settings: KeyboardSettings())
        b.autoCorrector = { [unowned self, unowned b] raw in self.decide(b, raw, rejected: rejected) }
        return b
    }

    // MARK: AutoCorrect — ứng viên chạm đúp

    func testDoubledKeyIsACandidateWithoutTouchEvidence() {
        let b = EngineBridge(settings: KeyboardSettings())
        XCTAssertEqual(decide(b, "anhh"), "anh")
        XCTAssertEqual(decide(b, "Anhh"), "Anh")
        XCTAssertEqual(decide(b, "ddii"), "đi")
        XCTAssertNil(decide(b, "toii"))                                       // "toi" (100) không đủ phổ biến
        XCTAssertNil(plan(b, "anh"))                                          // từ hợp lệ: không có kế hoạch sửa
    }

    // MARK: thanh gợi ý + dấu cách

    func testInvalidWordShowsQuotedTypedThenHighlightedFix() {
        let b = acBridge(), p = MockProxy()
        type(b, p, "Anhh")
        let s = bar(b, p)
        XCTAssertEqual(s.map { $0?.label }, ["\u{201C}Anhh\u{201D}", "Anh", "ánh"])
        XCTAssertEqual(s.map { $0?.highlight }, [false, true, false])
        XCTAssertEqual(s[0]?.payload, KeyboardView.keepTypedPrefix + "Anhh")
    }

    func testValidWordIsNotHighlighted() {
        let b = acBridge(), p = MockProxy()
        type(b, p, "anh")
        let s = bar(b, p)
        XCTAssertTrue(s.allSatisfy { $0?.highlight != true })
        XCTAssertEqual(s[0]?.payload, "anh")
    }

    func testSpaceWithAutoCorrectAppliesExactlyTheHighlightedSlot() {
        let b = acBridge(), p = MockProxy()
        type(b, p, "Anhh")
        let shown = bar(b, p).compactMap { $0 }.first { $0.highlight }!.label
        type(b, p, " ")
        XCTAssertEqual(p.text, shown + " ")
        XCTAssertEqual(p.text, "Anh ")
    }

    func testQuotedSlotRejectsWordSoItIsNotCorrectedNextTime() {
        let rejected = AutoCorrect.Rejected()
        let b = acBridge(rejected: rejected), p = MockProxy()
        type(b, p, "Anhh")
        let keep = bar(b, p, rejected: rejected)[0]!.payload
        XCTAssertTrue(keep.hasPrefix(KeyboardView.keepTypedPrefix))
        rejected.add(String(keep.dropFirst(KeyboardView.keepTypedPrefix.count)))   // controller keepTyped
        XCTAssertTrue(rejected.contains("anhh"))
        b.reset(); p.text = "Anhh "
        type(b, p, "anhh")
        XCTAssertTrue(bar(b, p, rejected: rejected).allSatisfy { $0?.highlight != true })
        type(b, p, " ")
        XCTAssertEqual(p.text, "Anhh anhh ")
    }

    func testAutoCorrectOffShowsHintButSpaceDoesNotCorrect() {
        let b = EngineBridge(settings: KeyboardSettings()), p = MockProxy()   // không closure = tự sửa tắt
        type(b, p, "Anhh")
        let s = bar(b, p)
        XCTAssertEqual(s[1]?.label, "Anh")
        XCTAssertEqual(s[1]?.highlight, true)
        type(b, p, " ")
        XCTAssertEqual(p.text, "Anhh ")
    }

    /// Hoa giữa câu = tên riêng / dính URL: dấu cách không sửa ⇒ không tô (thanh và dấu cách không lệch).
    func testNoHighlightWhereSpaceWouldNotCorrect() {
        let b = acBridge(), p = MockProxy(); p.text = "gặp "
        type(b, p, "Anhh")
        XCTAssertTrue(bar(b, p).allSatisfy { $0?.highlight != true })
        type(b, p, " ")
        XCTAssertEqual(p.text, "gặp Anhh ")
        let c = acBridge(), q = MockProxy(); q.text = "a@"
        type(c, q, "anhh")
        XCTAssertNil(c.autoCorrectPreview("anh", context: q.contextBeforeInput))
        let e = acBridge(), r = MockProxy()
        _ = e.setEnglish(true, proxy: r)
        type(e, r, "anhh")
        XCTAssertNil(e.autoCorrectPreview("anh", context: r.contextBeforeInput))   // chế độ Tiếng Anh
    }

    func testArrangeHighlightFollowsWordAcrossLayouts() {
        var set = KeyboardView.SuggestionSet()
        set.literal = "Anhh"; set.word = "Anh"; set.word2 = "ánh"; set.correction = true
        guard case .slots(let one, _) = SuggestionSlots.arrange(set, count: 1),
              case .slots(let five, _) = SuggestionSlots.arrange(set, count: 5) else { return XCTFail() }
        XCTAssertEqual(one[0], BarChip(label: "Anh", payload: "Anh", highlight: true))
        XCTAssertEqual(five.prefix(3).map { $0?.highlight }, [false, true, false])
        set.number = "1.000"                                                  // chip số chen giữa: tô theo chữ
        guard case .slots(let withNumber, _) = SuggestionSlots.arrange(set) else { return XCTFail() }
        XCTAssertEqual(withNumber.first { $0?.highlight == true }??.label, "Anh")
        set.number = nil; set.correction = false
        guard case .slots(let plain, _) = SuggestionSlots.arrange(set) else { return XCTFail() }
        XCTAssertEqual(plain[0]?.payload, "Anhh")
        XCTAssertTrue(plain.allSatisfy { $0?.highlight != true })
    }

    func testCorrectionHintReordersExistingCandidatesOnly() {
        var set = KeyboardView.SuggestionSet()
        set.literal = "anhh"; set.word = "ánh"; set.word2 = "Anh"; set.emojis = ["x"]
        CorrectionHint.apply(&set, typed: "Anhh", fix: "Anh", need: 2)
        XCTAssertEqual(set.literal, "Anhh")
        XCTAssertEqual(set.word, "Anh")
        XCTAssertEqual(set.word2, "ánh")                                      // ứng viên kế, bỏ trùng
        XCTAssertTrue(set.emojis.isEmpty)
        XCTAssertTrue(set.correction)
    }

    /// Nền / chữ ô tô nền theo theme (sáng, tối, theme có sẵn khác).
    func testPillFollowsTheme() {
        for theme in [KeyboardTheme.system, .peach] {
            for dark in [false, true] {
                let p = theme.palette(systemDark: dark)
                let c = KeyboardView.pillColors(p)
                XCTAssertEqual(c.fill, p.keyFill)
                XCTAssertEqual(c.ink, p.keyInk)
            }
        }
        XCTAssertNotEqual(KeyboardView.pillColors(KeyboardTheme.system.palette(systemDark: false)).fill,
                          KeyboardView.pillColors(KeyboardTheme.system.palette(systemDark: true)).fill)
    }

    // MARK: controller thật (thanh gợi ý thật, dấu cách thật)

    /// Controller kín (không đọc dữ liệu người dùng của máy chạy test: model học từ App Group —
    /// lượt chạy trước học "anhh" ⇒ thôi sửa —, từ từng từ chối, Thay thế văn bản), điểm chạm cấp
    /// thẳng (không phụ thuộc hình học phím của simulator). `lastTouch`: điểm chạm phím cuối.
    @MainActor private func runController(autoCorrect: Bool, word: String = "anhh",
                                          lastTouch: (Float, Float) = (0, 0), prefix: String = "",
                                          beforeSpace: ((KeyboardBenchTests.BenchProxy) -> Void)? = nil)
        -> (titles: [String?], pill: Int?, text: String, pillFill: UIColor?) {
        let saved = UserDefaultsProvider.shared
        let d = KeyboardBenchTests.makeDefaults("A")
        d.set(autoCorrect, forKey: "autoCorrect")
        d.set(false, forKey: "smartTouch")
        UserDefaultsProvider.shared = d
        KeyboardViewController.debugHermetic = true
        defer { UserDefaultsProvider.shared = saved; KeyboardViewController.debugHermetic = false }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        KeyboardBenchTests.spin(0.05)
        rig.proxy.text = prefix
        let kb = rig.vc.debugKeyboard
        XCTAssertNotNil(kb.onLetterTouch, "thanh gợi ý bật ⇒ controller nhận điểm chạm")
        for (i, c) in word.enumerated() {
            let t = i == word.count - 1 ? lastTouch : (0, 0)
            kb.onLetterTouch?(t.0, t.1)
            rig.vc.debugHandle(.letter(c))
            KeyboardBenchTests.spin(0.02)
        }
        KeyboardBenchTests.spin(0.2)                                          // gợi ý tính nền rồi về main
        let titles = kb.debugSlotTitles(), pill = kb.debugPillSlot, fill = kb.debugPillFill
        beforeSpace?(rig.proxy)
        _ = rig.key(" ", index: 1, drain: 0.05)
        return (titles, pill, rig.proxy.text, fill)
    }

    @MainActor func testControllerHighlightsAndSpaceAppliesIt() {
        let on = runController(autoCorrect: true)
        XCTAssertEqual(on.pill, 1, "\(on.titles)")
        XCTAssertEqual((on.titles.first ?? nil)?.lowercased(), "\u{201C}anhh\u{201D}")   // hoa đầu ô tuỳ auto-shift
        let fix = on.titles[1] ?? ""
        XCTAssertEqual(fix.lowercased(), "anh")
        XCTAssertTrue(on.text.hasSuffix(fix + " "), on.text)                  // dấu cách = đúng ô tô nền
        XCTAssertNotNil(on.pillFill)
        let off = runController(autoCorrect: false)
        XCTAssertEqual(off.pill, 1, "\(off.titles)")                          // tắt: vẫn tô làm gợi ý
        XCTAssertTrue(off.text.lowercased().hasSuffix("anhh "), off.text)     // …nhưng dấu cách không sửa
    }

    /// Dấu cách KHÔNG BAO GIỜ ra chữ khác ô tô nền, mọi điểm chạm phím cuối (h chạm lệch dần sang j:
    /// có thể ra "anh", "ạnh" hay không sửa — nhưng thanh và dấu cách luôn cùng một kết quả).
    @MainActor func testSpaceNeverDivergesFromHighlightedSlot() {
        for dx: Float in [0, 0.3, 0.45, 0.55, 0.7, 0.9] {
            let r = runController(autoCorrect: true, lastTouch: (dx, 0))
            let typed = String(r.text.dropLast())
            if let i = r.pill {
                XCTAssertEqual(typed, r.titles[i] ?? "", "dx=\(dx) \(r.titles)")
            } else {
                XCTAssertEqual(typed.lowercased(), "anhh", "dx=\(dx) không tô ⇒ không sửa \(r.titles)")
            }
        }
    }

    /// Thanh đã vẽ cho từ này mà KHÔNG tô (hoa giữa câu "gặp Anhh" ⇒ tên riêng) rồi chữ trước con trỏ
    /// đổi trước dấu cách (host sửa ô): tính lại lúc dấu cách sẽ sửa thành "Anh" — chữ không hề được
    /// tô. Dấu cách phải theo đúng thanh đã hiện ⇒ không sửa.
    @MainActor func testSpaceFollowsRenderedBarEvenIfContextChanges() {
        let r = runController(autoCorrect: true, word: "Anhh", prefix: "gặp ",
                              beforeSpace: { $0.text = String($0.text.dropFirst("gặp ".count)) })
        XCTAssertNil(r.pill, "\(r.titles)")
        XCTAssertEqual(r.text, "Anhh ")
    }
}
