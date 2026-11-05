// Retroactive English correction (Swift TelexCore RetroEnglishTests.swift, Kotlin
// RetroEnglishTest.kt): behaviour cases + the eval over the shared fixture
// iOS/KeyboardTests/Fixtures/retro-english-eval.txt with the same thresholds.
// Strong English word + englishByFrequency (Swift FrequencyEnglishTests.swift) and the
// shared parity fixture iOS/KeyboardTests/Fixtures/frequency-english-parity.txt
// (FrequencyEnglishParityTests.swift).
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>
#include "support.hpp"
#include "generated_tables.hpp"

namespace {

using vtx::TelexEngine;
using vtx::RetroCorrection;

TelexEngine appEngine(bool retro, bool contextual = true) {
    TelexEngine e;
    e.freeMarking = true;
    e.liveSpellCheck = true;
    e.eagerEnglishRestore = true;
    e.teencode = false;
    e.contextualEnglish = contextual;
    e.collisionPrefersVietnamese = true;
    e.retroactiveEnglish = retro;
    return e;
}

bool isWordChar(char32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0xC0; }

/// Type like a controller: letters feed, anything else is a boundary (commitText, insert,
/// report), every correction applied after checking `expected`. -1 edits = mismatch.
std::u32string typeKeys(TelexEngine& e, const std::string& keys, int& edits) {
    std::u32string screen;
    auto apply = [&](void) {
        RetroCorrection c;
        if (!e.takeRetroCorrection(c)) return;
        std::u32string want;
        for (int i = 0; i < c.expectedLength; ++i) want.push_back(c.expected[i]);
        if (c.backspaces > static_cast<int>(screen.size()) ||
            screen.substr(screen.size() - c.backspaces) != want) { edits = -1000; return; }
        screen.resize(screen.size() - c.backspaces);
        for (int i = 0; i < c.insertLength; ++i) screen.push_back(c.insert[i]);
        ++edits;
    };
    vtx::Action a;
    for (char32_t ch : vt::fromUtf8(keys)) {
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
            e.feed(ch, a);
        } else {
            screen += vt::fromUtf8(vt::commitText(e, true));
            screen.push_back(ch);
            e.noteBoundaryCharacter(ch);
            apply();
        }
    }
    screen += vt::fromUtf8(vt::commitText(e, true));
    apply();
    return screen;
}

std::string typed(const std::string& keys, bool retro = true, bool contextual = true) {
    TelexEngine e = appEngine(retro, contextual);
    int n = 0;
    std::u32string s = typeKeys(e, keys, n);
    return n < 0 ? std::string("<expected-text mismatch>") : vt::toUtf8(s);
}

std::vector<std::u32string> words(const std::u32string& s) {
    std::vector<std::u32string> out;
    std::u32string cur;
    for (char32_t c : s) {
        if (isWordChar(c)) cur.push_back(c);
        else if (!cur.empty()) { out.push_back(cur); cur.clear(); }
    }
    if (!cur.empty()) out.push_back(cur);
    return out;
}

vt::Counter C;
void check(bool ok, const std::string& what) {
    if (ok) { ++C.pass; return; }
    ++C.fail;
    std::fprintf(stderr, "FAIL retro: %s\n", what.c_str());
}
void eq(const std::string& got, const std::string& want, const std::string& what) {
    check(got == want, what + ": got \"" + got + "\" want \"" + want + "\"");
}

void behaviour() {
    eq(typed("His car is very fast"), "His car is very fast", "rewrite");
    eq(typed("His car is very fast", false), "Hí cả í very fast", "off");
    eq(typed("my car is here now"), "my car is here now", "my car");
    eq(typed("of course not"), "of course not", "of course");
    eq(typed("its time to go home"), "its time to go home", "its");
    eq(typed("This list is very long"), "This list is very long", "this list");
    for (const char* k : {"Mai car team hopj", "Guwir file cho car nhaf", "car team meeting",
                          "cais nayf as the best", "check car deploy build", "lamf car review code",
                          "hoom nay hopj car buoori with the team", "em sex check the logs"})
        eq(typed(k), typed(k, false), std::string("negative ") + k);
    eq(typed("Mai car team hopj"), "Mai cả team họp", "Mai cả team họp");
    eq(typed("Guwir file cho car nhaf"), "Gửi file cho cả nhà", "Gửi file cho cả nhà");
    // Depends on contextualEnglish ("Quyết định theo ngữ cảnh"): inert without it.
    for (const char* k : {"His car is very fast", "my car is here now", "of course not"})
        eq(typed(k, true, false), typed(k, false, false), std::string("no contextual ") + k);
    TelexEngine off = appEngine(true, false);
    check(!off.retroactiveEnglishActive(), "inactive without contextual");
    TelexEngine vni = appEngine(true);
    vni.vniMode = true;
    check(!vni.retroactiveEnglishActive(), "inactive in VNI");
    eq(typed("HIS CAR is very fast"), "HIS CAR is very fast", "case");
    eq(typed("His Car is very fast"), "His Car is very fast", "case 2");

    // Shape: relative to the caret, prefix stripped, grows with a reported boundary char.
    // "very" is a STRONG English word: with three anchored candidates before it, it
    // completes the run on its own (one word earlier than two English words in a row).
    TelexEngine e = appEngine(true);
    RetroCorrection c;
    for (const char* k : {"His", "car", "is"}) {
        vt::feedStr(e, k);
        vt::commitText(e, true);
        e.noteBoundaryCharacter(U' ');
        check(!e.takeRetroCorrection(c), std::string("no edit after ") + k);
    }
    vt::feedStr(e, "very");
    eq(vt::commitText(e, true), "very", "very commit");
    check(e.pendingRetroCorrection(c) && c.backspaces == 11 && c.words == 3 && !c.flipBack &&
          vt::toUtf8(c.expected, c.expectedLength) == "í cả í very" &&
          vt::toUtf8(c.insert, c.insertLength) == "is car is very", "pending shape");
    e.noteBoundaryCharacter(U'.');
    check(e.takeRetroCorrection(c) && c.backspaces == 12 &&
          vt::toUtf8(c.expected, c.expectedLength) == "í cả í very." &&
          vt::toUtf8(c.insert, c.insertLength) == "is car is very.", "taken shape");
    check(!e.takeRetroCorrection(c), "taken once");

    // Unknown edits drop the history.
    for (int which = 0; which < 6; ++which) {
        TelexEngine h = appEngine(true);
        for (const char* k : {"His", "car", "is", "very"}) {
            vt::feedStr(h, k);
            vt::commitText(h, true);
            h.noteBoundaryCharacter(U' ');
        }
        vtx::Action a;
        switch (which) {
        case 0: h.reset(); break;
        case 1: h.resetContext(); break;
        case 2: h.forgetLastCommit(); break;
        case 3: h.backspace(a); break;
        case 4: h.noteBoundaryCharacter(U','); break;
        case 5:
            h.retroactiveEnglish = false;
            vt::feedStr(h, "x"); vt::commitText(h, true); h.noteBoundaryCharacter(U' ');
            h.retroactiveEnglish = true;
            break;
        }
        vt::feedStr(h, "fast");
        vt::commitText(h, true);
        check(!h.takeRetroCorrection(c), "clear #" + std::to_string(which));
    }
    TelexEngine nosep = appEngine(true);
    for (const char* k : {"His", "car", "is", "very", "fast"}) { vt::feedStr(nosep, k); vt::commitText(nosep, true); }
    check(!nosep.takeRetroCorrection(c), "no separator reported");

    // commitBoundary path.
    TelexEngine b = appEngine(true);
    vtx::Action a;
    const char* ks[] = {"His", "car", "is", "very", "fast"};
    for (int i = 0; i < 5; ++i) {
        vt::feedStr(b, ks[i]);
        b.commitBoundary(true, a);
        if (i < 4) b.noteBoundaryCharacter(U' ');
    }
    check(b.takeRetroCorrection(c) && vt::toUtf8(c.insert, c.insertLength) == "is car is very fast", "commitBoundary");
}

void eval(const char* path) {
    std::ifstream f(path);
    if (!f) { check(false, std::string("fixture missing: ") + path); return; }
    std::string line;
    int sentences = 0, tp = 0, fp = 0, offWrong = 0, vChanged = 0;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        size_t t1 = line.find('\t'), t2 = line.find('\t', t1 + 1);
        if (t1 == std::string::npos || t2 == std::string::npos) continue;
        std::string keys = line.substr(t1 + 1, t2 - t1 - 1), mask = line.substr(t2 + 1);
        auto o = words(vt::fromUtf8(typed(keys, false)));
        auto n = words(vt::fromUtf8(typed(keys, true)));
        auto k = words(vt::fromUtf8(keys));
        if (!(o.size() == n.size() && n.size() == k.size() && k.size() == mask.size())) {
            check(false, "word count " + keys);
            continue;
        }
        ++sentences;
        for (size_t i = 0; i < k.size(); ++i) {
            bool english = mask[i] == 'e';
            const std::u32string& gold = english ? k[i] : o[i];
            if (o[i] != n[i]) {
                if (n[i] == gold) ++tp; else ++fp;
                if (!english) ++vChanged;
            }
            if (english && o[i] != gold) ++offWrong;
        }
    }
    double precision = tp + fp ? double(tp) / (tp + fp) : 1.0;
    double recall = offWrong ? double(tp) / offWrong : 0.0;
    std::printf("RETRO-EVAL c++ %d sentences | TP=%d FP=%d precision=%.4f recall=%d/%d=%.4f vChanged=%d\n",
                sentences, tp, fp, precision, tp, offWrong, recall, vChanged);
    check(sentences > 5000, "fixture size");
    check(vChanged == 0, "no Vietnamese word rewritten");
    check(fp == 0, "no false rewrite");
    check(precision >= 0.99, "precision");
    check(recall >= 0.30, "recall");
}

// ---- Strong English word + englishByFrequency (Swift FrequencyEnglishTests.swift) ------

TelexEngine freqEngine(bool retro, bool frequency, bool teencode = false) {
    TelexEngine e = appEngine(retro);
    e.teencode = teencode;
    e.englishByFrequency = frequency;
    return e;
}

/// Swift FrequencyEnglishTests `type` / parityType: letters feed; anything else commits,
/// applies the pending edit if (`autoApply` and not Enter) or it is a FLIP-BACK (always),
/// then inserts the char and reports it. "\n" = Enter; end of keys = like Enter.
std::u32string typeFreq(TelexEngine& e, const std::string& keys, bool autoApply, int* flips = nullptr,
                        bool* mismatch = nullptr) {
    std::u32string screen;
    auto apply = [&](bool enter) {
        RetroCorrection c;
        if (!e.pendingRetroCorrection(c) || !(c.flipBack || (autoApply && !enter))) return;
        std::u32string want;
        for (int i = 0; i < c.expectedLength; ++i) want.push_back(c.expected[i]);
        if (c.backspaces > static_cast<int>(screen.size()) ||
            screen.substr(screen.size() - c.backspaces) != want) { if (mismatch) *mismatch = true; return; }
        e.takeRetroCorrection(c);
        screen.resize(screen.size() - c.backspaces);
        for (int i = 0; i < c.insertLength; ++i) screen.push_back(c.insert[i]);
        if (c.flipBack && flips) ++*flips;
    };
    vtx::Action a;
    for (char32_t ch : vt::fromUtf8(keys)) {
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
            e.feed(ch, a);
        } else {
            screen += vt::fromUtf8(vt::commitText(e, true));
            apply(ch == U'\n');
            screen.push_back(ch);
            e.noteBoundaryCharacter(ch);
        }
    }
    screen += vt::fromUtf8(vt::commitText(e, true));
    apply(true);
    return screen;
}

std::string ftyped(const std::string& keys, bool retro = true, bool frequency = true, bool autoApply = false,
                   bool teencode = false) {
    TelexEngine e = freqEngine(retro, frequency, teencode);
    bool mismatch = false;
    std::u32string s = typeFreq(e, keys, autoApply, nullptr, &mismatch);
    return mismatch ? std::string("<expected-text mismatch>") : vt::toUtf8(s);
}

bool scores(const char* w, uint8_t& en, uint8_t& vn) {
    return vtx::gen::kEnglishFrequency.find(w, static_cast<int>(std::strlen(w)), en, vn);
}
bool pair(const char* p) {
    return vtx::gen::kFrequencyPairs.contains(p, static_cast<int>(std::strlen(p)));
}

void frequency() {
    // Tables.
    uint8_t en = 0, vn = 0;
    check(scores("his", en, vn) && vn > 0 && int(en) > int(vn) + 45, "table his");
    check(scores("very", en, vn) && vn == 0, "table very");
    check(scores("fast", en, vn) && vn == 0 && en >= vtx::gen::kFrequencyStrongMin, "table fast");
    check(!scores("zzzz", en, vn) && !scores("", en, vn), "table miss");
    check(pair("his>huwngr") && pair("last>nuwax") && pair("this>sinh"), "pairs");
    check(!pair("his>car") && !pair("his>huwng"), "pairs miss");

    // Strong word completes the run (retro, no frequency flag).
    eq(ftyped("His car is fast.", true, false, true), "His car is fast.", "strong auto");
    eq(ftyped("His car is fast.", true, false, false), "Hí cả í fast.", "strong offer");
    {
        TelexEngine e = freqEngine(true, false);
        RetroCorrection c;
        for (const char* k : {"His", "car", "is"}) {
            vt::feedStr(e, k);
            vt::commitText(e, true);
            e.noteBoundaryCharacter(U' ');
            check(!e.pendingRetroCorrection(c), std::string("strong: no edit after ") + k);
        }
        vt::feedStr(e, "very");
        vt::commitText(e, true);
        check(e.pendingRetroCorrection(c) && vt::toUtf8(c.insert, c.insertLength) == "is car is very" &&
              !c.flipBack, "strong fires at very");
    }
    for (const char* k : {"Mai car team hopj", "lamf car review code", "Guwir file cho car nhaf",
                          "car team meeting", "is fast"})
        eq(ftyped(k, true, false, true), ftyped(k, false, false), std::string("strong needs two picks ") + k);
    eq(ftyped("is fast", true, false, true), "í fast", "is fast");

    // Frequency rule.
    eq(ftyped("His car is fast.", true, true, true), "His car is fast.", "freq 1");
    eq(ftyped("His dog is cute."), "His dog is cute.", "freq 2");
    eq(ftyped("Is it ok?"), "Is it ok?", "freq 3");
    eq(ftyped("How are you?"), "How are you?", "freq 4");
    eq(ftyped("Tooi ddi. His dog is cute."), "Tôi đi. His dog is cute.", "freq after sentence");
    eq(ftyped("sao is"), "sao í", "left VN 1");
    eq(ftyped("em is aj"), "em í ạ", "left VN 2");
    eq(ftyped("cho con bus"), "cho con bú", "left VN 3");
    eq(ftyped("thawts now"), "thắt nơ", "left VN 4");
    eq(ftyped("cais now ddor"), "cái nơ đỏ", "left VN 5");
    eq(ftyped("its nhaats"), "ít nhất", "common 1");
    eq(ftyped("Its nhaats laf vaayj"), "Ít nhất là vậy", "common 2");
    eq(ftyped("Mai car team hopj"), "Mai cả team họp", "common 3");
    eq(ftyped("Car nhaf owi"), "Cả nhà ơi", "common 4");
    eq(ftyped("been treen"), "bên trên", "common 5");

    // Flip-back.
    eq(ftyped("his huwngr"), "hí hửng", "flip pair 1");
    eq(ftyped("His huwngr quas"), "Hí hửng quá", "flip pair 2");
    eq(ftyped("last nuwax goij laij nhes"), "lát nữa gọi lại nhé", "flip pair 3");
    eq(ftyped("Last nuwax anh veef"), "Lát nữa anh về", "flip pair 4");
    eq(ftyped("This sinh ddeens muoonj"), "Thí sinh đến muộn", "flip pair 5");
    eq(ftyped("his huwngr\n"), "hí hửng\n", "flip before Enter");
    eq(ftyped("his his"), "hí hí", "redup 1");
    eq(ftyped("His His"), "Hí Hí", "redup 2");
    eq(ftyped("his his his vui ghee"), "hí hí hí vui ghê", "redup 3");
    eq(ftyped("Hif hif"), "Hì hì", "redup 4");
    eq(ftyped("hows hows"), "hớ hớ", "redup 5");
    eq(ftyped("How how"), "Hơ hơ", "redup 6");
    eq(ftyped("uwf uwf"), "ừ ừ", "redup 7");
    eq(ftyped("His ha his huwngr"), "Hí ha hí hửng", "redup two back");

    // Flip correction shape.
    {
        TelexEngine e = freqEngine(true, true);
        RetroCorrection c;
        vt::feedStr(e, "His");
        eq(vt::commitText(e, true), "His", "flip shape His");
        e.noteBoundaryCharacter(U' ');
        check(!e.pendingRetroCorrection(c), "flip shape none yet");
        vt::feedStr(e, "huwngr");
        eq(vt::commitText(e, true), "hửng", "flip shape hửng");
        check(e.pendingRetroCorrection(c) && c.backspaces == 7 && c.words == 1 && c.flipBack &&
              vt::toUtf8(c.expected, c.expectedLength) == "is hửng" &&
              vt::toUtf8(c.insert, c.insertLength) == "í hửng", "flip shape pending");
        e.noteBoundaryCharacter(U' ');
        check(e.takeRetroCorrection(c) && c.flipBack && vt::toUtf8(c.insert, c.insertLength) == "í hửng ",
              "flip shape taken");
        char16_t b[vtx::kMaxText];
        int n = e.debugRetroShown(0, b, vtx::kMaxText);
        check(e.debugRetroCount() >= 1 && vt::toUtf8(b, n) == "Hí" && !e.debugRetroEnglish(0), "flip history");
    }

    // No flip without evidence.
    eq(ftyped("Test xong roofi nhes"), "Test xong rồi nhé", "no evidence 1");
    eq(ftyped("His car"), "His cả", "no evidence 2");

    // Gates.
    for (const char* k : {"His car is fast.", "his huwngr", "His His", "sao is", "Test xong roofi nhes",
                          "Is it ok?", "last nuwax"}) {
        eq(ftyped(k, true, false), ftyped(k, true, false), std::string("off ") + k);
        eq(ftyped(k, false, true), ftyped(k, false, false), std::string("needs retro ") + k);
    }
    TelexEngine g = freqEngine(false, true);
    check(!g.englishByFrequencyActive(), "inactive without retro");
    g.retroactiveEnglish = true;
    check(g.englishByFrequencyActive(), "active with retro");
    g.vniMode = true;
    check(!g.englishByFrequencyActive(), "inactive in VNI");

    // Teencode disables the frequency rule.
    eq(ftyped("bits gofi khoor lawms", true, true, false, true), "bít gòi khổ lắm", "teencode");
}

std::string unescape(const std::string& s) {
    std::string o;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size() && s[i + 1] == 'n') { o.push_back('\n'); ++i; }
        else o.push_back(s[i]);
    }
    return o;
}

/// Replays the parity fixture (Swift writes it): every column must match exactly.
void parity(const char* path) {
    std::ifstream f(path);
    if (!f) { check(false, std::string("parity fixture missing: ") + path); return; }
    std::string line;
    int rows = 0, bad = 0;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::vector<std::string> col;
        size_t start = 0;
        for (;;) {
            size_t t = line.find('\t', start);
            col.push_back(line.substr(start, t == std::string::npos ? std::string::npos : t - start));
            if (t == std::string::npos) break;
            start = t + 1;
        }
        if (col.size() != 4) { check(false, "parity columns: " + line); continue; }
        ++rows;
        const std::string keys = unescape(col[0]);
        const bool autos[3] = {true, false, true}, freqs[3] = {false, true, true};
        for (int k = 0; k < 3; ++k) {
            TelexEngine e = freqEngine(true, freqs[k]);
            std::string got = vt::toUtf8(typeFreq(e, keys, autos[k]));
            std::string want = unescape(col[k + 1]);
            if (got != want) {
                if (++bad <= 20) std::fprintf(stderr, "FAIL parity col %d: %s\n  got  %s\n  want %s\n",
                                              k + 1, col[0].c_str(), got.c_str(), want.c_str());
            }
        }
    }
    std::printf("FREQUENCY-PARITY c++ %d rows x 3 columns, %d mismatches\n", rows, bad);
    check(rows > 500, "parity fixture size");
    check(bad == 0, "parity fixture matches");
}

} // namespace

int runRetro(const char* fixture, const char* parityFixture) {
    behaviour();
    frequency();
    if (parityFixture) parity(parityFixture);
    eval(fixture);
    std::printf("retro: %d passed, %d failed\n", C.pass, C.fail);
    return C.fail ? 1 : 0;
}
