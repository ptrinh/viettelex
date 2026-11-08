// Theme JSON tương tác: "particles" (hạt tự tạo — hiệu ứng "Theo giao diện") + "keywords" (từ khoá tự tạo). Đọc / kiểm / kẹp
// nằm ở fixture chung theme-json-cases.txt (ThemeJSONTests chạy); ở đây: số phát hạt CHUNG Android (ThemeFxTests.kt),
// bảng từ khoá, trần pool, gốc lệch (#151), khứ hồi "Chép JSON" / kho / sao lưu, 0 chi phí khi không có, fuzz.
import XCTest
import UIKit

final class ThemeFxTests: XCTestCase {
    private let base = ##"{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"##
    private func spec(_ extra: String) -> ThemeSpec? { ThemeSpecParser.parse(base + "," + extra + "}").spec }

    private static let noodles = #""effect":"theme","particles":{"glyphs":["🍜","🥢"],"count":6,"spread":360,"speed":90,"gravity":260,"lifeMs":1400,"size":22,"sizeJitter":30,"spin":120}"#
    private static let hearts = #""keywords":[{"words":["yêu","love","năm mới"],"burst":{"glyphs":["❤️","💖"],"count":10,"spread":360,"speed":130,"gravity":-60},"text":"Yêu ❤️"},{"words":["phở","yêu"]}]"#

    // MARK: số phát hạt — CHUNG Android (FxRandom cùng chuỗi)

    func testSharedEmissionNumbers() {
        let p0 = ThemeParticles.fallback.particle(0, seed: 1)
        XCTAssertEqual(p0.vx, -95.516210961, accuracy: 1e-6)
        XCTAssertEqual(p0.vy, -67.493628301, accuracy: 1e-6)
        XCTAssertEqual(p0.size, 12.479176013, accuracy: 1e-6)
        let p4 = ThemeParticles.fallback.particle(4, seed: 3)
        XCTAssertEqual(p4.vx, 105.642016591, accuracy: 1e-6)
        XCTAssertEqual(p4.vy, -56.722040466, accuracy: 1e-6)
        XCTAssertEqual(p4.size, 13.783712520, accuracy: 1e-6)
        XCTAssertEqual(p4.life, 0.8, accuracy: 1e-12)
        XCTAssertEqual(p4.rotation, Double.pi * 0.8, accuracy: 1e-9, "180°/s × 0,8 s")
    }

    func testEmissionDirectionAndPhysics() {
        // Một hạt, không xoè: đúng hướng. 0 = lên, 90 = phải, 180 = xuống.
        for (dir, sx, sy) in [(0, 0.0, -1.0), (90, 1.0, 0.0), (180, 0.0, 1.0), (-90, -1.0, 0.0)] {
            let p = ThemeParticles(count: 1, spread: 0, direction: dir, speed: 100).particle(0, seed: 7)
            let sp = hypot(p.vx, p.vy)
            XCTAssertEqual(p.vx / sp, sx, accuracy: 1e-9, "\(dir)")
            XCTAssertEqual(p.vy / sp, sy, accuracy: 1e-9, "\(dir)")
            XCTAssertTrue((80...120).contains(sp), "tốc độ ±20%")
        }
        // Trọng lực: dương kéo xuống (y tăng theo t²).
        let g = ThemeParticle(vx: 0, vy: 0, gravity: 200, life: 1, size: 10, rotation: 0, fadeIn: false, colorIndex: 0, glyphIndex: 0)
        XCTAssertEqual(g.offset(0.5).y, 25, accuracy: 1e-9)
        XCTAssertEqual(g.offset(5).y, 100, accuracy: 1e-9, "kẹp ở cuối đời")
        // Mờ: "out" rõ tới nửa đời; "inOut" hiện dần; hết đời = 0.
        XCTAssertEqual(g.alpha(0.2), 1); XCTAssertEqual(g.alpha(0.75), 0.5, accuracy: 1e-9); XCTAssertEqual(g.alpha(1), 0)
        var fi = g; fi.fadeIn = true
        XCTAssertEqual(fi.alpha(0), 0); XCTAssertEqual(fi.alpha(0.075), 0.5, accuracy: 1e-9)
    }

    /// Mọi tổ hợp biên: số hữu hạn, cỡ trong khoảng, màu / hình theo vòng, ≤ 12 hạt.
    func testEmissionBoundedForExtremeSpecs() {
        var r = FxRandom(seed: 42)
        for _ in 0..<300 {
            func pick(_ k: String) -> Int {
                let rg = ThemeParticles.ranges.first { $0.key == k }!.range
                return rg.lowerBound + Int(r.next() * Double(rg.upperBound - rg.lowerBound))
            }
            var t = ThemeParticles()
            for (k, _) in ThemeParticles.ranges { t[int: k] = pick(k) }
            t.colors = [0xFF000000, 0xFFFFFFFF, 0x80FF0000]
            t.glyphs = ["🍜"]
            for i in 0..<t.effCount {
                let p = t.particle(i, seed: Int(r.next() * 1e6))
                for v in [p.vx, p.vy, p.size, p.rotation, p.life] { XCTAssertTrue(v.isFinite) }
                XCTAssertLessThanOrEqual(hypot(p.vx, p.vy), 600 * 1.2 + 1e-9)
                XCTAssertTrue((4...48 * 2).contains(p.size))
                XCTAssertTrue((0.2...2.5).contains(p.life))
                XCTAssertLessThan(p.colorIndex, 3); XCTAssertEqual(p.glyphIndex, 0)
            }
            XCTAssertLessThanOrEqual(t.effCount * ThemeParticles.slots(perBurst: t.effCount), KeyEffectPool.cap)
        }
        XCTAssertEqual(ThemeParticles.slots(perBurst: 12), 1)
        XCTAssertEqual(ThemeParticles.slots(perBurst: 4), 5)
        XCTAssertEqual(ThemeParticles.slots(perBurst: 1), 8)
    }

    /// #151: gốc bounds dời (y âm) ⇒ "bottom" / "top" / "key" vẫn trong bàn phím.
    func testOriginWithShiftedBounds() {
        let b = (minX: 0.0, minY: -180.0, maxX: 390.0, maxY: 110.0)
        let bottom = ThemeFxOrigin.point("bottom", key: (100, -20), size: 20, bounds: b)
        XCTAssertEqual(bottom.x, 100); XCTAssertEqual(bottom.y, 100)
        let top = ThemeFxOrigin.point("top", key: (500, 0), size: 20, bounds: b)
        XCTAssertEqual(top.x, 390, "x kẹp trong bàn phím"); XCTAssertEqual(top.y, -170)
        let key = ThemeFxOrigin.point("key", key: (-5, -400), size: 20, bounds: b)
        XCTAssertEqual(key.x, 0); XCTAssertEqual(key.y, -180)
    }

    // MARK: glyph / từ

    func testGlyphRules() {
        for g in ["🍜", "❤️", "👨‍👩‍👧", "🇻🇳", "👍🏽", "1️⃣", "ế", "e\u{0301}", "★", "A"] { XCTAssertTrue(ThemeGlyph.isSingle(g), g) }
        for g in ["", "ab", "🍜🌸", " ", "\u{0301}", "👨\u{200D}", "\u{200D}👨", "🇻", "🇻🇳🇺🇸", "a b", "\u{00A0}",
                  String(repeating: "\u{0301}", count: 20)] {
            XCTAssertFalse(ThemeGlyph.isSingle(g), g.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))
        }
        for w in ["yêu", "năm mới", "love", "phở"] { XCTAssertTrue(ThemeKeywordWord.isValid(w), w) }
        for w in ["", " yêu", "yêu ", "a  b", "a b c", "abc1", "c++", "yêu!"] { XCTAssertFalse(ThemeKeywordWord.isValid(w), w) }
    }

    // MARK: bảng từ khoá

    func testKeywordMatchingRules() throws {
        let s = try XCTUnwrap(spec(Self.hearts))
        let t = ThemeKeywordTable(try XCTUnwrap(s.keywords))
        XCTAssertEqual(t.lookup(word: "yêu", prev: nil), 0)
        XCTAssertEqual(t.lookup(word: "YÊU", prev: nil), 0, "không phân biệt hoa thường")
        XCTAssertEqual(t.lookup(word: "Love,", prev: nil), 0, "bỏ dấu câu hai đầu")
        XCTAssertNil(t.lookup(word: "yeu", prev: nil), "dấu tiếng Việt có nghĩa")
        XCTAssertEqual(t.lookup(word: "phở", prev: nil), 1)
        XCTAssertNil(t.lookup(word: "pho", prev: nil))
        XCTAssertEqual(t.lookup(word: "mới", prev: "năm"), 0, "cụm hai từ khớp với từ liền trước")
        XCTAssertNil(t.lookup(word: "mới", prev: "nam"))
        XCTAssertNil(t.lookup(word: "mới", prev: nil))
        XCTAssertEqual(t.lookup(word: "y\u{00EA}u", prev: nil), 0)
        XCTAssertEqual(t.lookup(word: "ye\u{0302}u", prev: nil), 0, "chữ tổ hợp (NFD) chuẩn hoá NFC")
        XCTAssertNil(t.lookup(word: "", prev: nil))
        XCTAssertNil(t.lookup(word: String(repeating: "a", count: 200), prev: nil))
        // Mục đầu thắng ("yêu" có ở cả mục 0 và 1).
        XCTAssertEqual(t.lookup(word: "yêu", prev: "anh"), 0)
        // Từ nhạy cảm: không bao giờ nổ (kể cả khi người dùng khai báo).
        if let bad = SensitiveWords.set.first(where: { ThemeKeywordWord.isValid($0) }) {
            let tb = ThemeKeywordTable([ThemeKeyword(words: [bad])])
            XCTAssertNil(tb.lookup(word: bad, prev: nil), bad)
        }
        // Trần 20 mục.
        let many = ThemeKeywordTable((0..<30).map { _ in ThemeKeyword(words: ["từ"]) })
        XCTAssertEqual(many.entries.count, ThemeKeyword.maxEntries)
    }

    func testThemeFxMakeIsNilWithoutFields() throws {
        XCTAssertNil(ThemeFx.make(nil))
        XCTAssertNil(ThemeFx.make(spec(#""effect":"heart""#)))
        XCTAssertNil(ThemeFx.make(spec(#""keywords":[]"#)), "mảng rỗng = không có")
        let fx = try XCTUnwrap(ThemeFx.make(spec(Self.hearts)))
        XCTAssertNil(fx.particles)
        XCTAssertEqual(fx.burst(keyword: 0).effCount, 10)
        XCTAssertEqual(fx.burst(keyword: 1), .keywordFallback, "không burst, không particles ⇒ tim mặc định")
        XCTAssertEqual(fx.keywordSlots, 1, "10 hạt + chữ > 10 ⇒ 1 chùm")
        let both = try XCTUnwrap(ThemeFx.make(spec(Self.noodles + "," + #""keywords":[{"words":["phở"]}]"#)))
        XCTAssertEqual(both.burst(keyword: 0), both.particles, "không burst ⇒ particles của theme")
        XCTAssertEqual(both.keywordSlots, 2)
        XCTAssertNil(ThemeFxPolicy.active(both, plus: false, lowPower: false))
        XCTAssertNil(ThemeFxPolicy.active(both, plus: true, lowPower: true))
        XCTAssertEqual(ThemeFxPolicy.active(both, plus: true, lowPower: false), both)
    }

    // MARK: khứ hồi

    func testRoundTripCopyStoreBackup() throws {
        let s = try XCTUnwrap(spec(Self.noodles + "," + Self.hearts))
        XCTAssertEqual(ThemeSpecParser.parse(s.canonical).spec, s, "chuỗi chuẩn đọc lại y hệt")
        XCTAssertEqual(ThemeSpecParser.parse(s.json.pretty).spec, s)
        // Kho theme tự tạo (sao lưu + iCloud lưu đúng chuỗi này).
        var custom = s; custom.id = "mi"
        let raw = CustomThemeStore.serialize(["mi": custom])
        XCTAssertEqual(CustomThemeStore.parse(raw)["mi"]?.particles, s.particles)
        XCTAssertEqual(CustomThemeStore.parse(raw)["mi"]?.keywords, s.keywords)
        XCTAssertEqual(CustomThemeStore.normalize(raw), raw)
        // "Chép JSON" theme tự tạo giữ cả hai trường.
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.custom("mi"), settings: ThemeSettings(), store: ["mi": custom]))
        let back = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(back.particles, s.particles)
        XCTAssertEqual(back.keywords, s.keywords)
        XCTAssertEqual(back.effect, "theme")
        XCTAssertTrue(text.contains("\"particles\"") && text.contains("\"keywords\""))
        // Theme không khai báo ⇒ "Chép JSON" không thêm gì.
        let plain = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.peach), settings: ThemeSettings(), store: [:]))
        XCTAssertFalse(plain.contains("particles")); XCTAssertFalse(plain.contains("keywords"))
    }

    /// Đầu vào hỏng ngẫu nhiên quanh hai trường mới: không bao giờ crash; bản đọc được thì khứ hồi ổn định.
    func testFuzzNeverCrashes() {
        let seeds = [base + "," + Self.noodles + "}", base + "," + Self.hearts + "}", base + "," + Self.noodles + "," + Self.hearts + "}"]
        let junk = ["{", "}", "[", "]", "\"", ":", ",", "null", "-", "9", "1.5", "\\u0301", "\\u200d", "🍜", "\"glyphs\"",
                    "\"words\"", "[[[[", "999999999", "\"#FF00FF\"", "\"count\":", "\"burst\":{"]
        var r = FxRandom(seed: 0x5EED)
        var oks = 0
        for i in 0..<3000 {
            var u = Array(seeds[Int(r.next() * Double(seeds.count - 1) + 0.5)].utf8)
            switch i % 5 {
            case 0: u = Array(u.prefix(Int(r.next() * Double(u.count))))
            case 1: for _ in 0..<3 where !u.isEmpty { let k = Int(r.next() * Double(u.count - 1)); u[k] ^= UInt8(1 << Int(r.next() * 7)) }
            case 2:
                let k = Int(r.next() * Double(u.count)), j = junk[Int(r.next() * Double(junk.count - 1))]
                u.insert(contentsOf: Array(j.utf8), at: min(k, u.count))
            case 3: u += Array(String(repeating: "[", count: Int(r.next() * 500)).utf8)
            default:
                // số biên vào các trường số
                let s = String(decoding: u, as: UTF8.self)
                    .replacingOccurrences(of: "\"count\":6", with: "\"count\":\(Int(r.next() * 2e6) - 1_000_000)")
                    .replacingOccurrences(of: "\"speed\":90", with: "\"speed\":-999999999")
                u = Array(s.utf8)
            }
            let out = ThemeSpecParser.parse(Data(u))
            if let s = out.spec {
                oks += 1
                XCTAssertTrue(out.errors.isEmpty)
                XCTAssertEqual(ThemeSpecParser.parse(s.canonical).spec?.canonical, s.canonical)
                if let p = s.particles { XCTAssertTrue((1...12).contains(p.effCount)); XCTAssertTrue((20...600).contains(p.effSpeed)) }
                if let k = s.keywords { XCTAssertLessThanOrEqual(k.count, ThemeKeyword.maxEntries) }
                _ = ThemeFx.make(s)?.keywords?.lookup(word: "yêu", prev: "năm")
            } else {
                XCTAssertFalse(out.errors.isEmpty)
            }
        }
        XCTAssertGreaterThan(oks, 0)
    }

    // MARK: overlay (Core Animation)

    @MainActor private func host(shift: CGFloat) -> UIView {
        let h = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        h.bounds.origin.y = shift
        return h
    }

    @MainActor func testThemeParticlesOverlayCappedAndInsideShiftedBounds() throws {
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        defer { KeyEffectOverlay.drawsOffscreen = false }
        let s = try XCTUnwrap(spec(#""particles":{"shape":"star","count":12,"origin":"bottom","size":20}"#))
        let h = host(shift: -180)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.theme, color: .systemPink, in: h, existing: nil, themeFx: ThemeFx.make(s)))
        XCTAssertTrue(o.clipsToBounds, "cắt theo bàn phím")
        for i in 0..<200 {
            o.emit(key: CGRect(x: CGFloat(i % 12) * 32, y: CGFloat(i % 3) * 50 - 180, width: 34, height: 42))
            if i % 3 == 0 { o.flush() }
        }
        o.flush()
        XCTAssertEqual(o.debugThemeBursts.count, 1, "12 hạt/chùm ⇒ 1 chùm (trần pool)")
        XCTAssertLessThanOrEqual(o.debugThemeBursts.reduce(0) { $0 + ($1.sublayers?.count ?? 0) }, KeyEffectPool.cap)
        for b in o.debugThemeBursts {
            XCTAssertEqual(b.sublayers?.count, 12)
            XCTAssertEqual(b.position.y, o.bounds.maxY - 10, accuracy: 0.5, "gốc = mép dưới (gốc bounds dời)")
            XCTAssertTrue(o.bounds.insetBy(dx: -1, dy: -1).contains(b.position))
        }
        o.halt()
        // Không "particles" ⇒ chùm sao mặc định, 4… hạt theo fallback.
        let d = try XCTUnwrap(KeyEffectOverlay.install(.theme, color: .red, in: host(shift: 0), existing: nil))
        d.emit(key: CGRect(x: 100, y: 100, width: 34, height: 42)); d.flush()
        XCTAssertEqual(d.debugThemeBursts.first?.sublayers?.count, ThemeParticles.fallback.effCount)
        #endif
    }

    @MainActor func testKeywordsFireWithAnyEffectAndZeroCostWhenAbsent() throws {
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        defer { KeyEffectOverlay.drawsOffscreen = false }
        let fx = try XCTUnwrap(ThemeFx.make(spec(Self.hearts)))
        let h = host(shift: 0)
        // Hiệu ứng "Không" + theme có từ khoá ⇒ overlay sống, chỉ vẽ khi có từ khớp.
        let o = try XCTUnwrap(KeyEffectOverlay.install(.none, color: .red, in: h, existing: nil, themeFx: fx))
        XCTAssertTrue(o.wantsBoundaryWord)
        o.emit(key: CGRect(x: 10, y: 10, width: 34, height: 42))
        XCTAssertEqual(o.debugPendingCount, 0, "phím thường không hẹn vẽ gì")
        o.queueThemeKeyword(99)
        XCTAssertNil(o.debugPendingThemeKeyword, "mục ngoài bảng ⇒ bỏ qua")
        o.queueThemeKeyword(0)
        o.emit(key: CGRect(x: 10, y: 10, width: 34, height: 42)); o.flush()
        XCTAssertEqual(o.debugThemeKeywordRoots.count, 1)
        XCTAssertEqual(o.debugThemeKeywordRoots.first?.entry, 0)
        XCTAssertEqual(o.debugThemeKeywordRoots.first?.root.sublayers?.count, 11, "10 hạt + chữ")
        for i in 0..<50 {   // gõ từ khoá liên tục: trần chùm từ khoá
            o.queueThemeKeyword(i % 2)
            o.emit(key: CGRect(x: 10, y: 10, width: 34, height: 42)); o.flush()
        }
        XCTAssertLessThanOrEqual(o.debugThemeKeywordRoots.count, fx.keywordSlots)
        XCTAssertLessThanOrEqual(o.debugThemeKeywordRoots.reduce(0) { $0 + ($1.root.sublayers?.count ?? 0) }, KeyEffectPool.cap)
        // Hiệu ứng khác (Trái tim) + từ khoá: cả hai cùng bắn.
        let heart = try XCTUnwrap(KeyEffectOverlay.install(.heart, color: .red, in: h, existing: o, themeFx: fx))
        heart.queueThemeKeyword(1)
        heart.emit(key: CGRect(x: 50, y: 50, width: 34, height: 42)); heart.flush()
        XCTAssertEqual(heart.debugBurstCount, 1, "tim vẫn bắn")
        XCTAssertEqual(heart.debugThemeKeywordRoots.first?.entry, 1, "từ khoá nổ thêm")
        // Không có gì ⇒ không overlay / không tra từ.
        XCTAssertNil(KeyEffectOverlay.install(.none, color: .red, in: h, existing: heart, themeFx: nil))
        let plain = try XCTUnwrap(KeyEffectOverlay.install(.heart, color: .red, in: h, existing: nil, themeFx: nil))
        XCTAssertFalse(plain.wantsBoundaryWord)
        XCTAssertNil(plain.themeFx)
        let particlesOnly = try XCTUnwrap(KeyEffectOverlay.install(.heart, color: .red, in: h, existing: nil,
                                                                   themeFx: ThemeFx.make(spec(Self.noodles))))
        XCTAssertFalse(particlesOnly.wantsBoundaryWord, "chỉ có particles ⇒ không tra từ")
        #endif
    }

    /// Ô xem thử "Theo giao diện" vẽ đúng hạt của theme.
    @MainActor func testPreviewShowsThemeParticles() throws {
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        defer { KeyEffectOverlay.drawsOffscreen = false }
        let p = try XCTUnwrap(spec(Self.noodles)?.particles)
        let v = KeyEffectPreviewView(frame: .zero)
        let pal = ThemeSettings.load(nil).palette(systemDark: false, wallpaperActive: false)
        v.update(effect: .theme, palette: pal, play: 0, themeParticles: p)
        v.frame = CGRect(x: 0, y: 0, width: 110, height: 84)
        v.layoutIfNeeded()
        v.update(effect: .theme, palette: pal, play: 1, themeParticles: p)
        let o = try XCTUnwrap(v.overlay)
        XCTAssertEqual(o.themeParticles, p)
        XCTAssertEqual(o.debugThemeBursts.first?.sublayers?.count, 6)
        XCTAssertNotNil((o.debugThemeBursts.first?.sublayers?.first)?.contents, "ảnh 🍜 đã dựng")
        #endif
    }
}
