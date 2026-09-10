
import XCTest
@testable import TelexCore

/// Items 4-6 of the gonhanh-learnings batch: English-collision restore,
/// cancel-restore semantics, ethnic-name syllables. Golden, engine-validated.
final class EnglishCollisionTests: XCTestCase {
    private func commit(_ keys: String) -> String {
        var e = TelexEngine(); e.freeMarking = true
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }
    private func commitSimple(_ keys: String) -> String {
        var e = TelexEngine(); e.simpleTelex = true; e.freeMarking = true
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    func testCommonEnglishRestores() {
        // POLICY 2026-07-23: true collisions belong to Vietnamese now (his→hí,
        // this→thí, is→í, of→ò, if→ì, us→ú, has→há, days→dáy — protect list);
        // this golden keeps only the words whose spelling is NOT a natural
        // telex order, which stay English.
        for w in ["see", "or", "must", "last", "most", "does", "those",
                  "these", "there", "here", "test", "now"] where w != "now" {
            XCTAssertEqual(commit(w), w, "English '\(w)' must survive")
        }
        // list→lít: từ Việt phiên âm mượn (lít nước). Free-marking li+s+t
        // trùng chính tả English; tiếng Việt thắng (protect list), giống hits→hít.
        XCTAssertEqual(commit("list"), "lít")
        XCTAssertEqual(commit("lits"), "lít")
        XCTAssertEqual(commit("did"), "đi")
        XCTAssertEqual(commit("his"), "hí")
        XCTAssertEqual(commit("this"), "thí")
    }

    func testDoubleLetterEnglishFollowsCancelPosition() {
        // Screen-truth v2 (2026-07-31): TRAILING double = deliberate escape → the
        // screen wins, even for real English words (the old dict-first order made
        // literal "pas"/"of" untypeable). MID-WORD double = nobody escapes there →
        // the dict still restores the eaten letter.
        for (w, kept) in [("off", "of"), ("class", "clas"), ("pass", "pas"),
                          ("press", "pres"), ("less", "les"), ("boss", "bos"),
                          ("access", "acces"), ("process", "proces")] {
            XCTAssertEqual(commit(w), kept, "'\(w)': trailing cancel keeps the screen")
        }
        for w in ["office", "message", "business"] {
            XCTAssertEqual(commit(w), w, "'\(w)': mid-word double must dict-restore")
        }
        // "address" stays a restore: dd→đ leaves a mark the trailing cancel never
        // cleaned up ("ađres" on screen is mangled, not an escape) — the
        // composedHasDiacritic guard restores raw, as designed.
        XCTAssertEqual(commit("address"), "address")
        // a cancel outside the dict keeps the composed text
        XCTAssertEqual(commit("hoass"), "hoas")
    }

    // REACH-BACK tone cancel (2026-07-26): the killed tone key was typed keys
    // earlier, so that key is itself a letter the word lost → restore. Decided
    // STRUCTURALLY: none of these words is in EnglishCollisions.
    func testReachBackToneCancelRestoresWithoutDict() {
        for w in ["hosts", "asks", "discs", "buses"] {
            XCTAssertFalse(EnglishCollisions.words.contains(w), "'\(w)' should test the RULE, not the dict")
            XCTAssertEqual(commit(w), w, "'\(w)': reach-back tone cancel must restore")
        }
    }

    // An ADJACENT double is the ESCAPE gesture and the composed text always wins,
    // wherever it sits in the word — its keystrokes are identical to an English
    // double consonant ("tessted"→tested vs "office"→ofice), so only the dict can
    // tell them apart. Field reports 2026-07-26 (tessted) / 2026-07-22 (Deffault).
    func testAdjacentDoubleKeepsWhatTheScreenShows() {
        XCTAssertEqual(commit("tessted"), "tested")     // mid-word escape
        XCTAssertEqual(commit("Deffault"), "Default")
        XCTAssertEqual(commit("hoass"), "hoas")         // trailing escape
        XCTAssertEqual(commit("banhss"), "banhs")
        XCTAssertEqual(commit("iss"), "is")
        XCTAssertEqual(commit("aff"), "af")
        // MARK doublers: same escape, any position.
        XCTAssertEqual(commit("gooogle"), "google")
        XCTAssertEqual(commit("DDDR"), "DDR")
        // …and the dict is what recovers the words that only LOOK like an escape.
        for w in ["office", "possess", "assess", "offset", "message"] {
            XCTAssertEqual(commit(w), w, "'\(w)': dict must restore the eaten double")
        }
    }

    func testVietnameseProtectedWords() {
        // raw sequences shared with English where Vietnamese WINS (protect list)
        XCTAssertEqual(commit("sex"), "sẽ")
        XCTAssertEqual(commit("teen"), "tên")
        XCTAssertEqual(commit("been"), "bên")
        XCTAssertEqual(commit("own"), "ơn")
        XCTAssertEqual(commit("car"), "cả")
        XCTAssertEqual(commit("too"), "tô")
        XCTAssertEqual(commit("its"), "ít")
        XCTAssertEqual(commit("as"), "á")
        XCTAssertEqual(commit("low"), "lơ")
        XCTAssertEqual(commit("list"), "lít")
    }

    func testTeencodeSurvivesInSimpleTelex() {
        XCTAssertEqual(commitSimple("was"), "wá")   // w-guard: literal w = teencode
    }

    // Đ-initial chat abbreviations survive auto-restore (đ, đm, đc, đkm…).
    func testDdAbbreviations() {
        XCTAssertEqual(commit("dd"), "đ")
        XCTAssertEqual(commit("ddc"), "đc")
        XCTAssertEqual(commit("ddm"), "đm")
        XCTAssertEqual(commit("ddkm"), "đkm")
        XCTAssertEqual(commit("Ddm"), "Đm")
        // vowelled words keep the normal path (unchanged behavior)
        XCTAssertEqual(commit("ddi"), "đi")
        XCTAssertEqual(commit("ddieen"), "điên")
        // literal lowercase dd stays reachable via the cancel
        XCTAssertEqual(commit("ddd"), "dd")
    }

    func testEthnicNameSyllables() {
        XCTAssertEqual(commit("DDawks"), "Đắk")
        XCTAssertEqual(commit("Lawks"), "Lắk")
        XCTAssertEqual(commit("Kroong"), "Krông")
    }

    // Coda k follows the stop-coda tone rule (sắc/nặng only, like c):
    // toneless or huyền forms are invalid and restore to raw.
    func testCodaKToneRule() {
        XCTAssertEqual(commit("DDawk"), "DDawk")    // toneless ăk → invalid
        XCTAssertEqual(commit("lawkf"), "lawkf")    // huyền on stop coda → invalid
        XCTAssertEqual(commit("lawkj"), "lặk")      // nặng allowed
    }

    // MARK: - Collision-table mechanics (item 4)

    func testCollisionRestoreIsCaseInsensitive() {
        // his/this belong to Vietnamese since 2026-07-23 — case carries over
        XCTAssertEqual(commit("His"), "Hí")
        XCTAssertEqual(commit("THIS"), "THÍ")
        // Screen-truth v2 2026-07-31: trailing cancel wins — case still carries over.
        XCTAssertEqual(commit("Off"), "Of")
        XCTAssertEqual(commit("OFF"), "OF")
    }

    func testCollisionTableCanBeDisabled() {
        var e = TelexEngine()
        e.freeMarking = true
        e.englishWordRestore = false
        for ch in "his" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "hí")   // validator-only behavior
    }

    func testCollisionSkipsUntransformedWords() {
        // words the engine never touched can't be "restored" (and must not be):
        // no transform → composed == raw → commit is a no-op either way
        for w in ["me", "do", "go", "no", "to", "and", "the"] {
            XCTAssertEqual(commit(w), w)
        }
    }

    // Regression net for future `gen-english` runs: the generated table must
    // keep the pain words, and must NEVER contain a protected/junk raw.
    func testGeneratedTableSanity() {
        for expected in ["see", "test",
                         "off", "class", "office", "mess", "boss"] {
            XCTAssertTrue(EnglishCollisions.words.contains(expected), "table lost '\(expected)'")
        }
        // protected: Vietnamese wins these raw sequences (sẽ=sex, ơn=own…)
        for banned in ["sex", "teen", "been", "own", "car", "too", "its", "as",
                       "low", "now", "how", "room", "box", "air", "bar", "beer",
                       "bus", "lee", "max", "moon", "seen", "sir", "six", "tax", "ups",
                       "his", "this", "is", "of", "if", "us", "has", "thus", "queen",
                       "list"] {
            XCTAssertFalse(EnglishCollisions.words.contains(banned), "protected '\(banned)' leaked into the table")
        }
        // web-corpus junk that would eat Vietnamese typing (sw = sư)
        for junk in ["sw", "nw", "aa", "ee", "usr", "var", "www"] {
            XCTAssertFalse(EnglishCollisions.words.contains(junk), "junk '\(junk)' leaked into the table")
        }
        // minimal means minimal: a few hundred words, not a dictionary
        XCTAssertLessThan(EnglishCollisions.words.count, 1000)
        XCTAssertGreaterThan(EnglishCollisions.words.count, 80)
    }

    // MARK: - Cancel contract (item 5)

    func testCancelContractMatrix() {
        // FINAL contract (field report 2026-07-22): dict wins over everything;
        // otherwise a cancel ALWAYS keeps the composed text — the extra key was
        // pressed to undo an unwanted diacritic, maybe mid-word.
        XCTAssertEqual(commit("Deffault"), "Default")   // Dè → f-cancel → keep typing
        XCTAssertEqual(commit("deffault"), "default")
        XCTAssertEqual(commit("asz"), "a")
        XCTAssertEqual(commit("DDDR"), "DDR")           // acronym via cancel
        XCTAssertEqual(commit("iss"), "is")             // not English → composed
        XCTAssertEqual(commit("banhss"), "banhs")
        // Screen-truth v2 2026-07-31: trailing double commits the screen; the way
        // to type the English word is the third letter (the screen already SHOWS
        // "off" after offf — no surprise restore at the boundary anymore).
        XCTAssertEqual(commit("boss"), "bos")
        XCTAssertEqual(commit("mess"), "mes")
        XCTAssertEqual(commit("off"), "of")      // trailing escape keeps the screen
        XCTAssertEqual(commit("offf"), "off")    // cancel + literal f → "off" as shown
        // same double-route for google (user requirement 2026-07-22):
        // typed straight → restore; typed with a fixing 3rd o → cancel keeps composed
        XCTAssertEqual(commit("google"), "google")    // "gôgle" restored (dict + validator)
        XCTAssertEqual(commit("gooogle"), "google")   // ooo-cancel → what you see is kept
        // and with live spell-check ON (the app default), both still hold
        var sp1 = TelexEngine(); sp1.freeMarking = true; sp1.liveSpellCheck = true
        for ch in "google" { _ = sp1.feed(ch) }
        XCTAssertEqual(sp1.commitText(autoRestore: true), "google")
        var sp2 = TelexEngine(); sp2.freeMarking = true; sp2.liveSpellCheck = true
        for ch in "gooogle" { _ = sp2.feed(ch) }
        XCTAssertEqual(sp2.commitText(autoRestore: true), "google")
    }

    // MARK: - Remote-desktop passthrough ids (item 3)

    func testNewPassthroughBundleIDs() {
        for id in ["com.carriez.rustdesk", "com.philandro.anydesk"] {
            XCTAssertTrue(ClientPolicy.isRemoteDesktop(id), "\(id) must be passthrough")
        }
        XCTAssertFalse(ClientPolicy.isRemoteDesktop("com.apple.Terminal"))
    }

    /// Corrected 07/08/2026 (maintainer field-test): iPhone Mirroring reuses the old
    /// Screen Sharing bundle id but bridges Continuity to a REAL text field on the
    /// phone, not raw scancodes — it must NOT be in the remote-desktop force list.
    func testIPhoneMirroringIsNotForcedPassthrough() {
        XCTAssertFalse(ClientPolicy.isRemoteDesktop("com.apple.ScreenContinuity"))
    }
}
