import XCTest
import UIKit

/// emoji.bin (Scripts/gen-emoji-data.py): dữ liệu đầy đủ / không trùng, lọc glyph,
/// tìm emoji tiếng Việt có/không dấu, kaomoji chèn đúng.
final class EmojiDataTests: XCTestCase {

    // MARK: dữ liệu

    func testCategoriesCompleteAndUnique() {
        let cats = EmojiData.rawCategories
        XCTAssertEqual(cats.map(\.name),
                       ["smileys", "animals", "food", "activity", "travel", "objects", "symbols", "flags"])
        // id liền nhau, phủ đúng cả bảng
        var next = 0
        for c in cats { XCTAssertEqual(c.start, next); next += c.count }
        XCTAssertEqual(next, EmojiData.count)
        XCTAssertGreaterThan(EmojiData.count, 1800)
        let all = (0..<EmojiData.count).map(EmojiData.emoji)
        XCTAssertEqual(Set(all).count, all.count, "emoji trùng")
        XCTAssertFalse(all.contains { $0.isEmpty || $0.contains(" ") })
        // không chuỗi mang tông da (popup giữ lâu tự sinh)
        XCTAssertFalse(all.contains { $0.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) } })
        // mốc quen + emoji mới (Emoji 16.0 / 17.0) + 🇻🇳 đầu nhóm cờ
        XCTAssertTrue(all.contains("😀"))
        XCTAssertTrue(all.contains("🫩"), "Emoji 16.0: face with bags under eyes")
        XCTAssertTrue(all.contains("🫪"), "Emoji 17.0: distorted face")
        let flags = cats.last!
        XCTAssertEqual(EmojiData.emoji(flags.start), "🇻🇳")
        let versions = (0..<EmojiData.count).map(EmojiData.version)
        XCTAssertEqual(versions.max(), 170)
        XCTAssertEqual(versions.min(), 6)   // E0.6
    }

    // MARK: lọc glyph

    func testGlyphFilter() {
        XCTAssertTrue(EmojiData.canRender("😀"))
        XCTAssertTrue(EmojiData.canRender("🇻🇳"))
        XCTAssertTrue(EmojiData.canRender("👨‍👩‍👧"))
        XCTAssertTrue(EmojiData.canRender("❤️"))
        // codepoint chưa gán / chuỗi ZWJ vô nghĩa → không vẽ được một glyph
        XCTAssertFalse(EmojiData.canRender("\u{1FAFF}"))
        XCTAssertFalse(EmojiData.canRender("🐶\u{200D}🍕"))
        XCTAssertFalse(EmojiData.canRender("a"))
        // Máy test (iOS 26+) vẽ được mọi emoji ≤ 16.0 → lưới giữ đủ những emoji đó.
        for id in 0..<EmojiData.count where EmojiData.version(id) <= 160 && EmojiData.version(id) > 140 {
            XCTAssertTrue(EmojiData.canRender(EmojiData.emoji(id)), "không vẽ được \(EmojiData.emoji(id))")
        }
        let shown = EmojiData.categories.reduce(0) { $0 + $1.ids.count }
        let upTo16 = (0..<EmojiData.count).filter { EmojiData.version($0) <= 160 }.count
        XCTAssertGreaterThanOrEqual(shown, upTo16)
    }

    func testGlyphCheckCost() {
        // Kiểm glyph toàn bộ emoji > 14.0 (đường tệ nhất, iOS 16.0) — phải rẻ.
        let ids = (0..<EmojiData.count).filter { EmojiData.version($0) > 140 }
        let t0 = CFAbsoluteTimeGetCurrent()
        for id in ids { _ = EmojiData.canRender(EmojiData.emoji(id)) }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        XCTAssertLessThan(ms, 250, "kiểm \(ids.count) glyph mất \(ms) ms")
    }

    // MARK: tìm kiếm

    func testFold() {
        XCTAssertEqual(EmojiSearch.fold("Chó"), "cho")
        XCTAssertEqual(EmojiSearch.fold("Đường  cười!"), "duong cuoi")
        XCTAssertEqual(EmojiSearch.fold("cờ: Việt Nam"), "co viet nam")
    }

    func testSearchVietnamese() {
        XCTAssertTrue(EmojiSearch.search("tim").contains("❤️"))
        XCTAssertTrue(EmojiSearch.search("chó").prefix(5).contains("🐶") ||
                      EmojiSearch.search("chó").prefix(5).contains("🐕"))
        XCTAssertTrue(EmojiSearch.search("cười").prefix(10).contains("😂") ||
                      EmojiSearch.search("cười").prefix(10).contains("😀"))
        XCTAssertFalse(EmojiSearch.search("yêu").isEmpty)
        XCTAssertTrue(EmojiSearch.search("việt nam").contains("🇻🇳"))
        // từ ở giữa khoá: "nam" khớp "cờ việt nam"
        XCTAssertTrue(EmojiSearch.search("viet").contains("🇻🇳"))
    }

    func testSearchWithoutDiacritics() {
        // không dấu khớp khoá có dấu
        XCTAssertTrue(Set(EmojiSearch.search("cho")).contains("🐶") || Set(EmojiSearch.search("cho")).contains("🐕"))
        XCTAssertTrue(EmojiSearch.search("cuoi").contains("😂") || EmojiSearch.search("cuoi").contains("😀"))
        // tiền tố
        XCTAssertFalse(EmojiSearch.search("cu").isEmpty)
        // có dấu xếp khoá đúng dấu lên trước: "chó" → 🐶/🐕 trước emoji của "cho"/"chờ"
        let exact = EmojiSearch.search("chó")
        let first = exact.firstIndex { $0 == "🐶" || $0 == "🐕" }
        XCTAssertNotNil(first)
        XCTAssertLessThan(first!, 3)
        XCTAssertTrue(EmojiSearch.search("").isEmpty)
        XCTAssertTrue(EmojiSearch.search("  ").isEmpty)
        XCTAssertTrue(EmojiSearch.search("zzqxj").isEmpty)
    }

    func testEmoticonSearch() {
        let want: [(String, String)] = [(":)", "😊"), (":D", "😄"), (":(", "☹️"), (";)", "😉"), (":P", "😛"),
            ("<3", "❤️"), ("=))", "😂"), (":))", "😆"), ("^_^", "😊"), ("-_-", "😑"), (":o", "😮"),
            ("xD", "😆"), (":'(", "😢")]
        for (q, e) in want { XCTAssertEqual(EmojiSearch.search(q).first, e, q) }
        // hoa thường / space hai đầu như nhau; không trùng
        XCTAssertEqual(EmojiSearch.search(":p"), EmojiSearch.search(" :P "))
        XCTAssertEqual(EmojiSearch.search("XD").first, "😆")
        let r = EmojiSearch.search("xd")
        XCTAssertEqual(Set(r).count, r.count)
        XCTAssertEqual(EmojiSearch.search(":)", limit: 2).count, 2)
        // mọi emoji trong bảng có trong emoji.bin (đúng dạng, kể cả FE0F)
        let all = Set((0..<EmojiData.count).map(EmojiData.emoji))
        for (k, v) in EmojiSearch.emoticons {
            XCTAssertEqual(k.lowercased(), k, "khoá viết thường")
            for e in v { XCTAssertTrue(all.contains(e), "\(k) → \(e)") }
        }
        // câu tìm thường không đổi
        XCTAssertEqual(EmojiSearch.search("tim"), EmojiSearch.ids("tim").map(EmojiData.emoji))
        XCTAssertTrue(EmojiSearch.emoticon("tim").isEmpty)
        // gõ emoticon qua ô tìm (Telex) ra đúng khoá
        for q in [":D", "xD", ":o", ":P", "^_^", ":'("] {
            var s = EmojiSearchSession()
            for c in q { s.type(c) }
            XCTAssertFalse(EmojiSearch.emoticon(s.query).isEmpty, "\(q) → \(s.query)")
        }
    }

    func testSearchResultsUniqueAndFiltered() {
        let r = EmojiSearch.search("mặt", limit: 200)
        XCTAssertEqual(Set(r).count, r.count)
        XCTAssertLessThanOrEqual(r.count, 200)
        // bộ lọc glyph áp cho kết quả
        let ids = EmojiSearch.ids("tim", supported: { _ in false })
        XCTAssertTrue(ids.isEmpty)
    }

    func testSearchSpeed() {
        let t0 = CFAbsoluteTimeGetCurrent()
        for q in ["t", "ti", "tim", "c", "cu", "cuo", "cuoi", "cười", "chó", "việt nam"] {
            _ = EmojiSearch.search(q)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000 / 10
        XCTAssertLessThan(ms, 30, "tìm trung bình \(ms) ms/phím")
    }

    // MARK: ô tìm có Telex

    func testSearchSessionTelex() {
        var s = EmojiSearchSession()
        for c in "chos" { s.type(c) }
        XCTAssertEqual(s.query, "chó")
        s.backspace()
        XCTAssertEqual(s.query, "ch")   // ⌫ xoá cả "ó" như ô nhập thật
        s.clear()
        for c in "cuwowif" { s.type(c) }
        XCTAssertEqual(s.query, "cười")
        s.space()
        for c in "Vui" { s.type(c) }
        XCTAssertEqual(s.query, "cười vui")
        for _ in 0..<20 { s.backspace() }
        XCTAssertEqual(s.query, "")
    }

    func testKeyboardViewSearchModeRoutesKeysToSearch() {
        var sent: [KeyboardView.Key] = []
        let kv = KeyboardView(needsGlobe: false, inputController: nil) { sent.append($0) }
        kv.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
        kv.layoutIfNeeded()
        let r = kv.debugEmojiSearch([.letter("c"), .letter("h"), .letter("o"), .letter("s")])
        XCTAssertEqual(r.query, "chó")
        XCTAssertTrue(r.results.contains("🐶") || r.results.contains("🐕"))
        XCTAssertTrue(sent.isEmpty, "phím trong ô tìm không được tới ô nhập")
        XCTAssertTrue(kv.debugInEmojiSearch)
        _ = kv.debugEmojiSearch([.newline])   // return → về lưới emoji
        XCTAssertFalse(kv.debugInEmojiSearch)
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: kaomoji

    func testKaomojiData() {
        let g = EmojiData.kaomoji
        XCTAssertEqual(g.map(\.name), ["vui", "buồn", "yêu", "động vật", "ký hiệu"])
        for grp in g {
            XCTAssertGreaterThanOrEqual(grp.items.count, 10)
            XCTAssertEqual(Set(grp.items).count, grp.items.count, "trùng trong \(grp.name)")
            XCTAssertFalse(grp.items.contains { $0.isEmpty })
        }
        let sym = g.last!.items
        XCTAssertTrue(sym.contains("₫"))
        XCTAssertTrue(sym.contains("→"))
        XCTAssertTrue(sym.contains("“”"))
        XCTAssertTrue(g[0].items.contains("¯\\_(ツ)_/¯"))
        XCTAssertTrue(g[0].items.contains("( ͡° ͜ʖ ͡°)"), "kaomoji có space giữ nguyên")
        // ký hiệu Unicode cũng là emoji (♥ ☀) mang FE0E để hiện dạng chữ
        XCTAssertTrue(sym.contains("♥\u{FE0E}"))
        XCTAssertTrue(sym.contains("★"))
    }

    func testKaomojiTapInsertsExactText() {
        let v = EmojiPlane.KaomojiView(groups: EmojiData.kaomoji, dark: false)
        v.frame = CGRect(x: 0, y: 0, width: 390, height: 200)
        v.layoutIfNeeded()
        var got: [String] = []
        v.onPick = { got.append($0) }
        let all = EmojiData.kaomoji.flatMap(\.items)
        XCTAssertEqual(v.chips.map(\.text), all)
        for (b, _) in v.chips.prefix(40) { b.sendActions(for: .touchUpInside) }
        XCTAssertEqual(got, Array(all.prefix(40)))
        // mọi chip nằm trong bề ngang (dàn dòng đúng)
        for (b, _) in v.chips { XCTAssertLessThanOrEqual(b.frame.maxX, 390 - 8 + 0.5) }
    }
}
