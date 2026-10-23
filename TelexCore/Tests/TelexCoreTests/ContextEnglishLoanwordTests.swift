import XCTest
@testable import TelexCore

// Field report 11/10/2026: "suggestion been treen" → "suggestion been trên"; the user
// wanted "suggestion bên trên" and could not get it. The lone English noun opened an
// English run (structural fallback) and "been" was restored. Fix (maintainer-approved):
//  1. ONE English content word no longer opens a run — only a function word
//     (EnglishContextWords.functionWords) or two English words in a row do;
//  2. "been" restores only right after have/has/had/having/'ve
//     (EnglishContextWords.predecessorGates).

/// Type `s` word by word. Space and apostrophe are word boundaries emitted literally —
/// what the controllers do ("I've" → commit "I", insert ', word "ve").
/// `app` = AppState.EngineFlags defaults; otherwise TelexCore defaults + context ON.
private func typed(_ s: String, app: Bool = true) -> String {
    var e = TelexEngine()
    e.liveSpellCheck = true
    e.contextualEnglish = true
    if app {
        e.freeMarking = true
        e.collisionPrefersVietnamese = true
    }
    var out = ""
    for ch in s {
        if ch == " " || ch == "'" {
            out += e.commitText(autoRestore: true)
            out.append(ch)
        } else {
            _ = e.feed(ch)
        }
    }
    return out + e.commitText(autoRestore: true)
}

final class ContextEnglishLoanwordTests: XCTestCase {

    /// Tên app (Phil 18/10/2026): "viettelex" / "telex" gõ ra nguyên văn — không bị Telex hoá (x = dấu ngã,
    /// ee = ê) — cả giữa câu Việt lẫn sau một từ tiếng Anh.
    func testAppNameStaysLiteral() {
        XCTAssertEqual(typed("viettelex"), "viettelex")
        XCTAssertEqual(typed("booj gox viettelex"), "bộ gõ viettelex")
        XCTAssertEqual(typed("the viettelex app"), "the viettelex app")
        XCTAssertEqual(typed("kieeur telex"), "kiểu telex")
        XCTAssertEqual(typed("viettelex", app: false), "viettelex")
        XCTAssertEqual(typed("Phil trinh"), "Phil trinh", "tên tác giả: trinh không dấu")
    }

    func testFieldReportSuggestionBenTren() {
        XCTAssertEqual(typed("suggestion been treen"), "suggestion bên trên")
        XCTAssertEqual(typed("suggestion been treen", app: false), "suggestion bên trên")
    }

    /// Vietnamese sentences with an English loanword (content word) stay Vietnamese.
    func testLoanwordInVietnameseSentenceDoesNotOpenRun() {
        XCTAssertEqual(typed("file leen"), "file lên")
        XCTAssertEqual(typed("commit leen github"), "commit lên github")
        XCTAssertEqual(typed("deploy xong"), "deploy xong")
        XCTAssertEqual(typed("review beenf"), "review bền")
        XCTAssertEqual(typed("review been kia"), "review bên kia")
        XCTAssertEqual(typed("meeting is"), "meeting í")
        XCTAssertEqual(typed("deadline as em"), "deadline á em")
        XCTAssertEqual(typed("feedback been duwowis"), "feedback bên dưới")
        XCTAssertEqual(typed("bug been trong"), "bug bên trong")
        // A Vietnamese word between two loanwords clears the candidate: still no run.
        XCTAssertEqual(typed("push xong merge is"), "push xong merge í")
    }

    /// Two English words in a row DO open the run; a function word opens it at once.
    func testTwoEnglishWordsOrFunctionWordOpenRun() {
        XCTAssertEqual(typed("fix bug is", app: false), "fix bug is")
        XCTAssertEqual(typed("github repo is", app: false), "github repo is")
        XCTAssertEqual(typed("he is", app: false), "he is")
        XCTAssertEqual(typed("he is"), "he is")
        XCTAssertEqual(typed("what is"), "what is")
        XCTAssertEqual(typed("the list", app: false), "the list")
        XCTAssertEqual(typed("the list"), "the list")
        // Neutral loanwords preserve the candidate ("deploy app" is not a run yet, but a
        // second English content word after it is).
        XCTAssertEqual(typed("deploy app is"), "deploy app í")
        XCTAssertEqual(typed("deploy app script is"), "deploy app script is")
    }

    /// An open run carries through content words and ends at a Vietnamese word.
    func testRunCarriesThroughContentWords() {
        XCTAssertEqual(typed("I fixed the bug in this file", app: false), "I fixed the bug in this file")
        XCTAssertEqual(typed("I fixed the bug in this file"), "I fixed the bug in this file")
        XCTAssertEqual(typed("and this is"), "and this is")
        XCTAssertEqual(typed("he fixed it xong roi is"), "he fixed it xong roi í")
    }

    /// "been" ⇔ "bên": English only right after a form of "have".
    func testBeenNeedsHavePredecessor() {
        XCTAssertEqual(typed("it has been", app: false), "it has been")
        XCTAssertEqual(typed("it has been"), "it has been")
        XCTAssertEqual(typed("I have been there", app: false), "I have been there")
        XCTAssertEqual(typed("I have been there"), "I have been there")
        XCTAssertEqual(typed("they had been"), "they had been")
        XCTAssertEqual(typed("having been"), "having been")
        XCTAssertEqual(typed("I've been there"), "I've been there")
        XCTAssertEqual(typed("we've been"), "we've been")
        // Inside a run but NOT after have: Vietnamese.
        XCTAssertEqual(typed("he been", app: false), "he bên")
        XCTAssertEqual(typed("the been"), "the bên")
        // A neutral word in between breaks the adjacency.
        XCTAssertEqual(typed("it has email been"), "it has email bên")
    }

    /// Contraction tails are neutral: they neither open a run nor end one.
    func testContractionTailsAreNeutral() {
        XCTAssertEqual(typed("you're is"), "you're is")
        XCTAssertEqual(typed("ve is"), "ve í")
    }

    /// Case-insensitive like the rest of the context tables.
    func testCaseInsensitive() {
        XCTAssertEqual(typed("It Has Been", app: false), "It Has Been")
        XCTAssertEqual(typed("Suggestion Been treen"), "Suggestion Bên trên")
    }

    /// Unchanged first-word behaviour (no context yet), pinned so the report is honest:
    /// a sentence-initial "this" (thí, deliberately not in the collision table) and "is"
    /// (í) stay Vietnamese with or without this fix; the word AFTER them is English.
    func testSentenceInitialAmbiguousWordsUnchanged() {
        XCTAssertEqual(typed("this is"), "thí í")
        XCTAssertEqual(typed("thiss is"), "this is")
        XCTAssertEqual(typed("is it"), "í it")
    }

    /// Re-opening a word (⌫ on the boundary) must compose against the full context the
    /// word saw — candidate and predecessor gate included.
    func testReopenRestoresCandidateAndGate() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "it" { _ = e.feed(ch) }; _ = e.commitBoundary(autoRestore: true)
        for ch in "has" { _ = e.feed(ch) }; _ = e.commitBoundary(autoRestore: true)
        for ch in "bee" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "bê")      // kept → re-openable
        XCTAssertNotNil(e.reopenLastCommit())
        _ = e.feed("n")
        XCTAssertEqual(e.commitText(autoRestore: true), "been")    // gate still satisfied

        var f = TelexEngine(); f.liveSpellCheck = true; f.contextualEnglish = true
        for ch in "fix" { _ = f.feed(ch) }; _ = f.commitBoundary(autoRestore: true)
        XCTAssertFalse(f.previousWordEnglish)                      // candidate only
        for ch in "bu" { _ = f.feed(ch) }; _ = f.commitBoundary(autoRestore: true)
        XCTAssertFalse(f.previousWordEnglish)                      // "bu" is Vietnamese
        XCTAssertNotNil(f.reopenLastCommit())
        _ = f.feed("g")
        _ = f.commitBoundary(autoRestore: true)
        XCTAssertTrue(f.previousWordEnglish)                       // fix + bug = run
    }

    /// External (swiped) words: function words open, content words are candidates.
    func testNoteExternalWord() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        e.noteExternalWord("suggestion", english: true)
        XCTAssertFalse(e.previousWordEnglish)
        for ch in "been" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "bên")

        e.resetContext()
        e.noteExternalWord("it", english: true)
        XCTAssertTrue(e.previousWordEnglish)
        e.noteExternalWord("has", english: true)
        for ch in "been" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "been")

        e.resetContext()
        e.noteExternalWord(english: true)                          // word unknown: content
        XCTAssertFalse(e.previousWordEnglish)
        e.noteExternalWord(english: true)                          // second English word
        XCTAssertTrue(e.previousWordEnglish)
        e.noteExternalWord(english: false)
        XCTAssertFalse(e.previousWordEnglish)
    }

    /// Table invariants: every function word is recognized English; the gate table is
    /// well-formed.
    func testTableInvariants() {
        for w in EnglishContextWords.functionWords {
            XCTAssertTrue(EnglishContextWords.words.contains(w) || EnglishCollisions.words.contains(w),
                          "function word \(w) must be recognized English")
        }
        XCTAssertFalse(EnglishContextWords.functionWords.contains("a"), "a is restore-only (#93)")
        XCTAssertEqual(EnglishContextWords.gateIndex(of: "been"), 0)
        XCTAssertNotEqual(EnglishContextWords.predecessorBits(of: "has"), 0)
        XCTAssertEqual(EnglishContextWords.predecessorBits(of: "is"), 0)
        XCTAssertLessThanOrEqual(EnglishContextWords.predecessorGates.count, 8)
    }

    /// Run keepers (23/10/2026): "box"/"car"/"mix" still compose Vietnamese, but inside an
    /// English run they no longer end it — the following function word stays English.
    func testRunKeeperDoesNotEndEnglishRun() {
        for app in [true, false] {
            XCTAssertEqual(typed("my car is here", app: app), "my cả is here")
            XCTAssertEqual(typed("it was a mix of both", app: app), "it was a mĩ of both")
            XCTAssertEqual(typed("the box is in the car", app: app), "the bõ is in the cả")
        }
        // Outside a run nothing changes: the keeper is Vietnamese and ends no run.
        XCTAssertEqual(typed("box is"), "bõ í")
        XCTAssertEqual(typed("car nhaf ow"), "cả nhà ơ")
        XCTAssertEqual(typed("ddi xe bus"), "đi xe bú")
    }

    /// "queue" → "quêu" passed the validator; restored in every context.
    func testQueueRestores() {
        for app in [true, false] {
            XCTAssertEqual(typed("queue", app: app), "queue")
            XCTAssertEqual(typed("put it in the queue", app: app), "put it in the queue")
        }
    }
}
