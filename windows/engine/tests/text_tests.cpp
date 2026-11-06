// Text tools + Thêm dấu parity on the SHARED fixtures (the same files iOS and Android
// test against):
//   iOS/KeyboardTests/Fixtures/text-tools.txt   TextTools.swift ≡ .kt ≡ this port
//   iOS/KeyboardTests/Fixtures/add-tones.txt    AddTones.restore (static data)
//   iOS/KeyboardTests/Fixtures/vnlm-parity.txt  SyllableLM v3 reader (+ model checksum)
// plus tests/unicode-sample.txt (NFC/NFD/upper/lower vs Python unicodedata).
//
//   vtx_text_tests <fixtures dir> <resources dir (vnlexicon.bin, enlexicon.bin, vnlm.bin)>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "viettelex/add_tones.hpp"
#include "viettelex/text_tools.hpp"

using namespace vtx;

namespace {

int gPass = 0, gFail = 0;
#define CHECK(cond) do { if (cond) ++gPass; else { ++gFail; std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

bool readFile(const std::string& path, std::vector<uint8_t>& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    out.assign(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
    return true;
}

std::vector<std::string> lines(const std::string& path) {
    std::vector<std::string> v;
    std::ifstream f(path, std::ios::binary);
    std::string l;
    while (std::getline(f, l)) {
        if (!l.empty() && l.back() == '\r') l.pop_back();
        v.push_back(l);
    }
    return v;
}

std::vector<std::string> split(const std::string& s, char sep) {
    std::vector<std::string> out;
    size_t a = 0;
    while (true) {
        size_t b = s.find(sep, a);
        out.push_back(s.substr(a, b == std::string::npos ? std::string::npos : b - a));
        if (b == std::string::npos) break;
        a = b + 1;
    }
    return out;
}

std::string replaceAll(std::string s, const std::string& from, const std::string& to) {
    for (size_t p = 0; (p = s.find(from, p)) != std::string::npos; p += to.size()) s.replace(p, from.size(), to);
    return s;
}

std::u32string hexCps(const std::string& s) {
    std::u32string o;
    std::istringstream in(s);
    std::string t;
    while (in >> t) o.push_back(static_cast<char32_t>(std::strtoul(t.c_str(), nullptr, 16)));
    return o;
}

std::string hexOf(const std::u32string& s) {
    std::string o;
    char b[12];
    for (char32_t c : s) {
        std::snprintf(b, sizeof b, "%s%X", o.empty() ? "" : " ", static_cast<unsigned>(c));
        o += b;
    }
    return o;
}

// ---------------------------------------------------------------- text-tools.txt

void textToolsFixture(const std::string& dir) {
    int n = 0, bad = 0;
    for (const std::string& line : lines(dir + "/text-tools.txt")) {
        if (line.empty() || line[0] == '#') continue;
        auto c = split(line, '|');
        if (c.size() != 3) { ++bad; std::printf("FAIL odd fixture line: %s\n", line.c_str()); continue; }
        auto op = split(c[0], '@');
        auto decode = [](const std::string& s) { return replaceAll(replaceAll(s, "␣", " "), "⏎", "\n"); };
        text::Tool tool;
        if (op[0] == "upper") tool = text::Tool::Upper;
        else if (op[0] == "lower") tool = text::Tool::Lower;
        else if (op[0] == "title") tool = text::Tool::Title;
        else if (op[0] == "sentence") tool = text::Tool::Sentence;
        else if (op[0] == "stripDiacritics") tool = text::Tool::StripDiacritics;
        else { ++bad; std::printf("FAIL unknown op %s\n", op[0].c_str()); continue; }
        std::u32string in = text::fromUtf8(decode(c[1]));
        if (op.size() > 1) in = text::nfd(in);
        const std::u32string want = text::fromUtf8(decode(c[2]));
        const std::u32string got = text::apply(tool, in);
        if (got != want) {
            if (++bad <= 8) std::printf("FAIL text-tools %s: got \"%s\"\n", line.c_str(), text::toUtf8(got).c_str());
        }
        ++n;
    }
    CHECK(n >= 150);
    CHECK(bad == 0);
    std::printf("text-tools.txt: %d cases, %d failures\n", n, bad);
}

// ---------------------------------------------------------------- unicode-sample.txt

void unicodeSample(const std::string& path) {
    int n = 0, bad = 0;
    for (const std::string& line : lines(path)) {
        if (line.empty() || line[0] == '#') continue;
        auto c = split(line, '|');
        if (c.size() != 5) { ++bad; continue; }
        const std::u32string in = hexCps(c[0]);
        const std::u32string got[4] = {text::nfc(in), text::nfd(in), text::upper(in), text::lower(in)};
        static const char* const names[4] = {"NFC", "NFD", "upper", "lower"};
        for (int k = 0; k < 4; ++k) {
            if (got[k] != hexCps(c[k + 1])) {
                if (++bad <= 8)
                    std::printf("FAIL %s(%s) = %s, want %s\n", names[k], c[0].c_str(), hexOf(got[k]).c_str(),
                                c[k + 1].c_str());
            }
        }
        ++n;
    }
    CHECK(n >= 500);
    CHECK(bad == 0);
    std::printf("unicode-sample.txt: %d strings, %d failures\n", n, bad);
}

void unicodeUnits() {
    CHECK(text::isLetter(U'a') && text::isLetter(0x1EA1) && text::isLetter(0x4E00) && !text::isLetter(U'1'));
    CHECK(text::isMark(0x0301) && !text::isMark(U'a'));
    CHECK(text::isDigit(U'7') && text::isDigit(0x0663) && !text::isDigit(U'x'));
    CHECK(text::upper(std::u32string(U"ß")) == U"SS");
    CHECK(text::lower(std::u32string(U"ΟΔΟΣ")) == U"οδος");
    CHECK(text::nfc(text::nfd(U"Tiếng Việt")) == U"Tiếng Việt");
    CHECK(text::nfc(U"각") == U"각");  // Hangul LVT
    const std::u16string u16 = text::toUtf16(U"a😀ệ");
    CHECK(u16.size() == 4 && text::fromUtf16(u16) == U"a😀ệ");
    const char16_t lone[] = {u'a', 0xD800, u'b'};
    CHECK(text::fromUtf16(lone, 3) == U"a�b");
}

// ---------------------------------------------------------------- data files

struct Data {
    std::vector<uint8_t> vnlex, enlex, vnlm;
    addtones::LanguageData lang;
};

bool loadData(const std::string& res, Data& d) {
    if (!readFile(res + "/vnlexicon.bin", d.vnlex) || !readFile(res + "/enlexicon.bin", d.enlex) ||
        !readFile(res + "/vnlm.bin", d.vnlm))
        return false;
    return d.lang.load(d.vnlex.data(), d.vnlex.size(), d.enlex.data(), d.enlex.size(), d.vnlm.data(), d.vnlm.size());
}

// Swift: Int((v * 16).rounded()) — Float multiply then round half away from zero.
int swiftQ(float v) { return static_cast<int>(std::round(v * 16.0f)); }

void lmParity(const std::string& dir, const Data& d) {
    const addtones::SyllableLM& lm = d.lang.lm;
    CHECK(lm.ok());
    if (!lm.ok()) return;
    CHECK(lm.payloadHashOK());
    int n = 0, bad = 0;
    for (const std::string& line : lines(dir + "/vnlm-parity.txt")) {
        if (line.empty() || line[0] == '#') continue;
        auto t = split(line, ' ');
        std::vector<long long> a;
        for (size_t i = 1; i < t.size(); ++i) a.push_back(std::strtoll(t[i].c_str(), nullptr, 10));
        bool ok = true;
        const int ai0 = a.empty() ? 0 : static_cast<int>(a[0]);
        if (t[0] == "CHECKSUM") ok = static_cast<uint32_t>(a[0]) == lm.modelChecksum();
        else if (t[0] == "FILE") ok = static_cast<uint32_t>(a[0]) == addtones::fnv1a(d.vnlm.data(), d.vnlm.size());
        else if (t[0] == "S") ok = swiftQ(lm.score(ai0, static_cast<int>(a[1]), static_cast<int>(a[2]))) == a[3];
        else if (t[0] == "P") ok = swiftQ(lm.bigram(ai0).pmi(static_cast<int>(a[1]))) == a[2];
        else if (t[0] == "E") ok = swiftQ(lm.bigram(ai0).explicitPmi(static_cast<int>(a[1]))) == a[2];
        else if (t[0] == "N") ok = lm.bigram(ai0).size() == a[1];
        if (!ok && ++bad <= 8) std::printf("FAIL vnlm parity: %s\n", line.c_str());
        ++n;
    }
    CHECK(n > 2000);
    CHECK(bad == 0);
    std::printf("vnlm-parity.txt: %d lines, %d failures\n", n, bad);

    // a corrupt / foreign file is refused (runs without the LM)
    addtones::SyllableLM x;
    std::vector<uint8_t> v = d.vnlm;
    v[48 + 4 * 9] = static_cast<uint8_t>(v[48 + 4 * 9] + 8);
    CHECK(!x.load(v.data(), v.size(), d.lang.lexicon.hash(), d.lang.lexicon.count()));
    v = d.vnlm;
    v[36] = 0;
    CHECK(!x.load(v.data(), v.size(), d.lang.lexicon.hash(), d.lang.lexicon.count()));
    CHECK(!x.load(d.vnlm.data(), d.vnlm.size(), d.lang.lexicon.hash() ^ 1, d.lang.lexicon.count()));
    CHECK(!x.load(d.vnlm.data(), 100, d.lang.lexicon.hash(), d.lang.lexicon.count()));
}

void addTonesFixture(const std::string& dir, const Data& d) {
    CHECK(d.lang.lexicon.count() == 7184);
    CHECK(d.lang.lexicon.formCount() > 1600);
    CHECK(d.lang.english.size() > 10000);
    int n = 0, bad = 0;
    for (const std::string& line : lines(dir + "/add-tones.txt")) {
        if (line.empty() || line[0] == '#') continue;
        auto parts = split(line, '\t');
        if (parts.size() != 2) { ++bad; continue; }
        const addtones::Result r = addtones::restore(text::nfc(text::fromUtf8(parts[0])), d.lang);
        const std::string got = text::toUtf8(r.text);
        if (got != parts[1] && ++bad <= 8)
            std::printf("FAIL add-tones \"%s\": got \"%s\", want \"%s\"\n", parts[0].c_str(), got.c_str(),
                        parts[1].c_str());
        ++n;
    }
    CHECK(n >= 40);
    CHECK(bad == 0);
    std::printf("add-tones.txt: %d cases, %d failures\n", n, bad);

    // without the LM / English list it still restores (lexicon only), never crashes
    addtones::LanguageData lexOnly;
    CHECK(lexOnly.load(d.vnlex.data(), d.vnlex.size(), nullptr, 0, nullptr, 0));
    CHECK(!lexOnly.lm.ok());
    const addtones::Result r = addtones::restore(U"toi di hoc", lexOnly);
    CHECK(r.text.size() == 10 && r.changed > 0);
    addtones::LanguageData none;
    CHECK(!none.load(nullptr, 0, nullptr, 0, nullptr, 0));
    CHECK(addtones::restore(U"toi di hoc", none).text == U"toi di hoc");
}

// The compact indexes (4 bytes per form / per English word, keys read from the file) answer
// exactly what a plain scan of the files says.
void compactIndexes(const Data& d) {
    const addtones::Lexicon& lx = d.lang.lexicon;
    // forms: consecutive ids with one folded key; every form found at its own index
    int forms = 0, bad = 0;
    for (int id = 0; id < lx.count(); ++id) {
        if (id > 0 && lx.folded(id) == lx.folded(id - 1)) continue;
        if (lx.formIndex(lx.folded(id)) != forms || lx.formFirstId(forms) != id) ++bad;
        ++forms;
    }
    CHECK(forms == lx.formCount());
    CHECK(bad == 0);
    CHECK(lx.formEndId(lx.formCount() - 1) == lx.count());
    CHECK(lx.formIndex("") == -1);
    CHECK(lx.formIndex("zzzzzz") == -1);
    CHECK(lx.formIndex("toi") >= 0 && lx.folded(lx.formFirstId(lx.formIndex("toi"))) == "toi");

    // English: record order, words, frequencies; contains / lowerBound
    const addtones::EnglishLexicon& en = d.lang.english;
    const std::vector<uint8_t>& b = d.enlex;
    size_t p = 8, i = 0;
    std::vector<std::string> words;
    bad = 0;
    for (; p + 2 <= b.size() && i < en.size(); ++i) {
        const std::string w(reinterpret_cast<const char*>(&b[p + 2]), b[p]);
        if (en.word(i) != w || en.freq(i) != b[p + 1] || !en.contains(w) || en.lowerBound(w) != i) ++bad;
        words.push_back(w);
        p += 2 + b[p];
    }
    CHECK(i == en.size() && p == b.size());
    CHECK(bad == 0);
    CHECK(!en.contains("") && !en.contains("zzzzzzzzq") && !en.contains("keyboardx"));
    CHECK(en.lowerBound("") == 0);
    CHECK(en.lowerBound("zzzzzzzzz") == en.size());
    CHECK(en.lowerBound("keyb") < en.size() && en.word(en.lowerBound("keyb")).substr(0, 4) >= "keyb");

    // an unsorted file is sorted at load (same as before: sorted word order)
    const uint8_t unsorted[] = {'V', 'T', 'E', '1', 3, 0, 0, 0, 3, 9, 'c', 'a', 't', 2, 7, 'a', 'n', 3, 5, 'b', 'e', 'e'};
    addtones::EnglishLexicon u;
    CHECK(u.load(unsorted, sizeof unsorted));
    CHECK(u.size() == 3 && u.word(0) == "an" && u.word(1) == "bee" && u.word(2) == "cat");
    CHECK(u.freq(0) == 7 && u.freq(1) == 5 && u.freq(2) == 9);
    CHECK(u.contains("bee") && !u.contains("be"));
    // corrupt: a non a–z byte, a count past the end
    const uint8_t badChar[] = {'V', 'T', 'E', '1', 1, 0, 0, 0, 2, 1, 'a', 'B'};
    CHECK(!u.load(badChar, sizeof badChar) && u.size() == 0 && !u.contains("ab"));
    const uint8_t badCount[] = {'V', 'T', 'E', '1', 0xFF, 0xFF, 0xFF, 0x7F, 2, 1, 'a', 'b'};
    CHECK(!u.load(badCount, sizeof badCount) && u.size() == 0);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: vtx_text_tests <fixtures dir> <resources dir> [unicode-sample.txt]\n");
        return 2;
    }
    const std::string fixtures = argv[1], res = argv[2];
    unicodeUnits();
    if (argc >= 4) unicodeSample(argv[3]);
    textToolsFixture(fixtures);
    Data d;
    const bool loaded = loadData(res, d);
    CHECK(loaded);
    if (loaded) {
        lmParity(fixtures, d);
        addTonesFixture(fixtures, d);
        compactIndexes(d);
    }
    std::printf("text tests: %d passed, %d failed\n", gPass, gFail);
    return gFail ? 1 : 0;
}
