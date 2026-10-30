import XCTest
import TelexCore
@testable import VietTelex

/// macOS › Bàn phím › Nhập văn bản: "Thêm dấu chấm khi nhấn đúp phím cách", "Tự động viết
/// hoa từ", "Sử dụng dấu ngoặc kép và dấu gạch thông minh" không chạy khi VietTelex là
/// input source (Phil kiểm chứng trên TextEdit 16/10/2026) — input method phải tự làm.
/// Phần quyết định thuần: SystemAutoText.swift.
final class SystemAutoTextTests: XCTestCase {
    typealias S = SystemAutoText
    private let ms: UInt64 = 1_000_000

    // MARK: Cài đặt

    func testSettingsAbsentMeansOnAndExplicitValuesHonored() {
        let none = S.settings(read: { _ in nil }, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(none, S.Settings(period: true, capitalize: true, quotes: true, dashes: true, quoteChars: .us))
        let vals: [String: Any] = [S.periodKey: NSNumber(value: false), S.capitalizeKey: NSNumber(value: true),
                                   S.quoteKey: NSNumber(value: 0), S.dashKey: NSNumber(value: 1)]
        let s = S.settings(read: { vals[$0] })
        XCTAssertFalse(s.period); XCTAssertTrue(s.capitalize); XCTAssertFalse(s.quotes); XCTAssertTrue(s.dashes)
        XCTAssertTrue(s.any)
        XCTAssertFalse(S.Settings().any)          // tất cả tắt ⇒ đường phím không làm gì
    }

    func testQuotesArrayParsedLikeDefaultsRead() {
        // Đúng dạng `defaults read -g NSUserQuotesArray` (macOS 27).
        XCTAssertEqual(S.parseQuotes(["“", "”", "‘", "’"]), .us)
        XCTAssertEqual(S.parseQuotes(["«", "»", "‹", "›"]),
                       S.Quotes(openDouble: "«", closeDouble: "»", openSingle: "‹", closeSingle: "›"))
        XCTAssertNil(S.parseQuotes(["“", "”"]))
        XCTAssertNil(S.parseQuotes(nil))
        let fr = S.settings(read: { $0 == S.quotesArrayKey ? ["„", "“", "‚", "‘"] : nil })
        XCTAssertEqual(fr.quoteChars.openDouble, "„")
    }

    func testExcludedApps() {
        XCTAssertFalse(S.appAllowed("com.apple.Terminal"))
        XCTAssertFalse(S.appAllowed("com.googlecode.iterm2"))
        XCTAssertFalse(S.appAllowed("com.microsoft.VSCode"))
        XCTAssertFalse(S.appAllowed("com.apple.dt.Xcode"))
        XCTAssertFalse(S.appAllowed("com.jetbrains.intellij"))
        XCTAssertFalse(S.appAllowed("com.apple.Spotlight"))
        XCTAssertFalse(S.appAllowed(nil))
        XCTAssertTrue(S.appAllowed("com.apple.TextEdit"))
        XCTAssertTrue(S.appAllowed("com.tinyspeck.slackmacgap"))
    }

    // MARK: Dấu chấm khi nhấn đúp phím cách

    func testDoubleSpaceAfterWordMakesPeriod() {
        XCTAssertEqual(S.doubleSpacePeriod(before: "xin chào ", gapNs: 200 * ms, isRepeat: false), "o")
        XCTAssertEqual(S.doubleSpacePeriod(before: "việt ", gapNs: 200 * ms, isRepeat: false), "t")
        XCTAssertEqual(S.doubleSpacePeriod(before: "năm 2026 ", gapNs: 200 * ms, isRepeat: false), "6")
        XCTAssertEqual(S.doubleSpacePeriod(before: "(xem trên) ", gapNs: 200 * ms, isRepeat: false), ")")
        XCTAssertEqual(S.doubleSpacePeriod(before: "“hay” ", gapNs: 200 * ms, isRepeat: false), "”")
    }

    func testDoubleSpaceNotAfterPunctuationOrSpaceOrStart() {
        for b in ["hết. ", "hết, ", "hết! ", "hết? ", "hết: ", "hết; ", "a - ", "hết.  ", " ", ""] {
            XCTAssertNil(S.doubleSpacePeriod(before: b, gapNs: 100 * ms, isRepeat: false), b)
        }
        XCTAssertNil(S.doubleSpacePeriod(before: "chào", gapNs: 100 * ms, isRepeat: false)) // không có dấu cách đầu
    }

    func testDoubleSpaceTimingAndAutorepeat() {
        XCTAssertNotNil(S.doubleSpacePeriod(before: "a ", gapNs: S.doubleSpaceWindowNs, isRepeat: false))
        XCTAssertNil(S.doubleSpacePeriod(before: "a ", gapNs: S.doubleSpaceWindowNs + 1, isRepeat: false))
        XCTAssertNil(S.doubleSpacePeriod(before: "a ", gapNs: 30 * ms, isRepeat: true))   // giữ phím cách
        XCTAssertEqual(S.doubleSpaceWindowNs, 1_100 * ms)
    }

    /// Dòng phím sau khi thay: "chào. " — dấu cách thứ ba không thêm dấu chấm nữa.
    func testTailAfterReplacementDoesNotRetrigger() {
        var t = ShortcutTail()
        t.append("chào "); t.replaceSuffix(" ", with: ". ")
        XCTAssertEqual(t.recent, "chào. ")
        XCTAssertNil(S.doubleSpacePeriod(before: t.recent + " ", gapNs: 100 * ms, isRepeat: false))
    }

    // MARK: Ngoặc kép cong

    func testSmartQuotesOpenAndClose() {
        let q = S.Quotes.us
        XCTAssertEqual(S.smartQuote("\"", prev: nil, quotes: q), "“")       // đầu văn bản
        XCTAssertEqual(S.smartQuote("\"", prev: " ", quotes: q), "“")
        XCTAssertEqual(S.smartQuote("\"", prev: "(", quotes: q), "“")
        XCTAssertEqual(S.smartQuote("\"", prev: "\n", quotes: q), "“")
        XCTAssertEqual(S.smartQuote("\"", prev: "o", quotes: q), "”")
        XCTAssertEqual(S.smartQuote("\"", prev: ".", quotes: q), "”")
        XCTAssertEqual(S.smartQuote("'", prev: "n", quotes: q), "’")        // don't → don’t
        XCTAssertEqual(S.smartQuote("'", prev: " ", quotes: q), "‘")
        XCTAssertEqual(S.smartQuote("'", prev: "“", quotes: q), "‘")        // “‘lồng’”
        XCTAssertEqual(S.smartQuote("\"", prev: "‘", quotes: q), "“")
        XCTAssertNil(S.smartQuote("-", prev: " ", quotes: q))
        let guillemets = S.Quotes(openDouble: "«", closeDouble: "»", openSingle: "‹", closeSingle: "›")
        XCTAssertEqual(S.smartQuote("\"", prev: " ", quotes: guillemets), "«")
        XCTAssertEqual(S.smartQuote("\"", prev: "a", quotes: guillemets), "»")
    }

    /// " và ' không bao giờ là phím của từ (Telex/VNI/phím ngoặc) — đổi chúng không thể
    /// làm hỏng việc ghép chữ.
    func testQuoteKeysAreNeverWordKeys() {
        for vni in [false, true] {
            for bracket in [false, true] {
                XCTAssertFalse(isWordKey(UInt8(ascii: "\""), vniMode: vni, bracketVowels: bracket))
                XCTAssertFalse(isWordKey(UInt8(ascii: "'"), vniMode: vni, bracketVowels: bracket))
                XCTAssertFalse(isWordKey(UInt8(ascii: "-"), vniMode: vni, bracketVowels: bracket))
            }
        }
    }

    // MARK: Gạch dài

    func testDoubleHyphenBecomesEmDash() {
        XCTAssertEqual(S.dash(before: "a-", lastWasOurEmDash: false), .emDash)
        XCTAssertEqual(S.dash(before: "a -", lastWasOurEmDash: false), .emDash)
        XCTAssertEqual(S.dash(before: "-", lastWasOurEmDash: false), .emDash)
        XCTAssertEqual(S.dash(before: "a", lastWasOurEmDash: false), .none)
        XCTAssertEqual(S.dash(before: "a--", lastWasOurEmDash: false), .none)    // đã ≥ 3 gạch
        XCTAssertEqual(S.dash(before: "<!-", lastWasOurEmDash: false), .none)    // chú thích HTML
        XCTAssertEqual(S.dash(before: "a—", lastWasOurEmDash: true), .restore)   // "---" giữ nguyên văn
        XCTAssertEqual(S.dash(before: "a—", lastWasOurEmDash: false), .none)     // "—" có sẵn + "-"
    }

    // MARK: Viết hoa đầu câu

    func testCapitalizeAtSentenceStart() {
        XCTAssertEqual(S.capitalization(before: "Xong rồi. ", atTextStart: false), .capitalize)
        XCTAssertEqual(S.capitalization(before: "Thật sao? ", atTextStart: false), .capitalize)
        XCTAssertEqual(S.capitalization(before: "Hay quá! ", atTextStart: false), .capitalize)
        XCTAssertEqual(S.capitalization(before: "Anh nói “đi thôi.” ", atTextStart: false), .capitalize)
        XCTAssertEqual(S.capitalization(before: "dòng một\n", atTextStart: false), .capitalize)
        XCTAssertEqual(S.capitalization(before: "dòng một\n  ", atTextStart: false), .capitalize)
        XCTAssertEqual(S.capitalization(before: nil, atTextStart: true), .capitalize)
        XCTAssertEqual(S.capitalization(before: "1. ", atTextStart: false), .capitalize)
    }

    func testNoCapitalizeMidSentenceAbbreviationsUrls() {
        XCTAssertEqual(S.capitalization(before: "xin ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "xin, ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "xin", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "e.g. ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "Mr. ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "x etc. ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "ở TP. ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "gửi a@b.vn. ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "xem viettelex.com. ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "J. ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "thế... ", atTextStart: false), .keep)
    }

    func testUnknownContextIsNotCapitalized() {
        XCTAssertEqual(S.capitalization(before: nil, atTextStart: false), .unknown)
        XCTAssertEqual(S.capitalization(before: "", atTextStart: false), .unknown)
        XCTAssertEqual(S.capitalization(before: "  ", atTextStart: false), .unknown)
    }

    /// Discord: "@Tuấn" + Enter chọn mention (không chèn "\n") + "sao" từng ra "Sao" vì
    /// dòng phím tin "\n" của phím Return. Return ⇒ ngữ cảnh không biết ⇒ đọc màn hình.
    func testReturnKeyIsNotAKnownNewlineForAutoCap() {
        var tail = ShortcutTail()
        tail.append("hỏi @Tuấn")
        tail.appendReturn()
        XCTAssertEqual(tail.recent, "hỏi @Tuấn\n")          // gõ tắt / dấu chấm đúp vẫn thấy "\n"
        XCTAssertNil(tail.autoCapKnownText)
        // Khoảng trắng gõ sau Return vẫn chưa xác nhận.
        tail.append(" ")
        XCTAssertNil(tail.autoCapKnownText)
        // Chữ thật sau đó: dòng phím lại đáng tin.
        tail.append("sao ")
        XCTAssertEqual(tail.autoCapKnownText, "hỏi @Tuấn\n sao ")
        // "\n" do mình chèn (gõ tắt nhiều dòng) vẫn là xuống dòng thật.
        var t2 = ShortcutTail()
        t2.append("dòng một\n")
        XCTAssertEqual(t2.autoCapKnownText, "dòng một\n")
        t2.appendReturn()
        t2.reset()
        XCTAssertFalse(t2.returnUnverified)
        XCTAssertEqual(S.autoCapKnownText(recent: "", returnUnverified: false), nil)
    }

    func testResolveCapitalizationAfterReturn() {
        func resolve(_ screen: String?, caret: Int?, multiline: Bool = true) -> S.CapContext {
            var tail = ShortcutTail()
            tail.append("hỏi @Tuấn")
            tail.appendReturn()
            return S.resolveCapitalization(
                known: tail.autoCapKnownText, caret: caret,
                readBefore: { n in screen.map { String($0.suffix(n)) } },
                multiline: { multiline })
        }
        // Enter chọn mention: AX thấy pill + dấu cách ⇒ giữ nguyên.
        XCTAssertEqual(resolve("hỏi @Tuấn - Tech Lead ", caret: 22), .keep)
        // Chromium trả U+FFFC cho pill.
        XCTAssertEqual(resolve("hỏi \u{FFFC} ", caret: 6), .keep)
        XCTAssertEqual(S.capitalization(before: "\u{FFFC} ", atTextStart: false), .keep)
        XCTAssertEqual(S.capitalization(before: "\u{FFFC}", atTextStart: false), .keep)
        // Xuống dòng thật (TextEdit/Notes): AX thấy "\n" ⇒ viết hoa.
        XCTAssertEqual(resolve("hỏi @Tuấn\n", caret: 10), .capitalize)
        // Gửi tin xong ô trống: caret 0 ⇒ luật đầu văn bản nhiều dòng như cũ.
        XCTAssertEqual(resolve(nil, caret: 0, multiline: true), .capitalize)
        XCTAssertEqual(resolve(nil, caret: 0, multiline: false), .unknown)
        // AX mù (không đọc được caret / chữ) ⇒ không viết hoa.
        XCTAssertEqual(resolve(nil, caret: nil), .unknown)
        XCTAssertEqual(resolve(nil, caret: 12), .unknown)
        // Ngữ cảnh dòng phím biết chắc thì không đọc màn hình.
        var read = false
        XCTAssertEqual(S.resolveCapitalization(known: "Xong. ", caret: 6,
                                               readBefore: { _ in read = true; return nil },
                                               multiline: { true }), .capitalize)
        XCTAssertFalse(read)
    }

    func testCapitalizedOnlyAsciiLowercase() {
        XCTAssertEqual(S.capitalized("d"), "D")
        XCTAssertEqual(S.capitalized("D"), "D")
        XCTAssertEqual(S.capitalized("1"), "1")
        XCTAssertEqual(S.capitalized("["), "[")
    }

    /// Viết hoa bằng chữ ĐƯA VÀO ENGINE, Telex vẫn ghép đúng: "dduwowcj" đầu câu → "Được".
    func testCapitalizedFirstKeyStillComposesTelex() {
        func compose(_ keys: String, capFirst: Bool) -> String {
            var e = TelexEngine()
            for (i, c) in keys.enumerated() { _ = e.feed(i == 0 && capFirst ? S.capitalized(c) : c) }
            return e.composed
        }
        XCTAssertEqual(compose("dduwowcj", capFirst: true), "Được")
        XCTAssertEqual(compose("dduwowcj", capFirst: false), "được")
        XCTAssertEqual(compose("vieejt", capFirst: true), "Việt")
    }

    /// Hồi quy (Phil 16/10/2026): chữ đầu tiên của văn bản không tự viết hoa — bản cũ chỉ
    /// viết hoa khi vai trò AX đúng là AXTextArea (đọc không được ⇒ không viết hoa).
    func testCapitalizeAtTextStartUnlessKnownSingleLine() {
        XCTAssertTrue(FocusedRole.capitalizesAtStart(role: nil))
        XCTAssertTrue(FocusedRole.capitalizesAtStart(role: "AXTextArea"))
        XCTAssertTrue(FocusedRole.capitalizesAtStart(role: "AXWebArea"))
        XCTAssertTrue(FocusedRole.capitalizesAtStart(role: "AXGroup"))
        XCTAssertFalse(FocusedRole.capitalizesAtStart(role: "AXTextField"))
        XCTAssertFalse(FocusedRole.capitalizesAtStart(role: "AXSearchField"))
        XCTAssertFalse(FocusedRole.capitalizesAtStart(role: "AXComboBox"))
    }

    /// Hồi quy (Phil 17/10/2026): ô tìm/thay thế ⌘F của Notes bị viết hoa — đọc AX trong lượt
    /// phím hết giờ (-25204) ⇒ coi là ô soạn thảo. Nay dùng vai trò đọc lúc kích hoạt ô.
    func testTextStartUsesRoleCachedAtActivation() {
        defer { FocusedRole._testSetCachedRole(nil) }
        FocusedRole._testSetCachedRole("AXTextField")
        XCTAssertFalse(FocusedRole.isMultilineText())
        FocusedRole._testSetCachedRole("AXTextArea")
        XCTAssertTrue(FocusedRole.isMultilineText())
        FocusedRole._testSetCachedRole("")            // đọc không được ⇒ như ô soạn thảo
        XCTAssertTrue(FocusedRole.isMultilineText())
    }
}
