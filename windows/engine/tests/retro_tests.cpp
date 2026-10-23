// Retroactive English correction (Swift TelexCore RetroEnglishTests.swift, Kotlin
// RetroEnglishTest.kt): behaviour cases + the eval over the shared fixture
// iOS/KeyboardTests/Fixtures/retro-english-eval.txt with the same thresholds.
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>
#include "support.hpp"

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
    TelexEngine e = appEngine(true);
    RetroCorrection c;
    for (const char* k : {"His", "car", "is", "very"}) {
        vt::feedStr(e, k);
        vt::commitText(e, true);
        e.noteBoundaryCharacter(U' ');
        check(!e.takeRetroCorrection(c), std::string("no edit after ") + k);
    }
    vt::feedStr(e, "fast");
    eq(vt::commitText(e, true), "fast", "fast commit");
    check(e.pendingRetroCorrection(c) && c.backspaces == 16 && c.words == 3 &&
          vt::toUtf8(c.expected, c.expectedLength) == "í cả í very fast" &&
          vt::toUtf8(c.insert, c.insertLength) == "is car is very fast", "pending shape");
    e.noteBoundaryCharacter(U'.');
    check(e.takeRetroCorrection(c) && c.backspaces == 17 &&
          vt::toUtf8(c.expected, c.expectedLength) == "í cả í very fast." &&
          vt::toUtf8(c.insert, c.insertLength) == "is car is very fast.", "taken shape");
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

} // namespace

int runRetro(const char* fixture) {
    behaviour();
    eval(fixture);
    std::printf("retro: %d passed, %d failed\n", C.pass, C.fail);
    return C.fail ? 1 : 0;
}
