// Hand-written expectations from TelexCore's Swift XCTests (via tools/port_tests.py).
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include "support.hpp"

using namespace vt;

namespace {

struct Case {
    const char* helper; const char* flags; const char* input; const char* expected;
    int negate; int n; int autoRestore; const char* origin;
};
const Case kCases[] = {
#include "ported_cases.inc"
};

std::vector<std::string> splitSpaces(const std::string& s, bool keepEmpty) {
    std::vector<std::string> out;
    std::string cur;
    for (char c : s) {
        if (c == ' ') { if (keepEmpty || !cur.empty()) out.push_back(cur); cur.clear(); }
        else cur += c;
    }
    if (keepEmpty || !cur.empty()) out.push_back(cur);
    return out;
}
std::string join(const std::vector<std::string>& v) {
    std::string o;
    for (size_t i = 0; i < v.size(); ++i) { if (i) o += ' '; o += v[i]; }
    return o;
}

std::string run(const Case& c) {
    vtx::TelexEngine e;
    configure(e, c.flags);
    std::string in = c.input;
    std::string h = c.helper;
    if (h == "composeWith") { feedStr(e, in); return composed(e); }
    if (h == "commitWith") { feedStr(e, in); return commitText(e, c.autoRestore != 0); }
    if (h == "backspaceWith") {
        feedStr(e, in);
        vtx::Action a;
        for (int i = 0; i < c.n; ++i) e.backspace(a);
        return composed(e);
    }
    if (h == "sentenceCtx") {           // commit at each space; final word if any (or empty input)
        std::vector<std::string> words;
        bool wrote = false;
        vtx::Action a;
        for (char32_t ch : fromUtf8(in)) {
            if (ch == U' ') { words.push_back(commitText(e, true)); wrote = false; }
            else { e.feed(ch, a); wrote = true; }
        }
        if (wrote || words.empty()) words.push_back(commitText(e, true));
        return join(words);
    }
    if (h == "sentenceSplit") {         // split on spaces (omit empties), commit each word
        std::vector<std::string> out;
        for (const auto& w : splitSpaces(in, false)) { feedStr(e, w); out.push_back(commitText(e, true)); }
        return join(out);
    }
    if (h == "sentenceToggle") {        // commit at each space and once more at the end
        std::vector<std::string> out;
        vtx::Action a;
        for (char32_t ch : fromUtf8(in)) {
            if (ch == U' ') out.push_back(commitText(e, true)); else e.feed(ch, a);
        }
        out.push_back(commitText(e, true));
        return join(out);
    }
    bool teen = std::strchr(c.flags, 't') == nullptr;
    std::u32string w = fromUtf8(in);
    if (h == "isValidSyllable") return vtx::SyllableValidator::isValidSyllable(w.data(), static_cast<int>(w.size()), teen) ? "1" : "0";
    if (h == "isValidPrefix") return vtx::SyllableValidator::isValidPrefix(w.data(), static_cast<int>(w.size()), teen) ? "1" : "0";
    return "<unknown helper>";
}

} // namespace

int runPorted() {
    int pass = 0, fail = 0;
    for (const Case& c : kCases) {
        std::string got = run(c);
        bool ok = c.negate ? got != c.expected : got == c.expected;
        if (ok) { ++pass; continue; }
        ++fail;
        std::printf("FAIL %s: %s(\"%s\") [%s] expected %s\"%s\" got \"%s\"\n", c.origin, c.helper, c.input,
                    c.flags, c.negate ? "!= " : "", c.expected, got.c_str());
    }
    std::printf("ported Swift tests: %d/%d pass\n", pass, pass + fail);
    return fail == 0 ? 0 : 1;
}
