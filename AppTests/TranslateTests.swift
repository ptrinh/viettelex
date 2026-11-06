// TranslateTests — Công cụ → Dịch (macOS 26+, TranslateAction.swift): phần THUẦN dùng
// chung iOS (Translate.swift + TranslatePrefs.swift) — luật chiều dịch, nhận ra ngôn ngữ,
// giữ khoảng trắng, ngôn ngữ đích — cùng ca với iOS/KeyboardTests/TranslateTests.swift,
// + phía macOS: đồng bộ iCloud của đích, nhãn tiếng Việt. Bản dịch thật (Apple Translation,
// gói ngôn ngữ) không chạy trong test — kiểm tay.
import XCTest
@testable import VietTelex

final class TranslateTests: XCTestCase {
    private typealias Pair = TranslateDirection.Pair

    // MARK: chiều dịch

    func testDefaultTargetEnglish() {
        XCTAssertEqual(TranslateDirection.resolve(detected: "vi", target: "en"), Pair(source: "vi", target: "en"))
        // Chữ đã là tiếng Anh ⇒ về tiếng Việt (khứ hồi bằng cùng một nút).
        XCTAssertEqual(TranslateDirection.resolve(detected: "en", target: "en"), Pair(source: "en", target: "vi"))
    }

    func testNonEnglishTargetJapanese() {
        XCTAssertEqual(TranslateDirection.resolve(detected: "vi", target: "ja"), Pair(source: "vi", target: "ja"))
        XCTAssertEqual(TranslateDirection.resolve(detected: "ja", target: "ja"), Pair(source: "ja", target: "vi"))
        // Ngôn ngữ thứ ba vẫn dịch SANG đích đã chọn.
        XCTAssertEqual(TranslateDirection.resolve(detected: "en", target: "ja"), Pair(source: "en", target: "ja"))
    }

    func testRegionalTargetComparesBaseLanguage() {
        // Đích zh-TW, chữ nhận ra là zh ⇒ đã là đích ⇒ dịch về tiếng Việt, nguồn dùng mã đích.
        XCTAssertEqual(TranslateDirection.resolve(detected: "zh", target: "zh-TW"), Pair(source: "zh-TW", target: "vi"))
        XCTAssertEqual(TranslateDirection.resolve(detected: "en", target: "en-GB"), Pair(source: "en-GB", target: "vi"))
        XCTAssertEqual(TranslateDirection.resolve(detected: "vi", target: "pt-PT"), Pair(source: "vi", target: "pt-PT"))
    }

    func testUnknownLanguageOrBadTarget() {
        XCTAssertNil(TranslateDirection.resolve(detected: nil, target: "en"))
        XCTAssertNil(TranslateDirection.resolve(detected: "", target: "ja"))
        // Đích lưu sai thành tiếng Việt ⇒ coi như mặc định (tiếng Anh).
        XCTAssertEqual(TranslateDirection.resolve(detected: "vi", target: "vi"), Pair(source: "vi", target: "en"))
    }

    // MARK: nhận ra ngôn ngữ

    func testLooksVietnamese() {
        XCTAssertTrue(TranslateText.looksVietnamese("Hôm nay trời đẹp quá", target: "ja"))
        XCTAssertTrue(TranslateText.looksVietnamese("Cảm ơn bạn nhiều", target: "fr"))
        XCTAssertTrue(TranslateText.looksVietnamese("ok, gặp lại sau nhé", target: "en"))
        // NFD (ô tổ hợp) cũng nhận.
        XCTAssertTrue(TranslateText.looksVietnamese("Hôm nay trời đẹp".decomposedStringWithCanonicalMapping, target: "ja"))
        // Đích tiếng Anh: nguyên âm Latin-1 có dấu cũng tính (tiếng Anh không có) — kể cả chữ hoa.
        XCTAssertTrue(TranslateText.looksVietnamese("BÉ ăn cơm", target: "en"))
        XCTAssertTrue(TranslateText.looksVietnamese("Cô ấy", target: "en"))
        // Đích Latin khác: sắc/huyền/mũ một mình là của tiếng Pháp/Bồ… — không tính.
        XCTAssertFalse(TranslateText.looksVietnamese("Café au lait très bon", target: "fr"))
        XCTAssertFalse(TranslateText.looksVietnamese("São Paulo é grande", target: "pt"))
        XCTAssertFalse(TranslateText.looksVietnamese("Good morning", target: "en"))
        XCTAssertFalse(TranslateText.looksVietnamese("123 !!", target: "en"))
    }

    func testDetectWithoutNaturalLanguage() {
        // Tiếng Việt ⇒ "vi"; chữ thuộc hệ chữ của đích ⇒ chính đích (khứ hồi).
        XCTAssertEqual(TranslateText.detect("Hôm nay trời đẹp quá", target: "en"), "vi")
        XCTAssertEqual(TranslateText.detect("The weather is really nice today, isn't it?", target: "en"), "en")
        XCTAssertEqual(TranslateText.detect("今日はとてもいい天気ですね", target: "ja"), "ja")
        XCTAssertEqual(TranslateText.detect("今天天气很好", target: "zh-TW"), "zh-TW")
        XCTAssertEqual(TranslateText.detect("Привет, как дела?", target: "ru"), "ru")
        XCTAssertEqual(TranslateText.detect("안녕하세요", target: "ko"), "ko")
        XCTAssertEqual(TranslateText.detect("สวัสดีครับ", target: "th"), "th")
        XCTAssertEqual(TranslateText.detect("Bonjour, ça va ?", target: "fr"), "fr")
        // Có kana ⇒ tiếng Nhật, không phải tiếng Trung ⇒ không coi là đích zh.
        XCTAssertEqual(TranslateText.detect("今日はいい天気", target: "zh"), "vi")
        // Không dấu, hệ chữ khác đích ⇒ coi là tiếng Việt (giới hạn đã biết: tiếng Anh khi đích ja).
        XCTAssertEqual(TranslateText.detect("hom nay troi dep", target: "ja"), "vi")
        XCTAssertNil(TranslateText.detect("123 456", target: "en"))
        XCTAssertNil(TranslateText.detect("  ", target: "ja"))
        // Đi qua luật chiều dịch.
        XCTAssertEqual(TranslateDirection.resolve(detected: TranslateText.detect("今日は", target: "ja"), target: "ja"),
                       .init(source: "ja", target: "vi"))
        XCTAssertEqual(TranslateDirection.resolve(detected: TranslateText.detect("chào bạn", target: "ja"), target: "ja"),
                       .init(source: "vi", target: "ja"))
    }

    // MARK: khoảng trắng

    func testRewrapKeepsOriginalWhitespace() {
        XCTAssertEqual(TranslateText.rewrap(original: "xin chào ", translated: "hello"), "hello ")
        XCTAssertEqual(TranslateText.rewrap(original: "  xin chào\u{00A0}", translated: " Hello\n"), "  Hello\u{00A0}")
        XCTAssertEqual(TranslateText.splitWhitespace("   ").core, "")
        XCTAssertEqual(TranslateText.splitWhitespace(" a b ").core, "a b")
    }

    // MARK: cài đặt đích

    func testTargetPrefs() {
        let d = UserDefaults(suiteName: "TranslateTests")!
        d.removePersistentDomain(forName: "TranslateTests")
        XCTAssertEqual(TranslatePrefs.target(d), "en")
        TranslatePrefs.setTarget("ja", d)
        XCTAssertEqual(TranslatePrefs.target(d), "ja")
        TranslatePrefs.setTarget("vi-VN", d)
        XCTAssertEqual(TranslatePrefs.target(d), "en")
        XCTAssertEqual(TranslatePrefs.target(nil), "en")
        XCTAssertFalse(TranslatePrefs.knownTargets.contains { TranslatePrefs.base($0) == "vi" })
        XCTAssertTrue(TranslatePrefs.knownTargets.contains("ja"))
    }

    func testPickerTargetsExcludeVietnameseDedupedSorted() {
        let ids = TranslatePrefs.pickerTargets(["ja", "vi", "en", "ja", "fr"], uiLanguage: "en")
        XCTAssertEqual(ids, ["en", "fr", "ja"])   // English, French, Japanese
        XCTAssertEqual(TranslatePrefs.displayName("ja", uiLanguage: "vi"), "Tiếng Nhật")
        XCTAssertEqual(TranslatePrefs.displayName("ja", uiLanguage: "en"), "Japanese")
    }

    func testAppStateTargetRoundTrip() {
        let saved = AppState.shared.defaults.object(forKey: TranslatePrefs.targetKey)
        defer { AppState.shared.defaults.set(saved, forKey: TranslatePrefs.targetKey) }
        AppState.shared.defaults.removeObject(forKey: TranslatePrefs.targetKey)
        XCTAssertEqual(AppState.shared.translateTarget, "en")
        AppState.shared.translateTarget = "ko"
        XCTAssertEqual(AppState.shared.defaults.string(forKey: TranslatePrefs.targetKey), "ko")
        AppState.shared.translateTarget = "vi"
        XCTAssertEqual(AppState.shared.translateTarget, "en")
    }

    // MARK: macOS

    func testOSGate() {
        if #available(macOS 26.0, *) {
            XCTAssertTrue(TranslateText.isSupportedOS)
        } else {
            XCTAssertFalse(TranslateText.isSupportedOS)
        }
        XCTAssertEqual(TextToolsPanelLogic.tools.contains(.translate), TranslateText.isSupportedOS)
    }

    func testStringsHaveVietnamese() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        for k in ["Translate", "Translate ↔ %@", "Translating…", "Translate to", "Vietnamese ↔ %@", "Download",
                  "Downloaded", "Not downloaded", "Not supported on this Mac",
                  "Couldn’t download the translation pack — try again later.",
                  "Translation pack not downloaded — open VietTelex Settings → Suggestions & tools.",
                  "This Mac can’t translate this language pair.",
                  ToolsTab.C.translate] {
            XCTAssertNotEqual(vi.localizedString(forKey: k, value: "∅", table: nil), "∅", k)
        }
        XCTAssertEqual(String(format: vi.localizedString(forKey: "Translate ↔ %@", value: nil, table: nil),
                              TranslatePrefs.displayName("en", uiLanguage: "vi")), "Dịch ↔ Tiếng Anh")
    }

    // MARK: nhiều đoạn (góp ý tester 15/10/2026) — dịch từng dòng trong một lô

    func testBatchSeparatorMatchesEngine() {
        XCTAssertEqual(TranslateText.batchSeparator, TranslateEngine.batchSeparator)
    }

    func testMultiParagraphTranslatedPerLineKeepingBreaks() async {
        var calls = 0
        let r = await TranslateText.translateLines("Xin chào\n\nTạm biệt\n") { packed in
            calls += 1
            let parts = packed.split(separator: TranslateText.batchSeparator, omittingEmptySubsequences: false)
            return .success(parts.map { "[\($0)]" }.joined(separator: String(TranslateText.batchSeparator)))
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try r.get(), "[Xin chào]\n\n[Tạm biệt]\n")
    }
}
