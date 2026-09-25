import XCTest
import QuartzCore

/// Screenshot 25/09/2026: lỗi chạm trượt phím kề khi gõ nhanh trên iPhone.
final class AdjacentKeyFixerTests: XCTestCase {
    private let bridge = EngineBridge(settings: {
        var s = KeyboardSettings(); s.simpleTelex = true; return s
    }())
    private var composeCalls = 0
    private func fix(_ raw: String) -> String? {
        AdjacentKeyFixer.correction(raw: raw,
                                    compose: { self.composeCalls += 1; return self.bridge.composeTrial($0) },
                                    frequency: { VNSuggest.frequency(of: $0) },
                                    hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty })
    }

    func testOnByDefault() {                     // maintainer 25/09/2026
        XCTAssertTrue(KeyboardSettings().autoFixAdjacent)
    }

    func testNeighborsAreQwertyAdjacent() {
        let h = AdjacentKeyFixer.neighbors["h"] ?? []
        XCTAssertTrue(h.contains("g") && h.contains("j") && h.contains("b") && h.contains("y"))
        XCTAssertFalse(h.contains("q"))
        let i = AdjacentKeyFixer.neighbors["i"] ?? []
        XCTAssertTrue(i.contains("j") || i.contains("k"))
    }

    func testFixesFromTheScreenshot() {
        XCTAssertEqual(fix("nbjeeuf"), "nhiều")     // h→b, i→j (2 sửa)
        XCTAssertEqual(fix("ohims"), "phím")        // p→o
        XCTAssertEqual(fix("nayd"), "này")          // f→d
        XCTAssertEqual(fix("cahcs"), "cách")        // đảo h/c
        XCTAssertEqual(fix("nbjr"), "nhỉ")
    }

    func testLeavesRealWordsAndPrefixesAlone() {
        XCTAssertNil(fix("nhieeuf"))                // đã đúng
        XCTAssertNil(fix("ng"))                     // đang gõ dở (tiền tố của nhiều từ)
        XCTAssertNil(fix("x"))                      // quá ngắn
    }

    func testKeepsSentenceCase() {
        XCTAssertEqual(fix("Ohims"), "Phím")
    }

    func testTouchOffsetMovesSelectionUp() {
        let p = TouchGeometry.keySelectionPoint(CGPoint(x: 10, y: 100))
        XCTAssertEqual(p.y, 100 - TouchGeometry.yOffset)
        XCTAssertEqual(p.x, 10)
    }

    /// Cắt tỉa tiền-tố-chết không được làm rơi bản sửa mà brute-force tìm ra:
    /// phím thanh cuối đổi thanh ("cuxmh": h→j đổi ngã→nặng) và phím thanh gõ giữa từ trước nguyên âm sau.
    func testPruningKeepsToneAndSwapFixes() {
        XCTAssertEqual(fix("cuxmh"), "cụm")
        XCTAssertEqual(fix("ddusoangf"), "đường")   // a→w, thanh "s" đứng giữa
        XCTAssertEqual(AdjacentKeyFixer.stripTones("cũm"), "cum")
        XCTAssertEqual(AdjacentKeyFixer.stripTones("đường"), "đương")
    }

    /// Từ không có trong lexicon (tiếng Anh, tên) = trường hợp tệ nhất: trước đây
    /// brute-force ~300–500 lần compose/phím (5–11 ms trên máy). Chặn cả số lần
    /// compose (tất định) lẫn thời gian thật trên simulator.
    func testTypicalMissIsCheap() {
        for w in ["keyboard", "position", "github"] {
            composeCalls = 0
            XCTAssertNil(fix(w), w)
            XCTAssertLessThanOrEqual(composeCalls, 160, "\(w): \(composeCalls) compose")
        }
        // Wall-clock: min của 5 lượt/từ (máy build hay bận — số compose ở trên mới là
        // chốt tất định). Brute-force cũ: Debug 35–70 ms/từ, Release sim 1.5–5 ms.
        #if DEBUG
        let budgetMs = 150.0   // máy build bận (agent song song) đo được tới ~55 ms
        #else
        let budgetMs = 5.0
        #endif
        for w in ["keyboard", "position", "github"] {
            var best = Double.infinity
            for _ in 0..<5 {
                let t0 = CACurrentMediaTime()
                _ = fix(w)
                best = min(best, (CACurrentMediaTime() - t0) * 1000)
            }
            XCTAssertLessThan(best, budgetMs, "\(w): \(best) ms")
        }
    }

    func testCacheByRawKeystrokes() {
        let b = EngineBridge(settings: KeyboardSettings())
        XCTAssertEqual(AdjacentKeyFixer.lexiconCorrection(raw: "ohims", bridge: b), "phím")
        XCTAssertNil(AdjacentKeyFixer.lexiconCorrection(raw: "github", bridge: b))
        XCTAssertEqual(b.adjacentFixCache.count, 2)
        XCTAssertEqual(AdjacentKeyFixer.lexiconCorrection(raw: "ohims", bridge: b), "phím")
        XCTAssertNil(AdjacentKeyFixer.lexiconCorrection(raw: "github", bridge: b))   // miss cũng cache
        XCTAssertEqual(b.adjacentFixCache.count, 2)
        var n = 0
        _ = b.adjacentFixCache.value(for: "ohims") { n += 1; return nil }
        XCTAssertEqual(n, 0)
    }
}
