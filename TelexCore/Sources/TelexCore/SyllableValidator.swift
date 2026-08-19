// SyllableValidator.swift
// Rule-based Vietnamese syllable validator. No dictionary file: a syllable is valid
// iff  onset ∈ ONSETS  AND  rime ∈ RIMES  AND  the tone/coda constraint holds.
// Used at word boundaries to decide whether to auto-restore raw keystrokes, and
// per-keystroke (prefix form) by live spell-check.
//
// The rule tables below are the SOURCE; at startup they compile into flat trie
// machines over the 33-letter class alphabet (Tables.letterClass). Even the
// tone/coda rule is data, not code: each rime's accepting node carries a 6-bit
// mask of the tones it allows (stop codas -c/-ch/-p/-t → sắc/nặng only). The hot
// paths walk byte arrays through these tries — no String, no hashing, no heap.

public enum SyllableValidator {

    // MARK: - Rule tables (human-readable source of truth)

    // Valid onsets (initial consonant clusters). "" = zero onset.
    // `z` and the `dz` cluster are not native Vietnamese onsets, but they're
    // included so casual/colloquial words type with diacritics like any consonant
    // ("zoo"→zô, "dzij"→dzị, "dzoo"→dzô — the "dz" spelling iOS Vietnamese accepts).
    // Cost: z-initial English words with a Telex tone letter (zero→zẻo, zoom→zôm)
    // transform instead of restore — the usual Telex trade-off, same as any onset;
    // switch input source for those.
    static let onsets: Set<String> = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l",
        "m", "n", "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th",
        "tr", "v", "x", "z", "dz",
        "kr",   // tên địa danh dân tộc thiểu số: Krông (Đắk Lắk)
    ]

    // Valid rimes = nucleus (+ coda), toneless, with marks. ~180 entries.
    // TEENCODE (maintainer decision 2026-08-04): the OPEN rime "ie" is accepted as a
    // rime of its own — chat spelling writes "bé"→"bíe", "mẹ"→"mịe", "thế"→"thíe", i.e.
    // the bare "ie" the Telex intermediate already renders. It carries all six tones
    // (no coda ⇒ no stop-coda restriction) and the tone sits on the i, exactly where
    // the engine's placement puts it, so "bies"→bíe / "miej"→mịe simply become VALID
    // syllables and the boundary keeps them with no special-case restore logic.
    // Scope is deliberately the OPEN rime only: closed "iec"/"ien"/… stay out (their
    // real forms are iêc/iên), so English "diet"/"field" are untouched.
    // TEENCODE/interjection "ưm ưn" (maintainer 2026-08-12): "ừm" (uh-huh), "ưn"
    // ("ưng") — full rime-table entries, ALL onsets ("hừm", "hửm" ride along),
    // unlike the zero-onset "oy" special case: these rimes require the explicit
    // w-mark (ư), so no bare-ascii English word can wander into them — reaching
    // "ưm" needs the literal key sequence "uw"+"m", which English doesn't produce.
    static let rimes: Set<String> = {
        let list = """
        a ac ach ai am an ang anh ao ap at au ay ak
        ă ăc ăm ăn ăng ăp ăt ăk
        â âc âm ân âng âp ât âu ây
        e ec em en eng eo ep et
        ê êch êm ên êng ênh êp êt êu
        i ich im in inh ip it iu ia
        iê iêc iêm iên iêng iêp iêt iêu
        ie
        o oc oi om on ong op ot
        oa oac oach oai oam oan oang oanh oao oap oat oay
        oă oăc oăm oăn oăng oăt
        oe oem oen oeo oet
        oo oong ooc
        ô ôc ôi ôm ôn ông ôp ôt
        ơ ơi ơm ơn ơp ơt
        u uc ui um un ung up ut ua
        uâ uân uâng uât uây
        uê uêch uên uênh
        uô uôc uôi uôm uôn uông uôt uơ
        uy uya uych uyn uynh uyt uyu uyên uyêt
        ư ưa ưc ưi ưm ưn ưng ưt ưu
        ươ ươi ươm ươn ương ươp ươt ươu ươc
        y yê yêm yên yêng yêt yêu
        """
        var set = Set<String>()
        for token in list.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            set.insert(String(token))
        }
        return set
    }()

    // MARK: - Compiled machines (rules → data, built once)

    /// Allowed-tone bitmask for a rime: bit = Tone.rawValue. Stop codas
    /// (-p/-t/-c/-ch) only permit sắc/nặng; everything else permits all six.
    private static func toneMask(forRime r: String) -> UInt8 {
        let stop = r.hasSuffix("p") || r.hasSuffix("t") || r.hasSuffix("c") || r.hasSuffix("ch")
            || r.hasSuffix("k")   // coda k (Đắk, Lắk): same stop-coda rule as c
        return stop ? (1 << Tone.acute.rawValue) | (1 << Tone.dot.rawValue) : 0b0011_1111
    }

    /// Exact matchers (marked letters, đ distinct from d): full-syllable validation.
    static let onsetExact = ClassTrie(onsets.map { ($0, UInt8(1)) })
    static let rimeExact = ClassTrie(rimes.map { ($0, toneMask(forRime: $0)) })

    /// Folded matchers (â/ă→a, ô/ơ→o, ư→u, ê→e, đ→d): prefix plausibility while
    /// typing, where the diacritic may simply not have been typed yet.
    static let onsetFolded = ClassTrie(onsets.map { (String($0.map(foldBase)), UInt8(1)) })
    static let rimeFolded = ClassTrie(rimes.map { (String($0.map(foldBase)), UInt8(1)) })

    /// Fold a marked vowel to its bare base letter (ô/ơ→o, ư→u, ê→e, ă/â→a, đ→d),
    /// so a Telex intermediate that has not yet received its diacritic ("uo", "ie",
    /// "uoi") matches the bare prefix of a real rime ("ươ", "iê", "ươi"). Vowel SHAPE
    /// is ignored for prefix matching; the base skeleton is what must stay plausible.
    static func foldBase(_ c: Character) -> Character {
        switch c {
        case "ă", "â": return "a"
        case "ê":      return "e"
        case "ô", "ơ": return "o"
        case "ư":      return "u"
        case "đ":      return "d"
        default:       return c
        }
    }

    // MARK: - Full-syllable validation

    /// Zero-allocation core: `classes[0..<n]` are letter classes
    /// (`Tables.letterClass`) of the composed word, `tone` its single tone.
    /// Splits onset deterministically (qu-/gi- glides), then: onset exact-accepted
    /// AND rime exact-accepted AND the rime's tone mask allows `tone`.
    public static func isValidSyllable(classes: [UInt8], count n: Int, tone: Tone) -> Bool {
        if n == 0 { return false }
        // TEENCODE "òy" (maintainer 07/08/2026): standalone open rime "oy" is a
        // valid syllable — chat spelling for "òi/rồi" ("òy", "óy"…). All six
        // tones (open rime). ZERO ONSET ONLY, deliberately NOT in the rime
        // table: blessing "b/t/j + oy" would let English "boys"/"toys" compose
        // to "bóy"/"tóy" the moment a trailing s lands. Widening this (e.g.
        // teencode "gòy") needs that collision review first.
        if n == 2, classes[0] == UInt8(ascii: "o") - UInt8(ascii: "a"),
           classes[1] == UInt8(ascii: "y") - UInt8(ascii: "a") {
            return true
        }
        // TEENCODE "đou" (maintainer 19/08/2026): ĐÚNG MỘT TỪ, không phải một vần.
        // Thử đưa "ou" vào bảng rime (kể cả khoá không-thanh) đã nổ hai hướng: có
        // thanh thì hour/sour/tour/pour thành hỏu/sỏu/tỏu/pỏu, và vào bảng là vào
        // luôn rimeFolded (prefix plausibility) làm live-spell-check hết freeze
        // được cả họ -ous/-ouse/-out tiếng Anh (house→hóue: quét từ điển miss
        // 111→3896 ở Simple Telex). Onset đ chỉ đến được từ phím dd nên đường này
        // không chạm bất kỳ từ tiếng Anh nào, và không đụng prefix table.
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

        // EVERY reading is tried and any one accepting is enough — the same permissive
        // contract `isValidPrefix` has always had. A single deterministic split silently
        // rejected real words (issue #29, 2026-07-27):
        //  • qu- glide: the u counts in BOTH the onset ("qu") and the rime ("uy…") —
        //    "quýt" = qu + uyt, the very rime huýt/tuýt/khuýt use. The rime table has no
        //    standalone "yt"/"ynh", and ADDING those would bless "hyt"/"bynh" too.
        //  • the glide split must not shadow the PLAIN one: "giếc" (cá giếc) split as
        //    gi + "êc" (not a rime) and never got tried as g + "iêc" (which is one).
        if accepts(onsetEnd: onsetEnd, rimeStart: onsetEnd) { return true }
        if quGlide, accepts(onsetEnd: onsetEnd, rimeStart: pos) { return true }
        return onsetEnd != pos && accepts(onsetEnd: pos, rimeStart: pos)
    }

    /// Returns true if `word` is a well-formed Vietnamese syllable. String façade
    /// over the class-based core (word-boundary use; not the per-key hot path).
    public static func isValidSyllable(_ word: String) -> Bool {
        if word.isEmpty { return false }
        var classes = [UInt8]()
        classes.reserveCapacity(word.count)
        var tone: Tone = .none
        for ch in word.lowercased() {
            guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
                return false
            }
            var toneless = ch
            if let (base, t) = Tables.detoneTable[scalar.value] {
                toneless = Character(Unicode.Scalar(base)!)
                if t != .none {
                    if tone != .none { return false } // two tones
                    tone = t
                }
            }
            guard let cls = Tables.charClass[toneless] else { return false }
            classes.append(cls)
        }
        return isValidSyllable(classes: classes, count: classes.count, tone: tone)
    }

    // MARK: - Prefix validity (live spell-check while typing)

    /// Zero-allocation core for the engine's per-keystroke path. `bases[i]` is the
    /// lowercase ascii BASE letter of display letter i (ơ→o, ă→a, đ→d…), with bit 7
    /// set when that letter carries a mark. Matching runs over the folded tries —
    /// the mark bit matters only for the qu-glide alternative (a horned ư never
    /// joins a "qu" onset).
    ///
    /// PERMISSIVE by design: it must never reject a valid word mid-typing (that
    /// would wrongly stop composing), so it errs toward true — callers use it only
    /// to DISABLE transforms on words that clearly cannot be Vietnamese.
    public static func isValidPrefix(bases: [UInt8], count n: Int) -> Bool {
        if n == 0 { return true }
        @inline(__always) func cls(_ i: Int) -> UInt8 { (bases[i] & 0x7F) &- UInt8(ascii: "a") }
        // Anything that isn't an ascii letter (VNI literal digits: "mp3", "html5") can
        // never start a Vietnamese syllable — bail out before the class arithmetic.
        for i in 0..<n where !isLetter(bases[i] & 0x7F) { return false }

        var pos = 0
        while pos < n && !isVowelAscii(bases[pos] & 0x7F) { pos += 1 }
        if pos == n {                                   // no vowel yet: partial onset
            var node: Int32 = 0
            for i in 0..<n {
                node = onsetFolded.step(node, cls(i))
                if node < 0 { return false }
            }
            return true                                 // any live trie node = valid prefix
        }

        // TEENCODE "òy": the standalone "oy" intermediate must stay composable
        // while typing (no rime starts with "oy", so the trie walk below would
        // freeze live spell-check at the y). Exact pair, zero onset, unmarked o —
        // longer tails ("oyt…") fall through and freeze as before.
        if n == 2, bases[0] == UInt8(ascii: "o"), bases[1] == UInt8(ascii: "y") {
            return true
        }
        // TEENCODE "đou": intermediate "d-o-u" phải sống qua live-spell-check tới
        // boundary (bases là bản FOLDED nên đ đã về d — không phân biệt được dou/đou
        // ở đây; boundary mới xét đúng onset đ). Đúng 3 ký tự — "dou" của
        // double/doubt vẫn freeze ở ký tự thứ 4 như trước, chỉ muộn hơn một phím.
        if n == 3, bases[0] & 0x7F == UInt8(ascii: "d"),
           bases[1] == UInt8(ascii: "o"), bases[2] == UInt8(ascii: "u") {
            return true
        }
        // Nucleus-start candidates. Default = right after the leading consonants; the
        // qu-/gi- glides give an alternative where the glide vowel joins the onset.
        // Every interpretation is tried and ANY plausible one accepts (permissive).
        let quAlt = (bases[0] & 0x7F == UInt8(ascii: "q")
                     && bases[pos] == UInt8(ascii: "u")) ? pos + 1 : -1   // unmarked u only
        let giAlt = (bases[0] & 0x7F == UInt8(ascii: "g")
                     && n >= 2 && bases[1] == UInt8(ascii: "i")) ? 2 : -1

        // (onsetEnd, rimeStart) — normally the same index, EXCEPT the qu- glide's second
        // reading where the u counts in both ("quýt" = qu + uyt, see isValidSyllable).
        for (onsetEnd, rimeStart) in [(pos, pos), (quAlt, quAlt), (giAlt, giAlt), (quAlt, pos)] {
            guard onsetEnd >= 0, onsetEnd <= n else { continue }
            var node: Int32 = 0
            var ok = true
            for i in 0..<onsetEnd {
                node = onsetFolded.step(node, cls(i))
                if node < 0 { ok = false; break }
            }
            guard ok, onsetFolded.mask(node) != 0 else { continue }
            var rnode: Int32 = 0
            ok = true
            for i in rimeStart..<n {
                rnode = rimeFolded.step(rnode, cls(i))
                if rnode < 0 { ok = false; break }
            }
            if ok { return true }                        // any live trie node = valid prefix
        }
        return false
    }

    /// String façade over the byte-level prefix check (tests / non-hot callers).
    public static func isValidPrefix(_ word: String) -> Bool {
        if word.isEmpty { return true }
        var bases = [UInt8]()
        bases.reserveCapacity(word.count)
        for ch in word.lowercased() {
            guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
            var toneless = ch
            if let (base, _) = Tables.detoneTable[scalar.value] {
                toneless = Character(Unicode.Scalar(base)!)
            }
            guard Tables.charClass[toneless] != nil else { return false }
            let folded = foldBase(toneless)
            guard let a = folded.asciiValue else { return false }
            bases.append(a | (folded == toneless ? 0 : 0x80))
        }
        return isValidPrefix(bases: bases, count: bases.count)
    }
}

// MARK: - Flat class trie (the compiled rule machine)

/// Flat trie over the 33-letter class alphabet (`Tables.letterClass`). Node i's
/// child for class c lives at next[i * 33 + Int(c)]; -1 = absent. Root = node 0.
/// Reaching a node ⇔ the walked string is a prefix of an inserted word. Each node
/// carries a byte `mask`: 0 = not a full word; nonzero = accepting, and for rime
/// tries the bits are the ALLOWED TONES (bit = Tone.rawValue) — the tone/coda rule
/// compiled into the data. Built once at startup, read-only after.
struct ClassTrie: Sendable {
    private let next: [Int32]
    private let masks: [UInt8]

    /// Build from (word, acceptMask) pairs; characters map through
    /// `Tables.charClass`. Words with unmappable characters are skipped.
    init(_ words: some Sequence<(String, UInt8)>) {
        let stride = Tables.classCount
        var next = [Int32](repeating: -1, count: stride)
        var masks: [UInt8] = [0]
        outer: for (w, accept) in words {
            var path = [Int]()
            for ch in w {
                guard let c = Tables.charClass[ch] else { continue outer }
                path.append(Int(c))
            }
            var node = 0
            for c in path {
                let slot = node * stride + c
                if next[slot] < 0 {
                    next[slot] = Int32(masks.count)
                    next.append(contentsOf: repeatElement(-1, count: stride))
                    masks.append(0)
                }
                node = Int(next[slot])
            }
            masks[node] |= max(accept, 1)
        }
        self.next = next
        self.masks = masks
    }

    /// One transition on a letter class. Returns -1 when absent.
    @inline(__always)
    func step(_ node: Int32, _ cls: UInt8) -> Int32 {
        // A class OUT of the 33-letter alphabet has no child — and must never index the
        // flat array. VNI puts literal DIGITS in the letter buffer ("mp3", "2020") and
        // `letterClass`/`cls()` map those by `base &- "a"`, which wraps to 200+ → the
        // subscript walked off the end and CRASHED the IME (issue #28, 2026-07-27; it
        // only crashed when the offset happened to land outside the array, so it read
        // garbage — wrong validity — the rest of the time). One unsigned compare, on a
        // path that runs a handful of times per keystroke.
        guard cls < UInt8(Tables.classCount) else { return -1 }
        return next[Int(node) * Tables.classCount + Int(cls)]
    }

    /// Accept mask of a node (0 = not a full inserted word).
    @inline(__always)
    func mask(_ node: Int32) -> UInt8 { masks[Int(node)] }
}