// Góp ý tester Plus 15/10/2026 (iOS 1.2.12):
//  1. "Bỏ dấu câu hơi bị lag" — đường phím không đổi giữa 1.2.11 / 1.2.12 / main (bench
//     KeyboardBenchTests VT_BENCH_CORPUS=tones); thứ duy nhất 1.2.12 thêm vào process bàn phím
//     là link Translation (nạp ~34 framework lúc khởi động) — main đã gỡ. Chặn tái phát: bàn
//     phím không link Translation trong project.yml + ngân sách việc mỗi phím dấu.
//  2. Dịch văn bản nhiều đoạn: dịch từng dòng (một lô), giữ xuống dòng / dòng trống; không
//     chọn gì thì nói rõ chỉ dịch đoạn đang gõ.
//  3. Clipboard: ghi cả khi con trỏ sau chữ; mở panel đọc ngay mục vừa copy; Toàn quyền đối
//     chiếu lại ở viewDidAppear; mục dài (≤ 10k ký tự) được lưu. Lưới Công cụ mở nhanh.
import XCTest
import UIKit

private final class FakePasteboard: PasteboardSource {
    var changeCount: Int
    var text: String?
    var reads = 0
    init(change: Int, text: String?) { changeCount = change; self.text = text }
    var hasStrings: Bool { text != nil }
    var string: String? { reads += 1; return text }
    var types: [String] { text == nil ? [] : ["public.utf8-plain-text"] }
}

final class PlusFeedback1015Tests: XCTestCase {

    // MARK: 1. lag gõ dấu

    /// project.yml: target bàn phím KHÔNG được có Translation.framework (kể cả weak) — đó là
    /// thứ 1.2.12 thêm vào process bàn phím (dyld nạp + ~34 framework phụ thuộc mỗi lần khởi động).
    func testKeyboardTargetDoesNotLinkTranslation() throws {
        let yml = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let s = try String(contentsOf: yml, encoding: .utf8)
        let lines = s.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "  VietTelexKeyboard:") else { return XCTFail("không thấy target") }
        var section: [String] = []
        for l in lines[(start + 1)...] {
            // Target kế tiếp: 2 dấu cách + tên + ":" (khối con thụt sâu hơn).
            if l.hasPrefix("  "), !l.hasPrefix("   "), l.hasSuffix(":") { break }
            section.append(l)
        }
        XCTAssertGreaterThan(section.count, 5)
        let linked = section.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .contains { $0.contains("Translation.framework") }
        XCTAssertFalse(linked, "bàn phím không được link Translation.framework")
    }

    /// Ngân sách mỗi phím trên chuỗi nặng phím dấu (s/f/r/x/j, đổi dấu, ⌫ không có): số lệnh
    /// tới host (đọc context / chèn / xoá) — mỗi lệnh là một IPC trên máy thật — và thời gian
    /// đồng bộ trung vị. Số đo 15/10/2026 (Debug, simulator): ctx 0.40, ins 0.97, del 0.42,
    /// sync p50 ≈ 0.5–0.8 ms. Ngưỡng rộng để không chập chờn, đủ bắt hồi quy cỡ "thêm việc
    /// mỗi phím" (thêm một lượt đọc context / ghi lại cả từ).
    @MainActor func testToneKeyHotPathBudget() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("B")
        defer { UserDefaultsProvider.shared = saved }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        let keys = Array(KeyboardBenchTests.toneCorpus)
        for c in keys { _ = rig.key(c, index: 1, drain: 0.002) }   // làm nóng
        rig.proxy.contextReads = 0; rig.proxy.inserts = 0; rig.proxy.deletes = 0
        var sync: [Double] = []
        var n = 0
        for c in keys {
            // index lẻ: không bao giờ chia hết cho 25 ⇒ không chen ⌫ vuốt của bench.
            let r = rig.key(c, index: 1, drain: 0.002)
            sync.append(r.sync); n += 1
        }
        let ctx = Double(rig.proxy.contextReads) / Double(n)
        let ins = Double(rig.proxy.inserts) / Double(n)
        let del = Double(rig.proxy.deletes) / Double(n)
        let p50 = KeyboardBenchTests.pct(sync, 0.5)
        print(String(format: "TONEBUDGET keys=%d ctx=%.2f ins=%.2f del=%.2f sync_p50=%.3f", n, ctx, ins, del, p50))
        XCTAssertEqual(rig.proxy.text.contains("việt"), true, "chuỗi dấu phải ra đúng chữ: \(rig.proxy.text.suffix(60))")
        XCTAssertLessThan(ctx, 0.8, "đọc context mỗi phím")
        XCTAssertLessThan(ins, 1.3, "insertText mỗi phím")
        XCTAssertLessThan(del, 0.8, "deleteBackward mỗi phím")
        XCTAssertLessThan(p50, 3.0, "thời gian đồng bộ trung vị mỗi phím (ms)")
    }

    // MARK: 2. Dịch nhiều đoạn

    func testSplitLinesKeepsBlankLinesAndCRLF() {
        let s = "Một\n\nHai\r\nBa\u{2028}Bốn"
        let (lines, breaks) = TranslateText.splitLines(s)
        XCTAssertEqual(lines, ["Một", "", "Hai", "Ba", "Bốn"])
        XCTAssertEqual(breaks, ["\n", "\n", "\r\n", "\u{2028}"])
        XCTAssertEqual(TranslateText.joinLines(lines, breaks: breaks), s)
        XCTAssertEqual(TranslateText.splitLines("").lines, [""])
        XCTAssertEqual(TranslateText.splitLines("a\n").lines, ["a", ""])
    }

    /// Bug: cả khối nhiều đoạn gửi thành MỘT chuỗi ⇒ mất ngắt dòng / chỉ ra một phần.
    /// Giờ: một lần gọi (một session), mỗi dòng có chữ là một mục; ráp lại đúng chỗ.
    func testTranslateLinesTranslatesEveryParagraphKeepingLayout() async {
        let src = "Xin chào\n\nHôm nay trời đẹp.\n- 1 2 3\n  Cảm ơn bạn  \n"
        var calls: [String] = []
        let r = await TranslateText.translateLines(src) { packed in
            calls.append(packed)
            let parts = packed.split(separator: TranslateText.batchSeparator, omittingEmptySubsequences: false)
            return .success(parts.map { "<\($0)>" }.joined(separator: String(TranslateText.batchSeparator)))
        }
        XCTAssertEqual(calls.count, 1, "một lô duy nhất")
        XCTAssertEqual(calls.first?.split(separator: TranslateText.batchSeparator).count, 3,
                       "chỉ dòng có chữ cái được gửi")
        XCTAssertEqual(try r.get(), "<Xin chào>\n\n<Hôm nay trời đẹp.>\n- 1 2 3\n  <Cảm ơn bạn>  \n")
    }

    func testTranslateLinesSingleLineSentAsIs() async {
        var calls: [String] = []
        let r = await TranslateText.translateLines("Xin chào bạn") { calls.append($0); return .success("Hello") }
        XCTAssertEqual(calls, ["Xin chào bạn"])
        XCTAssertEqual(try r.get(), "Hello")
    }

    func testTranslateLinesFailuresPropagate() async {
        let mismatch = await TranslateText.translateLines("a b\nc d") { _ in .success("chỉ một mục") }
        XCTAssertEqual(mismatch, .failure(.failed))
        let notInstalled = await TranslateText.translateLines("a b\nc d") { _ in .failure(.notInstalled) }
        XCTAssertEqual(notInstalled, .failure(.notInstalled))
        // Không dòng nào có chữ ⇒ giữ nguyên, không gọi dịch.
        var called = false
        let none = await TranslateText.translateLines("1\n\n2") { _ in called = true; return .success("") }
        XCTAssertEqual(try none.get(), "1\n\n2")
        XCTAssertFalse(called)
    }

    /// Không chọn gì: chỉ dịch được đoạn trước con trỏ (iOS chỉ đưa cửa sổ chữ quanh con trỏ)
    /// ⇒ ô còn chữ khác thì báo, không lặng lẽ dịch một phần.
    func testPartialNoticeOnlyWhenOtherTextRemains() {
        XCTAssertTrue(TranslateText.coversOnlyPart(isSelection: false, source: "Đoạn hai",
                                                   before: "Đoạn một\nĐoạn hai", after: ""))
        XCTAssertTrue(TranslateText.coversOnlyPart(isSelection: false, source: "Đoạn một",
                                                   before: "Đoạn một", after: "\nĐoạn hai"))
        XCTAssertFalse(TranslateText.coversOnlyPart(isSelection: false, source: "Chỉ một đoạn",
                                                    before: "Chỉ một đoạn", after: nil))
        XCTAssertFalse(TranslateText.coversOnlyPart(isSelection: false, source: "Hai",
                                                    before: "\n\nHai", after: "  "))
        XCTAssertFalse(TranslateText.coversOnlyPart(isSelection: true, source: "Một\nHai",
                                                    before: "Trước", after: "Sau"))
        XCTAssertFalse(KeyboardViewController.translatePartialNotice.isEmpty)
    }

    // MARK: 3. clipboard + Công cụ

    @MainActor private func clipRig(noPrompt: Bool, fullAccess: Bool = true,
                                     history: Bool = true) -> (KeyboardBenchTests.Rig, UserDefaults) {
        if let u = ClipboardHistory.defaultFileURL { try? FileManager.default.removeItem(at: u) }
        let d = KeyboardBenchTests.makeDefaults("CLIP")
        d.set(history, forKey: ClipboardFeature.historyKey)
        d.set(noPrompt, forKey: "pasteNoPrompt")
        UserDefaultsProvider.shared = d
        let rig = KeyboardBenchTests.Rig()
        rig.vc.debugFullAccess = fullAccess
        return (rig, d)
    }

    @MainActor private func closeClipRig(_ rig: KeyboardBenchTests.Rig, _ d: UserDefaults) {
        rig.close()
        d.set(false, forKey: ClipboardFeature.historyKey)
        if let u = ClipboardHistory.defaultFileURL { try? FileManager.default.removeItem(at: u) }
    }

    /// Bug: changeCount chỉ được đọc khi con trỏ đứng sau khoảng trắng ⇒ copy trong ô (con
    /// trỏ sau chữ) không bao giờ vào lịch sử.
    @MainActor func testCopyWithCaretAfterLetterIsRecorded() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let (rig, d) = clipRig(noPrompt: true)
        defer { closeClipRig(rig, d) }
        rig.proxy.text = "đã chọn chữ này"            // con trỏ sau chữ cái
        let pb = FakePasteboard(change: 4242, text: "nội dung vừa copy")
        rig.vc.debugPasteboard = pb
        rig.vc.debugUpdateSuggestions()
        XCTAssertEqual(rig.vc.debugClipTexts.first, "nội dung vừa copy")
    }

    /// Mở panel clipboard = người dùng chủ động ⇒ đọc mục hiện tại dù chưa "Cho phép dán"
    /// (tự đọc nền vẫn không đọc khi iOS còn hỏi).
    @MainActor func testOpeningPanelReadsCurrentClipboard() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let (rig, d) = clipRig(noPrompt: false)
        defer { closeClipRig(rig, d) }
        rig.proxy.text = "xin chào "
        let pb = FakePasteboard(change: 77, text: "mục mới")
        rig.vc.debugPasteboard = pb
        rig.vc.debugUpdateSuggestions()
        XCTAssertEqual(pb.reads, 0, "tự đọc nền không được bật hộp thoại hỏi dán")
        XCTAssertTrue(rig.vc.debugClipTexts.isEmpty)
        rig.vc.debugToggleClipboardPanel()
        XCTAssertTrue(rig.vc.debugClipboardPanelOpen)
        XCTAssertEqual(rig.vc.debugClipTexts, ["mục mới"])
        XCTAssertEqual(pb.reads, 1)
        // Mở lại, clipboard không đổi ⇒ không đọc lại.
        rig.vc.debugToggleClipboardPanel(); rig.vc.debugToggleClipboardPanel()
        XCTAssertEqual(pb.reads, 1)
        rig.vc.debugToggleClipboardPanel()
    }

    /// hasFullAccess sai ở viewWillAppear ⇒ nút 📋 mất cả lần hiện; viewDidAppear sửa lại.
    @MainActor func testFullAccessRecheckedOnDidAppear() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let d = KeyboardBenchTests.makeDefaults("CLIP2")
        d.set(true, forKey: ClipboardFeature.historyKey)
        UserDefaultsProvider.shared = d
        let rig = KeyboardBenchTests.Rig()          // Toàn quyền (thật) = false trong test
        defer { rig.close(); d.set(false, forKey: ClipboardFeature.historyKey) }
        XCTAssertFalse(rig.vc.debugClipboardButtonVisible)
        rig.vc.debugFullAccess = true
        rig.vc.debugViewDidAppear()
        XCTAssertTrue(rig.vc.debugClipboardButtonVisible)
        rig.vc.debugFullAccess = false
        rig.vc.debugViewDidAppear()
        XCTAssertFalse(rig.vc.debugClipboardButtonVisible)
    }

    /// ☰ → thẻ Công cụ: hiện ngay (đồng bộ, không chờ gì), không đọc ô nhập, nhanh.
    @MainActor func testToolsGridOpensImmediately() {
        let saved = UserDefaultsProvider.shared
        let savedPaywall = PlusGate.paywallEnabled
        defer { UserDefaultsProvider.shared = saved; PlusGate.paywallEnabled = savedPaywall }
        PlusGate.paywallEnabled = false
        let d = KeyboardBenchTests.makeDefaults("TOOLS")
        // Nhiều mẫu câu (lưới tự dàn dòng) — trường hợp nặng.
        d.set((0..<60).map { ["label": "", "text": "Mẫu câu số \($0) khá dài một chút"] }, forKey: "userTemplates")
        UserDefaultsProvider.shared = d
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        let kb = rig.vc.debugKeyboard
        XCTAssertTrue(kb.textToolsEnabled)
        var times: [Double] = []
        for _ in 0..<5 {
            let reads0 = rig.proxy.contextReads
            let t0 = CACurrentMediaTime()
            kb.debugTapLeftZone()                         // ☰ → lưới mẫu câu
            kb.layoutIfNeeded()
            XCTAssertTrue(kb.debugInTemplates)
            XCTAssertTrue(kb.debugTemplateSegmented, "thanh chọn [Mẫu câu | Công cụ]")
            kb.debugSelectTemplateSegment(0)              // về Mẫu câu (tab nhớ lựa chọn cuối)
            kb.layoutIfNeeded()
            XCTAssertTrue(kb.debugTemplateExtras.isEmpty, "tab Mẫu câu: không còn chip công cụ trong lưới")
            kb.debugSelectTemplateSegment(1)              // Công cụ
            kb.layoutIfNeeded()
            times.append((CACurrentMediaTime() - t0) * 1000)
            XCTAssertTrue(kb.debugTemplateExtras.contains(TextTool.allCases[0].label),
                          "danh sách công cụ phải hiện ngay: \(kb.debugTemplateExtras)")
            XCTAssertEqual(rig.proxy.contextReads, reads0, "mở lưới không được đọc ô nhập")
            kb.debugTapLeftZone()                         // đóng
            kb.layoutIfNeeded()
            XCTAssertFalse(kb.debugInTemplates)
        }
        let p50 = KeyboardBenchTests.pct(times, 0.5)
        print(String(format: "TOOLSOPEN p50=%.1f ms max=%.1f ms", p50, times.max() ?? 0))
        XCTAssertLessThan(p50, 120, "☰ → Công cụ (ms, Debug simulator)")
    }
}
