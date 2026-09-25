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
        }
        e.commitText(true, buf, vtx::kMaxText);
        e.feed(U'x', a); e.commitBoundary(true, a);
        e.backspace(a); e.reopenLastCommit(buf, vtx::kMaxText); e.reset();
        e.seed(u"thấy", 4); e.reset();
    }
    CHECK(gAllocs.load() - before == 0);
}

} // namespace

int runUnit() {
    screenAlwaysEqualsComposed();
    peekMatchesCommitOnCopy();
    reopenIssue40();
    reopenBackspaceThroughWord();
    seedRoundTrips();
    overflowPassesThrough();
    nonLetterPassesThrough();
    hotPathDoesNotAllocate();
    std::printf("unit invariants: %d/%d pass\n", gPass, gPass + gFail);
    return gFail == 0 ? 0 : 1;
}
