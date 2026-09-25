// EnglishContextWords.swift — curated set of common English words used ONLY by the
// experimental context-based decision (engine.contextualEnglish). This is SEPARATE
// from EnglishCollisions (which force-restores Telex-colliding words regardless of
// context): this set answers "was the previous word English?" and "is this ambiguous
// word a plausible English word?" so that after an English word, an ambiguous next
// word (composed is valid Vietnamese but the raw keys spell an English word) is
// restored to English — "he is" → "he is" (not "he í"), while "sao í" stays Vietnamese.
//
// Deliberately weighted toward function words (pronouns, auxiliaries, articles,
// prepositions, conjunctions) plus the highest-frequency content words — enough to
// carry English context through a sentence. Curated by hand (not gen-english): most of
// these do NOT collide with Telex, so they never appear in EnglishCollisions, yet they
// are exactly the words that establish an English run. Lowercase, ascii.
//
// FORMAT: các bảng là literal nhiều dòng (từ cách nhau bởi space/newline), split lazily
// ở lần tra đầu tiên — thay cho ~450 phần tử literal, tiết kiệm hàng chục KB
// __TEXT/__DATA. Cùng kiểu với SyllableValidator.rimes. Sửa tay bình thường: chỉ cần
// thêm/bớt từ trong literal, dấu phẩy và dấu ngoặc kép không còn cần thiết.
enum EnglishContextWords {
    static let words: Set<String> = parse(wordList)

    /// RESTORE-ONLY: khôi phục khi ĐANG trong mạch tiếng Anh, nhưng KHÔNG bao giờ mở
    /// mạch. Thán từ / từ chat đứng chung với tiếng Việt rất thường xuyên ("ok cám ơn",
    /// "wow đẹp quá", "hi mọi người") nên nếu chúng seed context thì từ Việt kế tiếp bị
    /// lật sang tiếng Anh (lý do chúng bị gỡ khỏi `words` ngày 2026-07-25). Nhưng khi
    /// mạch tiếng Anh đã mở bởi từ khác thì chính chúng phải giữ nguyên dạng tiếng Anh:
    /// "that's great wow" → wow, không phải "wơ" (field report 2026-07-26, Simple Telex:
    /// `w` literal + `ow` → ơ, và "wơ" lại hợp lệ qua teencode w→qu = "quơ").
    static let restoreOnly: Set<String> = parse(restoreOnlyList)

    /// NEUTRAL loanwords: English words Vietnamese sentences borrow constantly ("gửi
    /// email", "cái app này", "bật wifi"). They must PRESERVE the current context —
    /// neither open an English run (or "email bans" would keep "bans" instead of
    /// composing "bán") nor end one ("the email is" keeps the run "the" opened).
    /// Consulted only for words the classifier would otherwise call English by
    /// STRUCTURE (not a possible VN syllable, not in any dictionary) — the fallback
    /// added for the 2026-08-14 field report ("position is" → "position í": every
    /// unrecognized non-VN word used to default to Vietnamese context).
    static let neutralLoanwords: Set<String> = parse("""
        app apps email mail wifi web blog file files link links game games chat
        team teams fan fans form font menu tab tabs click share live stream
        video videos photo photos camera laptop phone sim online offline admin
        mod spam virus download upload update comment comments post posts story
        feed group groups page pages shop sale size order ship voucher deal
        combo view views like likes sub vlog idol hot top vip pro logo banner
        code demo test server client account profile password login logout
        macos ios windows android linux mac macbook imac iphone ipad ipod
        airpods apple gmail youtube facebook messenger instagram
        tiktok telegram whatsapp viber zalo discord slack zoom chrome
        safari firefox edge excel powerpoint outlook onedrive dropbox
        notion figma canva netflix spotify shopee lazada tiki grab momo
        vnpay viettel vinaphone mobifone samsung xiaomi oppo huawei
        """)

    /// Longest word in the set — lets the caller skip words that can't possibly match.
    static let maxLength = 12

    private static func parse(_ list: String) -> Set<String> {
        var set = Set<String>(minimumCapacity: 512)
        for token in list.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            set.insert(String(token))
        }
        return set
    }

    private static let wordList = [
        // pronouns
        """
        i you he she it we they
        me him her us them
        my your his its our their
        mine yours hers ours theirs
        this that these those
        who whom whose which what
        myself yourself himself herself itself ourselves themselves
        """,
        // be / auxiliaries / common verbs
        """
        is am are was were be been being
        do does did done doing
        have has had having
        will would shall should
        can could may might must
        get gets got go goes going
        make makes made take takes took
        see saw seen know knew want wants
        need needs like likes use uses used
        say says said come comes came
        think thinks look looks find found
        give gives tell work works call calls
        """,
        // articles / determiners / quantifiers
        """
        an the some any every each
        all both half few many much more most
        several enough such other another same
        """,
        // prepositions
        """
        of to in on at by for with from
        into onto up out off over under about
        after before between through during without
        within along across behind beyond upon
        """,
        // conjunctions
        """
        and or but nor so yet if then than
        because while when where why how though
        although unless until whether since as
        """,
        // common adverbs / adjectives / misc.
        // NOTE: interjections / greetings / politeness markers (ok, okay, hi, hello, hey,
        // yes, no, sorry, thanks, thank, please, well, really, maybe) are DELIBERATELY
        // NOT here — Vietnamese speakers open sentences with them ("ok cám ơn", "hi mọi
        // người", "sorry nha"), so seeding an English run from them flips the next
        // Vietnamese word ("ok cám ơn" → "ok cams ơn"). Left out, they fall through to
        // neutral/Vietnamese and never open an English run.
        // `default` — Deffault→Default: the mid-word tone-cancel escape (see shouldRestoreRaw)
        """
        not here there now just only also too very
        default
        back down new old good great big
        small little long high low right left
        next last first one two three
        again always never often still even much
        day time way man men people thing things
        """,
        // Hand-vetted ambiguous English words: each ALSO composes to a Vietnamese
        // syllable (runs→rún, songs→sóng, bans→bán, moms→móm, thus→thú), so they are
        // ONLY flipped to English inside an English run — after a Vietnamese/no-context
        // word they correctly stay Vietnamese. NOT bulk-imported: most collision words
        // hit COMMON Vietnamese (cos→có, sex→sẽ, max→mã) and would corrupt mixed text.
        """
        runs loans songs sons moms cams lens rays vans
        bans tins tans dams hams thus
        """,
        // Broad expansion (user opt-in): the `degrades_vn` rows from telex_test_suite —
        // English words whose Telex reading is a valid (mostly less-common) Vietnamese
        // syllable. Recognized as ambiguous so context can flip them after an English
        // word; alone they stay Vietnamese. The `never` rows (cos→có, sex→sẽ, max→mã,
        // this→thí…) are DELIBERATELY excluded — they collide with COMMON Vietnamese.
        """
        air ais ams ans arm asn asp bangs barn
        beer beest bens best bins bits bons boost boots born
        burn cans caps cast cats chair chans chaos charm
        chens chest chips choes choir chose cons corn cost
        cums cups cuts dans days deer deest dims dist
        docs doms dons dust ems ens eos est gaps gary
        gays hair hangs hans harm hats hays heer heest
        here hero hist hits hoest hongs horn host hungs inf
        ins ira ist its keeps kens kits langs lans laos
        last lats lays leer leest leos lets lips lisa
        list loes loest longs loops lose lost lots luis
        mais mans mary mats mays meest meets mens mere mias
        most must nams neer neest neos nest nons norm
        nuts oer oes oops owns past pest pets pics queens
        queest quest taxi teest term test thais thats theer
        theest there these tims tips tits toer toes toest
        toms tops towns turn ums ups uri urw usa usc
        vary vast vees veest vias visa vons was
        """,
    ].joined(separator: "\n")

    // "a" (issue #93, 25/09/2026): mạo từ tiếng Anh NHƯNG cũng là "a" = anh / "à" rất
    // thường trong chat tiếng Việt ("a còn ở đó không") — mở mạch tiếng Anh từ nó lật
    // từ Việt kế tiếp ("a conf" → "a conf"). Giữ ở lớp restore-only: trong mạch tiếng
    // Anh đã mở ("this is a test") vẫn đúng, nhưng không bao giờ tự mở mạch.
    private static let restoreOnlyList = """
        a
        wow ok okay oh ah aha hey hi hello yay yeah
        yep nope oops ouch hmm huh haha hehe lol omg
        wtf bye sorry thanks thank please welcome congrats
        cool wonderful awesome amazing
        """
}
