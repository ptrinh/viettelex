// FeatureRegressionTests — chốt hành vi của batch 24/07/2026: emoji blob,
// settings mới, hợp đồng peek/restore của bridge, cache topWords, và một
// memory-budget test chạy được trên CI (GitHub Actions macOS runner) làm
// regression guard cho RAM của các cấu trúc dữ liệu.
//
// Những phần KHÔNG unit-test được ở đây (cần UIInputViewController + host):
// strip 36/14/0 + chevron/burger hit-area, animation toggle, template plane,
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
        // và một ca restore thật (từ Anh thuần):
        let p2 = MockProxy()
        let b2 = EngineBridge(settings: KeyboardSettings())
        for ch in "loss" { b2.letter(ch, proxy: p2) }
        XCTAssertNotEqual(b2.composedWord, b2.boundary(" ", proxy: p2))
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
    override func tearDown() { try? FileManager.default.removeItem(at: url) }

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
            if FileManager.default.fileExists(atPath: url.path), check(loadedModel()) { return true }
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
        try? FileManager.default.removeItem(at: url)
        m.saveNow()                       // không có gì đổi → không ghi lại
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
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
