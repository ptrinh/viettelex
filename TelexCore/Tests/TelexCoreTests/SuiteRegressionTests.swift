import XCTest
@testable import TelexCore

// Regression harness over the external telex_test_suite.csv (bundled in Resources/).
// Every input is run through the engine and bucketed by `expected_behavior`:
//   • transform               → a Vietnamese word must render to its VN form (VN→VN)
//   • keep_as_typed           → an English word with no transform stays as typed (EN→EN)
//   • restore_raw             → an English word that DID transform is restored to raw (EN→EN)
//   • ambiguous_needs_context → composes to a valid VN syllable but the raw spells English;
//                               only the context feature (after an English word) can flip it
//
// The English suite is aspirational (the engine is not a full English dictionary), so the
// EN buckets assert a FLOOR, not 100% — the floors are the measured pass counts and must
// never drop (a regression fails the build). Raise them when the engine improves.
//
// IMPORTANT finding baked in as a guard (testCoreTelexSequencesAreNotAmbiguousEnglish):
// the suite mislabels core Telex sequences (aa→â, oo→ô, uw→ư, aw→ă, ar→ả, aj→ạ) as
// "ambiguous_needs_context" because they appear as tokens in an English frequency list.
// They must NEVER be treated as English — that would break Vietnamese typing — so they
// are explicitly excluded from any context whitelist.
final class SuiteRegressionTests: XCTestCase {

    private struct Row { let input: String; let expected: String; let behavior: String }

    private func loadSuite() throws -> [Row] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "telex_test_suite", withExtension: "csv"),
                                "telex_test_suite.csv missing from test bundle")
        let text = try String(contentsOf: url, encoding: .utf8)
        // CRLF: Swift folds "\r\n" into one grapheme, so split on any newline scalar.
        var lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
        lines.removeFirst()   // header
        // Columns 0..8: suite,input,freq,naive,expected,behavior,category,severity,notes.
        // input/expected/behavior are comma-free; a quoted notes field with commas only
        // adds trailing fields, so fixed indices stay correct.
        let known: Set<String> = ["transform", "restore_raw", "keep_as_typed",
                                  "ambiguous_needs_context", "cancel_keep_composed"]
        return lines.compactMap { line in
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            // Skip junk rows (a notes field with an embedded newline spills a partial line).
            guard f.count >= 6, known.contains(f[5]) else { return nil }
            return Row(input: f[1], expected: f[4], behavior: f[5])
        }
    }

    /// Boundary-accurate replay, exactly like the controller: letters compose; every
    /// non-letter (space, digit, punctuation) is a word boundary — commit the word, then
    /// emit the character literally. So "ipv4", "vieejt-nam", "xin chaof!" round-trip.
    /// Accept any of the `" / "`-separated alternatives the suite lists as valid (tone-
    /// placement style variants: "hòa / hoà", "thủy / thuỷ").
    private func matches(_ output: String, _ expected: String) -> Bool {
        if output == expected { return true }
        return expected.components(separatedBy: " / ").contains { $0 == output }
    }

    private func drive(_ input: String, primeEnglish: Bool, context: Bool) -> String {
        // liveSpellCheck on (shipped default). freeMarking is deliberately LEFT OFF here:
        // its aggressive mark reach-back mangles English double-vowel words in this raw
        // per-key replay ("excess"→"êcs"), which doesn't reflect real typing — so it would
        // understate English-restore. The few multi_path free-position rows it would fix
        // aren't worth that distortion.
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = context
        if primeEnglish { for ch in "he" { _ = e.feed(ch) }; _ = e.commitText(autoRestore: true) }
        var out = ""
        for ch in input {
            if let a = ch.asciiValue, isLetter(a) {
                _ = e.feed(ch)
            } else {
                out += e.commitText(autoRestore: true)
                out.append(ch)
            }
        }
        out += e.commitText(autoRestore: true)
        return out
    }

    private func run(_ input: String, context: Bool) -> String { drive(input, primeEnglish: false, context: context) }
    private func runAfterEnglish(_ input: String) -> String { drive(input, primeEnglish: true, context: true) }

    func testSuiteClassificationFloors() throws {
        let rows = try loadSuite()
        var pass: [String: Int] = [:], total: [String: Int] = [:]
        var ambiguousWithContext = 0, ambiguousTotal = 0
        for r in rows {
            total[r.behavior, default: 0] += 1
            if matches(run(r.input, context: false), r.expected) { pass[r.behavior, default: 0] += 1 }
            if r.behavior == "ambiguous_needs_context" {
                ambiguousTotal += 1
                if matches(runAfterEnglish(r.input), r.expected) { ambiguousWithContext += 1 }
            }
        }
        // Visibility.
        for k in total.keys.sorted() {
            print("SUITE \(k): \(pass[k] ?? 0)/\(total[k]!)")
        }
        print("SUITE ambiguous handled by context: \(ambiguousWithContext)/\(ambiguousTotal)")

        // EN→EN: an English word that doesn't transform must always survive verbatim.
        XCTAssertEqual(pass["keep_as_typed"], total["keep_as_typed"],
                       "an unchanged English word must never be mangled")
        // EN→EN: restore of transformed English words — floor (raise when improved).
        // 2026-07-26: 6790 → 7201 (reach-back tone-cancel rule + dict grown from the
        // suite's own English column, ≥5 chữ). 2026-07-31: 66 trailing-double rows
        // (pass/off/boss…) moved OUT of this bucket into cancel_keep_composed —
        // screen-truth now outranks the dict for the trailing escape (maintainer
        // decision; literal "pas" was untypeable under dict-first). Mid-word doubles
        // ("office"→ofice shape) stay dict-restored here. Remaining misses are
        // protected VN collisions (won=ươn, worst=ướt), acronyms (ieee, nginx) and
        // 2-3 letter tokens inside symbol strings (/usr/…, os.path).
        // 2026-08-04 (teencode, maintainer-approved): the OPEN rime "ie" became a valid
        // syllable so chat spellings commit as typed ("bies"→bíe, "miej"→mịe). The 12
        // English words that newly collided (chief, dies, hire, lies, life, mixer,
        // rise, tier, ties, tire, tires, tries) were added to the collision table via
        // gen-english's extra-corpus hook (757 → 769) — dict restore runs before the
        // valid-syllable keep, so the floor holds. (A FULL-corpus regeneration was
        // tried and REVERTED: it swept in unvetted VN-colliding words — mays≡máy,
        // vans≡ván. Only monotone base + explicit extras.)
        // 2026-08-12 (teencode, maintainer-approved): rimes "ưm"/"ưn" became valid
        // ("uwm"→ưm, "uwmf"→ừm, "uwn"→ưn). Two 2-letter suite tokens flipped —
        // "wm"≡ưm, "wn"≡ưn — the same protected-VN-collision class as won≡ươn /
        // wi≡ưi already counted among this bucket's accepted misses. 7135 → 7133.
        // 19/08/2026: +2 (wise, wife) — fix chồng đặc cách teencode (onset w→qu
        // KHÔNG được cộng dồn với rime "ie") nâng sàn 7133 → 7135.
        XCTAssertGreaterThanOrEqual(pass["restore_raw"] ?? 0, 7135,
                                    "English-restore coverage regressed")
        // Trailing-cancel screen-truth (2026-07-31): the escape gesture commits the
        // rendered text even when raw is a real English word — EXACT, no floor.
        XCTAssertEqual(pass["cancel_keep_composed"], total["cancel_keep_composed"],
                       "a trailing cancel stopped committing the screen text")
        // VN→VN: EVERY Vietnamese word must render correctly (style variants hoà/hòa
        // accepted via `matches`). 18 non-defect rows were removed from the suite —
        // suite-wrong (giaj→giạ, uow→uơ), undefined_behavior (expected "?"), spec/mixed-
        // case choices (ToAnS), and a two-syllable token (đôla) — so this is now exact.
        XCTAssertEqual(pass["transform"], total["transform"],
                       "a Vietnamese word rendered wrong")
        // Ambiguous handled once an English run is established — floor (raised after the
        // broad `degrades_vn` whitelist expansion).
        XCTAssertGreaterThanOrEqual(ambiguousWithContext, 632,
                                    "context coverage of ambiguous words regressed")
    }

    // Guard the finding: core Telex sequences the suite mislabels as ambiguous English
    // must render Vietnamese and must NOT be in the context whitelist — else typing "â"
    // (aa) after an English word would corrupt to "aa".
    func testCoreTelexSequencesAreNotAmbiguousEnglish() {
        let core: [(String, String)] = [("aa", "â"), ("oo", "ô"), ("ee", "ê"),
                                         ("uw", "ư"), ("aw", "ă"), ("ar", "ả"), ("aj", "ạ")]
        for (keys, vn) in core {
            XCTAssertFalse(EnglishContextWords.words.contains(keys),
                           "\(keys) is a core Telex sequence, not an English word")
            // Even inside an English run it must stay Vietnamese.
            XCTAssertEqual(runAfterEnglish(keys), vn, "\(keys) must render \(vn) even after English")
        }
    }
}

