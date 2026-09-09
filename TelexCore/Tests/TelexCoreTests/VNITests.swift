import XCTest
@testable import TelexCore

// VNI input method (engine.vniMode). In VNI, LETTERS are always literal and DIGITS
// carry the diacritics: 1-5 = sắc/huyền/hỏi/ngã/nặng, 6 = â/ê/ô, 7 = ơ/ư, 8 = ă,
// 9 = đ, 0 = clear tone. The core guarantee is that VNI produces byte-identical
// Vietnamese to the equivalent Telex keys — tone placement, ươ propagation, rendering
// and boundary restore are all shared, method-agnostic machinery.

private func vni(_ keys: String) -> String {
    var e = TelexEngine(); e.vniMode = true
    for ch in keys { _ = e.feed(ch) }
    return e.composed
}

private func telex(_ keys: String) -> String {
    var e = TelexEngine()
    for ch in keys { _ = e.feed(ch) }
    return e.composed
}

private func vniCommit(_ keys: String, spell: Bool = false) -> String {
    var e = TelexEngine(); e.vniMode = true; e.liveSpellCheck = spell
    for ch in keys { _ = e.feed(ch) }
    return e.commitText(autoRestore: true)
}

/// Type keys, press Backspace `n` times, return the composition.
private func vniBackspace(_ keys: String, _ n: Int = 1) -> String {
    var e = TelexEngine(); e.vniMode = true
    for ch in keys { _ = e.feed(ch) }
    for _ in 0..<n { _ = e.backspace() }
    return e.composed
}

private func telexBackspace(_ keys: String, _ n: Int = 1) -> String {
    var e = TelexEngine()
    for ch in keys { _ = e.feed(ch) }
    for _ in 0..<n { _ = e.backspace() }
    return e.composed
}

final class VNITests: XCTestCase {

    // MARK: Tones and marks on a single vowel (explicit)

    func testSingleVowelTonesAndMarks() {
        XCTAssertEqual(vni("a1"), "á")
        XCTAssertEqual(vni("a2"), "à")
        XCTAssertEqual(vni("a3"), "ả")
        XCTAssertEqual(vni("a4"), "ã")
        XCTAssertEqual(vni("a5"), "ạ")
        XCTAssertEqual(vni("a6"), "â")
        XCTAssertEqual(vni("a8"), "ă")
        XCTAssertEqual(vni("e6"), "ê")
        XCTAssertEqual(vni("o6"), "ô")
        XCTAssertEqual(vni("o7"), "ơ")
        XCTAssertEqual(vni("u7"), "ư")
        XCTAssertEqual(vni("d9"), "đ")
        // mark + tone
        XCTAssertEqual(vni("a61"), "ấ")
        XCTAssertEqual(vni("a65"), "ậ")
        XCTAssertEqual(vni("a81"), "ắ")
        XCTAssertEqual(vni("o71"), "ớ")
        XCTAssertEqual(vni("u75"), "ự")
        XCTAssertEqual(vni("e61"), "ế")
        // case preserved
        XCTAssertEqual(vni("A1"), "Á")
        XCTAssertEqual(vni("D9"), "Đ")
    }

    // MARK: VNI ≡ Telex — the load-bearing invariant

    func testVNIEqualsTelexForRealWords() {
        // (vniKeys, telexKeys) — must compose identically.
        let pairs = [
            ("a1", "as"), ("a2", "af"), ("a3", "ar"), ("a4", "ax"), ("a5", "aj"),
            ("a6", "aa"), ("a8", "aw"), ("o7", "ow"), ("u7", "uw"), ("d9", "dd"),
            ("a61", "aas"), ("a65", "aaj"), ("a81", "aws"), ("o71", "ows"), ("u75", "uwj"),
            ("tie61ng", "tieengs"),      // tiếng
            ("Vie65t", "Vieejt"),        // Việt
            ("nguoi72", "nguwowif"),     // người
            ("ngu7o7i2", "nguwowif"),    // người (marks typed per-vowel)
            ("d9uo7c5", "dduowcj"),      // được
            ("hoa2", "hoaf"),            // hoà / hòa (whatever Telex places)
            ("ca1c", "cacs"),            // các
            ("ho5c", "hocj"),            // học
        ]
        for (v, t) in pairs {
            XCTAssertEqual(vni(v), telex(t), "VNI \(v) should equal Telex \(t)")
        }
    }

    // MARK: Authoritative reference examples

    // Anchored to external references so the VNI rules can't silently drift:
    //  - ibus-bamboo `bamboo-core/input_method_def.go` "VNI" table
    //    (6=ÂÊÔ, 7=ƯƠ, 8=Ă, 9=Đ, 0=XoaDauThanh, 1-5=Sắc/Huyền/Hỏi/Ngã/Nặng), and
    //  - the Wikipedia VNI article's own worked example: truong + 7 + 2 → trường.
    func testAuthoritativeReferenceExamples() {
        XCTAssertEqual(vni("truong72"), "trường")   // Wikipedia canonical example
        XCTAssertEqual(vni("Vie65t"), "Việt")
        XCTAssertEqual(vni("d9uo7c5"), "được")
        XCTAssertEqual(vni("nguoi72"), "người")
        XCTAssertEqual(vni("tie61ng"), "tiếng")
        XCTAssertEqual(vni("hoc5"), "học")
        XCTAssertEqual(vni("toa2n"), "toàn")
        XCTAssertEqual(vni("thu7o7ng2"), "thường")
        XCTAssertEqual(vni("d9a5i"), "đại")
        XCTAssertEqual(vni("ho7n"), "hơn")
        XCTAssertEqual(vni("ba8ng2"), "bằng")
    }

    // Marks and tones combine in EITHER order (a defining VNI property).
    func testMarkToneOrderIndependence() {
        XCTAssertEqual(vni("a61"), vni("a16"))       // both → ấ
        XCTAssertEqual(vni("a61"), "ấ")
        XCTAssertEqual(vni("o71"), vni("o17"))       // both → ớ
        XCTAssertEqual(vni("a85"), vni("a58"))       // both → ặ
    }

    // MARK: Cancel / clear semantics

    func testCancelAndClear() {
        // Same tone digit twice cancels → tone gone, second digit literal (mirrors ss→s).
        XCTAssertEqual(vni("a11"), "a1")
        // 0 clears the tone (no literal 0 left).
        XCTAssertEqual(vni("a10"), "a")
        XCTAssertEqual(vniCommit("a10"), "a")
        // Same mark digit twice cancels → mark gone, digit literal.
        XCTAssertEqual(vni("a66"), "a6")
        XCTAssertEqual(vni("a88"), "a8")
        XCTAssertEqual(vni("d99"), "d9")
        // Lone 0 with no tone is a literal digit.
        XCTAssertEqual(vni("a0"), "a0")
    }

    // MARK: Digits as literal numbers (disambiguation)

    func testLiteralNumbers() {
        // No vowel to tone → the digit is literal, no spell-check needed.
        XCTAssertEqual(vniCommit("mp3"), "mp3")
        XCTAssertEqual(vniCommit("2020"), "2020")
        // Leading number then letters.
        XCTAssertEqual(vniCommit("3g"), "3g")
        // With live spell-check (the shipped default): once the word can't be Vietnamese,
        // every following digit is literal — English + digits survive intact.
        XCTAssertEqual(vniCommit("html5", spell: true), "html5")
        XCTAssertEqual(vniCommit("abc123", spell: true), "abc123")
        XCTAssertEqual(vniCommit("Windows10", spell: true), "Windows10")
        // Plain English letters (no digits) type through unchanged.
        XCTAssertEqual(vniCommit("hello"), "hello")
    }

    // Invalid VNI tone digits after a stop coda type through (same OpenKey rule
    // as Telex s/f/r/x/j): "sec3" must stay "sec3", not swallow 3 as hỏi.
    func testStopCodaRejectsToneDigitAsLiteral() {
        XCTAssertEqual(vni("sec3"), "sec3")
        XCTAssertEqual(vni("bat2"), "bat2")
        XCTAssertEqual(vni("bat3"), "bat3")
        XCTAssertEqual(vni("bat4"), "bat4")
        XCTAssertEqual(vni("bat1"), "bát")   // sắc still lands
        XCTAssertEqual(vni("bat5"), "bạt")   // nặng still lands
    }

    // MARK: Boundary restore reverts invalid VNI tokens

    func testInvalidTokenRestoresRaw() {
        // "xyz1" composes "xýz" (y takes the tone) — not a valid syllable, so the
        // boundary restore reverts to the raw keystrokes.
        XCTAssertEqual(vniCommit("xyz1"), "xyz1")
    }

    // MARK: Backspace — one DISPLAY grapheme at a time, identical to Telex

    func testBackspace() {
        // A composed vowel ("ấ", "đ") is ONE grapheme, so ⌫ removes the whole char —
        // exactly as Telex does. Assert VNI ⌫ ≡ Telex ⌫ (the true oracle).
        XCTAssertEqual(vniBackspace("a61"), telexBackspace("aas"))       // "ấ" → ""
        XCTAssertEqual(vniBackspace("a61", 2), telexBackspace("aas", 2)) // → ""
        XCTAssertEqual(vniBackspace("d9"), telexBackspace("dd"))         // "đ" → ""
        XCTAssertEqual(vniBackspace("d9uo7c5"), telexBackspace("dduowcj"))
        // Multi-letter word: ⌫ drops the last letter, leaving a real partial word.
        XCTAssertEqual(vniBackspace("tie61ng"), telexBackspace("tieengs"))
        XCTAssertEqual(vniBackspace("tie61ng"), "tiến")
    }

    // MARK: vniMode is required — Telex mode never composes digits

    func testDigitsInertInTelexMode() {
        var t = TelexEngine()                       // vniMode = false
        _ = t.feed("a")
        XCTAssertEqual(t.feed("1"), .passthrough)   // digit not consumed in Telex mode
        XCTAssertEqual(t.composed, "a")
    }

    // MARK: The gate — vniMode OFF must leave Telex byte-identical

    // Explicit: an engine with vniMode set false behaves exactly like a default engine,
    // AND every digit is a no-op passthrough. This is the "turning VNI off can't touch
    // Telex" guarantee, on top of the 140 pre-existing Telex tests (all run vniMode=off).
    func testTelexUntouchedWhenVniOff() {
        let telexWords = ["tieengs", "nguwowif", "dduowcj", "hoas", "vieejt",
                          "quocs", "ddaay", "truowngf", "as", "aa", "ww"]
        for keys in telexWords {
            var off = TelexEngine(); off.vniMode = false
            var def = TelexEngine()
            for ch in keys { _ = off.feed(ch); _ = def.feed(ch) }
            XCTAssertEqual(off.composed, def.composed, "explicit vniMode=off diverged for \(keys)")
        }
        // Every digit is an inert passthrough in Telex mode (buffer unchanged).
        var e = TelexEngine()
        for ch in "as" { _ = e.feed(ch) }           // "á"
        let before = e.composed
        for d in "0123456789" {
            XCTAssertEqual(e.feed(d), .passthrough, "digit \(d) not passthrough in Telex mode")
        }
        XCTAssertEqual(e.composed, before, "digits must not mutate the Telex composition")
    }

    // CRASH regression (issue #28, 2026-07-27). A literal DIGIT lands in the letter
    // buffer whenever VNI can't use it as a diacritic ("mp3", "2020", "html5"), and live
    // spell-check then runs the validator over those bases. `letterClass`/`cls()` map a
    // base by `base &- "a"`, which WRAPS for a digit (48 - 97 → 207) and used to index
    // the flat trie out of bounds — killing the IME mid-word (and silently returning
    // garbage validity whenever the stray offset stayed inside the array).
    func testLiteralDigitsSurviveLiveSpellCheck() {
        for token in ["mp3", "2020", "html5", "ipv4", "a4b3", "x9", "0", "99999999"] {
            var e = TelexEngine()
            e.vniMode = true; e.liveSpellCheck = true; e.freeMarking = true
            for ch in token { _ = e.feed(ch) }
            _ = e.peekCommitText(autoRestore: true)
            XCTAssertEqual(e.commitText(autoRestore: true), token,
                           "'\(token)' must survive VNI + live spell-check verbatim")
        }
    }

    // The same guard at its own level: a non-letter base is never a Vietnamese prefix,
    // and an out-of-alphabet class must resolve to "no child" instead of a wild index.
    func testValidatorRejectsNonLetterBases() {
        XCTAssertFalse(SyllableValidator.isValidPrefix(bases: Array("mp3".utf8), count: 3))
        XCTAssertFalse(SyllableValidator.isValidPrefix(bases: Array("2".utf8), count: 1))
        XCTAssertTrue(SyllableValidator.isValidPrefix(bases: Array("ng".utf8), count: 2))
        // classes straight from letterClass for digits are ≥ 33 (the alphabet size)
        XCTAssertFalse(SyllableValidator.isValidSyllable(
            classes: [Tables.letterClass(base: UInt8(ascii: "3"), mark: .none)],
            count: 1, tone: .none))
    }

    // A bounded, DETERMINISTIC fuzz over VNI keystrokes × settings — the crash above only
    // showed up on random digit/letter mixes, not on any hand-written case.
    func testVniFuzzDoesNotTrap() {
        struct LCG: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return state
            }
        }
        let alphabet = Array("abcdeghiklmnopqrstuvwxyzAEIOU0123456789")
        for seed in 1...4000 {
            var rng = LCG(state: UInt64(seed))
            var e = TelexEngine()
            e.vniMode = true
            e.freeMarking = Bool.random(using: &rng)
            e.liveSpellCheck = Bool.random(using: &rng)
            e.simpleTelex = Bool.random(using: &rng)
            e.quickTelex = Bool.random(using: &rng)
            for _ in 0..<Int.random(in: 1...14, using: &rng) {
                if Int.random(in: 0..<8, using: &rng) == 0 { _ = e.backspace() }
                else { _ = e.feed(alphabet.randomElement(using: &rng)!) }
            }
            _ = e.peekCommitText(autoRestore: true)
            _ = e.commitText(autoRestore: true)
        }
    }

    // Flipping the mode between words (as the Settings toggle does) is clean: a VNI word,
    // then vniMode off + reset, then a Telex word — each composes correctly, no bleed.
    func testModeFlipBetweenWordsIsClean() {
        var e = TelexEngine()
        e.vniMode = true
        for ch in "a61" { _ = e.feed(ch) }
        XCTAssertEqual(e.composed, "ấ")
        _ = e.commitText(autoRestore: true)         // word boundary
        e.vniMode = false                           // user switches to Telex
        for ch in "aas" { _ = e.feed(ch) }
        XCTAssertEqual(e.composed, "ấ")             // Telex path, same result
        _ = e.commitText(autoRestore: true)
        for ch in "a1" { _ = e.feed(ch) }           // now digits are inert again
        XCTAssertEqual(e.composed, "a")
    }
}
