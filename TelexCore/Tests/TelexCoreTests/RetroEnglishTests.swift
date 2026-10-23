import XCTest
@testable import TelexCore

// Retroactive English correction (TelexEngine.retroactiveEnglish, EXPERIMENTAL).
// Same cases in android/telexcore RetroEnglishTest.kt and windows/engine retro_tests.cpp;
// the eval corpus is the shared fixture iOS/KeyboardTests/Fixtures/retro-english-eval.txt
// (Scripts/gen-retro-english-eval.py).

/// App-default engine (AppState.EngineFlags) + the feature.
private func appEngine(retro: Bool, contextual: Bool = true) -> TelexEngine {
    var e = TelexEngine()
    e.freeMarking = true
    e.liveSpellCheck = true
    e.eagerEnglishRestore = true
    e.teencode = false
    e.contextualEnglish = contextual
    e.collisionPrefersVietnamese = true
    e.retroactiveEnglish = retro
    return e
}

/// Type `keys` like a controller does: letters feed, any other character is a boundary
/// (commitText, insert it, report it), and every retro correction is applied to the
/// simulated screen after checking `expected` against it.
private func typeKeys(_ keys: String, _ e: inout TelexEngine, edits: inout Int) -> String {
    var screen: [Unicode.Scalar] = []
    func apply(_ c: RetroCorrection?) {
        guard let c else { return }
        let tail = String(String.UnicodeScalarView(screen.suffix(c.backspaces)))
        XCTAssertEqual(tail, c.expected, "retro expected-text mismatch in \(keys)")
        guard tail == c.expected else { return }
        screen.removeLast(c.backspaces)
        screen.append(contentsOf: c.insert.unicodeScalars)
        edits += 1
    }
    for ch in keys {
        if ch.isASCII, ch.isLetter {
            _ = e.feed(ch)
        } else {
            screen += e.commitText(autoRestore: true).unicodeScalars
            screen += String(ch).unicodeScalars
            e.noteBoundaryCharacter(ch)
            apply(e.takeRetroCorrection())
        }
    }
    screen += e.commitText(autoRestore: true).unicodeScalars
    apply(e.takeRetroCorrection())
    return String(String.UnicodeScalarView(screen))
}

private func typed(_ keys: String, retro: Bool = true, contextual: Bool = true) -> String {
    var e = appEngine(retro: retro, contextual: contextual)
    var n = 0
    return typeKeys(keys, &e, edits: &n)
}

private func words(_ s: String) -> [String] { s.split(whereSeparator: { !$0.isLetter }).map(String.init) }

final class RetroEnglishTests: XCTestCase {

    // MARK: Behaviour

    func testRewritesCollisionWordsBeforeEnglishRun() {
        XCTAssertEqual(typed("His car is very fast"), "His car is very fast")
        XCTAssertEqual(typed("His car is very fast", retro: false), "Hí cả í very fast")
        XCTAssertEqual(typed("my car is here now"), "my car is here now")
        XCTAssertEqual(typed("of course not"), "of course not")
        XCTAssertEqual(typed("its time to go home"), "its time to go home")
        XCTAssertEqual(typed("This list is very long"), "This list is very long")
    }

    func testVietnameseWithLoanwordsUntouched() {
        for keys in ["Mai car team hopj", "Guwir file cho car nhaf", "car team meeting",
                     "cais nayf as the best", "check car deploy build", "lamf car review code",
                     "hoom nay hopj car buoori with the team", "em sex check the logs"] {
            XCTAssertEqual(typed(keys), typed(keys, retro: false), keys)
        }
        XCTAssertEqual(typed("Mai car team hopj"), "Mai cả team họp")
        XCTAssertEqual(typed("Guwir file cho car nhaf"), "Gửi file cho cả nhà")
        XCTAssertEqual(typed("car team meeting"), "cả team meeting")
    }

    /// Owner rule: the feature depends on "Quyết định theo ngữ cảnh" (contextualEnglish).
    func testInertWithoutContextualEnglish() {
        for keys in ["His car is very fast", "my car is here now", "of course not"] {
            XCTAssertEqual(typed(keys, retro: true, contextual: false),
                           typed(keys, retro: false, contextual: false), keys)
        }
        var e = appEngine(retro: true, contextual: false)
        XCTAssertFalse(e.retroactiveEnglishActive)
        var n = 0
        _ = typeKeys("His car is very fast", &e, edits: &n)
        XCTAssertEqual(n, 0)
        XCTAssertTrue(e.debugRetroHistory.isEmpty)
    }

    /// Documented limits (docs/DESIGN.md): the check only looks BACK from a 2-word English
    /// run. With the app defaults "His car is here now" has no word committed as English at
    /// all (here→hể: collisionPrefersVietnamese, now→nơ), so nothing triggers; any English
    /// continuation fixes the head. A sentence-initial "Ít" + English is read as "Its".
    func testKnownLimits() {
        XCTAssertEqual(typed("His car is here now"), "Hí cả í hể nơ")
        XCTAssertEqual(typed("His car is here now and it is fast"), "Hí cả í hể nơ and it is fast")
        XCTAssertEqual(typed("Its people know that"), "Its people know that")
    }

    func testInertInVNI() {
        var e = appEngine(retro: true)
        e.vniMode = true
        XCTAssertFalse(e.retroactiveEnglishActive)
    }

    func testCaseKeptExactly() {
        XCTAssertEqual(typed("HIS CAR is very fast"), "HIS CAR is very fast")
        XCTAssertEqual(typed("His Car is very fast"), "His Car is very fast")
    }

    /// The correction is one replace relative to the caret, unchanged prefix stripped.
    func testCorrectionShape() {
        var e = appEngine(retro: true)
        for k in ["His", "car", "is", "very"] {
            for ch in k { _ = e.feed(ch) }
            _ = e.commitText(autoRestore: true)
            e.noteBoundaryCharacter(" ")
            XCTAssertNil(e.takeRetroCorrection())
        }
        for ch in "fast" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "fast")
        // Before the boundary char: span "Hí cả í very fast" minus the shared "H".
        XCTAssertEqual(e.pendingRetroCorrection,
                       RetroCorrection(backspaces: 16, expected: "í cả í very fast",
                                       insert: "is car is very fast", words: 3))
        e.noteBoundaryCharacter(".")   // reported before taking: the edit grows with it
        XCTAssertEqual(e.takeRetroCorrection(),
                       RetroCorrection(backspaces: 17, expected: "í cả í very fast.",
                                       insert: "is car is very fast.", words: 3))
        XCTAssertNil(e.takeRetroCorrection())
    }

    /// Any edit the engine cannot follow drops the history: no stale rewrite later.
    func testHistoryClearedByUnknownEdits() {
        func prime(_ e: inout TelexEngine) {
            for k in ["His", "car", "is", "very"] {
                for ch in k { _ = e.feed(ch) }
                _ = e.commitText(autoRestore: true)
                e.noteBoundaryCharacter(" ")
            }
        }
        let clears: [(inout TelexEngine) -> Void] = [
            { $0.reset() }, { $0.resetContext() }, { $0.forgetLastCommit() },
            { _ = $0.backspace() },                         // ⌫ into committed text
            { $0.noteBoundaryCharacter(",") },              // punctuation = new phrase
            { $0.retroactiveEnglish = false; _ = $0.feed("x"); _ = $0.commitText(autoRestore: true)
              $0.noteBoundaryCharacter(" "); $0.retroactiveEnglish = true },
        ]
        for (i, clear) in clears.enumerated() {
            var e = appEngine(retro: true)
            prime(&e)
            clear(&e)
            for ch in "fast" { _ = e.feed(ch) }
            _ = e.commitText(autoRestore: true)
            XCTAssertNil(e.takeRetroCorrection(), "clear #\(i)")
        }
        // Missing separator report = not contiguous.
        var e = appEngine(retro: true)
        for k in ["His", "car", "is", "very", "fast"] {
            for ch in k { _ = e.feed(ch) }
            _ = e.commitText(autoRestore: true)
        }
        XCTAssertNil(e.takeRetroCorrection())
    }

    /// commitBoundary path (in-place controllers) behaves like commitText.
    func testCommitBoundaryPath() {
        var e = appEngine(retro: true)
        for k in ["His", "car", "is", "very", "fast"] {
            for ch in k { _ = e.feed(ch) }
            _ = e.commitBoundary(autoRestore: true)
            if k != "fast" { e.noteBoundaryCharacter(" ") }
        }
        XCTAssertEqual(e.takeRetroCorrection()?.insert, "is car is very fast")
    }

    func testPlanIsPure() {
        func w(_ raw: String, _ shown: String, eng: Bool, cand: Bool, gap: Int = 1) -> RetroWord {
            RetroWord(raw: raw, shown: shown, english: eng, candidate: cand,
                      cls: RetroEnglish.classBits(raw.lowercased()), gap: gap, leftNonEnglish: false)
        }
        let h = [w("His", "Hí", eng: false, cand: true, gap: 0), w("car", "cả", eng: false, cand: true),
                 w("is", "í", eng: false, cand: true), w("very", "very", eng: true, cand: false),
                 w("fast", "fast", eng: true, cand: false)]
        XCTAssertEqual(RetroEnglish.plan(h), [0, 1, 2])
        XCTAssertNil(RetroEnglish.plan(Array(h.dropLast())))          // run of one: no trigger
        var g = h; g[3].gap = 0                                       // run not contiguous
        XCTAssertNil(RetroEnglish.plan(Array(g)))
        var c = h; c[0].cls = 0                                       // no anchor: "car is" alone
        XCTAssertNil(RetroEnglish.plan(c))
    }

    // MARK: Eval (positives: English sentences; negatives: Vietnamese / mixed corpora)

    private func evalLines() -> [(label: String, keys: String, mask: [Character])] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("iOS/KeyboardTests/Fixtures/retro-english-eval.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { l in
            guard !l.hasPrefix("#") else { return nil }
            let p = l.split(separator: "\t", omittingEmptySubsequences: false)
            return p.count == 3 ? (String(p[0]), String(p[1]), Array(p[2])) : nil
        }
    }

    /// Word-level metrics. Gold per word (fixture mask): `e` = English → the raw keys,
    /// `v` = Vietnamese → whatever the engine commits with the feature OFF.
    ///   TP = word the feature changed to its gold; FP = word it changed away from gold.
    ///   recall = fixed English words / English words the engine gets wrong when OFF.
    /// Safety: no `v` word may ever change (the real target: ~0 false rewrites).
    func testEvalPrecisionRecall() {
        let lines = evalLines()
        XCTAssertGreaterThan(lines.count, 5000, "fixture missing")
        var tp = 0, fp = 0, offWrong = 0, reachable = 0, vChanged = 0
        var sentences = 0, sentencesTouched = 0, falseSentences = 0
        var report: [String] = []
        for (label, keys, mask) in lines {
            let off = typed(keys, retro: false)
            let on = typed(keys, retro: true)
            let (o, n, k) = (words(off), words(on), words(keys))
            XCTAssertTrue(o.count == n.count && n.count == k.count && k.count == mask.count, keys)
            guard o.count == n.count, n.count == k.count, k.count == mask.count else { continue }
            sentences += 1
            var touched = false, bad = false
            for i in 0..<k.count {
                let english = mask[i] == "e"
                let gold = english ? k[i] : o[i]
                if o[i] != n[i] {
                    touched = true
                    if n[i] == gold { tp += 1 } else { fp += 1; bad = true }
                    if !english { vChanged += 1 }
                }
                if english, o[i] != gold {
                    offWrong += 1
                    if RetroEnglish.isCandidateRaw(gold.lowercased()) { reachable += 1 }
                }
            }
            if touched { sentencesTouched += 1 }
            if bad { falseSentences += 1; report.append("FALSE \(label): \(off)  =>  \(on)") }
            else if mask.contains("e"), o != n || o.indices.contains(where: { mask[$0] == "e" && o[$0] != k[$0] }) {
                report.append((touched ? "FIX  " : "MISS ") + "\(label): \(off)  =>  \(on)")
            }
        }
        let precision = Double(tp) / Double(max(tp + fp, 1))
        let recall = Double(tp) / Double(max(offWrong, 1))
        let recallReach = Double(tp) / Double(max(reachable, 1))
        print(String(format: "RETRO-EVAL %d sentences (%d touched, %d with a false rewrite) | words: TP=%d FP=%d "
                     + "precision=%.4f | recall=%d/%d=%.4f (English words wrong with the feature OFF) | "
                     + "recall(collision words)=%d/%d=%.4f | Vietnamese words changed=%d",
                     sentences, sentencesTouched, falseSentences, tp, fp, precision, tp, offWrong, recall,
                     tp, reachable, recallReach, vChanged))
        if ProcessInfo.processInfo.environment["RETRO_EVAL_VERBOSE"] != nil {
            for r in report { print("RETRO-EVAL", r) }
        }
        XCTAssertEqual(vChanged, 0, "Vietnamese words must never be rewritten")
        XCTAssertEqual(fp, 0)
        XCTAssertGreaterThanOrEqual(precision, 0.99)
        XCTAssertGreaterThanOrEqual(recall, 0.30)
    }
}
