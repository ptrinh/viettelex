import XCTest
@testable import TelexCore

// Issue #138: a Vietnamese name glued to uppercase initials — the usual handle style in
// VN tech companies ("PhươngTH", "KiênTV", "HùngNV", "LinhPTT"). The whole token is no
// valid syllable, so the boundary used to restore the raw keys ("PhuwowngTH").
// Rule: Title-case head that is a valid, transformed, non-English syllable + a trailing
// run of 2–4 uppercase letters → keep the head's composition, initials literal.
final class InitialsSuffixTests: XCTestCase {

    private enum Cfg: CaseIterable { case plain, live, liveEager, liveFree }

    private func engine(_ c: Cfg) -> TelexEngine {
        var e = TelexEngine()
        switch c {
        case .plain: break
        case .live: e.liveSpellCheck = true
        case .liveEager: e.liveSpellCheck = true; e.eagerEnglishRestore = true
        case .liveFree: e.liveSpellCheck = true; e.freeMarking = true
        }
        return e
    }

    /// Feeds `keys` while simulating the screen; returns (screen before boundary, commit).
    private func type(_ keys: String, _ c: Cfg) -> (live: String, commit: String) {
        var e = engine(c)
        var screen: [Character] = []
        func apply(_ a: TelexAction, _ ch: Character?) {
            switch a {
            case .passthrough: if let ch { screen.append(ch) }
            case .none: break
            case let .replace(bs, ins): screen.removeLast(bs); screen.append(contentsOf: ins)
            }
        }
        for ch in keys {
            apply(e.feed(ch), ch)
            XCTAssertEqual(String(screen), e.composed, "screen desync typing \(keys) [\(c)]")
        }
        let live = String(screen)
        let peek = e.peekCommitText(autoRestore: true)
        var copy = e
        let text = copy.commitText(autoRestore: true)
        XCTAssertEqual(peek, text, "peek ≠ commit for \(keys) [\(c)]")
        apply(e.commitBoundary(autoRestore: true), nil)
        XCTAssertEqual(String(screen), text, "commitBoundary ≠ commitText for \(keys) [\(c)]")
        return (live, text)
    }

    func testNameWithInitialsKeepsVietnamese() {
        let cases: [(String, String)] = [
            ("PhuwowngTH", "PhươngTH"), ("KieenTV", "KiênTV"), ("HungfNV", "HùngNV"),
            ("LinhPTT", "LinhPTT"), ("TraanfTH", "TrầnTH"), ("DDinhNV", "ĐinhNV"),
            ("HungfNVVV", "HùngNVVV"), ("ThuyrNT", "ThủyNT"), ("NgocjAT", "NgọcAT"),
        ]
        for c in Cfg.allCases {
            for (keys, want) in cases {
                let r = type(keys, c)
                XCTAssertEqual(r.live, want, "live \(keys) [\(c)]")
                XCTAssertEqual(r.commit, want, "commit \(keys) [\(c)]")
            }
        }
    }

    /// Uppercase tone/mark keys inside the initials are LETTERS ("S" of Sơn, "X" of
    /// Xuân), not a sắc/ngã on the name — once the run is two capitals long.
    func testUppercaseToneKeysInInitialsAreLiteral() {
        for c in Cfg.allCases {
            XCTAssertEqual(type("KieenSV", c).commit, "KiênSV", "\(c)")
            XCTAssertEqual(type("NguyeenXJ", c).commit, "NguyênXJ", "\(c)")
            XCTAssertEqual(type("HungfNVJ", c).commit, "HùngNVJ", "\(c)")
            XCTAssertEqual(type("TuaanFR", c).commit, "TuânFR", "\(c)")
            XCTAssertEqual(type("AnhDD", c).commit, "AnhDD", "\(c)")   // no transform at all
        }
    }

    /// A SINGLE trailing capital keeps the historical behaviour: it is the camelCase
    /// shape of SaaS/OmS/PhD and cannot be told apart from it.
    func testSingleTrailingCapitalUnchanged() {
        for c in Cfg.allCases {
            XCTAssertEqual(type("KieenS", c).commit, "KieenS", "\(c)")
            XCTAssertEqual(type("KieenX", c).commit, "KieenX", "\(c)")
            XCTAssertEqual(type("PhuwowngT", c).commit, "PhuwowngT", "\(c)")
            XCTAssertEqual(type("SaaS", c).commit, "SaaS", "\(c)")
            XCTAssertEqual(type("OmS", c).commit, "OmS", "\(c)")
        }
    }

    func testGuardsStayAsBefore() {
        let same = ["iOS", "macOS", "PhD", "McDonald", "JavaScript", "TypeScript", "GitHub",
                    "MySQL", "NoSQL", "NodeJS", "DevOps", "YouTube", "LinkedIn", "iPhone",
                    "AsJSON", "HasID", "VieeJt", "PhuwowngABCDE"]
        for c in Cfg.allCases {
            for w in same { XCTAssertEqual(type(w, c).commit, w, "\(w) [\(c)]") }
            XCTAssertEqual(type("VIEETJ", c).commit, "VIỆT", "\(c)")
            XCTAssertEqual(type("HDDND", c).commit, "HĐND", "\(c)")
            XCTAssertEqual(type("NGUYEENX", c).commit, "NGUYỄN", "\(c)")
            // Lowercase after the initials breaks the shape → old whole-word decision.
            XCTAssertEqual(type("PhuwowngTHa", c).commit, "PhuwowngTHa", "\(c)")
        }
    }

    /// Code identifiers: a head whose tone/mark key forms an English word (max, res, pos,
    /// row, tax, box, las) + a code acronym is NOT a name with initials — "MaxID" used to
    /// split into "MãID". The acronym run (EnglishContextWords.codeAcronyms) blocks it.
    func testCodeAcronymRunIsNotInitials() {
        let same = ["MaxID", "ResID", "PosID", "RowID", "TaxID", "BoxID", "LasID",
                    "MaxIDS", "TaxURL", "PosAPI", "BoxUI", "RowJSON", "ResAPI", "MaxCSV",
                    "hasID", "userID", "getURL",
                    "HasID", "SetID", "DocID", "GetURL", "OrderID", "DataDB"]
        for c in Cfg.allCases {
            for w in same { XCTAssertEqual(type(w, c).commit, w, "\(w) [\(c)]") }
            // Runs left OUT of the list because they read as real initials still split.
            XCTAssertEqual(type("HungfVM", c).commit, "HùngVM", "\(c)")
            XCTAssertEqual(type("TuaansPX", c).commit, "TuấnPX", "\(c)")
            XCTAssertEqual(type("HungfDB", c).commit, "HùngDB", "\(c)")
        }
    }

    /// ⌫ must land on exactly what forward typing of the shorter word shows.
    func testBackspaceAcrossTheSplit() {
        for c in Cfg.allCases {
            var e = engine(c)
            for ch in "KieenSV" { _ = e.feed(ch) }
            XCTAssertEqual(e.composed, "KiênSV")
            _ = e.backspace()
            var fresh = engine(c)
            for ch in "KieenS" { _ = fresh.feed(ch) }
            XCTAssertEqual(e.composed, fresh.composed, "\(c)")
            _ = e.feed("V")
            XCTAssertEqual(e.composed, "KiênSV", "\(c)")

            var f = engine(c)
            for ch in "LinhPTTx" { _ = f.feed(ch) }
            _ = f.backspace()
            XCTAssertEqual(f.composed, "LinhPTT", "\(c)")
            XCTAssertEqual(f.commitText(autoRestore: true), "LinhPTT", "\(c)")

            var g = engine(c)
            for ch in "HungfNV" { _ = g.feed(ch) }
            _ = g.backspace(); _ = g.backspace()
            XCTAssertEqual(g.composed, "Hùng", "\(c)")
        }
    }

    /// ⌫ over the boundary re-opens "HùngNV" exactly as committed.
    func testReopenAfterBoundary() {
        var e = TelexEngine(); e.liveSpellCheck = true
        for ch in "HungfNV" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "HùngNV")
        XCTAssertEqual(e.reopenLastCommit(), "HùngNV")
    }

    func testVNIHeadWithInitials() {
        var e = TelexEngine(); e.vniMode = true
        for ch in "Phu7o7ngTH" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "PhươngTH")
        var f = TelexEngine(); f.vniMode = true
        for ch in "Hu2ngNV" { _ = f.feed(ch) }
        XCTAssertEqual(f.commitText(autoRestore: true), "HùngNV")
    }
}
