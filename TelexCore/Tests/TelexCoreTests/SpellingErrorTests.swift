import XCTest
@testable import TelexCore

/// Opt-in "Gạch đỏ âm tiết sai chính tả khi gõ" (Windows TSF / Linux preedit): the
/// decision lives here (SyllableValidator.isSpellingError + TelexEngine.hasSpellingError)
/// and is replayed byte for byte by the C++ port (windows/engine unit tests) and the
/// Linux C ABI (linux/common test_common) from the same vector file.
final class SpellingErrorTests: XCTestCase {
    private func appDefaultEngine(live: Bool) -> TelexEngine {
        var e = TelexEngine()
        e.freeMarking = true; e.liveSpellCheck = live; e.contextualEnglish = true
        e.collisionPrefersVietnamese = true; e.teencode = false
        return e
    }

    func testSharedVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "spelling_error_cases", withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows = 0
        for line in text.split(whereSeparator: { $0.isNewline }) where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3 else { continue }
            let want = f[2] == "1"
            let opts = f.count > 3 ? f[3] : ""
            rows += 1
            switch f[0] {
            case "syllable":
                XCTAssertEqual(SyllableValidator.isValidSyllable(f[1], teencode: false), want, "syllable \(f[1])")
            case "error":
                XCTAssertEqual(SyllableValidator.isSpellingError(f[1], teencode: false), want, "error \(f[1])")
            case "keys":
                var e = appDefaultEngine(live: !opts.contains("L"))
                for ch in f[1] { _ = e.feed(ch) }
                XCTAssertEqual(e.hasSpellingError(autoRestore: !opts.contains("R")), want, "keys \(f[1]) \(opts)")
            default:
                XCTFail("unknown row kind \(f[0])")
            }
        }
        XCTAssertGreaterThan(rows, 50)
    }

    func testEmptyAndOverflowNeverFlagged() {
        var e = appDefaultEngine(live: true)
        XCTAssertFalse(e.hasSpellingError(autoRestore: true))
        for ch in String(repeating: "dd", count: 20) { _ = e.feed(ch) }
        XCTAssertTrue(e.isOverflowed)
        XCTAssertFalse(e.hasSpellingError(autoRestore: true))
    }

    /// The flag follows the word as it is typed and edited: "đc" is flagged, ⌫ back to
    /// "đ" (still a plausible prefix) clears it.
    func testFollowsTypingAndBackspace() {
        var e = appDefaultEngine(live: true)
        for ch in "ddc" { _ = e.feed(ch) }
        XCTAssertEqual(e.composed, "đc")
        XCTAssertTrue(e.hasSpellingError(autoRestore: true))
        _ = e.backspace()
        XCTAssertEqual(e.composed, "đ")
        XCTAssertFalse(e.hasSpellingError(autoRestore: true))
    }
}
