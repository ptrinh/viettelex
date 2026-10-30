// Structural invariants (port of android EngineInvariantTest + Swift ScreenSimulation /
// PeekCommit / Reopen / Seed / Overflow tests) and the zero-allocation guarantee.
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <new>
#include <string>
#include "support.hpp"

// ---- allocation counter (whole test binary) ----------------------------------------
static std::atomic<long> gAllocs{0};
void* operator new(std::size_t n) {
    gAllocs.fetch_add(1, std::memory_order_relaxed);
    if (void* p = std::malloc(n ? n : 1)) return p;
    std::abort();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

using namespace vt;

namespace {

int gPass = 0, gFail = 0;
volatile int gSink = 0;   // keeps calls whose result is unused from being optimised away
#define CHECK(cond) do { if (cond) ++gPass; else { ++gFail; std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { auto _a = (a); auto _b = (b); if (_a == _b) ++gPass; else { ++gFail; \
    std::printf("FAIL %s:%d: %s == %s  (\"%s\" vs \"%s\")\n", __FILE__, __LINE__, #a, #b, std::string(_a).c_str(), std::string(_b).c_str()); } } while (0)

struct Rng {
    uint64_t s;
    uint64_t next() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
    int below(int n) { return static_cast<int>(next() % static_cast<uint64_t>(n)); }
    bool coin() { return next() & 1; }
};

bool isReplace(const vtx::Action& a, int bs, const char* insert) {
    return a.kind == vtx::Action::Replace && a.backspaces == bs && text(a) == insert;
}

void applyScreen(std::u32string& sb, const vtx::Action& a, char32_t ch, bool isBackspace, bool& ok) {
    if (a.kind == vtx::Action::Passthrough) {
        if (!isBackspace) sb.push_back(ch); else if (!sb.empty()) sb.pop_back();
    } else if (a.kind == vtx::Action::Replace) {
        if (static_cast<size_t>(a.backspaces) > sb.size()) { ok = false; return; }
        sb.resize(sb.size() - static_cast<size_t>(a.backspaces));
        for (int i = 0; i < a.length; ++i) sb.push_back(a.text[i]);
    }
}

void screenAlwaysEqualsComposed() {
    Rng rnd{40};
    const std::string keys = "aaeeoouuwwddsfrxjzbcghiklmnpqtvyAEOUWDSF<<<";
    int bad = 0;
    for (int it = 0; it < 20000; ++it) {
        vtx::TelexEngine e;
        e.freeMarking = rnd.coin(); e.simpleTelex = rnd.coin(); e.liveSpellCheck = rnd.coin();
        e.modernTone = rnd.coin(); e.quickTelex = rnd.below(4) == 0; e.teencode = rnd.coin();
        e.vniMode = rnd.below(8) == 0;
        std::u32string sb;
        int n = 1 + rnd.below(24);
        vtx::Action a;
        for (int i = 0; i < n; ++i) {
            char c = keys[static_cast<size_t>(rnd.below(static_cast<int>(keys.size())))];
            bool ok = true;
            if (c == '<') { e.backspace(a); applyScreen(sb, a, 0, true, ok); }
            else { e.feed(static_cast<char32_t>(c), a); applyScreen(sb, a, static_cast<char32_t>(c), false, ok); }
            if (!ok || toUtf8(sb) != composed(e)) { ++bad; break; }
        }
    }
    CHECK(bad == 0);
}

void peekMatchesCommitOnCopy() {
    Rng rnd{7};
    const std::string keys = "aeouwdsfrxjzbchnglmtiyAS";
    int bad = 0;
    for (int it = 0; it < 10000; ++it) {
        vtx::TelexEngine e;
        e.freeMarking = rnd.coin(); e.simpleTelex = rnd.coin(); e.liveSpellCheck = rnd.coin();
        e.contextualEnglish = rnd.coin(); e.collisionPrefersVietnamese = rnd.coin(); e.teencode = rnd.coin();
        vtx::Action a;
        int words = 1 + rnd.below(3);
        for (int w = 0; w < words; ++w) {
            int n = 1 + rnd.below(10);
            for (int i = 0; i < n; ++i) e.feed(static_cast<char32_t>(keys[static_cast<size_t>(rnd.below(static_cast<int>(keys.size())))]), a);
            bool autoRestore = rnd.coin();
            std::string before = composed(e);
            std::string p = peek(e, autoRestore);
            if (before != composed(e)) ++bad;
            vtx::TelexEngine copy = e;
            if (p != commitText(copy, autoRestore)) ++bad;
            commitText(e, autoRestore);
        }
    }
    CHECK(bad == 0);
}

void reopenIssue40() {
    vtx::TelexEngine e;
    e.freeMarking = true; e.simpleTelex = true; e.liveSpellCheck = true;
    feedStr(e, "thasy");
    CHECK_EQ(composed(e), std::string("tháy"));
    vtx::Action a;
    e.commitBoundary(true, a);
    CHECK(a.kind == vtx::Action::None);
    CHECK(e.canReopenLastCommit());
    char16_t b[vtx::kMaxText];
    int n = e.reopenLastCommit(b, vtx::kMaxText);
    CHECK_EQ(toUtf8(b, n > 0 ? n : 0), std::string("tháy"));
    CHECK_EQ(raw(e), std::string("thasy"));
    e.feed(U'a', a);
    CHECK(isReplace(a, 2, "ấy"));
    CHECK_EQ(composed(e), std::string("thấy"));
}

void reopenBackspaceThroughWord() {
    vtx::TelexEngine e;
    e.freeMarking = true; e.simpleTelex = true; e.liveSpellCheck = true;
    feedStr(e, "dduwowngf");
    vtx::Action a;
    e.commitBoundary(true, a);
    char16_t b[vtx::kMaxText];
    int n = e.reopenLastCommit(b, vtx::kMaxText);
    CHECK_EQ(toUtf8(b, n > 0 ? n : 0), std::string("đường"));
    const char* steps[] = {"đườn", "đườ", "đư", "đ", ""};
    for (const char* s : steps) { e.backspace(a); CHECK_EQ(composed(e), std::string(s)); }
    CHECK(!e.canReopenLastCommit());
    CHECK(e.reopenLastCommit(b, vtx::kMaxText) == -1);
}

void seedRoundTrips() {
    vtx::TelexEngine e;
    vtx::Action a;
    CHECK(seed(e, "toan")); e.feed(U's', a); CHECK(isReplace(a, 2, "án"));
    CHECK(seed(e, "Việt")); CHECK_EQ(composed(e), std::string("Việt"));
    CHECK(!seed(e, "google"));
    CHECK(!seed(e, "hoà"));
    e.modernTone = true;
    CHECK(seed(e, "hoà"));
    e.vniMode = true;
    CHECK(seed(e, "đường")); CHECK_EQ(raw(e), std::string("d9u7o7ng2"));
    e.vniMode = false; e.modernTone = false;
    CHECK(seed(e, "ĐƯỜNG")); CHECK_EQ(raw(e), std::string("DDUWOWNGf"));
    CHECK(!seed(e, "a1"));
    CHECK(!seed(e, "é́"));
    // UTF-16 entry point (what the TIP passes from ITfRange::GetText).
    const char16_t w[] = u"thấy";
    CHECK(e.seed(w, 4)); CHECK_EQ(composed(e), std::string("thấy"));
    const char16_t sur[] = {0xD83D, 0xDE00};
    CHECK(!e.seed(sur, 2)); CHECK(e.isEmpty());
}

void overflowPassesThrough() {
    vtx::TelexEngine e;
    vtx::Action a;
    bool allPass = true;
    for (int i = 0; i < 32; ++i) { e.feed(U'b', a); allPass = allPass && a.kind == vtx::Action::Passthrough; }
    CHECK(allPass);
    CHECK(!e.isOverflowed());
    e.feed(U'b', a); CHECK(a.kind == vtx::Action::Passthrough);
    CHECK(e.isOverflowed());
    e.backspace(a); CHECK(a.kind == vtx::Action::Passthrough);
    e.commitBoundary(true, a); CHECK(a.kind == vtx::Action::None);
    CHECK(e.isEmpty());
}

void nonLetterPassesThrough() {
    vtx::TelexEngine e;
    vtx::Action a;
    for (char32_t c : fromUtf8("1.,!ễ[")) { e.feed(c, a); CHECK(a.kind == vtx::Action::Passthrough); }
    e.feed(0x1F600, a); CHECK(a.kind == vtx::Action::Passthrough);
    CHECK(e.isEmpty());
}

void hotPathDoesNotAllocate() {
    vtx::TelexEngine e;
    e.freeMarking = true; e.liveSpellCheck = true; e.contextualEnglish = true;
    e.collisionPrefersVietnamese = true; e.teencode = false;
    const char* text = "Vieetj Nam laf mootj ddaats nuwowcs xinh ddepj googlee installer thiss is the list "
                       "nguoiwf truwowngf DDHQG hooongggg aaaa<< ddaay<<<";
    vtx::Action a;
    char16_t buf[vtx::kMaxText];
    long before = gAllocs.load();
    for (int rep = 0; rep < 200; ++rep) {
        for (const char* p = text; *p; ++p) {
            if (*p == ' ') { e.peekCommitText(true, buf, vtx::kMaxText); e.commitBoundary(true, a); }
            else if (*p == '<') e.backspace(a);
            else e.feed(static_cast<char32_t>(*p), a);
            gSink += e.hasSpellingError(true) ? 1 : 0;   // opt-in underline: per-key, no heap
        }
        e.commitText(true, buf, vtx::kMaxText);
        // Acronym / typo keep / glue / restore-undo paths (boundary-only, fixed buffers).
        for (const char* p = "NAS lanwm his my_var 100W "; *p; ++p) {
            if (*p == ' ' || *p == '_' || (*p >= '0' && *p <= '9')) {
                e.commitBoundary(true, a);
                vtx::RestoreUndo u;
                gSink += e.takeRestoreUndo(u) ? u.vietnameseLength : 0;
                e.noteBoundaryCharacter(static_cast<char32_t>(*p));
            } else {
                e.feed(static_cast<char32_t>(*p), a);
            }
        }
        e.feed(U'x', a); e.commitBoundary(true, a);
        e.backspace(a); e.reopenLastCommit(buf, vtx::kMaxText); e.reset();
        e.seed(u"thấy", 4); e.reset();
    }
    CHECK(gAllocs.load() - before == 0);
}

// Shared vectors (TelexCore/Tests/TelexCoreTests/Resources/spelling_error_cases.tsv) for
// the opt-in red underline: isValidSyllable / isSpellingError / hasSpellingError.
void spellingErrorCases() {
#ifdef VTX_SPELLING_CASES
    std::FILE* f = std::fopen(VTX_SPELLING_CASES, "rb");
    CHECK(f != nullptr);
    if (!f) return;
    char line[512];
    int rows = 0;
    while (std::fgets(line, sizeof line, f)) {
        std::string l(line);
        while (!l.empty() && (l.back() == '\n' || l.back() == '\r')) l.pop_back();
        if (l.empty() || l[0] == '#') continue;
        std::string col[4];
        int c = 0;
        for (char ch : l) {
            if (ch == '\t') { if (++c > 3) break; continue; }
            col[c].push_back(ch);
        }
        const bool want = col[2] == "1";
        bool got = false;
        if (col[0] == "syllable" || col[0] == "error") {
            std::u32string w = fromUtf8(col[1]);
            const int n = static_cast<int>(w.size());
            got = col[0] == "syllable" ? vtx::SyllableValidator::isValidSyllable(w.data(), n, false)
                                       : vtx::SyllableValidator::isSpellingError(w.data(), n, false);
        } else if (col[0] == "keys") {
            vtx::TelexEngine e;   // app defaults
            e.freeMarking = true; e.contextualEnglish = true; e.collisionPrefersVietnamese = true;
            e.teencode = false;
            e.liveSpellCheck = col[3].find('L') == std::string::npos;
            const bool autoRestore = col[3].find('R') == std::string::npos;
            vtx::Action a;
            for (char k : col[1]) e.feed(static_cast<char32_t>(static_cast<unsigned char>(k)), a);
            got = e.hasSpellingError(autoRestore);
        } else {
            CHECK(!"unknown row kind");
            continue;
        }
        ++rows;
        if (got == want) ++gPass;
        else { ++gFail; std::printf("FAIL spelling case: %s %s want %d\n", col[0].c_str(), col[1].c_str(), want); }
    }
    std::fclose(f);
    CHECK(rows > 50);
#else
    CHECK(!"VTX_SPELLING_CASES not defined");
#endif
    // Never flagged without a word, and the C ABI agrees with the method.
    vtx::TelexEngine empty;
    CHECK(!empty.hasSpellingError(true));
}

// UpperToneBackspaceTests.testBackspaceEqualsRetypeWithoutLastKey (same LCG, same
// sequences as Swift/Kotlin): when the last key was inserted literally, ⌫ == retyping
// the keys without it on a fresh engine with the same settings.
void backspaceEqualsRetypeWithoutLastKey() {
    uint64_t seed = 0x9E3779B97F4A7C15ULL;
    auto next = [&seed]() { seed = seed * 6364136223846793005ULL + 1442695040888963407ULL; return seed >> 33; };
    auto typed = [](int cfg, const std::string& keys) {
        vtx::TelexEngine e;
        e.liveSpellCheck = (cfg & 1) != 0; e.freeMarking = (cfg & 2) != 0;
        e.simpleTelex = (cfg & 4) != 0; e.teencode = (cfg & 8) != 0; e.vniMode = (cfg & 16) != 0;
        feedStr(e, keys);
        return e;
    };
    const std::string telexKeys = "aeiouydwsfrxjzntcghl";
    const std::string vniKeys = "aeiouydntcgh1234567890";
    int checked = 0, bad = 0;
    for (int cfg = 0; cfg < 32; ++cfg) {
        const std::string& keys = (cfg & 16) ? vniKeys : telexKeys;
        for (int it = 0; it < 600; ++it) {
            std::string word;
            const int len = 3 + static_cast<int>(next() % 6);
            for (int i = 0; i < len; ++i) {
                char c = keys[static_cast<size_t>(next() % keys.size())];
                if (next() % 3 == 0 && c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
                word.push_back(c);
            }
            if (checked == 0) word = "uxuJxwl";
            for (size_t n = 2; n <= word.size(); ++n) {
                const std::string prefix = word.substr(0, n - 1);
                vtx::TelexEngine e = typed(cfg, word.substr(0, n));
                const std::string fresh = composed(typed(cfg, prefix));
                if (composed(e) != fresh + word[n - 1]) continue;
                ++checked;
                vtx::Action a;
                e.backspace(a);
                if (composed(e) != fresh) {
                    if (++bad <= 10) std::printf("FAIL ⌫ cfg=%d keys=%s got %s want %s\n", cfg,
                                                 word.substr(0, n).c_str(), composed(e).c_str(), fresh.c_str());
                }
            }
        }
    }
    for (const char* k : {"VieeJt", "uxuJxwl"}) {
        const std::string keys = k;
        for (int cfg = 0; cfg < 16; ++cfg) {
            vtx::TelexEngine e = typed(cfg, keys);
            vtx::Action a;
            e.backspace(a);
            CHECK_EQ(composed(e), composed(typed(cfg, keys.substr(0, keys.size() - 1))));
        }
    }
    CHECK(bad == 0);
    CHECK(checked > 20000);
}

// Issue #138: Vietnamese name + glued uppercase initials ("PhuwowngTH" → PhươngTH).
// Twin of TelexCore InitialsSuffixTests.swift; the golden corpus covers the rest.
void initialsSuffix() {
    struct Case { const char* keys; const char* want; };
    const Case cases[] = {
        {"PhuwowngTH", "PhươngTH"}, {"KieenTV", "KiênTV"}, {"HungfNV", "HùngNV"},
        {"LinhPTT", "LinhPTT"}, {"KieenSV", "KiênSV"}, {"NguyeenXJ", "NguyênXJ"},
        {"DDinhNV", "ĐinhNV"},
        // guards: unchanged behaviour
        {"KieenS", "KieenS"}, {"SaaS", "SaaS"}, {"iOS", "iOS"}, {"macOS", "macOS"},
        {"PhD", "PhD"}, {"JavaScript", "JavaScript"}, {"GitHub", "GitHub"},
        {"AsJSON", "AsJSON"}, {"HasID", "HasID"}, {"VIEETJ", "VIỆT"}, {"HDDND", "HĐND"},
        {"PhuwowngTHa", "PhuwowngTHa"},
    };
    for (int live = 0; live < 2; ++live) {
        for (const auto& c : cases) {
            vtx::TelexEngine e;
            e.liveSpellCheck = live != 0;
            feedStr(e, c.keys);
            CHECK_EQ(peek(e, true), std::string(c.want));
            CHECK_EQ(commitText(e, true), std::string(c.want));
        }
        vtx::TelexEngine e;
        e.liveSpellCheck = live != 0;
        vtx::Action a;
        feedStr(e, "KieenSV");
        e.backspace(a);
        CHECK_EQ(composed(e), std::string("KieenS"));
        e.feed(U'V', a);
        CHECK_EQ(composed(e), std::string("KiênSV"));
    }
}

// Controller-style replay (Swift ZZ harness / platform sessions): letters compose; any other
// character commits the word, is inserted, and is reported with noteBoundaryCharacter.
// Restore-undo records are appended as "{restored>vietnamese}".
std::string typeLikeController(vtx::TelexEngine& e, const std::string& text) {
    std::u32string in = fromUtf8(text);
    std::string out;
    auto commit = [&] {
        out += commitText(e, true);
    };
    std::string undos;
    auto takeUndo = [&] {
        vtx::RestoreUndo u;
        if (e.takeRestoreUndo(u))
            undos += "{" + toUtf8(u.restored, u.restoredLength) + ">" + toUtf8(u.vietnamese, u.vietnameseLength) + "}";
    };
    vtx::Action a;
    for (char32_t c : in) {
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) { e.feed(c, a); continue; }
        commit();
        takeUndo();
        std::u32string one(1, c);
        out += toUtf8(one);
        e.noteBoundaryCharacter(c);
    }
    commit();
    takeUndo();
    return out + undos;
}

// Acronyms, Vietnamese typo keep, glued separators/digits, restore-undo (Swift parity:
// TelexCore AcronymTypoGlueTests).
void acronymTypoGlueUndo() {
    struct Case { const char* in; const char* want; };
    const Case suite[] = {   // liveSpellCheck on, everything else engine default
        {"NAS", "NAS{NAS>NÁ}"}, {"OS", "OS{OS>Ó}"}, {"AWS", "AWS{AWS>Ắ}"}, {"TOAS", "TOAS{TOAS>TÓA}"},
        {"VIEEJT", "VIỆT"}, {"DDAF NAWXNG", "ĐÀ NẴNG"}, {"HDDND", "HĐND"}, {"VNDD", "VNĐ"},
        {"AA", "Â"}, {"COS", "CÓ"}, {"QUYEETS DDINHJ", "QUYẾT ĐỊNH"},
        {"deepseek", "deepseek"}, {"casual", "casual"}, {"tester", "tester"}, {"keep", "keep"},
        {"tieengsm", "tiếngm"},
        {"my_var", "my_var"}, {"MAX_SIZE", "MÃ_SIZE"}, {"ok.ddi", "ok.đi"}, {"haha.thooi", "haha.thôi"},
        {"vaf/hoawcj", "và/hoặc"}, {"anh/chij", "anh/chị"}, {"TP.Hoof", "TP.Hồ"},
        {"100W", "100W"}, {"10kW", "10kW"}, {"5trawm", "5trăm"}, {"2tieengs", "2tiếng"},
        {"100dd", "100đ"}, {"5s", "5s"}, {"4G", "4G"}, {"5tuw", "5tư"},
        {"bene NAS", "bene NAS{NAS>NÁ}"},
    };
    for (const Case& c : suite) {
        vtx::TelexEngine e;
        e.liveSpellCheck = true;
        CHECK_EQ(typeLikeController(e, c.in), std::string(c.want));
    }
    {   // free marking: the typo stays on screen; "lanwm" without it has two vowel groups
        vtx::TelexEngine e;
        e.liveSpellCheck = true; e.freeMarking = true;
        CHECK_EQ(typeLikeController(e, "lanwm"), std::string("lănm"));
        vtx::TelexEngine s;
        s.liveSpellCheck = true;
        CHECK_EQ(typeLikeController(s, "lanwm"), std::string("lanwm"));
    }
    {   // teencode elongation keeps its own rule (all caps too)
        vtx::TelexEngine e;
        CHECK_EQ(typeLikeController(e, "DAJA"), std::string("DẠA"));
    }
    {   // English collision restore offers ⌫-undo; the acronym never opens an English run
        vtx::TelexEngine e;
        e.liveSpellCheck = true; e.contextualEnglish = true;
        CHECK_EQ(typeLikeController(e, "he is"), std::string("he is{is>í}"));
        vtx::TelexEngine r;
        r.liveSpellCheck = true; r.freeMarking = true; r.contextualEnglish = true; r.retroactiveEnglish = true;
        CHECK_EQ(typeLikeController(r, "bene ASL USB"), std::string("bên ASL USB"));
    }
    {   // the record is dropped by the next key, and restoreUndoApplied ends the English run
        vtx::TelexEngine e;
        e.contextualEnglish = true;
        vtx::Action a;
        feedStr(e, "the");
        e.commitBoundary(true, a);
        e.noteBoundaryCharacter(U' ');
        feedStr(e, "NAS");
        e.commitBoundary(true, a);
        vtx::RestoreUndo u;
        CHECK(e.pendingRestoreUndo(u));
        e.feed(U'x', a);
        CHECK(!e.takeRestoreUndo(u));
        e.reset();
        feedStr(e, "he");
        e.commitBoundary(true, a);
        e.noteBoundaryCharacter(U' ');
        feedStr(e, "is");
        e.commitBoundary(true, a);
        CHECK(e.takeRestoreUndo(u));
        CHECK_EQ(toUtf8(u.restored, u.restoredLength), std::string("is"));
        CHECK_EQ(toUtf8(u.vietnamese, u.vietnameseLength), std::string("í"));
        CHECK(e.previousWordEnglish());
        e.restoreUndoApplied();
        CHECK(!e.previousWordEnglish());
        CHECK(!e.takeRestoreUndo(u));
    }
}

} // namespace

int runUnit() {
    acronymTypoGlueUndo();
    initialsSuffix();
    screenAlwaysEqualsComposed();
    peekMatchesCommitOnCopy();
    reopenIssue40();
    reopenBackspaceThroughWord();
    seedRoundTrips();
    overflowPassesThrough();
    nonLetterPassesThrough();
    hotPathDoesNotAllocate();
    spellingErrorCases();
    backspaceEqualsRetypeWithoutLastKey();
    std::printf("unit invariants: %d/%d pass\n", gPass, gPass + gFail);
    return gFail == 0 ? 0 : 1;
}
