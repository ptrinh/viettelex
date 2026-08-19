import XCTest
@testable import TelexCore

// TEENCODE (feature 2026-08-04, maintainer-approved). Two rules, both about chat
// spellings that are NOT dictionary Vietnamese but ARE what the user meant:
//
//  (a) ELONGATION — the composition splits as `valid syllable` + a run of ONE repeated
//      letter, run ≥ 3 ("hôn"+"gggg", "có"+"aaaaaa", "ạ"+"aaaaaaa", "đẹp"+"ppppp").
//      Live spell-check must not FREEZE such a word (freezing folded the tone key back
//      to a literal and showed raw "cosaaaa"), the tone must stay inside the HEAD (free
//      marking otherwise drifts it onto the tail: "coáaaa"), and the boundary must KEEP
//      the composition instead of auto-restoring the raw keystrokes.
//  (b) the OPEN rime "ie" is a valid syllable (SyllableValidator), so "bies"→bíe,
//      "miej"→mịe commit as rendered with no special boundary rule at all.
//
// Everything runs with the shipped defaults for this feature: autoRestore + freeMarking
// + liveSpellCheck all ON.
final class TeencodeTests: XCTestCase {

    private func engine() -> TelexEngine {
        var e = TelexEngine()
        e.freeMarking = true
        e.liveSpellCheck = true
        return e
    }

    private func commit(_ keys: String) -> String {
        var e = engine()
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    /// Screen state after typing `keys` (what the user is looking at mid-word).
    // MARK: Field case 19/08/2026 — "wise.com"→"wíe.com" (Simple Telex) + "www"→"ww"

    private func commitSimple(_ keys: String) -> String {
        var e = engine()
        e.simpleTelex = true
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    func testTeencodeOnsetDoesNotStackWithTeencodeRime() {
        // Simple Telex: w là chữ w thật, s/f giữa từ vẫn là phím dấu → "wise" compose
        // ra "wíe", "wife" ra "wìe". Trước fix, onset teencode (w→qu) CHỒNG rime
        // teencode ("ie") cho "quíe/quìe" validate → boundary giữ nguyên chữ hỏng.
        // Một từ chỉ được MỘT đặc cách teencode: chồng hai cái → invalid → restore raw.
        XCTAssertEqual(commitSimple("wise"), "wise")
        XCTAssertEqual(commitSimple("wife"), "wife")
        // Full Telex cùng chuỗi phím đã restore đúng từ trước — pin làm đối chứng.
        XCTAssertEqual(commit("wise"), "wise")
        XCTAssertEqual(commit("wife"), "wife")
        // Mỗi đặc cách RIÊNG LẺ vẫn sống nguyên:
        XCTAssertEqual(commitSimple("was"), "wá")     // onset teencode + rime thường ("wá" = quá)
        XCTAssertEqual(commit("bies"), "bíe")         // rime teencode + onset thường
        XCTAssertEqual(commit("miej"), "mịe")
    }

    // MARK: Teencode "đou" — đúng MỘT TỪ, không phải một vần (maintainer 19/08/2026)

    func testTeencodeDouIsAWordNotARime() {
        // "đou" giữ nguyên ở boundary; scope là đúng từ này (onset đ + ou, không thanh).
        XCTAssertEqual(commit("ddou"), "đou")
        XCTAssertEqual(commit("ddoi"), "đoi")                 // vần thật kế bên không đổi
        // Vì sao KHÔNG phải một vần: đưa "ou" vào bảng rime là (a) họ -our tiếng Anh
        // chết (hour→hỏu — r là phím hỏi), (b) vào luôn prefix table làm
        // live-spell-check hết freeze họ -ous/-ouse (house→hóue; quét từ điển:
        // miss Simple Telex 111→3896). Pin đủ bộ để ai "nâng cấp thành vần" phải qua đây.
        for w in ["hour", "sour", "tour", "pour", "dour", "house", "ddous"] {
            XCTAssertEqual(commit(w), w, "\(w) phải restore — ou không phải vần")
        }
        XCTAssertEqual(commitSimple("house"), "house")
        // Có thanh thì không còn là "đou" → restore raw ("đóu" chưa hỗ trợ, chủ đích).
        XCTAssertEqual(commit("ddouj"), "ddouj")
    }

    func testAllWWordRestoresAtBoundary() {
        // "www" là prefix URL, không phải escape: gõ live ww→w giữ nguyên (user
        // decision 22/07) nhưng boundary phải trả đủ chữ — trước fix "www." chốt
        // thành "ww." (mất một w). Từ 2 phím (ww) vẫn là escape đúng nghĩa.
        XCTAssertEqual(commit("www"), "www")
        XCTAssertEqual(commit("wwww"), "wwww")
        XCTAssertEqual(commitSimple("www"), "www")    // Simple Telex: vốn literal, không đổi
        XCTAssertEqual(commit("ww"), "w")             // escape 2 phím giữ nguyên hành vi cũ
    }

    private func screen(_ keys: String) -> String {
        var e = engine()
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    // MARK: - The nine field examples

    func testElongationCommits() {
        // Tail letter counts follow doubler-cancel semantics: a mark doubler eats one key
        // (aa→â) and the third key cancels it back to two literal letters, so 7 typed a's
        // land as 6 ("cosaaaaaaa"); a consonant tail has no doubler, so every key lands.
        XCTAssertEqual(commit("ajaaaaaaaaa"), "ạaaaaaaaa")
        XCTAssertEqual(commit("hoonggggg"), "hônggggg")
        XCTAssertEqual(commit("vaanggggg"), "vânggggg")
        XCTAssertEqual(commit("cosaaaaaaa"), "cóaaaaaa")
        XCTAssertEqual(commit("quafaaaa"), "quàaaa")
        XCTAssertEqual(commit("ddepjpppp"), "đẹppppp")
        // Already worked before the feature — must not regress (no transform at all).
        XCTAssertEqual(commit("xinnnn"), "xinnnn")
    }

    func testIeRimeCommits() {
        XCTAssertEqual(commit("bies"), "bíe")
        XCTAssertEqual(commit("miej"), "mịe")
        // Same class, other tones / onsets.
        XCTAssertEqual(commit("thies"), "thíe")
        XCTAssertEqual(commit("mief"), "mìe")
        // Toneless "ie" was already committed verbatim (nothing transforms) — pinned so
        // the new rime can't change it.
        XCTAssertEqual(commit("die"), "die")
        XCTAssertEqual(commit("tie"), "tie")
        XCTAssertEqual(commit("lie"), "lie")
        // Closed "ie" rimes stay OUT of the table: their real spelling is iê, so English
        // keeps restoring.
        XCTAssertEqual(commit("diet"), "diet")
        XCTAssertEqual(commit("field"), "field")
        XCTAssertEqual(commit("client"), "client")
        XCTAssertEqual(commit("science"), "science")
    }

    /// Rule (a) on top of rule (b): the elongation head may itself be an "ie" syllable.
    func testElongatedIeSyllable() {
        XCTAssertEqual(commit("bieseee"), "bíeee")
        XCTAssertEqual(commit("bieseeee"), "bíeeee")
    }

    // MARK: - The freeze must not fire, and must re-evaluate

    /// The word must be composed ON SCREEN while typing, not replayed as literal keys:
    /// the freeze used to fire at the first invalid point and fold the tone key back
    /// ("cosaaaa" on screen). One extra character is genuinely ambiguous, so the freeze
    /// still fires there; the run's third letter resolves it and the screen re-renders in
    /// ONE keystroke.
    func testFreezeReEvaluatesOnElongation() {
        XCTAssertEqual(screen("cos"), "có")
        XCTAssertEqual(screen("cosa"), "cóa")          // still a plausible prefix
        XCTAssertEqual(screen("cosaa"), "coấ")         // the aa doubler fired
        XCTAssertEqual(screen("cosaaa"), "cosaa")      // cancel + run of 2: could be a typo
        XCTAssertEqual(screen("cosaaaa"), "cóaaa")     // run of 3 ⇒ unfrozen, tone back
        XCTAssertEqual(screen("cosaaaaa"), "cóaaaa")
        // Same for a consonant tail with a pending tone (the j must never fold to 'j').
        XCTAssertEqual(screen("ddepjppp"), "đẹpppp")
        XCTAssertEqual(screen("ddepjpppp"), "đẹppppp")
        // And for the doubler-cancel path.
        XCTAssertEqual(screen("ajaaaa"), "ạaaa")
    }

    /// The tone belongs to the HEAD: free marking would otherwise drift it onto the
    /// first tail vowel ("coáaaa", "aạaaa").
    func testTonePlacementStaysInHead() {
        XCTAssertEqual(screen("cosaaaaaa"), "cóaaaaa")
        XCTAssertEqual(screen("ajaaaaaa"), "ạaaaaa")
        XCTAssertEqual(screen("quafaaaa"), "quàaaa")
    }

    /// ⌫ over an elongation tail must stay in sync: each backspace removes exactly one
    /// displayed character, and the freeze/tone state is recomputed for the shorter word
    /// (no retroactive re-marking, no desync with the screen).
    func testBackspaceOverElongationTail() {
        var e = engine()
        for ch in "cosaaaaa" { _ = e.feed(ch) }
        XCTAssertEqual(e.composed, "cóaaaa")
        // Each step is EXACTLY what forward typing shows at that length (see
        // testFreezeReEvaluatesOnElongation) — ⌫ replays the freeze, it never lifts it.
        let expected = ["cóaaa", "cosaa", "coấ", "co", "c", ""]
        for want in expected {
            _ = e.backspace()
            XCTAssertEqual(e.composed, want, "⌫ desync")
        }
    }

    /// commitBoundary (event-tap client) must agree with commitText (marked-text client)
    /// on every teencode word — a keep is `.none`, never a partial rewrite.
    func testBoundaryActionsAgree() {
        for keys in ["ajaaaaaaaaa", "hoonggggg", "vaanggggg", "cosaaaaaaa", "quafaaaa",
                     "bies", "miej", "xinnnn", "ddepjpppp", "bieseee"] {
            var e = engine()
            for ch in keys { _ = e.feed(ch) }
            let composedBefore = e.composed
            let peek = e.peekCommitText(autoRestore: true)
            let action = e.commitBoundary(autoRestore: true)
            XCTAssertEqual(peek, composedBefore, "\(keys): teencode must keep the screen")
            switch action {
            case .none: break
            default: XCTFail("\(keys): boundary must not rewrite a kept teencode word")
            }
        }
    }

    // MARK: - Guards: nothing else may change

    /// Auto-restore's flagship cases and the English protections must be untouched.
    func testEnglishGuards() {
        XCTAssertEqual(commit("retore"), "retore")
        XCTAssertEqual(commit("google"), "google")
        // "his" is a KNOWN pre-existing miss of the collision table (hí wins without
        // context; the English-context feature is what restores it) — pinned to prove
        // teencode changed nothing here.
        XCTAssertEqual(commit("his"), "hí")
        XCTAssertEqual(commit("excess"), "excess")
        XCTAssertEqual(commit("vibes"), "vibes")
        // Screen-truth trailing cancel (POLICY V2, 2026-07-31) — untouched.
        XCTAssertEqual(commit("pass"), "pas")
    }

    /// English DOUBLES letters, it never triples them — that is why the elongation run
    /// must be ≥ 3. These all restore (a run of 2 is not an elongation).
    func testDoubledEnglishStillRestores() {
        for w in ["wall", "walls", "watt", "watts", "will", "wifi",
                  "balls", "bills", "calls", "cells", "eggs", "apps", "inns", "ascii"] {
            XCTAssertEqual(commit(w), w, "\(w): a run of 2 must not read as elongation")
        }
    }

    /// KNOWN COST of the "ie" rime (maintainer decision 2026-08-04): these English words
    /// now compose to a valid syllable and are NOT in the generated collision table, so
    /// they commit as Vietnamese. Pinned deliberately — if the table is ever regenerated
    /// (`swift run gen-english`) these flip back to raw and this test is the reminder to
    /// update the suite floor with them.
    /// The 12 English words whose Telex form became a VALID "ie" syllable were added
    /// to the collision table (gen-english extra-corpus, 2026-08-04, 757 → 769) so
    /// blind English typing stays protected — the dict check runs BEFORE the
    /// valid-syllable keep, so "dies" restores while teencode "bies" (not English)
    /// commits "bíe". NOTE: a FULL-corpus regeneration was tried and reverted — it
    /// swept in unvetted words that collide with real Vietnamese ("mays"≡máy,
    /// "vans"≡ván); only the curated monotone base + explicit extras is safe.
    func testIeRimeEnglishWordsAreDictProtected() {
        for w in ["dies", "ties", "lies", "tries", "life", "chief",
                  "rise", "tire", "tires", "tier", "hire", "mixer"] {
            XCTAssertEqual(commit(w), w, "'\(w)' must dict-restore")
        }
        // Teencode remains reachable: non-English "ie" syllables commit as seen.
        XCTAssertEqual(commit("bies"), "bíe")
        XCTAssertEqual(commit("miej"), "mịe")
    }

    /// Real Vietnamese must be unaffected by the tone-scope cap and the freeze escape.
    func testVietnameseUnaffected() {
        let pairs = [("tieengs", "tiếng"), ("nguwowif", "người"), ("dduowcj", "được"),
                     ("vieejt", "việt"), ("hoaf", "hòa"), ("thuyr", "thủy"),
                     ("xinnn", "xinnn"), ("khoong", "không"), ("ddepj", "đẹp"),
                     ("hoon", "hôn"), ("vaang", "vâng"), ("cos", "có")]
        for (keys, want) in pairs {
            XCTAssertEqual(commit(keys), want, keys)
        }
    }

    /// Mode-agnostic: VNI types the same teencode shapes with digit tone keys.
    func testVniTeencode() {
        func commitVNI(_ keys: String) -> String {
            var e = TelexEngine()
            e.vniMode = true
            e.freeMarking = true
            e.liveSpellCheck = true
            for ch in keys { _ = e.feed(ch) }
            return e.commitText(autoRestore: true)
        }
        XCTAssertEqual(commitVNI("bie1"), "bíe")        // sắc via VNI 1
        XCTAssertEqual(commitVNI("mie5"), "mịe")        // nặng via VNI 5
        // VNI has no letter doubler (marks are digits 6-9), so every typed a lands —
        // one more than the Telex spelling "cosaaaaaaa" produces.
        XCTAssertEqual(commitVNI("co1aaaaaaa"), "cóaaaaaaa")
        XCTAssertEqual(commitVNI("ho6nggggg"), "hônggggg")
        XCTAssertEqual(commitVNI("va6nggggg"), "vânggggg")
    }
}

// TEENCODE "òy" (maintainer 07/08/2026): vần mở "oy" ĐỨNG MỘT MÌNH là âm tiết
// hợp lệ — chat spelling của "òi/rồi" ("òy", "óy"…). Zero onset CÓ CHỦ ĐÍCH:
// bless "b/t/j + oy" là "boys"/"toys" tiếng Anh thành "bóy"/"tóy" ngay khi s
// đáp xuống. Muốn nới (vd "gòy") phải review collision tiếng Anh trước.
final class TeencodeOyTests: XCTestCase {

    private func run(_ keys: String) -> String {
        var e = TelexEngine()
        e.freeMarking = true
        e.liveSpellCheck = true
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    func testStandaloneOyTakesTonesLikeOi() {
        XCTAssertEqual(run("oyf"), "òy")
        XCTAssertEqual(run("oys"), "óy")
        XCTAssertEqual(run("oyj"), "ọy")
        XCTAssertEqual(run("oyr"), "ỏy")
    }

    func testUppercaseVariant() {
        XCTAssertEqual(run("Oyf"), "Òy")
    }

    func testEnglishOnsetWordsAreUntouched() {
        // Onset chặn vần "oy": các từ tiếng Anh phổ biến không được biến hình.
        XCTAssertEqual(run("boys"), "boys")
        XCTAssertEqual(run("toys"), "toys")
        XCTAssertEqual(run("joys"), "joys")
        XCTAssertEqual(run("oyster"), "oyster")
    }

    func testValidatorScopeIsZeroOnsetOnly() {
        XCTAssertTrue(SyllableValidator.isValidSyllable("òy"))
        XCTAssertTrue(SyllableValidator.isValidSyllable("oy"))
        XCTAssertFalse(SyllableValidator.isValidSyllable("bòy"))
        XCTAssertFalse(SyllableValidator.isValidSyllable("gòy"), "nới gòy cần review collision trước")
        XCTAssertTrue(SyllableValidator.isValidPrefix("oy"))
        XCTAssertFalse(SyllableValidator.isValidPrefix("oyt"), "đuôi dài hơn vẫn freeze như cũ")
    }
}

// TEENCODE/interjection "ưm ưn" (maintainer 12/08/2026): "uwm"→ưm, "uwmf"→ừm
// (uh-hứm), "uwn"→ưn ("ưng"). Vào thẳng bảng rime (mọi onset — "hừm" đi kèm),
// KHÁC 'oy' zero-onset: vần này đòi mark w tường minh (ư) nên không từ tiếng Anh
// bare-ascii nào lạc vào được — muốn tới "ưm" phải gõ đúng chuỗi "uw"+"m".
final class TeencodeUmUnTests: XCTestCase {

    private func run(_ keys: String) -> String {
        var e = TelexEngine()
        e.freeMarking = true
        e.liveSpellCheck = true
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    func testStandaloneUmUnCompose() {
        XCTAssertEqual(run("uwm"), "ưm")
        XCTAssertEqual(run("uwn"), "ưn")
    }

    func testTonesOnUm() {
        XCTAssertEqual(run("uwmf"), "ừm")
        XCTAssertEqual(run("uwms"), "ứm")
        XCTAssertEqual(run("uwmj"), "ựm")
        XCTAssertEqual(run("uwnf"), "ừn")
    }

    func testUppercaseVariant() {
        XCTAssertEqual(run("Uwmf"), "Ừm")
    }

    func testOnsetsRideAlong() {
        // Bảng rime bless mọi onset — hừm/hửm là từ cảm thán thật.
        XCTAssertEqual(run("huwmf"), "hừm")
        XCTAssertEqual(run("huwmr"), "hửm")
    }

    func testValidatorAcceptsNewRimes() {
        XCTAssertTrue(SyllableValidator.isValidSyllable("ưm"))
        XCTAssertTrue(SyllableValidator.isValidSyllable("ừm"))
        XCTAssertTrue(SyllableValidator.isValidSyllable("ưn"))
        XCTAssertFalse(SyllableValidator.isValidSyllable("ưnh"), "chỉ thêm ưm/ưn, không thêm ưnh")
    }

    func testEnglishStaysUntouched() {
        // Không có 'uw' + m/n trong tiếng Anh thường — các từ un/um thật không đổi.
        XCTAssertEqual(run("unwind"), "unwind")
        XCTAssertEqual(run("umbrella"), "umbrella")
        XCTAssertEqual(run("column"), "column")
    }
}
