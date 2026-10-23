// RetroEnglish.swift — RETROACTIVE English correction (EXPERIMENTAL, engine flag
// `TelexEngine.retroactiveEnglish`, default OFF, inert unless `contextualEnglish` is on).
//
// Mixed typing: words whose raw keys collide with Vietnamese ("His"→Hí, "car"→cả,
// "is"→í) are composed as Vietnamese because, at the time they were typed, nothing said
// the sentence was English. Once an English run becomes CERTAIN (two consecutive words
// committed as English, the second one just now), the words right before the run that
// (a) were committed as Vietnamese, (b) whose raw keys are a known English word and
// (c) read as plausible English together with the run, are rewritten back to their raw
// keys: "Hí cả í very fast" → "His car is very fast".
//
// This file holds the PURE decision (`RetroEnglish.plan`) over a short per-session
// history of committed words; the engine records the history and turns the plan into
// one screen edit (`RetroCorrection`). Ported 1:1 to Kotlin (android/telexcore) and C++
// (windows/engine) — keep the three in sync. Design doc: docs/DESIGN.md
// ("Retroactive English correction").

/// One screen edit that rewrites the words before the caret.
/// Apply it like a `TelexAction.replace`: delete `backspaces` characters (Unicode scalars
/// == UTF-16 units: every character involved is precomposed BMP or ASCII) immediately
/// before the caret, then insert `insert`. `expected` is exactly the text those
/// `backspaces` characters are right now — integrators that can read the document
/// (AX / getTextBeforeCursor / ITfRange) should compare and skip the edit on mismatch.
public struct RetroCorrection: Equatable {
    public let backspaces: Int
    public let expected: String
    public let insert: String
    /// How many words the edit rewrites (for logging / undo UI).
    public let words: Int
}

/// A committed word as the retroactive check sees it. Internal; built by the engine at
/// each boundary while the feature is active.
struct RetroWord: Equatable {
    /// Raw keystrokes, case kept ("His").
    var raw: String
    /// What the commit left on screen ("Hí", or "His" when restored).
    var shown: String
    /// Committed as ENGLISH: the context classifier calls it English (function or content
    /// word) and the screen shows plain ascii.
    var english: Bool
    /// Rewrite CANDIDATE: committed with a Vietnamese diacritic, raw is a known English word.
    var candidate: Bool
    /// `EnglishContextWords.retroClasses` bits of the lowercased raw (0 = open class).
    var cls: UInt8
    /// Spaces between the previous history word and this one; 0 = not contiguous
    /// (sentence start, punctuation/newline, unknown edit, or the caller never reported
    /// the separator).
    var gap: Int
    /// At record time: there WAS a contiguous previous word and it was not English. Used
    /// only when that previous word has already left the history ring.
    var leftNonEnglish: Bool
    /// `EnglishContextWords.predecessorGates`: bit of the rule this word is gated by (0 =
    /// not gated), and the rules it satisfies as the preceding word.
    var gateBit: UInt8 = 0
    var predBits: UInt8 = 0
}

enum RetroEnglish {
    /// Class letters in bit order (see `EnglishContextWords.retroClassList`).
    static let classLetters: [Character] = ["P", "O", "D", "B", "R", "C", "X"]
    static let clsP: UInt8 = 1 << 0, clsO: UInt8 = 1 << 1, clsD: UInt8 = 1 << 2
    static let clsB: UInt8 = 1 << 3, clsR: UInt8 = 1 << 4, clsC: UInt8 = 1 << 5, clsX: UInt8 = 1 << 6
    /// Classes that can START a rewritten span (open a clause/phrase).
    static let anchorMask: UInt8 = clsP | clsD | clsR | clsC

    /// History ring size: the 2-word run + the 3-word lookback window + one left neighbour.
    static let historyCapacity = 6
    /// Max words BEFORE the English run that the lookback considers.
    static let window = 3
    /// More spaces than this between two words = not the same phrase.
    static let maxGap = 2
    /// Longest raw word considered (same bound as the English tables).
    static let maxWordLength = EnglishContextWords.maxLength

    /// Raw (lowercased ascii) is an English word the engine knows collides or may collide
    /// with Vietnamese: the generated collision table (lít/list, tét/test), the context
    /// word list (is/his/of/as/its/this…), the run keepers (cả/car, bõ/box — common
    /// Vietnamese, NEVER restored on their own) and the hard-coded exceptions. The
    /// interjection layer (`restoreOnly`) is left out on purpose: "á/ừ/ờ"-style words
    /// are chat particles first.
    static func isCandidateRaw(_ w: String) -> Bool {
        EnglishCollisions.words.contains(w) || EnglishContextWords.words.contains(w)
            || EnglishContextWords.runKeepers.contains(w)
            || w == "was" || w == "wow" || w == "yes" || w == "queue"
    }

    static func classBits(_ w: String) -> UInt8 { EnglishContextWords.retroClasses[w] ?? 0 }

    /// English bigram plausibility for (left, right) class bits (0 = open class).
    /// True if ANY reading of the pair is allowed.
    static func pairAllowed(_ l: UInt8, _ r: UInt8) -> Bool {
        if l == 0 { return true }
        if l & (clsO | clsB | clsC) != 0 { return true }
        if l & clsP != 0, r == 0 || r & clsB != 0 { return true }
        if l & clsD != 0, r == 0 { return true }
        if l & clsR != 0, r == 0 || r & (clsD | clsP | clsO) != 0 { return true }
        return false
    }

    /// The decision. `h` = committed words, oldest first; the LAST one was just committed.
    /// Returns the history indices to rewrite to their raw keys (ascending), or nil.
    static func plan(_ h: [RetroWord]) -> [Int]? {
        let n = h.count
        guard n >= 2, h[n - 1].english, h[n - 2].english, h[n - 1].gap > 0 else { return nil }
        // Start of the English run (consecutive English words ending at the last one).
        var s = n - 2
        while s > 0, h[s].gap > 0, h[s - 1].english { s -= 1 }
        // Lookback window: up to 3 contiguous words before the run that are candidates or
        // English; stop at anything else (Vietnamese, neutral loanword, punctuation…).
        var lo = s
        var k = 0
        while k < window, lo > 0, h[lo].gap > 0, h[lo - 1].candidate || h[lo - 1].english {
            lo -= 1; k += 1
        }
        guard lo < s else { return nil }
        // Longest plausible span first: the span [a, s) must be ANCHORED (see `anchors`)
        // and every adjacent pair from a through the run's first word plausible English.
        for a in lo..<s {
            var picks: [Int] = []
            for i in a..<s where h[i].candidate { picks.append(i) }
            guard !picks.isEmpty, anchors(h, a, picks) else { continue }
            var ok = true
            for i in a..<s where !pairAllowed(h[i].cls, h[i + 1].cls) { ok = false; break }
            // Predecessor gates apply here too: "been" only right after have/has/had/'ve
            // ("push code bên this repo" keeps "bên").
            for i in picks where h[i].gateBit != 0 {
                if i == a || h[i - 1].predBits & h[i].gateBit == 0 { ok = false; break }
            }
            guard ok else { continue }
            // Mid-sentence after a Vietnamese word ("cái này á the best"), ONE rewritten
            // word is too weak a signal — chat particles and common syllables (á, ít, ò)
            // sit right before English all the time. Need two.
            if h[a].candidate, leftIsNonEnglish(h, a), picks.count < 2 { continue }
            return picks
        }
        return nil
    }

    /// Can a rewritten span start at `a`?
    ///  - a word that opens a clause/phrase: subject pronoun, determiner, preposition,
    ///    conjunction ("His car is…", "of course…", "as far as…");
    ///  - a be/auxiliary at the very start of a phrase followed by a subject pronoun — the
    ///    question inversion ("Did you…", "Is this…", "Does he…");
    ///  - a word already committed as English, when every rewritten word is a be/auxiliary
    ///    ("winter í coming on" → is, "no man í free"): an open-class candidate between
    ///    English words stays Vietnamese ("check cả deploy build" — "cả" = both, very
    ///    common in dev chat), and so does an X word ("merge đi this PR" — đi = imperative
    ///    particle right after English verbs).
    private static func anchors(_ h: [RetroWord], _ a: Int, _ picks: [Int]) -> Bool {
        let w = h[a]
        if w.cls & anchorMask != 0 { return true }
        if w.candidate, w.cls & clsB != 0, a + 1 < h.count, h[a + 1].cls & clsP != 0,
           !hasContiguousLeft(h, a) { return true }
        if w.english, !w.candidate,
           picks.allSatisfy({ h[$0].cls & clsB != 0 && h[$0].cls & clsX == 0 }) { return true }
        return false
    }

    /// There is a word right before `a` in the same phrase (in the history or already
    /// dropped from the ring — `gap` is only set when a previous word existed).
    private static func hasContiguousLeft(_ h: [RetroWord], _ a: Int) -> Bool { h[a].gap > 0 }

    private static func leftIsNonEnglish(_ h: [RetroWord], _ a: Int) -> Bool {
        guard h[a].gap > 0 else { return false }
        if a > 0 { return !h[a - 1].english }
        return h[a].leftNonEnglish
    }

    /// Turn a plan into one edit: from the first rewritten word to the end of the last
    /// committed word (the caret, before the boundary character of that word), with the
    /// unchanged leading characters ("H" of "Hí"→"His") left alone.
    static func correction(_ h: [RetroWord], _ picks: [Int]) -> RetroCorrection? {
        guard let first = picks.first else { return nil }
        var expected = String.UnicodeScalarView()
        var insert = String.UnicodeScalarView()
        for i in first..<h.count {
            if i > first {
                for _ in 0..<h[i].gap { expected.append(" "); insert.append(" ") }
            }
            expected.append(contentsOf: h[i].shown.unicodeScalars)
            insert.append(contentsOf: (picks.contains(i) ? h[i].raw : h[i].shown).unicodeScalars)
        }
        var e = Array(expected), r = Array(insert)
        var lcp = 0
        while lcp < e.count, lcp < r.count, e[lcp] == r[lcp] { lcp += 1 }
        e.removeFirst(lcp); r.removeFirst(lcp)
        var es = String.UnicodeScalarView(), rs = String.UnicodeScalarView()
        es.append(contentsOf: e); rs.append(contentsOf: r)
        return RetroCorrection(backspaces: e.count, expected: String(es), insert: String(rs),
                               words: picks.count)
    }
}
