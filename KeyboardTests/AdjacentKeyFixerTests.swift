import XCTest

/// Screenshot 25/09/2026: lỗi chạm trượt phím kề khi gõ nhanh trên iPhone.
final class AdjacentKeyFixerTests: XCTestCase {
    private let bridge = EngineBridge(settings: {
        var s = KeyboardSettings(); s.simpleTelex = true; return s
    }())
    private func fix(_ raw: String) -> String? {
        AdjacentKeyFixer.correction(raw: raw,
                                    compose: { self.bridge.composeTrial($0) },
                                    frequency: { VNSuggest.frequency(of: $0) },
                                    hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty })
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
}
