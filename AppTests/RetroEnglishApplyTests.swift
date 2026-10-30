// RetroEnglishApplyTests — "Tự sửa từ phía trước" (RetroEnglishApply.swift): chọn kênh áp
// theo chế độ gõ, xác nhận màn hình trước khi viết lại, ⌫ hoàn tác, và luồng tích hợp của
// app (lấy phép sửa TRƯỚC khi ký tự ranh giới tới app) trên một màn hình giả lập.
import Foundation
import XCTest
import TelexCore
@testable import VietTelex

final class RetroEnglishApplyTests: XCTestCase {
    private typealias R = RetroApply

    /// Màn hình giả: đọc range UTF-16 như attributedSubstring / AX kStringForRange.
    private func reader(_ screen: String) -> (NSRange) -> String? {
        let ns = screen as NSString
        return { r in
            guard r.location >= 0, r.location + r.length <= ns.length else { return nil }
            return ns.substring(with: r)
        }
    }

    // MARK: Kênh theo chế độ gõ

    func testIMKChannelOnlyForProvenInPlaceApps() {
        XCTAssertEqual(R.imkChannel(appAllowed: true, marked: false, edge: false, replacesCommittedText: true),
                       .imkReplace)
        // Marked (Terminal ở IMK, app hỏng in-place): không bao giờ.
        XCTAssertEqual(R.imkChannel(appAllowed: true, marked: true, edge: false, replacesCommittedText: true), .none)
        // Edge burst (Slate-class) áp async: không.
        XCTAssertEqual(R.imkChannel(appAllowed: true, marked: false, edge: true, replacesCommittedText: true), .none)
        // App chưa chứng minh tôn trọng replacementRange (có thể APPEND): không.
        XCTAssertEqual(R.imkChannel(appAllowed: true, marked: false, edge: false, replacesCommittedText: false), .none)
        // Terminal / app mã nguồn / Spotlight: không.
        XCTAssertEqual(R.imkChannel(appAllowed: false, marked: false, edge: false, replacesCommittedText: true), .none)
    }

    func testTapChannelOnlyBackspaceRetypeWithDrainedQueue() {
        XCTAssertEqual(R.tapChannel(appAllowed: true, emitMode: .backspace, queueDrained: true), .tapRetype)
        XCTAssertEqual(R.tapChannel(appAllowed: true, emitMode: .backspace, queueDrained: false), .none)
        XCTAssertEqual(R.tapChannel(appAllowed: true, emitMode: .selection, queueDrained: true), .none)
        XCTAssertEqual(R.tapChannel(appAllowed: true, emitMode: .emptyReset, queueDrained: true), .none)
        XCTAssertEqual(R.tapChannel(appAllowed: false, emitMode: .backspace, queueDrained: true), .none)
    }

    func testTerminalsAndCodeEditorsAreExcluded() {
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
                   "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.jetbrains.intellij"] {
            XCTAssertFalse(SystemAutoText.appAllowed(id), id)
            XCTAssertEqual(R.tapChannel(appAllowed: SystemAutoText.appAllowed(id), emitMode: .backspace,
                                        queueDrained: true), .none, id)
            XCTAssertEqual(R.imkChannel(appAllowed: SystemAutoText.appAllowed(id), marked: false, edge: false,
                                        replacesCommittedText: true), .none, id)
        }
        XCTAssertFalse(SystemAutoText.appAllowed(nil))
        XCTAssertTrue(SystemAutoText.appAllowed("com.apple.TextEdit"))
    }

    // MARK: Xác nhận màn hình

    func testVerifiedRangeNeedsExactTextBeforeCaret() {
        let screen = "Hí cả í very fast"
        let caret = (screen as NSString).length
        let r = R.verifiedRange("í cả í very fast", caret: caret, read: reader(screen))
        XCTAssertEqual(r, NSRange(location: 1, length: 16))
        // Lệch một ký tự / con trỏ lệch / có vùng chọn / không đọc được / không biết con trỏ.
        XCTAssertNil(R.verifiedRange("í cả í very fasT", caret: caret, read: reader(screen)))
        XCTAssertNil(R.verifiedRange("í cả í very fast", caret: caret - 1, read: reader(screen)))
        XCTAssertNil(R.verifiedRange("í cả í very fast", caret: caret, selectionLength: 2, read: reader(screen)))
        XCTAssertNil(R.verifiedRange("í cả í very fast", caret: caret, read: { _ in nil }))
        XCTAssertNil(R.verifiedRange("í cả í very fast", caret: nil, read: reader(screen)))
        XCTAssertNil(R.verifiedRange("", caret: caret, read: reader(screen)))
        XCTAssertNil(R.verifiedRange("xx Hí cả í very fast", caret: caret, read: reader(screen)))
    }

    func testVerifiedRangeComparesUTF16NotCanonical() {
        // Ô NFD: "í" = i + U+0301 — Swift `==` coi bằng NFC nhưng độ dài range lệch ⇒ bỏ.
        let nfd = "Hi\u{0301} ca\u{0309} i\u{0301} very fast"
        let caret = (nfd as NSString).length
        XCTAssertNil(R.verifiedRange("í cả í very fast", caret: caret, read: reader(nfd)))
    }

    // MARK: ⌫ hoàn tác

    func testUndoRecordNeedsOnePrintableBoundary() {
        let u = R.undo(expected: "í cả í very fast", insert: "is car is very fast", boundary: " ")
        XCTAssertEqual(u, RetroUndo(previous: "í cả í very fast ", current: "is car is very fast "))
        XCTAssertNotNil(R.undo(expected: "í", insert: "is", boundary: ","))
        XCTAssertNil(R.undo(expected: "í", insert: "is", boundary: nil))
        XCTAssertNil(R.undo(expected: "í", insert: "is", boundary: "\n"))
        XCTAssertNil(R.undo(expected: "í", insert: "is", boundary: "\t"))
        XCTAssertNil(R.undo(expected: "í", insert: "is", boundary: "ab"))
        XCTAssertNil(R.undo(expected: "", insert: "is", boundary: " "))
        XCTAssertNil(R.undo(expected: "is", insert: "is", boundary: " "))
    }

    /// ⌫ sau khi tự khôi phục tiếng Anh ("NÁ" → "NAS"): bản ghi từ engine, cùng luật ranh giới,
    /// và màn hình phải còn đúng "NAS " thì ⌫ mới trả lại "NÁ ".
    func testRestoreUndoFromEngineRecord() {
        var e = TelexEngine()
        for ch in "NAS" { _ = e.feed(ch) }
        _ = e.commitBoundary(autoRestore: true)
        let rec = try? XCTUnwrap(e.takeRestoreUndo())
        XCTAssertEqual(rec, RestoreUndo(restored: "NAS", vietnamese: "NÁ"))
        guard let rec else { return }
        let u = R.restoreUndo(rec, boundary: " ")
        XCTAssertEqual(u, RetroUndo(previous: "NÁ ", current: "NAS ", restore: true))
        XCTAssertNil(R.restoreUndo(rec, boundary: "\n"))
        XCTAssertNil(R.restoreUndo(rec, boundary: nil))
        let screen = "ok NAS "
        let caret = (screen as NSString).length
        XCTAssertEqual(R.revertRange(u!, caret: caret, read: reader(screen)), NSRange(location: 3, length: 4))
        XCTAssertNil(R.revertRange(u!, caret: caret, read: reader("ok NAS!")))
        // Restored garbage ("gôgle" → "google") offers nothing; any next key drops the record.
        var g = TelexEngine(); g.liveSpellCheck = true
        for ch in "google" { _ = g.feed(ch) }
        _ = g.commitBoundary(autoRestore: true)
        XCTAssertNil(g.takeRestoreUndo())
        for ch in "NAS" { _ = g.feed(ch) }
        _ = g.commitBoundary(autoRestore: true)
        _ = g.feed("x")
        XCTAssertNil(g.takeRestoreUndo())
    }

    func testRevertOnlyWhenScreenStillEndsWithTheRewrite() {
        let u = RetroUndo(previous: "í cả í very fast ", current: "is car is very fast ")
        let screen = "His car is very fast "
        let caret = (screen as NSString).length
        XCTAssertEqual(R.revertRange(u, caret: caret, read: reader(screen)),
                       NSRange(location: 1, length: 20))
        // User đã sửa gì đó / con trỏ dời / vùng chọn / AX mù ⇒ ⌫ thường.
        XCTAssertNil(R.revertRange(u, caret: caret, read: reader("His car is very fat ")))
        XCTAssertNil(R.revertRange(u, caret: caret - 1, read: reader(screen)))
        XCTAssertNil(R.revertRange(u, caret: caret, selectionLength: 1, read: reader(screen)))
        XCTAssertNil(R.revertRange(u, caret: nil, read: reader(screen)))
        XCTAssertNil(R.revertRange(u, caret: caret, read: { _ in nil }))
    }

    func testBoundaryCharacterReported() {
        XCTAssertEqual(R.boundaryCharacter(" "), " ")
        XCTAssertEqual(R.boundaryCharacter("."), ".")
        XCTAssertEqual(R.boundaryCharacter("“"), "“")
        XCTAssertNil(R.boundaryCharacter(nil))
        XCTAssertNil(R.boundaryCharacter(""))
        XCTAssertNil(R.boundaryCharacter("ab"))
    }

    // MARK: Luồng tích hợp của app trên màn hình giả

    /// Như controller: chữ cái → feed; ký tự khác → commit (từ đã nằm trên màn hình in-place).
    /// Cờ engine theo "Quyết định theo ngữ cảnh" (`RetroApply.engineFlag`); công tắc chọn chế
    /// độ (`RetroApply.mode`). Tự áp: lấy + xác nhận + áp TRƯỚC ký tự ranh giới. Đề xuất: KHÔNG
    /// đọc màn hình trên đường phím; gợi ý tự xác nhận sau ranh giới (đọc lại màn hình). Ký tự ranh giới
    /// tới app rồi được báo cho engine. Trả về màn hình + bản ghi hoàn tác + đề xuất cuối.
    private func typeLikeApp(_ keys: String, setting: Bool, contextual: Bool = true, slowApp: Bool = false,
                             reads: UnsafeMutablePointer<Int>? = nil)
        -> (screen: String, undo: RetroUndo?, offer: CaretSuggestion?, engine: TelexEngine) {
        var e = TelexEngine()
        var flags = AppState.EngineFlags()
        flags.contextualEnglish = contextual
        flags.retroactiveEnglish = R.engineFlag(contextualEnglish: contextual)
        e.apply(flags)
        var screen = ""
        var undo: RetroUndo?
        var offer: CaretSuggestion?
        for ch in keys {
            if ch.isASCII, ch.isLetter { _ = e.feed(ch); continue }
            screen += e.commitText(autoRestore: true)
            offer = nil
            var applied: RetroCorrection?
            var offered: RetroCorrection?
            if let c = e.pendingRetroCorrection {
                let ns = screen as NSString
                let read = reader(screen)
                let counted: (NSRange) -> String? = { reads?.pointee += 1; return read($0) }
                switch R.keyPathMode(R.mode(contextualEnglish: e.contextualEnglish, autoApply: setting),
                                     slowApp: slowApp) {
                case .autoApply:
                    if let r = R.verifiedRange(c.expected, caret: ns.length, read: counted) {
                        _ = e.takeRetroCorrection()
                        screen = ns.replacingCharacters(in: r, with: c.insert)
                        applied = c
                    }
                case .offer: offered = c          // không đọc màn hình trên đường phím
                case .none: XCTFail("engine decided with contextual English off")
                }
            }
            screen.append(ch)
            if let b = R.boundaryCharacter(String(ch)) { e.noteBoundaryCharacter(b) }
            undo = applied.flatMap { R.undo(expected: $0.expected, insert: $0.insert, boundary: String(ch)) }
            if let c = offered, let o = R.offer(expected: c.expected, insert: c.insert, boundary: String(ch)),
               let d = R.offerDisplay(before: screen, replace: o.replace, insert: o.insert) {
                offer = CaretSuggestion(kind: .retro, display: d, replace: o.replace, insert: o.insert)
            }
        }
        return (screen, undo, offer, e)
    }

    func testSettingOnRewritesThenBackspaceRestoresExactPreviousText() {
        let on = typeLikeApp("His car is very fast ", setting: true)
        XCTAssertEqual(on.screen, "His car is very fast ")
        let u = try? XCTUnwrap(on.undo)
        XCTAssertNotNil(u)
        guard let u else { return }
        let ns = on.screen as NSString
        let r = R.revertRange(u, caret: ns.length, read: reader(on.screen))
        XCTAssertNotNil(r)
        if let r {
            XCTAssertEqual(ns.replacingCharacters(in: r, with: u.previous), "Hí cả í very fast ")
        }
    }

    func testSettingOffOffersInsteadOfRewriting() {
        var run = typeLikeApp("His car is very fast ", setting: false)
        XCTAssertEqual(run.screen, "Hí cả í very fast ")
        XCTAssertNil(run.undo)
        let o = try? XCTUnwrap(run.offer)
        XCTAssertNotNil(o)
        guard let o else { return }
        XCTAssertEqual(o.kind, .retro)
        XCTAssertEqual(o.display, "His car is")
        XCTAssertTrue(o.replace.hasSuffix(" "))      // gồm ký tự ranh giới
        // Tab: đọc lại khớp ⇒ thay đúng range đó (như applyRetroOffer).
        let ns = run.screen as NSString
        let r = R.verifiedRange(o.replace, caret: ns.length, read: reader(run.screen))
        XCTAssertNotNil(r)
        if let r { XCTAssertEqual(ns.replacingCharacters(in: r, with: o.insert), "His car is very fast ") }
        // Phép sửa vẫn đang chờ đúng bằng đề xuất ⇒ lấy được (lịch sử ghi tiếng Anh).
        XCTAssertEqual(run.engine.pendingRetroCorrection?.expected, o.replace)
        XCTAssertNotNil(run.engine.takeRetroCorrection())
        // Màn hình đã khác (người dùng sửa tay) ⇒ không áp.
        XCTAssertNil(R.verifiedRange(o.replace, caret: 10, read: reader("Hí cả í ve")))
    }

    func testContextualOffDoesNothingInEitherMode() {
        for setting in [true, false] {
            let off = typeLikeApp("His car is very fast ", setting: setting, contextual: false)
            XCTAssertNil(off.undo)
            XCTAssertNil(off.offer)
            XCTAssertFalse(off.screen.hasPrefix("His car"))
        }
    }

    func testEnterOrTabBoundaryNeverOffers() {
        func offer(_ b: String?) -> CaretSuggestion? { R.offer(expected: "í cả í", insert: "is car is", boundary: b) }
        XCTAssertNil(offer("\n"))
        XCTAssertNil(offer("\r"))
        XCTAssertNil(offer("\t"))
        XCTAssertNil(offer(nil))
        XCTAssertNil(offer("ab"))
        let o = offer(".")
        XCTAssertEqual(o?.replace, "í cả í.")
        XCTAssertEqual(o?.insert, "is car is.")
        XCTAssertNil(R.offer(expected: "ab", insert: "ab", boundary: " "))
        XCTAssertNil(R.offer(expected: "", insert: "x", boundary: " "))
    }

    // MARK: Chi phí đường phím

    func testOfferModeNeverReadsTheScreenOnTheKeyPath() {
        var reads = 0
        let run = typeLikeApp("His car is very fast ", setting: false, reads: &reads)
        XCTAssertEqual(reads, 0, "offer mode must not read the screen before the boundary reaches the app")
        XCTAssertEqual(run.offer?.display, "His car is")       // vẫn xác nhận lúc hiện gợi ý
        // Tự áp: đúng MỘT lần đọc (range đúng bằng `expected`) cho cả cụm.
        reads = 0
        XCTAssertNotNil(typeLikeApp("His car is very fast ", setting: true, reads: &reads).undo)
        XCTAssertEqual(reads, 1)
    }

    func testSlowAppDemotesAutoApplyToOffer() {
        XCTAssertEqual(R.keyPathMode(.autoApply, slowApp: false), .autoApply)
        XCTAssertEqual(R.keyPathMode(.autoApply, slowApp: true), .offer)
        XCTAssertEqual(R.keyPathMode(.offer, slowApp: true), .offer)
        XCTAssertEqual(R.keyPathMode(.none, slowApp: true), .none)
        // Tap (trình duyệt/Electron): sửa cả cụm ⇒ đề xuất; một từ vẫn tự áp (Phil 23/10/2026).
        XCTAssertEqual(R.tapMode(.autoApply, words: 3), .offer)
        XCTAssertEqual(R.tapMode(.autoApply, words: 1), .autoApply)
        XCTAssertEqual(R.tapMode(.offer, words: 3), .offer)
        XCTAssertEqual(R.tapMode(.none, words: 3), .none)
        var reads = 0
        let run = typeLikeApp("His car is very fast ", setting: true, slowApp: true, reads: &reads)
        XCTAssertEqual(reads, 0)
        XCTAssertNil(run.undo)
        XCTAssertEqual(run.screen, "Hí cả í very fast ")
        XCTAssertEqual(run.offer?.display, "His car is")
    }

    func testSlowAppsBudgetAndPenalty() {
        var g = RetroSlowApps()
        let b = RetroSlowApps.budgetNs, p = RetroSlowApps.penaltyNs
        g.record("com.a", elapsedNs: b, now: 1_000)                 // đúng ngân sách: không ghi
        XCTAssertFalse(g.isSlow("com.a", now: 1_000))
        XCTAssertTrue(g.until.isEmpty)
        g.record("com.a", elapsedNs: b + 1, now: 1_000)
        XCTAssertTrue(g.isSlow("com.a", now: 1_000))
        XCTAssertTrue(g.isSlow("com.a", now: 1_000 + p - 1))
        XCTAssertFalse(g.isSlow("com.a", now: 1_000 + p))           // hết phạt ⇒ thử tự áp lại
        XCTAssertFalse(g.isSlow("com.b", now: 1_000))
        XCTAssertFalse(g.isSlow(nil, now: 1_000))
        g.record(nil, elapsedNs: b * 10, now: 1_000)
        XCTAssertEqual(g.until.count, 1)
        // Bảng có trần: đầy ⇒ dọn mục hết hạn, vẫn đầy ⇒ xoá hết; luôn ghi mục mới.
        var h = RetroSlowApps()
        for i in 0..<RetroSlowApps.capacity { h.record("app\(i)", elapsedNs: b + 1, now: 0) }
        XCTAssertEqual(h.until.count, RetroSlowApps.capacity)
        h.record("new", elapsedNs: b + 1, now: 1)
        XCTAssertLessThanOrEqual(h.until.count, RetroSlowApps.capacity)
        XCTAssertTrue(h.isSlow("new", now: 1))
    }

    func testModeAndEngineFlag() {
        XCTAssertEqual(R.mode(contextualEnglish: true, autoApply: true), .autoApply)
        XCTAssertEqual(R.mode(contextualEnglish: true, autoApply: false), .offer)
        XCTAssertEqual(R.mode(contextualEnglish: false, autoApply: true), .none)
        XCTAssertEqual(R.mode(contextualEnglish: false, autoApply: false), .none)
        XCTAssertTrue(R.engineFlag(contextualEnglish: true))
        XCTAssertFalse(R.engineFlag(contextualEnglish: false))
    }

    func testAppStateEngineFlagFollowsContextualNotSwitch() {
        let s = AppState.shared
        let (ctx, sw) = (s.contextualEnglish, s.retroactiveEnglish)
        defer { s.contextualEnglish = ctx; s.retroactiveEnglish = sw }
        for (c, w) in [(true, false), (true, true), (false, true), (false, false)] {
            s.contextualEnglish = c; s.retroactiveEnglish = w
            XCTAssertEqual(s.engineFlags().retroactiveEnglish, c)
        }
    }

    func testOfferDisplayShowsWholeRewrittenWords() {
        XCTAssertEqual(R.offerDisplay(before: "ok. Hí cả í very fast ", replace: "í cả í very fast ",
                                      insert: "is car is very fast "), "His car is")
        // Từ đầu đổi ngay chữ đầu (không có phần LCP).
        XCTAssertEqual(R.offerDisplay(before: "xem ò course ", replace: "ò course ", insert: "of course "), "of")
        // Ký tự không phải chữ trước phần thay không lọt vào ô.
        XCTAssertEqual(R.offerDisplay(before: "(Hí cả í very ", replace: "í cả í very ",
                                      insert: "is car is very "), "His car is")
        // Màn hình không kết thúc đúng bằng replace ⇒ không đề xuất.
        XCTAssertNil(R.offerDisplay(before: "Hí cả í very", replace: "í cả í very ", insert: "is car is very "))
        // NFD trên màn hình không được coi là khớp.
        XCTAssertNil(R.offerDisplay(before: "Hi\u{301} very ", replace: "í very ", insert: "is very "))
    }

    func testRetroHintWinsOverOtherHints() {
        typealias L = CaretHintLogic
        // Đề xuất sửa ngược thay mọi gợi ý đang hiện.
        for k in [CaretSuggestion.Kind.tones, .typo, .predict, .email, .date, .number, .math] {
            XCTAssertFalse(L.yields(.retro, to: k))
            XCTAssertTrue(L.yields(k, to: .retro), "\(k) must not replace the retro hint")
        }
        XCTAssertFalse(L.yields(.retro, to: nil))
        XCTAssertFalse(L.yields(.retro, to: .retro))
        // Luật cũ giữ nguyên: gợi ý từ nhường loại khác, loại khác thay gợi ý từ.
        XCTAssertTrue(L.yields(.predict, to: .tones))
        XCTAssertFalse(L.yields(.predict, to: .email))
        XCTAssertFalse(L.yields(.tones, to: .predict))
        XCTAssertFalse(L.yields(.typo, to: nil))
        // Tab nhận, Enter KHÔNG nhận (đi tiếp như thường), Esc tắt.
        XCTAssertEqual(L.action(kind: .retro, keyCode: L.kTab, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .retro, keyCode: L.kReturn, plain: true), .dismissPass)
        XCTAssertEqual(L.action(kind: .retro, keyCode: L.kEscape, plain: true), .dismissConsume)
        XCTAssertEqual(L.action(kind: .retro, keyCode: 0, plain: true), .dismissPass)
    }

    func testVietnameseSentenceUntouched() {
        XCTAssertNil(typeLikeApp("Mai car team hojp ", setting: true).undo)
        XCTAssertNil(typeLikeApp("Mai car team hojp ", setting: false).offer)
    }

    func testEngineFlagCarriesTheSetting() {
        var e = TelexEngine()
        var f = AppState.EngineFlags()
        f.retroactiveEnglish = true
        e.apply(f)
        XCTAssertTrue(e.retroactiveEnglish)
        XCTAssertTrue(e.retroactiveEnglishActive)
        f.contextualEnglish = false
        e.apply(f)
        XCTAssertFalse(e.retroactiveEnglishActive)
        f.retroactiveEnglish = false
        e.apply(f)
        XCTAssertFalse(e.retroactiveEnglish)
    }
}
