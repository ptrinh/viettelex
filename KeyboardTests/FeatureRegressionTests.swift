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
