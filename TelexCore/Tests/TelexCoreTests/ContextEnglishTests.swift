import XCTest
@testable import TelexCore

// Context-based decision (engine.contextualEnglish, EXPERIMENTAL). After an English
// word, an AMBIGUOUS next word — composition is a valid Vietnamese syllable but the raw
// keys spell an English word — is restored to English. After a Vietnamese/undetermined
// word it stays Vietnamese. "he is" → "he is"; "sao í" (keys "sao is") → "sao í".

/// Type a space-separated sentence, committing each word at its boundary (like the
/// controller does), and return the committed words rejoined with spaces.
private func sentence(_ s: String, context: Bool) -> String {
    var e = TelexEngine()
    e.liveSpellCheck = true          // shipped default; needed for clean disambiguation
    e.contextualEnglish = context
    var words: [String] = []
    var wroteCurrent = false
    for ch in s {
        if ch == " " {
            words.append(e.commitText(autoRestore: true)); wroteCurrent = false
        } else {
            _ = e.feed(ch); wroteCurrent = true
        }
    }
    if wroteCurrent || words.isEmpty { words.append(e.commitText(autoRestore: true)) }
    return words.joined(separator: " ")
}

final class ContextEnglishTests: XCTestCase {

    // MARK: The examples from the spec

    func testEnglishRunPrefersEnglish() {
        // "is" alone composes "í"; after an English word it must stay "is".
        XCTAssertEqual(sentence("he is", context: true), "he is")
        XCTAssertEqual(sentence("she is", context: true), "she is")
        XCTAssertEqual(sentence("it is", context: true), "it is")
    }

    // Case is preserved and does not affect English detection (raw is lowercased for
    // the dictionary lookup): "He is" → "He is", "HE IS" → "HE IS".
    func testUppercaseEnglishRun() {
        XCTAssertEqual(sentence("He is", context: true), "He is")
        XCTAssertEqual(sentence("She is", context: true), "She is")
        XCTAssertEqual(sentence("It is", context: true), "It is")
        XCTAssertEqual(sentence("HE IS", context: true), "HE IS")
        XCTAssertEqual(sentence("He Is", context: true), "He Is")
        // Capitalised Vietnamese word → the next ambiguous word stays Vietnamese.
        XCTAssertEqual(sentence("Sao is", context: true), "Sao í")
        // Off: unchanged (composes the Vietnamese "Í").
        XCTAssertEqual(sentence("He is", context: false), "He í")
    }

    func testVietnameseOrUnknownKeepsVietnamese() {
        // After a valid Vietnamese word, the ambiguous word stays Vietnamese.
        XCTAssertEqual(sentence("sao is", context: true), "sao í")
        // A Vietnamese word BREAKS the English run (context = immediate previous word).
        XCTAssertEqual(sentence("he sao is", context: true), "he sao í")
    }

    // MARK: The gate — OFF must not change anything

    func testOffLeavesTelexUnchanged() {
        // With the feature off, "is" stays the Vietnamese "í" even after English.
        XCTAssertEqual(sentence("he is", context: false), "he í")
        XCTAssertEqual(sentence("she is", context: false), "she í")
        XCTAssertEqual(sentence("sao is", context: false), "sao í")
        // On or off, a genuinely Vietnamese sentence is identical.
        XCTAssertEqual(sentence("toi yeu em", context: true),
                       sentence("toi yeu em", context: false))
    }

    // MARK: previousWordEnglish classification + resetContext

    func testPreviousWordClassification() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        XCTAssertTrue(e.previousWordEnglish, "\"he\" should seed English context")
        for ch in "sao" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        XCTAssertFalse(e.previousWordEnglish, "\"sao\" is Vietnamese → context cleared")
        // "she" is not a valid VN syllable → English by structure alone.
        for ch in "she" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        XCTAssertTrue(e.previousWordEnglish)
        // resetContext wipes it (focus / app switch).
        e.resetContext()
        XCTAssertFalse(e.previousWordEnglish)
    }

    // No preceding word (fresh field, or after a newline/new prompt which the controller
    // signals via resetContext) → the ambiguous word stays Vietnamese.
    func testNoPreviousWordKeepsVietnamese() {
        XCTAssertEqual(sentence("is", context: true), "í")          // very first word
        // English word, then a newline (resetContext), then "is" → "í" on the new line.
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }; _ = e.commitText(autoRestore: true)
        e.resetContext()                                            // newline / new prompt
        for ch in "is" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "í")
    }

    // MARK: Field report 15/08/2026 — "early too⏎" gửi thành "early tô" (WhatsApp)
    //
    // ORDER INVARIANT for the controllers' newline handling: resetContext() belongs
    // AFTER the boundary commit, never before. Both controllers had a Swift
    // defer-scope bug (`if newline { defer { resetContext() } }` fires immediately)
    // that wiped the "early = English" context BEFORE the restore decision, so Enter
    // committed "tô" while space restored "too". These two tests pin each order.
    func testNewlineResetAfterCommitKeepsEnglishRestore() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "early" { _ = e.feed(ch) }; _ = e.commitText(autoRestore: true)
        for ch in "too" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "too")   // context intact → restored
        e.resetContext()                                          // Enter: reset AFTER commit
        for ch in "is" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "í")     // new line: run is broken
    }

    func testNewlineResetBeforeCommitLosesTheRestore() {
        // The buggy order, kept as documentation of WHY the invariant matters: reset
        // first and the same keystrokes ship the Vietnamese composition instead.
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "early" { _ = e.feed(ch) }; _ = e.commitText(autoRestore: true)
        for ch in "too" { _ = e.feed(ch) }
        e.resetContext()                                          // ← the defer-scope bug
        XCTAssertEqual(e.commitText(autoRestore: true), "tô")
    }

    // Context does not leak across a resetContext(): "he" then reset then "is" → "í".
    func testResetContextBreaksTheRun() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        e.resetContext()
        for ch in "is" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "í")
    }

    // In-word backspace must NOT clear the context — the PREVIOUS word is unchanged, so a
    // fixed-up ambiguous word still resolves against it. (The controller resets context
    // only on an EMPTY-buffer backspace, i.e. deleting back into committed text.)
    func testInWordBackspaceKeepsContext() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }; _ = e.commitText(autoRestore: true)   // prev = English
        _ = e.feed("i"); _ = e.backspace()          // in-word edit of the next word
        XCTAssertTrue(e.previousWordEnglish, "in-word backspace must not clear context")
        for ch in "is" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "is")   // still after "he" → English
    }

    // Hand-vetted ambiguous words: English inside an English run, Vietnamese otherwise.
    func testHandVettedContextWords() {
        let pairs = [("runs", "rún"), ("songs", "sóng"), ("sons", "són"),
                     ("moms", "móm"), ("cams", "cám"), ("lens", "lén"), ("rays", "ráy"),
                     ("vans", "ván"), ("bans", "bán"), ("tins", "tín"), ("tans", "tán"),
                     ("dams", "dám"), ("hams", "hám"), ("thus", "thú")]
        for (en, vn) in pairs {
            XCTAssertEqual(sentence(en, context: true), vn, "\(en) with no English before → \(vn)")
            XCTAssertEqual(sentence("she \(en)", context: true), "she \(en)", "she \(en) → English")
        }
        // "loans" is already an unconditional English-collision word → always English.
        XCTAssertEqual(sentence("loans", context: true), "loans")
        XCTAssertEqual(sentence("she loans", context: true), "she loans")
        // list→lít: Vietnamese loanword (litre) when alone; English only inside
        // an English run (stays on the context whitelist, off the collision table).
        XCTAssertEqual(sentence("list", context: true), "lít")
        XCTAssertEqual(sentence("she list", context: true), "she list")
        XCTAssertEqual(sentence("toi list nuoc", context: true), "toi lít nuoc")
    }

    // Vietnamese loanwords (email/app/web) are NEUTRAL: they don't open an English run,
    // but they preserve one already open.
    func testLoanwordsAreNeutral() {
        XCTAssertEqual(sentence("email bans hangf", context: true), "email bán hàng")
        XCTAssertEqual(sentence("app bans", context: true), "app bán")
        XCTAssertEqual(sentence("the email is", context: true), "the email is")
    }

    // Interjections / greetings / politeness markers must NOT open an English run —
    // Vietnamese speakers use them to start Vietnamese sentences.
    func testInterjectionsDoNotSeedEnglish() {
        XCTAssertEqual(sentence("ok cams own", context: true), "ok cám ơn")
        XCTAssertEqual(sentence("ok hats", context: true), "ok hát")
        XCTAssertEqual(sentence("sorry nha", context: true), "sorry nha")
        XCTAssertEqual(sentence("thanks em", context: true), "thanks em")
        XCTAssertEqual(sentence("hi cac banj", context: true), "hi cac bạn")
        // …while genuine grammatical English still opens the run.
        XCTAssertEqual(sentence("he bans", context: true), "he bans")
    }

    // …but INSIDE an English run those same interjections must come back as English
    // (EnglishContextWords.restoreOnly). Field report 2026-07-26: "that's great wow"
    // committed "wơ" in Simple Telex (literal w + ow→ơ, and "wơ" validates through the
    // teencode w→qu fold as "quơ", so plain validity can't catch it).
    func testInterjectionsRestoreInsideAnEnglishRun() {
        var e = TelexEngine()
        e.liveSpellCheck = true; e.simpleTelex = true; e.contextualEnglish = true
        for ch in "great" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "great")
        for ch in "wow" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "wow")
        // Standing alone (no English run) the teencode reading still wins.
        var v = TelexEngine(); v.liveSpellCheck = true; v.simpleTelex = true; v.contextualEnglish = true
        for ch in "wow" { _ = v.feed(ch) }
        XCTAssertEqual(v.commitText(autoRestore: true), "wơ")
        // And they still must not OPEN a run: the word after stays Vietnamese.
        XCTAssertEqual(sentence("wow ddepj quas", context: true), "wow đẹp quá")
    }

    // A whitelist word that renders Vietnamese (bans→bán after a Vietnamese word) seeds
    // VIETNAMESE — the following ambiguous word must stay Vietnamese, not flip.
    func testRenderedVietnameseSeedsVietnamese() {
        XCTAssertEqual(sentence("toi bans is", context: true), "toi bán í")
    }

    func testSpecPhrases() {
        XCTAssertEqual(sentence("she thus", context: true), "she thus")
        XCTAssertEqual(sentence("their moms", context: true), "their moms")
        // …and each stays Vietnamese with the feature OFF.
        XCTAssertEqual(sentence("she thus", context: false), "she thú")
        XCTAssertEqual(sentence("their moms", context: false), "their móm")
    }

    // Clearly-Vietnamese words are NEVER flipped, even mid English run (no ambiguity).
    func testUnambiguousVietnameseNeverFlips() {
        // "he được" — "được" has no English spelling, stays Vietnamese after English.
        XCTAssertEqual(sentence("he dduowcj", context: true), "he được")
        // "he tieengs" → "he tiếng" (valid VN, not an English word → not flipped).
        XCTAssertEqual(sentence("he tieengs", context: true), "he tiếng")
    }
}

// Field report 2026-08-14 (maintainer): "position is not okay" → "position í not
// okay" with the feature ON. "position" is untouched plain ascii (the validator
// refuses to compose it, which is also exactly why the collision table can't carry
// it), and the classifier's old default called every unrecognized ascii word
// Vietnamese. Now the same validator that blocked composition decides the context:
// structurally-impossible Vietnamese opens an English run.
final class ContextEnglishFieldReportTests: XCTestCase {
    func testPositionSeedsEnglishContext() {
        XCTAssertEqual(sentence("position is not okay", context: true), "position is not okay")
        XCTAssertEqual(sentence("github is", context: true), "github is")
        XCTAssertEqual(sentence("Position is", context: true), "Position is")   // case-blind
    }

    /// The other half of the tradeoff must not move: toneless-Vietnamese words that
    /// ARE valid syllables keep the context Vietnamese.
    func testTonelessVietnameseStillKeepsVietnameseContext() {
        XCTAssertEqual(sentence("sao is", context: true), "sao í")
        XCTAssertEqual(sentence("khong is", context: true), "khong í")
    }

    /// Field report 2026-08-14 #2: "thiss is" → "this í". The doubled `s` ESCAPES the
    /// tone, so the screen shows plain ascii "this" — but the classifier's first branch
    /// asked "does the composition differ from the raw keys?", which a cancelled
    /// transform also satisfies, and called it Vietnamese. The question it meant to ask
    /// is "is a diacritic on screen?".
    func testEscapedEnglishWordSeedsEnglishContext() {
        XCTAssertEqual(sentence("thiss is", context: true), "this is")
        XCTAssertEqual(sentence("gooogle is", context: true), "google is")
        XCTAssertEqual(sentence("tessted is", context: true), "tested is")
        // Escaped LOANWORD stays NEUTRAL: it must not open a run, so a following
        // Vietnamese word still composes. "wweb" is the real escape here — a lone `w`
        // composes ư, so the doubled w is how "web" gets typed in full Telex.
        XCTAssertEqual(sentence("wweb bans", context: true), "web bán")
    }

    /// The escape fix must not weaken the Vietnamese side: a word whose composition
    /// really does carry a diacritic still ends any English run.
    func testDiacriticOnScreenStillEndsTheRun() {
        XCTAssertEqual(sentence("he thoi is", context: true), "he thoi í")
        XCTAssertEqual(sentence("he thois is", context: true), "he thói í")
    }
}
