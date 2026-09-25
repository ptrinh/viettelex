import XCTest
@testable import TelexCore

/// Issue #94 (25/09/2026): teencode spelling is a toggle, OFF by default in the app.
/// OFF = standard spelling only — w/z/dz/k(+a/o/u) onsets and the ie/ik/ưk/òy/đou
/// forms stop composing, so English words typed through them survive.
final class TeencodeToggleTests: XCTestCase {
    private func commit(_ keys: String, teencode: Bool, simple: Bool = false) -> String {
        var e = TelexEngine(); e.liveSpellCheck = true; e.simpleTelex = simple; e.teencode = teencode
        var out: [String] = []
        for ch in keys {
            if ch == " " { out.append(e.commitText(autoRestore: true)) } else { _ = e.feed(ch) }
        }
        out.append(e.commitText(autoRestore: true))
        return out.joined(separator: " ")
    }

    func testTeencodeFormsNeedTheToggle() {
        // (keys, simpleTelex, with teencode ON)
        let cases: [(String, Bool, String)] = [
            ("was", true, "wá"), ("wos", true, "wó"),          // w → qu (Simple Telex)
            ("zoo", false, "zô"), ("zuij", false, "zụi"),      // z → d
            ("dzij", false, "dzị"),
            ("kos", false, "kó"),                              // k + o
            ("bies", false, "bíe"), ("thiks", false, "thík"),  // rimes ie / ik
            ("gofy", false, "gòy"), ("oyf", false, "òy"),      // òy / -òy
            ("uwkf", false, "ừk"),                             // ưk
        ]
        for (keys, simple, on) in cases {
            XCTAssertEqual(commit(keys, teencode: true, simple: simple), on, "ON \(keys)")
            XCTAssertNotEqual(commit(keys, teencode: false, simple: simple), on, "OFF \(keys)")
        }
    }

    func testEnglishWordsFromTheIssueSurviveWhenOff() {
        for w in ["was", "war", "worse", "wore", "wos", "zoo"] {
            XCTAssertEqual(commit(w, teencode: false, simple: true), w, w)
        }
        XCTAssertEqual(commit("worry", teencode: false, simple: true), "worry")
    }

    func testStandardSpellingUnaffectedWhenOff() {
        let words: [(String, String)] = [
            ("quas", "quá"), ("kere", "kể"), ("kinf", "kìn"), ("kyx", "kỹ"),
            ("ddi", "đi"), ("dduwowngf", "đường"), ("ddawks", "đắk"), ("uwmf", "ừm"),
            ("nghieeng", "nghiêng"), ("gif", "gì"), ("khoong", "không"),
        ]
        for (k, v) in words { XCTAssertEqual(commit(k, teencode: false), v, k) }
    }

    /// Every Vietnamese row of the reference suite must still render with teencode OFF,
    /// except rows whose expected output IS a teencode form.
    func testSuiteTransformRowsWithTeencodeOff() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "telex_test_suite", withExtension: "csv"))
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline }).dropFirst()
        var failed: [String] = [], total = 0
        for line in lines {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, f[5] == "transform" else { continue }
            total += 1
            var e = TelexEngine(); e.liveSpellCheck = true; e.teencode = false
            var out = ""
            for ch in f[1] {
                if let a = ch.asciiValue, (a | 0x20) >= 97, (a | 0x20) <= 122 { _ = e.feed(ch) }
                else { out += e.commitText(autoRestore: true); out.append(ch) }
            }
            out += e.commitText(autoRestore: true)
            if out != f[4], !f[4].components(separatedBy: " / ").contains(out) {
                failed.append("\(f[1])→\(out) (want \(f[4]))")
            }
        }
        XCTAssertTrue(total > 0)
        XCTAssertEqual(failed, [], "standard Vietnamese broke with teencode OFF")
    }
}
