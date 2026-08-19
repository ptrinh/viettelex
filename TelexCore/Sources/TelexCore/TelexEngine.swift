// TelexEngine.swift
// Simple Telex (strict). Hot path works over fixed-capacity (32) buffers.
//
// Strategy: keep the raw keystroke buffer (letters only) plus an INCREMENTAL parse
// state: each new key is folded into the persistent (letters + tone) state by one
// `parseStep` — the word is no longer re-parsed from scratch per key. Rendering
// copies the letters into a scratch, applies the post-passes (ươ propagation, tone
// placement) on the copy, and diffs against the previous render to yield the
// minimal (backspaces, insert) edit for the input client. Backspace and mid-word
// setting changes fall back to a full rebuild (replay of parseSteps) — identical
// semantics, since the parse is a left-to-right fold over the raw keys.
//
// Note: fixed-capacity `[UInt8]`/`[UInt32]` buffers are pre-reserved (capacity 32)
// and mutated in place — including the render/parse scratch buffers, which live on
// the instance so the hot path allocates nothing per keystroke (the live
// spell-check runs on a flat trie, not Strings). InlineArray would give a stronger
// zero-heap guarantee but requires macOS 26; reserved arrays keep the macOS 14
// deployment target.

public enum TelexAction: Equatable {
    /// Not handled by the engine; let the system insert the character.
    case passthrough
    /// Replace `backspaces` trailing characters already on screen with `insert`.
    /// `insert` may be empty (pure consume) or `backspaces` may be 0 (pure insert).
    case replace(backspaces: Int, insert: String)
    /// Nothing to do.
    case none
}

/// One output letter before tone placement.
private struct LetterUnit {
    var base: UInt8 = 0     // lowercase ascii
    var mark: Mark = .none
    var upper: Bool = false
}

public struct TelexEngine {

    /// "Bỏ dấu tự do" (free mark placement). When true, modifier keys (circumflex
    /// aa/ee/oo, breve/horn w) reach back over consonants to the target vowel
    /// ("ama"→âm, "trangw"→trăng). When false (default = Minimal Telex / strict), a
    /// modifier only transforms the vowel adjacent to it (across intervening vowels
    /// still, but never a consonant): "ama"→ama, "trangw"→trangw, but "aam"→âm and
    /// "trawng"→trăng. Preserved across `reset()`; the caller sets it from settings.
    public var freeMarking = false

    /// Tone-mark placement style for OPEN glide-initial diphthongs. false (default) =
    /// OLD style (`hòa`, `khỏe`, `thủy`); true = MODERN/new style (`hoà`, `khoẻ`,
    /// `thuý`). Only affects `oa`/`oe`/`uy` open nuclei — every other placement
    /// (ê/ơ magnet, coda, qu/gi glide, `múa`/`mía` falling diphthongs) is identical.
    /// Preserved across `reset()`; the caller sets it from settings.
    public var modernTone = false

    /// Live spell-check. When true, as soon as the word
    /// in progress can no longer become a valid Vietnamese syllable
    /// (`SyllableValidator.isValidPrefix` fails), the engine STOPS transforming: every
    /// further key is emitted literally, so foreign words / URLs stop being mangled
    /// mid-word ("gôgle…" no longer keeps accreting diacritics). Already-applied edits
    /// stay on screen until the word boundary, where auto-restore reverts the whole
    /// token. Preserved across `reset()`; the caller sets it from settings.
    public var liveSpellCheck = false

    /// Simple Telex. When true, a STANDALONE `w` (no adjacent
    /// a/o/u to horn/breve) never becomes `ư` — it stays a literal `w`, so `ư` must be
    /// typed `uw` ("cw"→cw, not cư; "cuw"→cư). `w` still breves/horns an adjacent vowel
    /// (aw→ă, ow→ơ, uw→ư). (Brackets are already literal in
    /// this engine, the other Simple-Telex difference.) Preserved across `reset()`.
    public var simpleTelex = false

    /// Quick Telex ("gõ nhanh"): a doubled onset consonant expands to its digraph —
    /// cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th. Word-INITIAL pair only
    /// (these are onset digraphs; mid-word doubles like "occur" stay literal).
    /// Default OFF. Preserved across `reset()`; the caller sets it from settings.
    public var quickTelex = false

    /// Bracket vowels (UniKey/macOS-Simple-Telex habit, EXPERIMENTAL, default OFF):
    /// `[` types ơ, `]` types ư, `{`/`}` their uppercase. One keystroke each, so ⌫
    /// removes the whole vowel and auto-restore hands back the BRACKET the user
    /// pressed ("th[" → "thơ", restored → "th[") — the raw buffer keeps the bracket
    /// byte and only the parse translates it, so nothing downstream needs to know.
    ///
    /// A 15-year touch-typing habit for UniKey users (Facebook request 2026-08-14), and
    /// opt-in for a reason: with it on, `[`/`]` are word KEYS, so they no longer end a
    /// word — anyone typing `arr[i]` in code wants this off, which is the default.
    /// Preserved across `reset()`; the caller sets it from settings.
    public var bracketVowels = false

    /// VNI input method. When true the engine parses VNI, not Telex: LETTERS are
    /// always literal, and DIGITS carry the diacritics — 1-5 = sắc/huyền/hỏi/ngã/nặng,
    /// 6 = â/ê/ô (circumflex), 7 = ơ/ư (horn), 8 = ă (breve), 9 = đ, 0 = clear tone.
    /// A digit is a diacritic only when it can apply (a tone needs a vowel; a mark needs
    /// its target letter; 0 needs a tone) — otherwise it types literally ("mp3", "a4"
    /// paper size stays…"a4" only via spell-check freeze; a lone "a4" → "ã", the same
    /// inherent VNI ambiguity every VNI IME has). Preserved across `reset()`.
    public var vniMode = false

    /// Context-based decision (EXPERIMENTAL, default OFF). When the previous committed
    /// word was English, an AMBIGUOUS current word — one whose composition is a valid
    /// Vietnamese syllable but whose raw keys also spell an English word — is restored to
    /// English instead of kept Vietnamese: "he is" → "he is" (not "he í"). After a valid
    /// Vietnamese or undetermined word, the ambiguous word stays Vietnamese: "sao í".
    /// Uses `EnglishContextWords`. Preserved across `reset()`; cleared by `resetContext()`.
    public var contextualEnglish = false

    /// Whether the PREVIOUS committed word was classified English (for `contextualEnglish`).
    /// Cross-word state: survives `reset()` (which runs per word), updated at each commit,
    /// wiped by `resetContext()` (caller: focus / app switch). Read-only to callers/tests.
    public private(set) var previousWordEnglish = false

    /// Force-restore top-frequency English words that collide with valid
    /// Vietnamese syllables ("his"→hí) at the word boundary. Default ON.
    /// gen-english turns this OFF to regenerate the table against the
    /// validator-only behavior (the table must not observe itself).
    public var englishWordRestore = true

    static let capacity = 32

    // Raw keystrokes that make up the current word (ascii, case preserved).
    private var raw: [UInt8]
    private var rawCount = 0

    // Set once `rawCount` hits capacity: the word is longer than the engine can
    // hold, so its 32-char view is a stale prefix of what the caller has on screen.
    // While overflowed the word is treated as non-composable — backspace passes
    // through (the app deletes natively) and the boundary neither auto-restores nor
    // rewrites — so the engine never diffs its short view against the longer screen
    // and silently drops the overflow characters. Reset per word.
    private var overflowed = false

    // Current on-screen composition (scalar values) — kept to diff against.
    private var out: [UInt32]
    private var outCount = 0

    // Scratch buffers reused every keystroke (never allocated on the hot path).
    // Valid only during/right after the call that filled them.
    private var scratch: [UInt32]              // render output, diffed against `out`
    private var renderLetters: [LetterUnit]    // render-time copy of `letters` (post-passes)
    private var basesScratch: [UInt8]          // folded bases for the trie prefix check
    private var rawLetter: [Int]               // raw index -> display-letter provenance
    private var toneKeys: [Int]                // raw indices of deferred tone/z keys
    private var vowelIdx: [Int]                // vowel positions (tone placement)

    // MARK: Incremental parse state (the left-to-right fold, persisted per key)
    //
    // `letters[0..<pCount]` + `pTone` are the fold of raw[0..<pProcessed]. feed()
    // advances it by ONE parseStep; backspace / a mid-word setting flip rebuild it
    // by replaying every key (same semantics — the parse is a pure fold). The
    // render post-passes (ươ propagation, tone placement) never mutate this state:
    // they run on the `renderLetters` copy.
    private var letters: [LetterUnit]
    private var pCount = 0
    private var pTone: Tone = .none
    private var pToneKeyCount = 0
    private var pCancelled = false
    // Distance (in raw keys) from the cancelled tone key to the key that cancelled it:
    // 1 = the classic adjacent double ("iss", "aff"), >1 = the cancel reached back over
    // letters, which means the tone key it kills was itself an eaten letter
    // ("hosts"→hots, "asks"→aks). 0 = no tone cancel in this word.
    private var pToneCancelSpan = 0
    // Raw index of the last TONE-key cancel (ss/ff/rr/xx/jj, z, VNI 1-5/0), -1 if none.
    // A tone cancel means different things depending on WHERE it happened — at the end of
    // the word it's the literal-letter escape, mid-word it ate a letter. See
    // `shouldRestoreRaw`. Mark doublers (aa a, ww, dd d, VNI 6-9) never set it.
    private var pToneCancelAt = -1
    private var pProcessed = 0
    private var pFreeMarking = false    // settings snapshot the state was built with
    private var pSimpleTelex = false
    private var pQuickTelex = false
    private var pVniMode = false
    private var pBracketVowels = false
    // Snapshot of `liveSpellCheck` the freeze state was computed with. Unlike the
    // other parse settings this one does not change how a single key folds — it
    // decides WHERE the word freezes (`disabledAtCount`), which is a function of the
    // whole word, so a mid-word flip has to replay it (see feed()).
    private var pLiveSpellCheck = false

    // Raw index from which keys are emitted literally because live spell-check found
    // the word can no longer be valid Vietnamese. Int.max = not disabled. Unlike
    // `markCancelled` this does NOT suppress boundary auto-restore (foreign words
    // still revert to raw). Reset per word.
    private var disabledAtCount = Int.max

    // True when the current word's parse involved an explicit diacritic CANCELLATION
    // (double tone key ss/ff/rr/xx/jj, z, double circumflex aaa/eee/ooo, double
    // breve/horn aww, double-d ddd). That is a deliberate "I want the literal letter"
    // gesture, so auto-restore leaves the word alone even when it isn't a valid
    // Vietnamese syllable: "iss"→is (not restored to "iss"), "ass"→as.
    private var markCancelled = false

    // Snapshots of `pToneCancelAt` / `pToneCancelSpan`, taken with `markCancelled`.
    private var toneCancelAt = -1
    private var toneCancelSpan = 0

    // Rebuild directive: fold every tone key back to its literal letter. Set ONLY
    // for the second pass of a frozen-word rebuild when a tone is still PENDING
    // ("installer": the early s floated as sắc onto the post-freeze a). A CANCELLED
    // tone (ss/ff/…) must NOT fold — forward typing rendered the cancel ("ress" →
    // res), and a rebuild that resurrects both keys as literals ("ress") desyncs
    // the screen: ⌫ on "rese" showed "ress" (tester report 2026-07-24).
    private var pFoldTones = false

    // Effective tone of the last render (after the stop-coda drop) — the composed
    // word's tone, used by the zero-alloc boundary validation.
    private var lastEffTone: Tone = .none

    // True when a tone key (s f r x j, or z) was CONSUMED as a tone while typed
    // UPPERCASE. In a mixed-case word that is an English/code signal ("SaaS": the
    // trailing S applies sắc → "Sấ", a *valid* syllable that plain validation
    // would keep), so boundary auto-restore forces the raw keystrokes back. An
    // ALL-CAPS word is exempt — "VIEEJT"→VIỆT types tone keys uppercase
    // legitimately. Mark doublers (DDaay, AAn) are NOT counted: shift held across
    // a doubler is normal typing.
    private var upperToneKey = false

    // MARK: Re-open snapshot (⌫ right after a word boundary — issue #40)
    //
    // The keystrokes of the word the LAST boundary committed, kept only while that
    // word is still exactly what the screen shows: the commit did not auto-restore
    // to raw and did not overflow, so `composed` is on screen character for
    // character. Deleting the boundary character then re-opens the word instead of
    // starting from nothing ("tháy" ␣ ⌫ a → "thấy"), which is what every other
    // Vietnamese IME does. Fixed buffers — the capture runs on the boundary hot
    // path and must not allocate.
    private var reopenRaw: [UInt8]
    private var reopenOut: [UInt32]
    private var reopenRawCount = 0
    private var reopenOutCount = 0
    // `previousWordEnglish` as it was BEFORE the commit folded this word in. Re-opening
    // puts the word back into the buffer, so the context it composes against must be
    // the one from the word BEFORE it, not the one it just produced.
    private var reopenPrevEnglish = false

    public init() {
        raw = [UInt8](repeating: 0, count: Self.capacity)
        reopenRaw = [UInt8](repeating: 0, count: Self.capacity)
        reopenOut = [UInt32](repeating: 0, count: Self.capacity)
        out = [UInt32](repeating: 0, count: Self.capacity)
        scratch = [UInt32](repeating: 0, count: Self.capacity)
        letters = [LetterUnit](repeating: LetterUnit(), count: Self.capacity)
        renderLetters = [LetterUnit](repeating: LetterUnit(), count: Self.capacity)
        basesScratch = [UInt8](repeating: 0, count: Self.capacity)
        rawLetter = [Int](repeating: -1, count: Self.capacity)
        toneKeys = [Int](repeating: 0, count: Self.capacity)
        vowelIdx = [Int](repeating: 0, count: Self.capacity)
    }

    public var isEmpty: Bool { rawCount == 0 }

    // MARK: - Public entry points

    /// RE-EDIT an already committed word: rebuild the engine state from TEXT that is
    /// already on screen, so the next keystroke can add a diacritic to it ("toan" + `s`
    /// → "toán"). Returns true only when the word round-trips EXACTLY.
    ///
    /// How: the word is turned back into the keystrokes that would have produced it
    /// (detone → mark expansion → trailing tone key, or the VNI digits in VNI mode) and
    /// those keys are replayed through `feed`. Everything downstream — tone placement,
    /// ươ propagation, ⌫ mapping, boundary restore — therefore behaves exactly as if the
    /// user had just typed the word, with no second code path to keep in sync.
    ///
    /// The round-trip check is the SAFETY: if replaying the keys does not reproduce the
    /// word character-for-character, the engine is reset and false is returned, so the
    /// caller must leave the text alone. That is what refuses
    ///   • non-Vietnamese text ("google" → keys "google" → composes "gôgle" ✗),
    ///   • a tone-placement style the current settings spell differently
    ///     ("hòa" on screen while `modernTone` produces "hoà" ✗),
    ///   • anything with a character no keystroke can produce (digits, symbols, é/ñ…).
    /// Refusing costs the user nothing (the word simply isn't re-editable); guessing
    /// would rewrite text they never asked to change.
    public mutating func seed(_ word: String) -> Bool {
        reset()
        guard !word.isEmpty, word.count <= Self.capacity / 2 else { return false }
        guard let keys = Self.seedKeystrokes(for: word, vni: vniMode) else { return false }
        guard keys.count <= Self.capacity else { reset(); return false }
        for ch in keys { _ = feed(ch) }
        guard composed == word else { reset(); return false }
        return true
    }

    /// Keystrokes that would compose `word`, or nil if some character can't be typed.
    /// Telex: marks expand (â→aa, ư→uw, đ→dd) and the tone key goes last, the way the
    /// generator in the typing-matrix tests does it. VNI: letters stay literal, marks
    /// are digits (6 circumflex, 7 horn, 8 breve, 9 đ) and tones are 1-5, also last.
    private static func seedKeystrokes(for word: String, vni: Bool) -> String? {
        var out = ""
        var toneKey: Character?
        for ch in word {
            let isUpper = ch.isUppercase
            let lower = Character(ch.lowercased())
            // Strip the tone first: "ấ" → ("â", acute).
            var toneless = lower
            if lower.unicodeScalars.count == 1, let sc = lower.unicodeScalars.first,
               let (base, t) = Tables.detoneTable[sc.value] {
                if t != .none {
                    guard toneKey == nil else { return nil }   // two tones in one syllable
                    toneKey = vni ? Self.vniToneKey(t) : Self.telexToneKey(t)
                }
                toneless = Character(Unicode.Scalar(base)!)
            }
            let expanded: String
            if let e = (vni ? Self.vniMarkExpansion : Self.telexMarkExpansion)[toneless] {
                expanded = e
            } else {
                guard toneless.isASCII, toneless.isLetter else { return nil }
                expanded = String(toneless)
            }
            // A mark digit is never uppercased; a mark LETTER follows the letter's case.
            out += isUpper ? (vni ? Self.upperFirst(expanded) : expanded.uppercased()) : expanded
        }
        if let toneKey { out.append(toneKey) }
        return out
    }

    private static let telexMarkExpansion: [Character: String] = [
        "â": "aa", "ă": "aw", "ê": "ee", "ô": "oo", "ơ": "ow", "ư": "uw", "đ": "dd",
    ]
    private static let vniMarkExpansion: [Character: String] = [
        "â": "a6", "ê": "e6", "ô": "o6", "ơ": "o7", "ư": "u7", "ă": "a8", "đ": "d9",
    ]
    private static func telexToneKey(_ t: Tone) -> Character? {
        switch t {
        case .acute: return "s"; case .grave: return "f"; case .hook: return "r"
        case .tilde: return "x"; case .dot: return "j"; case .none: return nil
        }
    }
    private static func vniToneKey(_ t: Tone) -> Character? {
        switch t {
        case .acute: return "1"; case .grave: return "2"; case .hook: return "3"
        case .tilde: return "4"; case .dot: return "5"; case .none: return nil
        }
    }
    /// "a6" → "A6" (only the LETTER takes the case; the mark digit must stay a digit).
    private static func upperFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return String(f).uppercased() + String(s.dropFirst())
    }

    /// Feed one typed character. Only ascii letters compose; other characters
    /// should be routed through `commitBoundary` by the caller.
    public mutating func feed(_ ch: Character) -> TelexAction {
        guard let ascii = ch.asciiValue,
              isLetter(ascii) || (vniMode && isDigit(ascii))
                || (bracketVowels && Self.bracketVowel(ascii) != nil) else {
            return .passthrough
        }
        guard rawCount < Self.capacity else { overflowed = true; return .passthrough }

        // First key of a NEW word: whatever the last boundary committed is now two
        // edits away from the caret, so a later ⌫ must not re-open it (typing then
        // backspacing all the way back would otherwise resurrect the wrong word).
        if rawCount == 0 { reopenRawCount = 0; reopenOutCount = 0 }

        raw[rawCount] = ascii
        rawCount += 1

        // Fold the new key into the incremental parse state — or rebuild it when a
        // setting that changes parse behavior flipped mid-word (rare; the controller
        // re-applies settings every key, they just normally don't change mid-word).
        if pLiveSpellCheck != liveSpellCheck {
            // liveSpellCheck flipped mid-word. The freeze point depends on the WHOLE
            // word, not on this key, so recompute it with the same replay ⌫ uses:
            // turning the flag ON must freeze a word that already went invalid
            // ("googl" + 'e' → "gôgle", frozen from the 4th key, not from the 6th),
            // turning it OFF must lift a stale freeze instead of leaving the tail
            // literal until the boundary.
            recomputeFreeze()
            rebuildFrozenAware()
        } else if pProcessed != rawCount - 1
            || pFreeMarking != freeMarking || pSimpleTelex != simpleTelex
            || pQuickTelex != quickTelex || pVniMode != vniMode
            || pBracketVowels != bracketVowels {
            rebuildFrozenAware()
        } else {
            parseStep(rawCount - 1)
            pProcessed = rawCount
        }

        var newCount = render()
        markCancelled = pCancelled
        toneCancelAt = pToneCancelAt
        toneCancelSpan = pToneCancelSpan

        // Uppercase tone/mark key in a MIXED-case word ("OmS", "SaaS", "JavaScript")
        // → this is English/code, not Vietnamese. Freeze the WHOLE word to its raw
        // keystrokes IMMEDIATELY (not just at the boundary) so the tone never even
        // flashes on screen ("OmS" stays "OmS", never briefly "Óm"). Rebuild with
        // transforms disabled from the first key, then re-render.
        if disabledAtCount == Int.max, forceRestoreUpperTone {
            disabledAtCount = 0
            rebuildParseState()
            newCount = render()
            markCancelled = pCancelled
        toneCancelAt = pToneCancelAt
        toneCancelSpan = pToneCancelSpan
        }

        // Live spell-check: once the word can no longer be valid Vietnamese, freeze
        // transforms from the NEXT key on. Letter MARKS applied so far stay
        // ("gôgle" — historical, cosmetic until boundary restore), but a pending
        // TONE is CANCELLED: the word cannot be Vietnamese, so a floating tone has
        // no meaning and would otherwise land on whatever vowel follows in the
        // frozen tail — "installer" rendered "intáller" (the s applied as sắc onto
        // the post-freeze a; user report via its ⌫ variant "intálle").
        // TEENCODE elongation escape: a word that is "valid syllable + a run of one
        // repeated letter" ("hôngggg", "cóaaaa", "đẹpppp") is not a foreign word — it is
        // a chat spelling of a real syllable, so the freeze must NOT fire (it would fold
        // the tone back to a literal key and show raw "cosaaaa"/"ddepjpppp").
        if liveSpellCheck, disabledAtCount == Int.max, !prefixIsValid(newCount),
           elongationHeadCount(newCount, tone: pTone) <= 0 {
            disabledAtCount = rawCount
            if pTone != .none {
                // Rebuild with pFoldTones: parseStep folds every TONE key back
                // to its literal letter (see the tone branch), so the s in
                // "installer" comes back as 's' instead of floating as sắc.
                pFoldTones = true
                rebuildParseState()
                pFoldTones = false
                newCount = render()
                // The fold rewrote the cancel bookkeeping (a tone key that used to
                // float is now a literal letter), so the snapshots taken before the
                // freeze are stale — shouldRestoreRaw() would decide keep-vs-restore
                // at the boundary on pre-freeze data. Re-take them, exactly like the
                // upper-tone freeze above and ⌫ already do.
                markCancelled = pCancelled
                toneCancelAt = pToneCancelAt
                toneCancelSpan = pToneCancelSpan
            }
        }

        // Elongation UNFREEZE: the FIRST extra character can't be told apart from a
        // typo, so the word legitimately freezes there ("quafa" after "quàa" — one
        // stray 'a' is not yet an elongation). The moment the repeat arrives the shape
        // is unambiguous, so re-evaluate the freeze from scratch and lift it, which
        // re-renders the tone in ONE keystroke ("quàaa"). Gated on "frozen AND this key
        // repeats the previous one", so it never runs on ordinary typing.
        if liveSpellCheck, disabledAtCount != Int.max, !forceRestoreUpperTone,
           rawCount >= 2, raw[rawCount - 1] == raw[rawCount - 2] {
            recomputeFreeze()
            rebuildFrozenAware()
            newCount = render()
            markCancelled = pCancelled
            toneCancelAt = pToneCancelAt
            toneCancelSpan = pToneCancelSpan
        }

        // No-transform fast path: render is exactly the previous output plus this
        // character. Let the system insert it (cheapest, no flicker).
        if newCount == outCount + 1,
           scratch[newCount - 1] == UInt32(ascii),
           commonPrefixLength(scratch, out, upTo: outCount) == outCount {
            copyOut(newCount)
            return .passthrough
        }

        let action = diff(newCount)
        copyOut(newCount)
        return action
    }

    /// Backspace: delete the whole last DISPLAYED character (not just undo one
    /// keystroke), then reconcile the screen. Typing "khoo" shows "khô"; one
    /// backspace gives "kh", not "kho". Achieved by dropping every raw key that
    /// produced the last displayed letter (tracked via `rawLetter` provenance).
    public mutating func backspace() -> TelexAction {
        guard rawCount > 0 else { return .passthrough }
        // Overflowed: the engine's 32-char view is a stale prefix of the screen, so
        // any rebuild/diff would rewrite the whole range with the short composition
        // and drop the overflow. Let the app delete the last char natively instead.
        if overflowed { return .passthrough }

        // Provenance must reflect what the user SEES — i.e. the CURRENT freeze
        // state. (It briefly ran unfrozen "for historical semantics", which mis-
        // deleted on frozen words: unfrozen "installer" consumes the trailing r as
        // a hỏi tone, so "last displayed letter" pointed at the e and ⌫ produced
        // "installr".)
        rebuildFrozenAware()
        _ = render()                             // maps tone-key provenance

        if pCount == 0 {
            // Safety net, UNREACHABLE by construction (uncovered in coverage runs
            // and that's fine): pCount == 0 with rawCount > 0 would need every raw
            // key consumed as a tone (rawLetter == -1), but a tone key is only
            // consumed when a vowel LETTER precedes it — so some key always maps to
            // a letter. Kept in case a future parse rule breaks that invariant.
            rawCount -= 1                        // nothing on screen -> drop one key
        } else {
            let last = pCount - 1
            var w = 0
            for r in 0..<rawCount where rawLetter[r] != last {
                raw[w] = raw[r]; w += 1
            }
            rawCount = w
        }

        // Re-freeze exactly as forward typing would have computed it over the
        // SHORTENED word. Lifting the freeze permanently re-applied transforms
        // retroactively: frozen "installer" ⌫ became "intálle" once free marking
        // could reach the 'a'. The replay is bounded (≤32 keys, parseStep is ~ns)
        // and runs only on ⌫.
        recomputeFreeze()
        rebuildFrozenAware()
        let newCount = render()
        markCancelled = pCancelled
        toneCancelAt = pToneCancelAt
        toneCancelSpan = pToneCancelSpan
        let action = diff(newCount)
        copyOut(newCount)
        return action
    }

    /// Word boundary reached. Optionally auto-restore the raw keystrokes when the
    /// composed word is not a valid Vietnamese syllable. Resets the engine.
    /// The caller inserts the boundary character itself afterwards.
    public mutating func commitBoundary(autoRestore: Bool) -> TelexAction {
        defer { resetWord() }
        guard rawCount > 0 else { reopenRawCount = 0; reopenOutCount = 0; return .none }
        // Overflowed: the 32-char view is stale vs. the screen, so `outCount`
        // backspaces would hit the wrong characters. No restore, no rewrite.
        if overflowed {
            if contextualEnglish { previousWordEnglish = false }   // undetermined → Vietnamese
            reopenRawCount = 0; reopenOutCount = 0                 // stale prefix: never re-open
            return .none
        }
        // Skip restore when the user cancelled a diacritic on purpose ("iss"→is).
        // Validation runs on letter classes + tone (no String); Strings are built
        // only when a restore actually happens. shouldRestoreRaw() reads the PREVIOUS
        // word's context; previousWordEnglish is refreshed for the NEXT word after.
        let wantsRestore = autoRestore && outCount > 0 && shouldRestoreRaw()
        var action: TelexAction = .none
        if wantsRestore, compositionDiffersFromRaw() {
            // Strip the shared leading run, exactly like diff() does per keystroke:
            // an unchanged prefix (the "g" in "gôgle"→"google") must NOT be
            // deleted+retyped. Re-typing a still-correct leading char surfaces as a
            // duplicate ("ggoogle") when the editor offsets our deletion — Chrome's
            // omnibox inline-autocomplete absorbs one Shift+Left in .selection mode.
            let limit = min(rawCount, outCount)
            var lcp = 0
            while lcp < limit, UInt32(raw[lcp]) == out[lcp] { lcp += 1 }
            let backspaces = outCount - lcp
            var s = String.UnicodeScalarView()
            s.reserveCapacity(rawCount - lcp)
            for i in lcp..<rawCount { s.append(Unicode.Scalar(raw[i])) }
            action = .replace(backspaces: backspaces, insert: String(s))
        }
        captureReopen(restored: wantsRestore)
        updateContext(restored: wantsRestore)
        return action
    }

    /// Remember the just-committed word so a ⌫ on the boundary character can put it
    /// back (see `reopenLastCommit`). Only when the screen ends up showing `composed`:
    /// a restore-to-raw ("google") or a caller-side rewrite leaves other text there,
    /// and re-opening would desync the buffer from the screen. Allocation-free.
    private mutating func captureReopen(restored: Bool) {
        guard !restored, rawCount > 0 else { reopenRawCount = 0; reopenOutCount = 0; return }
        for i in 0..<rawCount { reopenRaw[i] = raw[i] }
        for i in 0..<outCount { reopenOut[i] = out[i] }
        reopenRawCount = rawCount
        reopenOutCount = outCount
        reopenPrevEnglish = previousWordEnglish
    }

    /// Discard the re-open snapshot: the boundary character the caller inserted after
    /// a commit is no longer the thing a ⌫ would delete (shortcut expansion, a
    /// caller-side rewrite, a dropped composition). Cheaper and clearer at the call
    /// site than a full `reset()`, which also throws away the live word.
    public mutating func forgetLastCommit() {
        reopenRawCount = 0
        reopenOutCount = 0
    }

    /// True while `reopenLastCommit()` has something to put back.
    public var canReopenLastCommit: Bool { rawCount == 0 && reopenRawCount > 0 }

    /// RE-OPEN the word the last boundary committed — the ⌫ counterpart of `seed`.
    /// The user typed a word, ended it, then deleted the boundary character; the word
    /// is still on screen and they expect to keep editing it ("tháy" ␣ ⌫ then `a` →
    /// "thấy", issue #40). Replays the remembered keystrokes so tone placement, ươ
    /// propagation, ⌫ mapping and the boundary decision all behave exactly as if the
    /// word had never been committed.
    ///
    /// Returns the composed word now in the buffer — which is byte-for-byte what the
    /// screen shows, so the caller can point its tracking window at it — or nil when
    /// there is nothing to re-open. Like `seed`, the replay is VERIFIED: if a setting
    /// changed since the commit and the word no longer composes the same, the engine
    /// resets and nil is returned rather than compose against text it cannot match.
    /// The snapshot is consumed either way — one ⌫ gets one chance.
    public mutating func reopenLastCommit() -> String? {
        guard canReopenLastCommit else { return nil }
        let n = reopenRawCount
        let expected = reopenOutCount
        let prevEnglish = reopenPrevEnglish
        reset()                                   // consume the snapshot before replaying
        previousWordEnglish = prevEnglish         // compose against the word BEFORE this one
        for i in 0..<n { _ = feed(Character(Unicode.Scalar(reopenRaw[i]))) }
        guard rawCount == n, outCount == expected else { reset(); return nil }
        for i in 0..<outCount where out[i] != reopenOut[i] { reset(); return nil }
        return composed
    }

    /// Boundary restore decision, shared by both commit paths.
    /// Order matters: the English-collision table wins over EVERYTHING, including
    /// a cancel — that is what restores "off"/"office"/"class" (their raw doubles
    /// are real English). After that, a deliberate double-key cancel normally KEEPS
    /// the composed text: the user pressed the extra key to undo an unwanted
    /// diacritic and may keep typing ("Deffault" keys → Default, field report
    /// 2026-07-22 — an earlier validity-based rule here restored the raw double-f).
    /// TWO exceptions, both meaning the cancel did NOT leave clean text:
    ///  1. the composition still carries a Vietnamese diacritic — free-marking reached
    ///     back BEFORE the cancel ("excess"→"êcs") → restore the raw keys; while
    ///     "iss"→"is", "messs"→"mess" (plain ascii after the cancel) are kept;
    ///  2. a TONE-key cancel that REACHED BACK over letters (the killed tone key was
    ///     typed keys earlier, so it is itself a letter the word lost): "hosts"→hots,
    ///     "asks"→aks → restore. An escape gesture is ALWAYS an adjacent double, so a
    ///     reach-back cancel is never one.
    /// Only then do the standard validity/exception rules decide.
    /// NON-mutating (scratch-free) so `peekCommitText` can share it verbatim.
    private func shouldRestoreRaw() -> Bool {
        // ORDER IS THE POLICY. The cancel branch comes FIRST: a TRAILING escape
        // gesture (adjacent double modifier as the word's final keystroke — the user
        // is LOOKING at the screen and said "no diacritic, keep the letter") outranks
        // the English dictionary, so "pass"→pas, "off"→of commit exactly what the
        // screen showed. Decided 2026-07-31 (maintainer): screen-truth wins over
        // English-protection — this REVERSES the PR #3-era verdicts that restored
        // trailing-double English words ("pass"/"miss"/"boss") for blind English
        // typists; the cost (a blind-typed "pass" loses its last letter) is accepted
        // because the escape hatch must be reliable: under the old order, literal
        // "pas" was UNTYPEABLE. Scope is TRAILING only — a mid-word double
        // ("office"/"message"/"sorry") still consults the dictionary: nobody escapes
        // mid-word to type "ofice"/"sory", those commits would be pure misspellings.
        // English protection is also untouched where no cancel happened at all
        // ("his"→hís restores "his") and for accidental reach-back cancels
        // ("hosts", span > 1).
        // Từ TOÀN chữ w từ 3 phím trở lên = "www" gõ URL, không phải escape:
        // escape ww→w (user decision 22/07) giữ nguyên khi GÕ LIVE, nhưng ở boundary
        // thì "www." mà chốt thành "ww." là mất chữ thật (field case 19/08,
        // "www.wise.com"→"ww.wise.com"). Restore về raw trả lại đủ w; từ 2 phím (ww)
        // vẫn là escape đúng nghĩa, không đụng.
        if rawCount >= 3 {
            var allW = true
            for i in 0..<rawCount where raw[i] | 0x20 != UInt8(ascii: "w") { allW = false; break }
            if allW { return true }
        }
        if markCancelled {
            if composedIsValidSyllable() { return false }
            // A TONE-key cancel that REACHED BACK over letters (span > 1): the tone key
            // it killed was typed keys ago, so that key is itself a letter the word lost
            // — "hosts"→hots, "asks"→aks, "discs"→dics, "buses"→bues. NOT the deliberate
            // escape (that is the adjacent double, span == 1) — treat as accident:
            // restore the raw keys unless the result is a real English word whose raw
            // keys are not.
            if toneCancelSpan > 1 {
                return !composedIsRecognizedEnglish() || rawIsEnglishContextWord()
            }
            // MID-WORD adjacent double whose raw keys spell a real English word:
            // dictionary wins ("office"→ofice would be a misspelling nobody asked
            // for). Trailing cancels (toneCancelAt == last raw key) skip this — the
            // escape is the final, deliberate act. Mark doublers (toneCancelAt == -1)
            // stay screen-truth as before ("gooogle", "DDDR", "uw").
            if toneCancelAt >= 0, toneCancelAt < rawCount - 1, rawIsEnglishCollision() {
                return true
            }
            // Chat elongation whose tail came from a mark doubler that cancelled
            // ("cosaaaaaaa" → "cóaaaaaa", "ajaaaaaaa" → "ạaaaaaa"): the composition is
            // a valid syllable plus the repeated tail, i.e. exactly what the user meant
            // — keep it even though a diacritic survived the cancel.
            if isTeencodeKeep() { return false }
            // The deliberate literal-letter escape — keep the screen ("pas", "tessted"→
            // tested, "Deffault"→Default: field reports 2026-07-26 / 07-22). Unless
            // free-marking left a diacritic stuck before the cancel, i.e. the cancel
            // did NOT clean the word up ("excess"→"êcs", "lenses"→"lêns").
            return composedHasDiacritic()
        }
        if rawIsEnglishCollision() { return true }
        // `isTeencodeKeep()` runs AFTER the English table above on purpose: the dictionary
        // still wins ("google" restores), and only a word that no dictionary claims gets
        // kept as "valid syllable + repeated tail" ("hôngggg", "vângggg", "đẹpppp").
        if forceRestoreUpperTone || rawIsEnglishException()
            || (!composedIsValidSyllable() && !isTeencodeKeep()) { return true }
        // Context-based (experimental): after an English word, an ambiguous word whose raw
        // keys spell an English word is restored to English ("he is" → "is", not "í").
        // Gated so vniMode/default typing pays nothing (the String build only runs when the
        // flag is on AND the previous word was English).
        if contextualEnglish, previousWordEnglish,
           rawIsEnglishContextWord(includingRestoreOnly: true) { return true }
        return false
    }

    /// True if the current composition still carries any Vietnamese diacritic — a mark
    /// (â/ê/ô/ơ/ư/ă/đ) on any letter, or a pending tone. NON-mutating.
    private func composedHasDiacritic() -> Bool {
        if pTone != .none { return true }
        for k in 0..<pCount where letters[k].mark != .none { return true }
        return false
    }

    /// True if the composed form is itself a recognized English word (collision table or
    /// context whitelist) — the tone-cancel escape ("iss"→is, "Deffault"→Default) vs a
    /// mangled letter-drop ("possess"→posess). NON-mutating; boundary-only (one String).
    private func composedIsRecognizedEnglish() -> Bool {
        guard outCount >= 2, outCount <= 12 else { return false }
        var v = String.UnicodeScalarView()
        v.reserveCapacity(outCount)
        for i in 0..<outCount {
            var b = out[i]
            if b >= 0x41, b <= 0x5A { b |= 0x20 }
            guard b >= 0x61, b <= 0x7A else { return false }   // non-ascii ⇒ not English
            v.append(Unicode.Scalar(b)!)
        }
        let w = String(v)
        return EnglishCollisions.words.contains(w) || EnglishContextWords.words.contains(w)
    }

    /// How a committed word affects the NEXT word's context. THREE-way, not binary:
    /// - `.english`   — a recognized English word (whitelist / collision / exception):
    ///                   start or continue an English run (seed context = English).
    /// - `.vietnamese`— a valid Vietnamese syllable: end the English run (context = VN).
    /// - `.neutral`   — a loanword / foreign / brand token that is neither (e.g. "email",
    ///                   "app", "wifi"): PRESERVE the current context. This is what makes
    ///                   "email bán" stay Vietnamese (email doesn't start an English run)
    ///                   while "the email is" keeps the English run "the" opened.
    enum WordContext { case english, vietnamese, neutral }
    /// Classify by what was ACTUALLY committed (so it never disagrees with the screen):
    /// - restored to raw ascii → English if it's a recognized English word, else `.neutral`
    ///   (a loanword/foreign token like "email" that was only restored because it isn't a
    ///   VN syllable — must NOT open an English run);
    /// - kept a composition WITH a Vietnamese diacritic ("lít", "được") → `.vietnamese`;
    /// - kept plain ascii (no transform): English if recognized ("he", "the"), else VN.
    private func isRecognizedEnglish() -> Bool {
        rawIsEnglishContextWord() || rawIsEnglishCollision() || rawIsEnglishException()
    }
    private func classifyWordContext(restored: Bool) -> WordContext {
        // A Vietnamese diacritic actually ON SCREEN outranks everything. Tested on the
        // OUTPUT, not on "differs from raw": a cancelled transform ("thiss" → plain
        // ascii "this") also differs, and calling that Vietnamese is what made
        // "thiss is" come out "this í" (field report 2026-08-14).
        if !restored, compositionHasDiacritic() { return .vietnamese }
        if isRecognizedEnglish() { return .english }            // "he", "the", collisions
        // Escape-typed English: the doubled key that cancels the transform leaves the
        // real word on screen while the RAW keys ("thiss", "gooogle") are in no
        // dictionary. Ask the same dictionaries about what the user actually SEES.
        if let word = composedAsciiWord(),
           EnglishContextWords.words.contains(word)
            || EnglishCollisions.words.contains(word)
            || EnglishContextWords.neutralLoanwords.contains(word) {
            return EnglishContextWords.neutralLoanwords.contains(word) ? .neutral : .english
        }
        // Neutral loanwords ("email", "app", "wifi") and restore-only interjections
        // ("ok", "wow", "hi" — designed to never OPEN a run, see restoreOnly):
        // Vietnamese sentences use them constantly — preserve the context (neither
        // open nor end a run), or "email bans" would keep "bans" instead of "bán"
        // and "ok cams" would keep "cams" instead of "cám".
        if rawIsNeutralLoanword() || rawIsEnglishContextWord(includingRestoreOnly: true) {
            return .neutral
        }
        // Toneless-Vietnamese typing ("sao", "khong") keeps the context Vietnamese.
        if !restored, SyllableValidator.isValidSyllable(composed.lowercased()) { return .vietnamese }
        // Everything left is a word NO Vietnamese syllable can be — untouched
        // ("github") or restored-to-raw ("position", whose restore is a textual
        // no-op) — and that structure is as strong an English-run signal as a
        // dictionary hit. The dictionaries deliberately can't carry these: the
        // collision table only holds words the engine MANGLES, and a word the
        // validator refuses to compose is exactly the word that never gets mangled.
        // Field report 2026-08-14: "position is" → "position í" — "position" fell
        // to the old defaults (.neutral when restored, .vietnamese when untouched)
        // and never opened the English run.
        return .english
    }

    /// Raw keystrokes spell a neutral loanword (see EnglishContextWords.neutralLoanwords).
    private func rawIsNeutralLoanword() -> Bool {
        guard rawCount > 0, rawCount <= EnglishContextWords.maxLength else { return false }
        var v = String.UnicodeScalarView()
        v.reserveCapacity(rawCount)
        for i in 0..<rawCount {
            var b = raw[i]
            if b >= UInt8(ascii: "A"), b <= UInt8(ascii: "Z") { b |= 0x20 }
            guard b >= UInt8(ascii: "a"), b <= UInt8(ascii: "z") else { return false }
            v.append(Unicode.Scalar(b))
        }
        return EnglishContextWords.neutralLoanwords.contains(String(v))
    }

    /// Fold the just-committed word into the cross-word context (only when the feature is on).
    private mutating func updateContext(restored: Bool) {
        guard contextualEnglish, rawCount > 0 else { return }
        switch classifyWordContext(restored: restored) {
        case .english:    previousWordEnglish = true
        case .vietnamese: previousWordEnglish = false
        case .neutral:    break                       // loanword/foreign: preserve
        }
    }

    /// Raw keystrokes spell a common English word (see EnglishContextWords). NON-mutating.
    /// `includingRestoreOnly` also accepts the interjection layer (wow/ok/hey…): those
    /// must be RESTORED inside an English run but must never OPEN one, so the context
    /// classifier calls this with the default (false) and only the restore decision
    /// passes true.
    private func rawIsEnglishContextWord(includingRestoreOnly: Bool = false) -> Bool {
        guard rawCount > 0, rawCount <= EnglishContextWords.maxLength else { return false }
        var v = String.UnicodeScalarView()
        v.reserveCapacity(rawCount)
        for i in 0..<rawCount {
            var b = raw[i]
            if b >= UInt8(ascii: "A"), b <= UInt8(ascii: "Z") { b |= 0x20 }
            guard b >= UInt8(ascii: "a"), b <= UInt8(ascii: "z") else { return false }
            v.append(Unicode.Scalar(b))
        }
        let w = String(v)
        if EnglishContextWords.words.contains(w) { return true }
        return includingRestoreOnly && EnglishContextWords.restoreOnly.contains(w)
    }

    /// Clear the cross-word English context (caller: focus change / app switch), so a new
    /// typing context doesn't inherit the previous field's last word.
    public mutating func resetContext() { previousWordEnglish = false }

    /// Final text to commit at a word boundary, with auto-restore applied
    /// (non-Vietnamese syllables fall back to the raw keystrokes). Resets the engine.
    /// Used by the marked-text controller path.
    public mutating func commitText(autoRestore: Bool) -> String {
        defer { resetWord() }
        // Overflowed: never restore to `rawKeystrokes` (only the first 32 keys) —
        // return the composed prefix unchanged; the caller keeps the rest on screen.
        if overflowed {
            if contextualEnglish { previousWordEnglish = false }
            reopenRawCount = 0; reopenOutCount = 0                 // stale prefix: never re-open
            return composed
        }
        // Decide with the PREVIOUS word's context, then refresh it for the NEXT word
        // (reusing the restore decision — no repeated checks).
        let wantsRestore = autoRestore && outCount > 0 && shouldRestoreRaw()
        captureReopen(restored: wantsRestore)
        updateContext(restored: wantsRestore)
        return wantsRestore ? rawKeystrokes : composed
    }

    /// Non-mutating twin of `commitText(autoRestore:)`: điều boundary SẼ chốt,
    /// không reset, không đụng state — caller (suggestion bar iOS) peek mỗi phím
    /// trực tiếp trên engine, khỏi COW-copy cả struct (~10 buffer cố định mỗi
    /// lần copy khi `commitText` mutate). Phải trả về byte-identical với
    /// `{ var e = self; return e.commitText(autoRestore:) }`.
    public func peekCommitText(autoRestore: Bool) -> String {
        // Overflowed: mirror commitText — composed prefix, không bao giờ restore.
        if overflowed { return composed }
        if autoRestore, outCount > 0, shouldRestoreRaw() {
            return rawKeystrokes
        }
        return composed
    }

    /// Common English words whose FULL-Telex transform collides with a VALID
    /// Vietnamese syllable, so validity-based auto-restore keeps the Vietnamese
    /// ("was"→ứa, "wow"→Ươ). Force-restored at the boundary instead — the reverse
    /// of the "đc" whitelist. Zero-alloc byte compare on the raw keys; extend as
    /// field reports arrive (candidate for a user-editable list later).
    private static let englishExceptions: [[UInt8]] = [
        Array("was".utf8), Array("wow".utf8),
        Array("yes".utf8),   // "ýe" slips through the validator as a syllable
    ]
    /// Generated English-collision table (EnglishCollisions.swift, gen-english):
    /// top-frequency English words whose default-Telex transform yields a VALID
    /// Vietnamese syllable, so validity-based restore can't catch them
    /// ("his"→hí, "this"→thí, "see"→sê). Boundary-only; the String is built only
    /// after cheap byte pre-filters, never on the per-key hot path.
    private func rawIsEnglishCollision() -> Bool {
        guard englishWordRestore else { return false }
        guard rawCount >= 2, rawCount <= 12 else { return false }
        guard compositionDiffersFromRaw() else { return false }   // untouched words can't collide
        // w-entries count only when the w actually BECAME ư (full Telex) — in
        // Simple Telex the literal-w teencode forms ("wá" = quá) must survive.
        if (raw[0] | 0x20) == UInt8(ascii: "w") {
            let wTransformed = pCount > 0 && renderLetters[0].base == UInt8(ascii: "u")
                && renderLetters[0].mark == .horn
            if !wTransformed { return false }
        }
        var v = String.UnicodeScalarView()
        v.reserveCapacity(rawCount)
        for i in 0..<rawCount {
            var b = raw[i]
            if b >= UInt8(ascii: "A"), b <= UInt8(ascii: "Z") { b |= 0x20 }
            guard b >= UInt8(ascii: "a"), b <= UInt8(ascii: "z") else { return false }
            v.append(Unicode.Scalar(b))
        }
        return EnglishCollisions.words.contains(String(v))
    }

    private func rawIsEnglishException() -> Bool {
        guard pCount > 0 else { return false }
        // w-initiated entries apply ONLY when the w actually BECAME ư (full Telex):
        // in Simple Telex the literal-w teencode forms ("wá" = quá) are the point
        // and must survive. Non-w entries (yes) apply in every mode.
        let wTransformed = renderLetters[0].base == UInt8(ascii: "u")
            && renderLetters[0].mark == .horn
        outer: for word in Self.englishExceptions {
            guard word.count == rawCount else { continue }
            if word[0] == UInt8(ascii: "w"), !wTransformed { continue }
            for i in 0..<rawCount where lowercased(raw[i]) != word[i] { continue outer }
            return true
        }
        return false
    }

    /// Zero-allocation twin of `SyllableValidator.isValidSyllable(String)` on the
    /// current composition: letter classes come from the render copy (post ươ
    /// propagation), the tone from the last render's effective tone.
    /// TEENCODE onsets folded to their canonical spelling FOR VALIDATION ONLY
    /// (rendering keeps the literal letters): w→qu ("wá"=quá, "wó"), z→d/gi/v-class
    /// ("zô", "zị", "zậy"), dz→d ("dzô", "dzị"). The informal onset is swapped and
    /// the REST of the syllable still has to pass the normal rime+tone rules, so
    /// English/garbage stays restorable. f→ph was considered and dropped: it makes
    /// the common English "fair" a valid syllable (fải).
    /// Returns the canonical onset's ascii letters + how many leading letters it
    /// replaces, or nil when the word has no informal onset.
    private func teencodeOnset() -> (canonical: [UInt8], skip: Int)? {
        guard pCount >= 2, renderLetters[0].mark == .none else { return nil }
        switch renderLetters[0].base {
        case UInt8(ascii: "w"): return ([UInt8(ascii: "q"), UInt8(ascii: "u")], 1)
        case UInt8(ascii: "z"): return ([UInt8(ascii: "d")], 1)
        case UInt8(ascii: "d")
            where pCount >= 3 && renderLetters[1].base == UInt8(ascii: "z")
               && renderLetters[1].mark == .none:
            return ([UInt8(ascii: "d")], 2)
        default: return nil
        }
    }

    /// True when every letter parsed so far is a bare CONSONANT (no vowel — a
    /// rendered Đ counts as its consonant base, not a mark exception) and shares
    /// ONE case with `upper`. This is the shape of a Vietnamese initialism typed
    /// with dd for Đ ANYWHERE in the string — "VNĐ", "HTĐ", "HĐND" — not just at
    /// the start ("ĐSQ"/"ĐHQG" already worked: the live-spell-check freeze hadn't
    /// triggered yet when their doubler ran, since a leading 'd' alone doesn't
    /// invalidate any prefix). No real English or Vietnamese WORD is ever
    /// multiple letters with zero vowels — "add"/"odd"/"ladder"/"kidding"/"middle"
    /// all carry a vowel before their "dd" — so this can never fire on them.
    private func isAbbreviationPrefix(upper: Bool) -> Bool {
        guard pCount > 0 else { return false }
        for k in 0..<pCount {
            let l = letters[k]
            if isVowelAscii(l.base) || l.upper != upper { return false }
        }
        return true
    }

    /// Live-spell-check freeze exception (2026-08-06, maintainer-specified feature):
    /// a 'd' that continues a bare-consonant, single-case prefix keeps folding to
    /// Đ even after the word has frozen — see `isAbbreviationPrefix`. VNI spells
    /// Đ with a digit, not by doubling, so it is untouched.
    private func abbreviationDoublerException(lower: UInt8, upper: Bool) -> Bool {
        !pVniMode && lower == UInt8(ascii: "d") && isAbbreviationPrefix(upper: upper)
    }

    /// NON-mutating: letter classes go into a small STACK buffer
    /// (`withUnsafeTemporaryAllocation`, ≤33 bytes — no heap), not `basesScratch`,
    /// so the boundary decision is shareable by `peekCommitText` per keystroke.
    private func composedIsValidSyllable() -> Bool {
        // Đ-initial ABBREVIATIONS (chat shorthand), not real syllables: đ, đc, đm,
        // đk, đkm… survive auto-restore — typing "ddm" keeps đm instead of
        // reverting to raw (generalized from the đc whitelist, user decision
        // 2026-07-22). Shape: leading đ (from dd) + ZERO or more bare consonants,
        // no tone. Vowelled words (đi, đau) take the normal validation path;
        // a literal lowercase "dd…" remains reachable via the ddd cancel.
        if pCount >= 1, lastEffTone == .none,
           renderLetters[0].base == UInt8(ascii: "d"), renderLetters[0].mark == .bar {
            var bareConsonantsOnly = true
            for k in 1..<pCount {
                let l = renderLetters[k]
                if l.mark != .none || isVowelAscii(l.base) { bareConsonantsOnly = false; break }
            }
            if bareConsonantsOnly { return true }
        }
        // Single-case abbreviation whose only transform is DD→Đ ("ĐSQ" = Đại Sứ
        // Quán, "ĐHQG", "VNĐ", "HTĐ", "HĐND"…): the doubled D was deliberate,
        // restoring to raw is strictly worse (ALL-CAPS: user report 2026-07-21;
        // generalized to all-lowercase, "vnđ" etc.: maintainer spec 2026-08-06 —
        // ONE case throughout, never mixed, since a mixed-case word is a real
        // typing attempt, not an initialism). Conditions: every raw key the SAME
        // case, no tone, EVERY letter a bare consonant except the đ bar — a
        // VOWEL anywhere exits the rule (that's a real word attempt, not an
        // initialism: "address"/"ladder" have a vowel before their "dd" and MUST
        // still restore to raw; "ddsqa" — consonants then a trailing vowel — is
        // the same exit, tested explicitly). A literal DD is still reachable
        // through the double-key cancel: DDD → DD (so DDDR → DDR, "ddd" → "dd").
        if lastEffTone == .none, rawCount >= 2 {
            var sameCase = true
            let firstIsUpper = isUpperAscii(raw[0])
            for i in 0..<rawCount where isUpperAscii(raw[i]) != firstIsUpper {
                sameCase = false
                break
            }
            if sameCase {
                var hasBar = false
                var onlyBar = true
                for k in 0..<pCount {
                    let l = renderLetters[k]
                    if isVowelAscii(l.base) { onlyBar = false; break }
                    if l.base == UInt8(ascii: "d"), l.mark == .bar { hasBar = true }
                    else if l.mark != .none { onlyBar = false; break }
                }
                if hasBar, onlyBar { return true }
            }
        }
        // Teencode onset: validate as if spelled canonically ("wá" checks as quá).
        // n ≤ pCount + 1 (canon ≤ 2, skip ≥ 1) nên capacity + 1 luôn đủ.
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Self.capacity + 1) { buf in
            // MỘT đặc cách teencode mỗi từ (19/08/2026, field case "wise.com"→"wíe.com"
            // ở Simple Telex): onset teencode (w→qu) CHỒNG rime teencode ("ie") cho
            // "wíe" validate thành "quíe" → boundary không restore, "wise"/"wife" chết
            // thành wíe/wìe. Rime teencode CÓ THANH duy nhất chạm được từ ascii trần
            // là "ie" ("oy" đòi zero-onset, "ưm/ưn" đòi ư có dấu, "ou" chỉ nhận
            // không-thanh nên composed ≡ raw — không stack được) nên guard shape đó:
            // phần sau onset là đúng hai chữ i-e trần → bỏ nhánh teencode-onset,
            // để đường validate thường (onset 'w' không hợp lệ) từ chối và restore.
            let stacksTeencodeRime = pCount >= 3
                && renderLetters[pCount - 2].base == UInt8(ascii: "i")
                && renderLetters[pCount - 2].mark == .none
                && renderLetters[pCount - 1].base == UInt8(ascii: "e")
                && renderLetters[pCount - 1].mark == .none
                && teencodeOnset().map { $0.skip == pCount - 2 } ?? false
            if !stacksTeencodeRime, pCount < Self.capacity - 1, let (canon, skip) = teencodeOnset() {
                var n = 0
                for c in canon { buf[n] = Tables.letterClass(base: c, mark: .none); n += 1 }
                for k in skip..<pCount {
                    buf[n] = Tables.letterClass(base: renderLetters[k].base,
                                                mark: renderLetters[k].mark)
                    n += 1
                }
                if SyllableValidator.isValidSyllable(classes: buf, count: n,
                                                     tone: lastEffTone) { return true }
            }
            for k in 0..<pCount {
                buf[k] = Tables.letterClass(base: renderLetters[k].base,
                                            mark: renderLetters[k].mark)
            }
            return SyllableValidator.isValidSyllable(classes: buf, count: pCount,
                                                     tone: lastEffTone)
        }
    }

    // MARK: - Teencode elongation ("hôngggg", "cóaaaa", "ạaaaa", "đẹpppp")

    /// Chat elongation: the letters split as a VALID syllable HEAD followed by a TAIL
    /// that is a run of ONE repeated letter ("hôn"+"gggg", "có"+"aaaa", "ạ"+"aaaa",
    /// "đẹp"+"pppp"). Returns the head letter count, or -1 when the word has no such
    /// shape.
    ///
    /// The run must be at least THREE letters. Two was the first design (2026-08-04) and
    /// it cost 24 English words in the regression suite: English doubles letters all the
    /// time, so "wall"→ưall, "balls"→báll, "eggs"→égg, "apps"→ápp, "ascii"→ácii,
    /// "wifi"→ừii all became "valid syllable + run of 2" and stopped restoring. NO
    /// English or Vietnamese word TRIPLES a letter, so ≥3 is the shape that means "the
    /// user is leaning on a key" and nothing else. Cost: "hoongg" (2 g's) still restores
    /// to raw — one repeat short of an elongation.
    ///
    /// The SHORTEST valid head wins. That is what keeps the tone where the user saw it
    /// before the elongation started: "cosaaaaaaa" has both splits "co"+"aaaaaa" and
    /// "coa"+"aaaaa" (both heads are real rimes), and only the shortest one puts the
    /// sắc back on the o — "cóaaaaaa", not "coáaaaa". The longest tail also matches the
    /// intent: everything after the syllable is the user leaning on one key.
    ///
    /// NON-mutating; reads `renderLetters` (post ươ-propagation), so callers must have
    /// rendered first. Allocation-free (the head check uses a stack buffer).
    private func elongationHeadCount(_ count: Int, tone: Tone) -> Int {
        let minRun = 3
        guard count >= minRun + 1 else { return -1 }
        // Cheap gate first: the word must END in `minRun` copies of one letter.
        // Everything else (validator work) sits behind this, so ordinary typing pays a
        // couple of byte compares per keystroke.
        let last = renderLetters[count - 1]
        for j in (count - minRun)..<(count - 1) {
            guard renderLetters[j].base == last.base,
                  renderLetters[j].mark == last.mark else { return -1 }
        }
        var runStart = count - minRun
        while runStart > 0,
              renderLetters[runStart - 1].base == last.base,
              renderLetters[runStart - 1].mark == last.mark { runStart -= 1 }
        if runStart < 1 { runStart = 1 }          // the head needs at least one letter
        var k = runStart
        while k <= count - minRun {               // tail length ≥ minRun
            if isValidHead(k, tone: tone) { return k }
            k += 1
        }
        return -1
    }

    /// Valid-syllable check over `renderLetters[0..<k]` with an explicit tone — the head
    /// half of the elongation split. Teencode onsets (w→qu, z→d, dz→d) fold exactly like
    /// `composedIsValidSyllable`, and the stop-coda tone rule is applied to the HEAD's
    /// coda. NON-mutating, stack buffer, no heap.
    private func isValidHead(_ k: Int, tone: Tone) -> Bool {
        guard k >= 1, k <= Self.capacity else { return false }
        var t = tone
        if t == .grave || t == .hook || t == .tilde, hasStopCoda(k) { t = .none }
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Self.capacity + 1) { buf in
            if let (canon, skip) = teencodeOnset(), skip < k {
                var n = 0
                for c in canon { buf[n] = Tables.letterClass(base: c, mark: .none); n += 1 }
                for j in skip..<k {
                    buf[n] = Tables.letterClass(base: renderLetters[j].base,
                                                mark: renderLetters[j].mark)
                    n += 1
                }
                if SyllableValidator.isValidSyllable(classes: buf, count: n, tone: t) { return true }
            }
            for j in 0..<k {
                buf[j] = Tables.letterClass(base: renderLetters[j].base,
                                            mark: renderLetters[j].mark)
            }
            return SyllableValidator.isValidSyllable(classes: buf, count: k, tone: t)
        }
    }

    /// Boundary keep rule for chat elongation: the composition is not a valid syllable
    /// on its own, but it IS one plus a repeated tail the user typed on purpose
    /// ("hôngggg", "cóaaaa", "ạaaaa", "đẹpppp") — commit what is on screen instead of
    /// snapping back to the raw keystrokes. Boundary-only (one word), NON-mutating.
    private func isTeencodeKeep() -> Bool {
        elongationHeadCount(pCount, tone: lastEffTone) > 0
    }

    /// True when the composed scalars differ from the raw keystrokes (i.e. some
    /// transform actually happened) — compared numerically, no Strings.
    private func compositionDiffersFromRaw() -> Bool {
        if outCount != rawCount { return true }
        for i in 0..<outCount where out[i] != UInt32(raw[i]) { return true }
        return false
    }

    /// Is there a Vietnamese diacritic ACTUALLY ON SCREEN? Non-ascii output is exactly
    /// that: every Telex transform that survives to the screen produces a non-ascii
    /// scalar (â ê ô ơ ư đ + tones), and nothing else can.
    ///
    /// Distinct from `compositionDiffersFromRaw()`, which is also true when the diff is
    /// a CANCELLED transform — "thiss" (doubled s to escape the tone) composes plain
    /// ascii "this" yet differs from its raw keys. The context classifier needs THIS
    /// question; using the other one called escaped English words Vietnamese (field
    /// report 2026-08-14: "thiss is" → "this í").
    private func compositionHasDiacritic() -> Bool {
        for i in 0..<outCount where out[i] > 127 { return true }
        return false
    }

    /// The composed text, lowercased ascii, when it is PURE ascii — the form an escaped
    /// English word ends up in ("thiss" → "this", "gooogle" → "google"). nil when the
    /// composition carries a diacritic (then it is Vietnamese, not a dictionary word) or
    /// is longer than any word we look up. Lets the English dictionaries answer for the
    /// escape class, whose RAW keys ("thiss") no dictionary can carry.
    private func composedAsciiWord() -> String? {
        guard outCount > 0, outCount <= EnglishContextWords.maxLength else { return nil }
        var v = String.UnicodeScalarView()
        v.reserveCapacity(outCount)
        for i in 0..<outCount {
            var c = out[i]
            if c > 127 { return nil }
            if c >= UInt32(UInt8(ascii: "A")), c <= UInt32(UInt8(ascii: "Z")) { c |= 0x20 }
            guard c >= UInt32(UInt8(ascii: "a")), c <= UInt32(UInt8(ascii: "z")),
                  let scalar = Unicode.Scalar(c) else { return nil }
            v.append(scalar)
        }
        return String(v)
    }

    /// Uppercase tone/mark key preceded by a lowercase letter (camelCase like
    /// "SaaS", "OmS", "JavaScript") → English/code, freeze/restore to raw even if
    /// the composed form is a valid syllable. `upperToneKey` already encodes the
    /// "a lowercase came before it" test (see `hasLowercaseBefore`), so an uppercase
    /// tone key that is first ("OSm") or in an all-caps word ("VIEEJT") never sets it.
    private var forceRestoreUpperTone: Bool { upperToneKey }

    /// True if any raw keystroke before index `at` is a lowercase ascii letter.
    /// True if the FIRST raw key that produced letter `idx` was a w — i.e. the
    /// letter is a standalone-w ư, not a typed u that a later w horned.
    @inline(__always)
    private func letterCreatedByW(_ idx: Int) -> Bool {
        for i in 0..<rawCount where rawLetter[i] == idx {
            return raw[i] == UInt8(ascii: "w") || raw[i] == UInt8(ascii: "W")
        }
        return false
    }

    @inline(__always)
    private func hasLowercaseBefore(_ at: Int) -> Bool {
        for i in 0..<at where raw[i] >= UInt8(ascii: "a") && raw[i] <= UInt8(ascii: "z") {
            return true
        }
        return false
    }

    /// Drop the current word AND the re-open snapshot. What callers use when the
    /// composition is abandoned (focus change, app switch, caret moved): after this
    /// no ⌫ may re-open anything, because the text before the caret is unknown.
    public mutating func reset() {
        resetWord()
        reopenRawCount = 0
        reopenOutCount = 0
    }

    /// Word state only; the re-open snapshot survives. The boundary commits capture
    /// the snapshot and then clear the word through THIS — a full `reset()` would
    /// wipe what they just captured.
    private mutating func resetWord() {
        rawCount = 0
        outCount = 0
        markCancelled = false
        toneCancelAt = -1
        toneCancelSpan = 0
        upperToneKey = false
        overflowed = false
        disabledAtCount = Int.max
        pCount = 0
        pTone = .none
        pToneKeyCount = 0
        pCancelled = false
        pToneCancelAt = -1
        pToneCancelSpan = 0
        pProcessed = 0
    }

    /// True if the current parse state's first `n` letters form a valid Vietnamese
    /// syllable prefix. Walks the validator's flat tries over the letters' folded
    /// bases (bit 7 = carries a mark) — no String, no hashing, no allocation.
    private mutating func prefixIsValid(_ n: Int) -> Bool {
        // Teencode onsets validate as their canonical spelling ("w…" as "qu…",
        // "z…"/"dz…" as "d…") so live spell-check doesn't freeze "wá"/"zô"-class
        // words at their very first key. Mirrors teencodeOnset() on the PARSE
        // letters (render hasn't happened yet on this path).
        var out = 0
        var start = 0
        if n >= 1, letters[0].mark == .none, n < Self.capacity - 1 {
            switch letters[0].base {
            case UInt8(ascii: "w"):
                basesScratch[0] = UInt8(ascii: "q"); basesScratch[1] = UInt8(ascii: "u")
                out = 2; start = 1
            case UInt8(ascii: "z"):
                basesScratch[0] = UInt8(ascii: "d"); out = 1; start = 1
            case UInt8(ascii: "d")
                where n >= 2 && letters[1].base == UInt8(ascii: "z") && letters[1].mark == .none:
                basesScratch[0] = UInt8(ascii: "d"); out = 1; start = 2
            default: break
            }
        }
        for k in start..<n {
            basesScratch[out] = letters[k].base | (letters[k].mark != .none ? 0x80 : 0)
            out += 1
        }
        return SyllableValidator.isValidPrefix(bases: basesScratch, count: out)
    }

    // MARK: - Test / caller helpers

    /// TRUE while the current word has exceeded the 32-key capacity. Callers need this
    /// to tell an overflow `.passthrough` (key NOT recorded — the app must render and
    /// delete natively) from an ordinary literal-letter `.passthrough` (key recorded,
    /// composition still live). The action alone cannot distinguish the two.
    public var isOverflowed: Bool { overflowed }

    /// Current composed word.
    public var composed: String {
        var s = String.UnicodeScalarView()
        s.reserveCapacity(outCount)
        for i in 0..<outCount { s.append(Unicode.Scalar(out[i])!) }
        return String(s)
    }

    /// The raw keystrokes typed for the current word.
    public var rawKeystrokes: String {
        var s = String.UnicodeScalarView()
        s.reserveCapacity(rawCount)
        for i in 0..<rawCount { s.append(Unicode.Scalar(raw[i])) }
        return String(s)
    }

    /// Test-only (internal): the cancel snapshots `shouldRestoreRaw` decides on, and the
    /// live parse state they must mirror. Any freeze/rebuild that changes the parse has
    /// to re-take the snapshots — a stale pair makes the boundary commit decide on
    /// pre-freeze data. Compared key-by-key by the regression tests; not part of the
    /// public API.
    var debugCancelSnapshot: (cancelled: Bool, at: Int, span: Int) {
        (markCancelled, toneCancelAt, toneCancelSpan)
    }
    var debugParseCancelState: (cancelled: Bool, at: Int, span: Int) {
        (pCancelled, pToneCancelAt, pToneCancelSpan)
    }
    /// Test-only (internal): raw index from which live spell-check froze the word
    /// (`Int.max` = not frozen).
    var debugFreezeAt: Int { disabledAtCount }

    // MARK: - Rendering

    @inline(__always)
    private mutating func copyOut(_ n: Int) {
        for i in 0..<n { out[i] = scratch[i] }
        outCount = n
    }

    /// Render the current parse state into `scratch` (composed scalars) and return
    /// the count. Copies `letters` into `renderLetters` first, then applies the two
    /// post-passes (ươ propagation, tone placement) on the COPY — the persistent
    /// parse state stays exactly the raw fold, so incremental steps never see a
    /// post-pass side effect.
    private mutating func render() -> Int {
        let count = pCount
        for k in 0..<count { renderLetters[k] = letters[k] }

        // ươ propagation: in a "uo" cluster, if EITHER letter is horned, mirror it
        // onto the other so both become ươ — in a closed syllable (coda/offglide
        // after), and not the "qu" glide. This covers both key orders, so fast
        // typing that reorders o/w ("uow" vs "uwo") still yields ươ: trường, được,
        // nước, người, sương. Stays plain "uơ" when the o is the last letter (open:
        // thuở, huơ) or after "qu" (quở, quởn).
        for k in 1..<max(1, count) {
            guard renderLetters[k - 1].base == UInt8(ascii: "u"),
                  renderLetters[k].base == UInt8(ascii: "o") else { continue }
            let prevHorn = renderLetters[k - 1].mark == .horn
            let curHorn = renderLetters[k].mark == .horn
            guard prevHorn != curHorn else { continue }   // exactly one horned
            let oIsLast = (k == count - 1)
            let isQuGlide = (k >= 2 && renderLetters[k - 2].base == UInt8(ascii: "q"))
            if !oIsLast && !isQuGlide {
                renderLetters[k - 1].mark = .horn
                renderLetters[k].mark = .horn
            }
        }

        // Tone placement; map deferred tone/z keys onto the toned vowel (or the
        // last letter when there is no tone, so they group with it for backspace).
        var effTone = pTone
        // TEENCODE elongation: a repeated tail ("cosaaaaaaa", "ajaaaa") is NOT part of
        // the syllable, so it must not attract the tone — place the mark inside the
        // valid head only ("cóaaaaaa", "ạaaaaaa"; without the cap free-marking drifts
        // the tone onto the first tail vowel: "coáaaaa", "aạaaaa"). Gated on "a tone is
        // pending AND the word ends in a doubled letter", so normal words pay nothing.
        var toneScope = count
        if pTone != .none {
            let head = elongationHeadCount(count, tone: pTone)
            if head > 0 { toneScope = head }
        }
        var toneIdx = pTone == .none ? -1 : toneVowelIndex(toneScope)
        // Stop codas (-c, -ch, -p, -t) only allow sắc (´) and nặng (.). Drop an
        // invalid huyền/hỏi/ngã (e.g. "batf" stays "bat", not "bàt").
        if toneIdx >= 0, effTone == .grave || effTone == .hook || effTone == .tilde,
           hasStopCoda(toneScope) {
            effTone = .none
            toneIdx = -1
        }
        let target = toneIdx >= 0 ? toneIdx : max(0, count - 1)
        for j in 0..<pToneKeyCount { rawLetter[toneKeys[j]] = target }
        lastEffTone = effTone

        for k in 0..<count {
            let u = renderLetters[k]
            var scalar = Tables.markedScalar(base: u.base, mark: u.mark, upper: u.upper)
            if k == toneIdx { scalar = Tables.applyTone(scalar, effTone) }
            scratch[k] = scalar
        }
        return count
    }

    // MARK: - Incremental parse (one fold step per key)

    /// Rebuild the whole parse state by replaying every raw key. Used by backspace
    /// (raw changed non-append) and mid-word parse-setting flips; identical to the
    /// incremental path because the parse is a pure left-to-right fold.
    /// Rebuild reproducing what forward typing PUT ON SCREEN for the current raw
    /// keys + freeze state: keys replay faithfully (a cancelled tone stays a
    /// cancel), then — only if the frozen word still carries a pending tone — a
    /// second pass folds the tone keys to literals, exactly like feed() did at the
    /// freeze site. One-pass for the common cases; the second pass is ⌫-only cost.
    private mutating func rebuildFrozenAware() {
        rebuildParseState()
        if disabledAtCount != Int.max, pTone != .none {
            pFoldTones = true
            rebuildParseState()
            pFoldTones = false
        }
    }

    /// Recompute the live-spell-check freeze point (`disabledAtCount`) from scratch by
    /// replaying the word one key at a time — exactly what forward typing computed
    /// incrementally. Needed whenever the freeze can no longer be extended from the
    /// previous state: ⌫ (the word SHRANK — lifting the freeze permanently re-applied
    /// transforms retroactively, frozen "installer" ⌫ became "intálle") and a mid-word
    /// `liveSpellCheck` flip (the flag's verdict covers the whole word). The replay is
    /// bounded (≤32 keys, parseStep is ~ns) and never runs on the hot per-key path.
    /// Leaves the parse state built for the FULL word but possibly not fold-aware —
    /// callers must follow with `rebuildFrozenAware()`.
    private mutating func recomputeFreeze() {
        // An upper-tone freeze (mixed-case English/code, `disabledAtCount == 0`) is not
        // a spell-check verdict, so spell-check must not clear it while it still holds.
        if disabledAtCount == 0, forceRestoreUpperTone, !liveSpellCheck { return }
        let full = rawCount
        disabledAtCount = Int.max
        guard liveSpellCheck else { return }
        var r = 1
        while r <= full {
            rawCount = r
            rebuildParseState()
            if disabledAtCount == Int.max, pCount > 0, !prefixIsValid(pCount) {
                // Same teencode-elongation escape forward typing applies. render()
                // fills `renderLetters` for the split check; every buffer it touches is
                // rebuilt by the caller's `rebuildFrozenAware()` + `render()` after.
                _ = render()
                if elongationHeadCount(pCount, tone: pTone) <= 0 { disabledAtCount = r }
            }
            r += 1
        }
        rawCount = full
        // A freeze the extra characters have since EXPLAINED must be lifted: "quafa"
        // freezes on the first stray 'a' and the second one turns the tail into an
        // elongation ("quàaa"). The walk above can't see that (it stops looking once
        // frozen), so re-test the whole word unfrozen — this is the ⌫/replay twin of
        // feed()'s unfreeze step, so both paths agree on the final freeze state.
        if disabledAtCount != Int.max {
            let frozenAt = disabledAtCount
            disabledAtCount = Int.max
            rebuildParseState()
            _ = render()
            if elongationHeadCount(pCount, tone: pTone) <= 0 { disabledAtCount = frozenAt }
        }
    }

    private mutating func rebuildParseState() {
        pCount = 0
        pTone = .none
        pToneKeyCount = 0
        pCancelled = false
        pToneCancelAt = -1
        pToneCancelSpan = 0
        upperToneKey = false
        pFreeMarking = freeMarking
        pSimpleTelex = simpleTelex
        pQuickTelex = quickTelex
        pVniMode = vniMode
        pBracketVowels = bracketVowels
        pLiveSpellCheck = liveSpellCheck
        for i in 0..<rawCount { rawLetter[i] = -1 }
        for i in 0..<rawCount { parseStep(i) }
        pProcessed = rawCount
    }

    /// Fold raw key `at` into the parse state (`letters`, `pTone`, provenance…).
    /// This is the single-key body of the historical whole-word parse loop; feeding
    /// keys one at a time through it is equivalent to re-parsing the word.
    /// Bracket → the horned vowel it types, or nil. `{`/`}` are the shifted keys, so
    /// they carry the uppercase flag. Pure + static so both `feed`'s gate and the parse
    /// read one definition.
    static func bracketVowel(_ key: UInt8) -> (base: UInt8, upper: Bool)? {
        switch key {
        case UInt8(ascii: "["): return (UInt8(ascii: "o"), false)   // ơ
        case UInt8(ascii: "]"): return (UInt8(ascii: "u"), false)   // ư
        case UInt8(ascii: "{"): return (UInt8(ascii: "o"), true)    // Ơ
        case UInt8(ascii: "}"): return (UInt8(ascii: "u"), true)    // Ư
        default: return nil
        }
    }

    private mutating func parseStep(_ at: Int) {
        let key = raw[at]
        let lower = lowercased(key)
        let upper = isUpperAscii(key)

        // (The historical pWWord "leading w = English word" guard is GONE — it
        // blocked the teencode w-forms in Simple Telex ("wá" = quá, "wó"…). English
        // w-words are protected by englishExceptions + auto-restore instead.)

        // Once a diacritic has been cancelled, the word is English: every further
        // key is literal (no tone/mark), so "messs"→mess (not "més") and the whole
        // token stays as typed. The cancel itself is handled by the branches below,
        // which set `pCancelled`; from the next key on this short-circuits.
        // Cancelled diacritic, OR live spell-check froze the word from here on:
        // emit every remaining key literally (no tone/mark transforms) — UNLESS
        // this 'd' continues a bare-consonant abbreviation prefix (VNĐ, HTĐ,
        // HĐND…), where dd→Đ must still fire (see abbreviationDoublerException).
        if pCancelled || (at >= disabledAtCount && !abbreviationDoublerException(lower: lower, upper: upper)) {
            appendLetter(base: lower, mark: .none, upper: upper)
            rawLetter[at] = pCount - 1
            return
        }

        // Bracket vowels (opt-in): `[`→ơ, `]`→ư, `{`/`}` uppercase. Emitted as a
        // FINISHED horned letter, not as an o+w pair — one keystroke, one letter, so ⌫
        // removes the whole vowel and ươ words compose from the letters themselves
        // ("tr" + ] + [ + "ng" → letters t,r,ư,ơ,n,g = trương, no propagation needed).
        // AFTER the freeze/cancel branch above on purpose: in a word already frozen as
        // English/code the bracket must stay the literal character it is.
        if pBracketVowels, let bracket = Self.bracketVowel(key) {
            appendLetter(base: bracket.base, mark: .horn, upper: bracket.upper)
            rawLetter[at] = pCount - 1
            return
        }

        // VNI: letters literal, digits carry the diacritics. Separate fold entirely —
        // none of the Telex letter transforms (tone letters, w, doublers, dd) apply.
        if pVniMode {
            parseStepVNI(at, key: key, lower: lower, upper: upper)
            return
        }

        // Tone keys: s f r x j
        if let t = toneForKey(lower) {
            // Second pass of a frozen-word rebuild with a PENDING tone: every
            // tone key folds back to its literal letter, even those typed BEFORE
            // the freeze point — a tone has no meaning on a non-Vietnamese word,
            // and keeping it made "installer" render "intáller" (the early s
            // floated as sắc onto the post-freeze a). Gated on pFoldTones (not the
            // freeze itself): a rebuild of a frozen word must otherwise replay
            // history faithfully — in particular a CANCELLED tone stays cancelled,
            // see pFoldTones.
            if pFoldTones {
                appendLetter(base: lower, mark: .none, upper: upper)
                rawLetter[at] = pCount - 1
                return
            }
            if hasVowel(pCount) {
                if pTone == t {
                    pTone = .none // double same tone -> cancel, emit literal
                    pCancelled = true; pToneCancelAt = at
                pToneCancelSpan = pToneKeyCount > 0 ? at - toneKeys[pToneKeyCount - 1] : 1
                    appendLetter(base: lower, mark: .none, upper: upper)
                    rawLetter[at] = pCount - 1
                    // The canceled tone's ORIGINAL key(s) are orphaned now: with no
                    // tone, render mapped them to the LAST letter of the word — so
                    // a later ⌫ on an unrelated trailing letter dragged them out of
                    // raw too, and the re-parse RESURRECTED the tone ("airrw" ⌫
                    // gave ải instead of air — tester bug 2026-07-23). Pair them
                    // with this literal letter instead: ⌫ on the displayed 'r'
                    // removes both r keys, ⌫ on anything else leaves them alone.
                    for j in 0..<pToneKeyCount where rawLetter[toneKeys[j]] == -1 {
                        rawLetter[toneKeys[j]] = pCount - 1
                    }
                    pToneKeyCount = 0
                } else {
                    pTone = t
                    // English/code signal ONLY when a lowercase letter came BEFORE
                    // this uppercase tone key (camelCase: "OmS"). If the uppercase
                    // tone key is first / precedes any lowercase ("OSm", "VIEEJT"),
                    // it's just a capital, so keep the tone ("OSm"→Óm).
                    if upper && hasLowercaseBefore(at) { upperToneKey = true }
                    rawLetter[at] = -1                    // mapped to the toned vowel at render
                    toneKeys[pToneKeyCount] = at; pToneKeyCount += 1
                }
            } else {
                appendLetter(base: lower, mark: .none, upper: upper)
                rawLetter[at] = pCount - 1
            }
            return
        }

        // z: clear tone if there is one; otherwise it's a literal letter. Matching
        // OpenKey (`removeMark(); if !isChanged insertKey`): `z` is NOT an absolute
        // control key — it only vanishes when it actually removes a tone. With no
        // tone to clear it types through ("z"→z, "pizza"→pizza, "xyz"→xyz), instead
        // of being silently swallowed.
        if lower == UInt8(ascii: "z") {
            if pTone != .none {                          // a tone to clear -> consume z
                pCancelled = true; pToneCancelAt = at
                pToneCancelSpan = pToneKeyCount > 0 ? at - toneKeys[pToneKeyCount - 1] : 1
                pTone = .none
                if upper && hasLowercaseBefore(at) { upperToneKey = true }
                rawLetter[at] = -1
                toneKeys[pToneKeyCount] = at; pToneKeyCount += 1
            } else {                                     // nothing to clear -> literal z
                appendLetter(base: lower, mark: .none, upper: upper)
                rawLetter[at] = pCount - 1
            }
            return
        }

        // w: breve / horn modifier, or standalone ư. The modifier reaches back
        // over any coda to the nearest a/o/u, so "quatw"->quăt, "moiw"->mơi,
        // "nguoiwf"->người even when w is typed after the final consonant.
        if lower == UInt8(ascii: "w") {
            var tIdx = -1
            var k = pCount - 1
            while k >= 0 {
                let b = letters[k].base
                if b == UInt8(ascii: "a") || b == UInt8(ascii: "o") || b == UInt8(ascii: "u") { tIdx = k; break }
                // Strict (Minimal Telex): the horn/breve may cross intervening
                // vowels (offglides: người) but NOT a consonant coda, so "trangw"
                // and "quatw" stay literal. Free mode scans all the way back.
                if !freeMarking && !isVowelAscii(b) { break }
                k -= 1
            }
            // "ua" nucleus: w horns the u (→ ưa: mưa, chưa, nữa), not breve the a
            // — "uă" is not a valid Vietnamese nucleus. So an unmarked 'a' target
            // whose immediate predecessor is a REAL, unmarked 'u' vowel retargets
            // to that u. Excludes the "qu" glide ("quatw"→quăt) and "oa" (→ oă:
            // hoăc), where breve on a is correct. Makes marks order-free:
            // "nuawx" and "nuwax" both give "nữa".
            if tIdx >= 1,
               letters[tIdx].base == UInt8(ascii: "a"), letters[tIdx].mark == .none,
               letters[tIdx - 1].base == UInt8(ascii: "u"), letters[tIdx - 1].mark == .none,
               !(tIdx >= 2 && letters[tIdx - 2].base == UInt8(ascii: "q")) {
                tIdx -= 1
            }
            // "uu" nucleus: w horns the FIRST u (→ ưu: lưu, cứu, hưu) — "uư" is not
            // a valid Vietnamese nucleus, so "luuw"→lưu / "cuuws"→cứu instead of
            // the useless "luư". Same shape as the "ua" retarget above, and the
            // same "qu" exclusion ("quuw" keeps the glide u untouched).
            if tIdx >= 1,
               letters[tIdx].base == UInt8(ascii: "u"), letters[tIdx].mark == .none,
               letters[tIdx - 1].base == UInt8(ascii: "u"), letters[tIdx - 1].mark == .none,
               !(tIdx >= 2 && letters[tIdx - 2].base == UInt8(ascii: "q")) {
                tIdx -= 1
            }
            if tIdx >= 0 {
                let p = letters[tIdx]
                if p.mark == .none && p.base == UInt8(ascii: "a") {
                    letters[tIdx].mark = .breve; rawLetter[at] = tIdx; return
                }
                if p.mark == .none && (p.base == UInt8(ascii: "o") || p.base == UInt8(ascii: "u")) {
                    letters[tIdx].mark = .horn; rawLetter[at] = tIdx; return
                }
                if p.mark == .breve && p.base == UInt8(ascii: "a") {
                    letters[tIdx].mark = .none
                    pCancelled = true
                    appendLetter(base: UInt8(ascii: "w"), mark: .none, upper: upper)
                    rawLetter[at] = pCount - 1; return
                }
                if p.mark == .horn && (p.base == UInt8(ascii: "o") || p.base == UInt8(ascii: "u")) {
                    letters[tIdx].mark = .none
                    pCancelled = true
                    // The ư was CREATED by a standalone w (full Telex, no typed u
                    // behind it): cancelling reverts the letter ITSELF to a
                    // literal w — w→ư, ww→w, www→ww (user decision 2026-07-22).
                    // A 'w' letter is never a horn target, so the third w
                    // appends literally with no extra state. A "uw"-typed horn
                    // keeps the classic revert (uww→uw).
                    if p.base == UInt8(ascii: "u"), letterCreatedByW(tIdx) {
                        letters[tIdx].base = UInt8(ascii: "w")
                        rawLetter[at] = tIdx
                        return
                    }
                    appendLetter(base: UInt8(ascii: "w"), mark: .none, upper: upper)
                    rawLetter[at] = pCount - 1; return
                }
            }
            // Standalone w -> ư only when the letters so far form an onset that
            // can legally begin a "ư" syllable (cư, thư, giữ, ngư…). After an
            // onset that never precedes ư (k, q, gh, ngh, p) or after another
            // vowel, keep the literal 'w' so English words type through
            // ("kw", "windows", "ew"); auto-restore then leaves them intact.
            // Simple Telex disables this entirely — a lone `w` is always literal
            // (type `uw` for ư). Full Telex converts, including word-initial w
            // (English w-words recover via englishExceptions + auto-restore).
            if !simpleTelex && standaloneHornUAllowed(pCount) {
                appendLetter(base: UInt8(ascii: "u"), mark: .horn, upper: upper)
            } else {
                appendLetter(base: UInt8(ascii: "w"), mark: .none, upper: upper)
            }
            rawLetter[at] = pCount - 1
            return
        }

        // circumflex doublers: a e o
        if lower == UInt8(ascii: "a") || lower == UInt8(ascii: "e") || lower == UInt8(ascii: "o") {
            if pCount > 0 {
                let pIdx = pCount - 1
                let p = letters[pIdx]
                if p.base == lower && p.mark == .none {
                    letters[pIdx].mark = .circumflex; rawLetter[at] = pIdx; return
                }
                if p.base == lower && p.mark == .circumflex {
                    letters[pIdx].mark = .none
                    pCancelled = true
                    appendLetter(base: lower, mark: .none, upper: upper)
                    rawLetter[at] = pCount - 1; return
                }
            }
            // Free mode ("bỏ dấu tự do"): reach back over a consonant coda AND
            // across the whole NUCLEUS (contiguous vowel run) to circumflex an
            // earlier bare same-vowel — "ama"→âm, "coto"→côt, and since 1.3.1 also
            // "daua"→dâu / "dauas"→dấu (the doubling `a` crosses the `u`, matching
            // UniKey's free-marking). The scan never crosses into the onset
            // (consonant boundary), so qu/gi glides and English words stay safe
            // ("quao" stays literal). Strict mode skips all of this: "ama"/"coto"/
            // "data"/"daua" stay as typed.
            if freeMarking {
                var k = pCount - 1
                while k >= 0 && !isVowelAscii(letters[k].base) { k -= 1 }   // skip coda
                while k >= 0, isVowelAscii(letters[k].base) {               // walk nucleus
                    if letters[k].base == lower, letters[k].mark == .none {
                        letters[k].mark = .circumflex; rawLetter[at] = k; return
                    }
                    // Cancel mirror of the reach-back (tester bug 2026-07-23):
                    // "theme"→thêm, then a third e must UNDO the mark and go
                    // literal — "theme" — exactly like the adjacent "ee" cancel.
                    // Without this the e appended ("thême") and boundary
                    // auto-restore emitted the raw keys: "themee".
                    if letters[k].base == lower, letters[k].mark == .circumflex {
                        letters[k].mark = .none
                        pCancelled = true
                        appendLetter(base: lower, mark: .none, upper: upper)
                        rawLetter[at] = pCount - 1; return
                    }
                    k -= 1
                }
            }
            appendLetter(base: lower, mark: .none, upper: upper)
            rawLetter[at] = pCount - 1
            return
        }

        // d doubler -> đ
        if lower == UInt8(ascii: "d") {
            if pCount > 0 {
                let pIdx = pCount - 1
                let p = letters[pIdx]
                if p.base == UInt8(ascii: "d") && p.mark == .none {
                    letters[pIdx].mark = .bar; rawLetter[at] = pIdx; return
                }
                if p.base == UInt8(ascii: "d") && p.mark == .bar {
                    letters[pIdx].mark = .none
                    pCancelled = true
                    appendLetter(base: UInt8(ascii: "d"), mark: .none, upper: upper)
                    rawLetter[at] = pCount - 1; return
                }
            }
            // A trailing d (after a formed syllable) converts the onset d to đ,
            // so "did"->đi, "dand"->đan, "duwowngd"->đường even without doubling
            // at the start. FREE MARKING ONLY (user decision 2026-07-22): with
            // strict placement off…on, "did"/"dand" must stay literal English.
            if freeMarking, pCount > 1,
               letters[0].base == UInt8(ascii: "d"), letters[0].mark == .none {
                letters[0].mark = .bar; rawLetter[at] = 0; return
            }
            // Cancel mirror: "did"→đi, then a third d undoes the bar and goes
            // literal ("did"), same family as the circumflex reach-back cancel.
            if freeMarking, pCount > 1,
               letters[0].base == UInt8(ascii: "d"), letters[0].mark == .bar,
               letters[pCount - 1].base != UInt8(ascii: "d") {
                letters[0].mark = .none
                pCancelled = true
                appendLetter(base: UInt8(ascii: "d"), mark: .none, upper: upper)
                rawLetter[at] = pCount - 1; return
            }
            appendLetter(base: UInt8(ascii: "d"), mark: .none, upper: upper)
            rawLetter[at] = pCount - 1
            return
        }

        // Quick Telex: doubled onset consonant → digraph (cc→ch, gg→gi, kk→kh,
        // nn→ng, qq→qu, pp→ph, tt→th). Word-initial pair ONLY (pCount == 1): the
        // targets are onset digraphs, and the guard keeps mid-word doubles
        // ("occur", "running") literal. The second letter's case carries over
        // ("Cc"→"Ch", "CC"→"CH"). No special revert: a literal word-initial
        // double is vanishingly rare and auto-restore returns the raw keys.
        if quickTelex, pCount == 1,
           letters[0].base == lower, letters[0].mark == .none,
           let second = Self.quickTelexSecond(lower) {
            appendLetter(base: second, mark: .none, upper: upper)
            rawLetter[at] = pCount - 1
            return
        }

        // ordinary letter
        appendLetter(base: lower, mark: .none, upper: upper)
        rawLetter[at] = pCount - 1
    }

    /// VNI fold step. LETTERS are always literal (case preserved); DIGITS carry the
    /// diacritics. A digit only transforms when it can apply — otherwise it's a literal
    /// digit, so numbers ("mp3", years, "A4") survive. Reuses the SAME tone-deferral
    /// (`pTone`/`toneKeys`), mark-on-letter, cancel and `rawLetter` machinery as Telex,
    /// so tone placement, ươ propagation, boundary restore and backspace all just work.
    private mutating func parseStepVNI(_ at: Int, key: UInt8, lower: UInt8, upper: Bool) {
        // Non-digit → literal letter. (No Telex transforms in VNI.)
        guard isDigit(key) else {
            appendLetter(base: lower, mark: .none, upper: upper)
            rawLetter[at] = pCount - 1
            return
        }

        // Frozen-rebuild with a pending tone: fold the tone digit back to a literal
        // digit (mirrors the Telex tone branch's pFoldTones path).
        if pFoldTones, Self.vniTone(key) != nil {
            appendLetter(base: key, mark: .none, upper: false)
            rawLetter[at] = pCount - 1
            return
        }

        // Tone digits 1-5. Deferred onto the toned vowel at render (rawLetter = -1),
        // exactly like a Telex s/f/r/x/j. Same digit again cancels (→ literal digit).
        if let t = Self.vniTone(key) {
            if hasVowel(pCount) {
                if pTone == t {
                    pTone = .none
                    pCancelled = true; pToneCancelAt = at
                pToneCancelSpan = pToneKeyCount > 0 ? at - toneKeys[pToneKeyCount - 1] : 1
                    appendLetter(base: key, mark: .none, upper: false)
                    rawLetter[at] = pCount - 1
                    for j in 0..<pToneKeyCount where rawLetter[toneKeys[j]] == -1 {
                        rawLetter[toneKeys[j]] = pCount - 1
                    }
                    pToneKeyCount = 0
                } else {
                    pTone = t
                    rawLetter[at] = -1
                    toneKeys[pToneKeyCount] = at; pToneKeyCount += 1
                }
            } else {                                    // no vowel to tone → literal digit
                appendLetter(base: key, mark: .none, upper: false)
                rawLetter[at] = pCount - 1
            }
            return
        }

        // 0 → clear tone (like Telex z): consume only when there's a tone to remove.
        if key == UInt8(ascii: "0") {
            if pTone != .none {
                pCancelled = true; pToneCancelAt = at
                pToneCancelSpan = pToneKeyCount > 0 ? at - toneKeys[pToneKeyCount - 1] : 1
                pTone = .none
                rawLetter[at] = -1
                toneKeys[pToneKeyCount] = at; pToneKeyCount += 1
            } else {
                appendLetter(base: key, mark: .none, upper: false)
                rawLetter[at] = pCount - 1
            }
            return
        }

        // Mark digits 6/7/8/9. Scan back to the nearest applicable letter (VNI types
        // the digit right after its target; reach-back over a coda handles "viet6"→việt
        // and onset-d "d…9"→đ). Same digit again on an already-marked target cancels.
        if let mark = Self.vniMark(key) {
            var k = pCount - 1
            while k >= 0 {
                if Self.vniMarkAccepts(base: letters[k].base, mark: mark) {
                    if letters[k].mark == .none {
                        letters[k].mark = mark
                        rawLetter[at] = k
                        return
                    }
                    if letters[k].mark == mark {        // re-applied → cancel, literal digit
                        letters[k].mark = .none
                        pCancelled = true
                        appendLetter(base: key, mark: .none, upper: false)
                        rawLetter[at] = pCount - 1
                        return
                    }
                    break                                // conflicting mark → literal digit
                }
                k -= 1
            }
            appendLetter(base: key, mark: .none, upper: false)
            rawLetter[at] = pCount - 1
            return
        }

        // Any other digit → literal.
        appendLetter(base: key, mark: .none, upper: false)
        rawLetter[at] = pCount - 1
    }

    /// VNI tone digit → Tone (1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng). nil otherwise.
    @inline(__always)
    private static func vniTone(_ d: UInt8) -> Tone? {
        switch d {
        case UInt8(ascii: "1"): return .acute
        case UInt8(ascii: "2"): return .grave
        case UInt8(ascii: "3"): return .hook
        case UInt8(ascii: "4"): return .tilde
        case UInt8(ascii: "5"): return .dot
        default:                return nil
        }
    }

    /// VNI mark digit → Mark (6 circumflex, 7 horn, 8 breve, 9 bar/đ). nil otherwise.
    @inline(__always)
    private static func vniMark(_ d: UInt8) -> Mark? {
        switch d {
        case UInt8(ascii: "6"): return .circumflex
        case UInt8(ascii: "7"): return .horn
        case UInt8(ascii: "8"): return .breve
        case UInt8(ascii: "9"): return .bar
        default:                return nil
        }
    }

    /// Which base letters a VNI mark can attach to: circumflex→a/e/o, horn→o/u,
    /// breve→a, bar→d.
    @inline(__always)
    private static func vniMarkAccepts(base: UInt8, mark: Mark) -> Bool {
        switch mark {
        case .circumflex: return base == UInt8(ascii: "a") || base == UInt8(ascii: "e") || base == UInt8(ascii: "o")
        case .horn:       return base == UInt8(ascii: "o") || base == UInt8(ascii: "u")
        case .breve:      return base == UInt8(ascii: "a")
        case .bar:        return base == UInt8(ascii: "d")
        case .none:       return false
        }
    }

    /// Quick-Telex digraph table: the letter the SECOND key of a doubled onset
    /// consonant becomes (cc→c+h, gg→g+i, …). nil = not a Quick-Telex consonant.
    @inline(__always)
    private static func quickTelexSecond(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "c"), UInt8(ascii: "k"), UInt8(ascii: "p"), UInt8(ascii: "t"):
            return UInt8(ascii: "h")
        case UInt8(ascii: "g"): return UInt8(ascii: "i")
        case UInt8(ascii: "n"): return UInt8(ascii: "g")
        case UInt8(ascii: "q"): return UInt8(ascii: "u")
        default: return nil
        }
    }

    // MARK: - Tone placement (old style: òa, úy) — reads the render copy

    private mutating func toneVowelIndex(_ count: Int) -> Int {
        var vcount = 0

        var start = 0
        // qu: the u after a leading q is part of the onset.
        if count >= 2, renderLetters[0].base == UInt8(ascii: "q"),
           renderLetters[1].base == UInt8(ascii: "u"), renderLetters[1].mark == .none {
            start = 2
        }
        // gi: the i after a leading g is part of the onset, if a vowel follows.
        else if count >= 3, renderLetters[0].base == UInt8(ascii: "g"),
                renderLetters[1].base == UInt8(ascii: "i"), renderLetters[1].mark == .none,
                isVowelAscii(renderLetters[2].base) {
            start = 2
        }

        for k in start..<count where isVowelAscii(renderLetters[k].base) {
            vowelIdx[vcount] = k
            vcount += 1
        }
        if vcount == 0 {
            for k in 0..<count where isVowelAscii(renderLetters[k].base) { return k }
            return count - 1
        }

        // 1) A marked vowel takes the tone (last one covers ươ -> ơ).
        var lastMarked = -1
        for j in 0..<vcount where renderLetters[vowelIdx[j]].mark != .none { lastMarked = vowelIdx[j] }
        if lastMarked >= 0 { return lastMarked }

        // 2) No marked vowel.
        if vcount == 1 { return vowelIdx[0] }

        let hasCoda = vowelIdx[vcount - 1] < (count - 1)
        if vcount == 2 {
            if hasCoda { return vowelIdx[1] }   // closed: second vowel (toàn)
            // Open nucleus. OLD style: first vowel (hóa, khỏe, thúy). MODERN style:
            // second vowel BUT only for a /w/-glide-initial diphthong (oa, oe, uy →
            // hoà, khoẻ, uý). Falling diphthongs (ua, ưa, ia, ai, oi…) keep the first
            // vowel in both styles (múa, mía, tài), so only oa/oe/uy differ.
            if modernTone {
                let a = renderLetters[vowelIdx[0]].base, b = renderLetters[vowelIdx[1]].base
                let glideInitial =
                    (a == UInt8(ascii: "o") && (b == UInt8(ascii: "a") || b == UInt8(ascii: "e"))) ||
                    (a == UInt8(ascii: "u") && b == UInt8(ascii: "y"))
                if glideInitial { return vowelIdx[1] }
            }
            return vowelIdx[0]                  // open, old style: first vowel (hóa, úy)
        }
        return vowelIdx[1]                      // 3 vowels: middle (oái, ngoáy)
    }

    // MARK: - Diffing (SIMD longest-common-prefix over the scalar buffers)

    /// Length of the common prefix of `a` and `b` within `limit`. Compares 8 scalars
    /// per step with SIMD8<UInt32>; both buffers are fixed capacity-32 allocations,
    /// so reading a full lane past `limit` is always in bounds.
    @inline(__always)
    private func commonPrefixLength(_ a: [UInt32], _ b: [UInt32], upTo limit: Int) -> Int {
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                let ra = UnsafeRawPointer(pa.baseAddress!)
                let rb = UnsafeRawPointer(pb.baseAddress!)
                var i = 0
                while i + 8 <= limit {
                    let va = ra.loadUnaligned(fromByteOffset: i << 2, as: SIMD8<UInt32>.self)
                    let vb = rb.loadUnaligned(fromByteOffset: i << 2, as: SIMD8<UInt32>.self)
                    if any(va .!= vb) {
                        var j = i
                        while pa[j] == pb[j] { j += 1 }
                        return j
                    }
                    i += 8
                }
                while i < limit, pa[i] == pb[i] { i += 1 }
                return i
            }
        }
    }

    private func diff(_ newCount: Int) -> TelexAction {
        let lcp = commonPrefixLength(scratch, out, upTo: min(newCount, outCount))

        let backspaces = outCount - lcp
        if backspaces == 0 && lcp == newCount {
            return .replace(backspaces: 0, insert: "") // consumed no-op
        }
        var s = String.UnicodeScalarView()
        s.reserveCapacity(newCount - lcp)
        for i in lcp..<newCount { s.append(Unicode.Scalar(scratch[i])!) }
        return .replace(backspaces: backspaces, insert: String(s))
    }

    // MARK: - Small helpers

    /// Onsets that can begin a "ư" nucleus, as a flat trie. A standalone `w`
    /// becomes ư only after one of these; after k/q/gh/ngh/p, after "qu", or after
    /// a vowel, `w` stays a literal letter (C3: block spurious "kư" for English
    /// words like "kw").
    private static let onsetsAllowingStandaloneU = ClassTrie([
        "", "b", "c", "ch", "d", "g", "h", "kh", "l", "m", "n", "ng", "nh",
        "ph", "r", "s", "t", "th", "tr", "v", "x", "gi",
    ].map { ($0, UInt8(1)) })

    /// True if the letters typed before a standalone `w` form an onset (built from
    /// base letters, marks ignored — đ reads as "d") that can precede ư.
    private func standaloneHornUAllowed(_ count: Int) -> Bool {
        var node: Int32 = 0
        for k in 0..<count {
            node = Self.onsetsAllowingStandaloneU.step(node, letters[k].base &- UInt8(ascii: "a"))
            if node < 0 { return false }
        }
        return Self.onsetsAllowingStandaloneU.mask(node) != 0
    }

    @inline(__always)
    private func hasVowel(_ count: Int) -> Bool {
        for k in 0..<count where isVowelAscii(letters[k].base) { return true }
        return false
    }

    /// Does the syllable end in a stop coda (-p, -t, -c, -ch, -k)? Such codas only
    /// allow sắc/nặng. Only meaningful when a vowel precedes (checked by caller).
    /// Reads the render copy (post-propagation state).
    /// `-k` is in here to stay in lockstep with `SyllableValidator.toneMask`, which
    /// also treats it as a stop (the ak/ăk/ưk rimes: Đắk, Lắk). Without it "bakf"
    /// rendered "bàk" and got auto-restored at the boundary instead of silently
    /// dropping the invalid huyền like "batf"→"bat".
    @inline(__always)
    private func hasStopCoda(_ count: Int) -> Bool {
        guard count > 0 else { return false }
        let last = renderLetters[count - 1].base
        if last == UInt8(ascii: "p") || last == UInt8(ascii: "t")
            || last == UInt8(ascii: "c") || last == UInt8(ascii: "k") {
            return true
        }
        // "ch" coda: trailing h preceded by c.
        if last == UInt8(ascii: "h"), count >= 2, renderLetters[count - 2].base == UInt8(ascii: "c") {
            return true
        }
        return false
    }

    @inline(__always)
    private mutating func appendLetter(base: UInt8, mark: Mark, upper: Bool) {
        guard pCount < Self.capacity else { return }
        letters[pCount] = LetterUnit(base: base, mark: mark, upper: upper)
        pCount += 1
    }
}

// MARK: - Validator buffer twin (peek path)

private extension SyllableValidator {
    /// Buffer-pointer twin of `isValidSyllable(classes:count:tone:)` — the exact
    /// same deterministic onset split + trie walk, but over a caller-provided
    /// STACK buffer so `composedIsValidSyllable` stays non-mutating and
    /// heap-free (dùng cho cả commit lẫn `peekCommitText` mỗi phím).
    /// Keep in lockstep with the Array version in SyllableValidator.swift.
    static func isValidSyllable(classes: UnsafeMutableBufferPointer<UInt8>,
                                count n: Int, tone: Tone) -> Bool {
        if n == 0 { return false }
        // TEENCODE "òy" — lockstep with the Array twin (zero-onset "oy" only).
        if n == 2, classes[0] == UInt8(ascii: "o") - UInt8(ascii: "a"),
           classes[1] == UInt8(ascii: "y") - UInt8(ascii: "a") {
            return true
        }
        // TEENCODE "-òy" — lockstep with the Array twin (huyền-only, onset g/r/z/dz/ch).
        if n >= 3, tone == .grave,
           classes[n - 2] == UInt8(ascii: "o") - UInt8(ascii: "a"),
           classes[n - 1] == UInt8(ascii: "y") - UInt8(ascii: "a") {
            let gC = UInt8(ascii: "g") - UInt8(ascii: "a")
            let rC = UInt8(ascii: "r") - UInt8(ascii: "a")
            let zC = UInt8(ascii: "z") - UInt8(ascii: "a")
            let dC = UInt8(ascii: "d") - UInt8(ascii: "a")
            let cC = UInt8(ascii: "c") - UInt8(ascii: "a")
            let hC = UInt8(ascii: "h") - UInt8(ascii: "a")
            if n == 3, classes[0] == gC || classes[0] == rC || classes[0] == zC { return true }
            if n == 4, (classes[0] == dC && classes[1] == zC)
                    || (classes[0] == cC && classes[1] == hC) { return true }
        }
        // TEENCODE "đou" — lockstep with the Array twin (đúng một từ, xem comment ở đó).
        if n == 3, tone == .none, classes[0] == 32 /* đ */,
           classes[1] == UInt8(ascii: "o") - UInt8(ascii: "a"),
           classes[2] == UInt8(ascii: "u") - UInt8(ascii: "a") {
            return true
        }
        let q = UInt8(ascii: "q") - UInt8(ascii: "a")
        let u = UInt8(ascii: "u") - UInt8(ascii: "a")
        let g = UInt8(ascii: "g") - UInt8(ascii: "a")
        let i = UInt8(ascii: "i") - UInt8(ascii: "a")

        var pos = 0
        while pos < n && !Tables.isVowelClass(classes[pos]) { pos += 1 }
        var onsetEnd = pos
        var quGlide = false
        // qu / gi glide handling ("qu" + vowel: the unmarked u joins the onset).
        if pos >= 1, classes[0] == q, pos < n, classes[pos] == u,
           pos + 1 < n, Tables.isVowelClass(classes[pos + 1]) {
            onsetEnd = pos + 1
            quGlide = true
        } else if n >= 3, classes[0] == g, classes[1] == i, Tables.isVowelClass(classes[2]) {
            onsetEnd = 2
        }

        @inline(__always) func accepts(onsetEnd: Int, rimeStart: Int) -> Bool {
            var node: Int32 = 0
            for k in 0..<onsetEnd {
                node = onsetExact.step(node, classes[k])
                if node < 0 { return false }
            }
            guard onsetExact.mask(node) != 0 else { return false }
            var rnode: Int32 = 0
            for k in rimeStart..<n {
                rnode = rimeExact.step(rnode, classes[k])
                if rnode < 0 { return false }
            }
            return (rimeExact.mask(rnode) >> tone.rawValue) & 1 == 1
        }

        // Every reading is tried (see the Array twin for why): the qu- glide's u counted
        // twice ("quýt" = qu + uyt), and the plain split as a fallback so the glide
        // reading can't shadow it ("giếc" = g + iêc, not gi + êc).
        if accepts(onsetEnd: onsetEnd, rimeStart: onsetEnd) { return true }
        if quGlide, accepts(onsetEnd: onsetEnd, rimeStart: pos) { return true }
        return onsetEnd != pos && accepts(onsetEnd: pos, rimeStart: pos)
    }
}

// MARK: - ascii helpers

@inline(__always)
func isLetter(_ c: UInt8) -> Bool {
    (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) ||
    (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
}

@inline(__always)
func isDigit(_ c: UInt8) -> Bool {
    c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")
}

@inline(__always)
func isUpperAscii(_ c: UInt8) -> Bool {
    c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z")
}

@inline(__always)
func lowercased(_ c: UInt8) -> UInt8 {
    isUpperAscii(c) ? c &+ 32 : c
}
