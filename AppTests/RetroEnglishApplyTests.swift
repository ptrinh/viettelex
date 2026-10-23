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

    /// Như controller: chữ cái → feed; ký tự khác → commit (từ đã nằm trên màn hình in-place),
    /// lấy + xác nhận + áp phép sửa TRƯỚC ký tự ranh giới, rồi ký tự ranh giới tới app và
    /// được báo cho engine. Trả về màn hình + bản ghi hoàn tác cuối.
    private func typeLikeApp(_ keys: String, setting: Bool, contextual: Bool = true)
        -> (screen: String, undo: RetroUndo?) {
        var e = TelexEngine()
        var flags = AppState.EngineFlags()
        flags.contextualEnglish = contextual
        flags.retroactiveEnglish = setting
        e.apply(flags)
        var screen = ""
        var undo: RetroUndo?
        for ch in keys {
            if ch.isASCII, ch.isLetter { _ = e.feed(ch); continue }
            screen += e.commitText(autoRestore: true)
            var applied: RetroCorrection?
            if let c = e.pendingRetroCorrection {
                let ns = screen as NSString
                if let r = R.verifiedRange(c.expected, caret: ns.length, read: reader(screen)) {
                    _ = e.takeRetroCorrection()
                    screen = ns.replacingCharacters(in: r, with: c.insert)
                    applied = c
                }
            }
            screen.append(ch)
            if let b = R.boundaryCharacter(String(ch)) { e.noteBoundaryCharacter(b) }
            undo = applied.flatMap { R.undo(expected: $0.expected, insert: $0.insert, boundary: String(ch)) }
        }
        return (screen, undo)
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

    func testSettingOffOrContextualOffChangesNothing() {
        XCTAssertEqual(typeLikeApp("His car is very fast ", setting: false).screen, "Hí cả í very fast ")
        XCTAssertNil(typeLikeApp("His car is very fast ", setting: false).undo)
        // Cờ engine bật nhưng "Quyết định theo ngữ cảnh" tắt ⇒ engine không bao giờ đề xuất.
        let off = typeLikeApp("His car is very fast ", setting: true, contextual: false)
        XCTAssertNil(off.undo)
        XCTAssertFalse(off.screen.hasPrefix("His car"))
    }

    func testVietnameseSentenceUntouched() {
        XCTAssertNil(typeLikeApp("Mai car team hojp ", setting: true).undo)
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
