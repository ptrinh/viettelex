// typo_fix_tests — "Gợi ý sửa lỗi gõ sai" with the real data (typo_fix.h), mirroring macOS
// AppTests/CaretSuggestionsTests.swift (typo part) and the precision eval of
// AppTests/TypoFixEvalTests.swift (same simulation: heldout sentences -> Telex keys -> one
// physical-keyboard slip per word at rate 10%/20%, plus the keep-as-is sets), and the
// app's answer to the TIP's jobs (caret_hint_ipc.h).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>
#include <vector>

#include <viettelex/add_tones.hpp>
#include <viettelex/text_tools.hpp>
#include <viettelex/vtx_engine.h>

#include "caret_hint_ipc.h"
#include "caret_hints.h"
#include "settings.h"
#include "test.h"
#include "typo_fix.h"

using namespace vtx;
using namespace vtx::app;

namespace {

std::vector<uint8_t> readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

struct Data {
    std::vector<uint8_t> vl, el, lm;
    addtones::LanguageData d;
    bool ok = false;
    Data() {
        vl = readFile(VTX_KB_RESOURCES "/vnlexicon.bin");
        el = readFile(VTX_KB_RESOURCES "/enlexicon.bin");
        lm = readFile(VTX_KB_RESOURCES "/vnlm.bin");
        ok = d.load(vl.data(), vl.size(), el.data(), el.size(), lm.data(), lm.size());
    }
};
const Data& data() {
    static const Data d;
    return d;
}

uint32_t macDefaultFlags() { return Settings{}.engineFlags(); }  // Windows defaults = macOS defaults

typo::LexiconSource& source() {
    static typo::LexiconSource s(data().d, macDefaultFlags());
    return s;
}

std::u32string U(const char* s) { return text::fromUtf8(std::string(s)); }
std::string S(const std::u32string& s) { return text::toUtf8(s); }
std::string S(const std::optional<std::u32string>& s) { return s ? S(*s) : std::string("-"); }
std::string fix(const char* raw) { return S(typo::correction(U(raw), source())); }

}  // namespace

// ---------------------------------------------------------------- lexicon lookups (VNSuggest)

TEST(typo_lexicon_index_matches_vnsuggest) {
    CHECK(data().ok);
    typo::LexiconIndex ix(data().d.lexicon);
    CHECK(ix.frequency(U("tôi")).has_value());
    CHECK(ix.frequency(U("Tôi")).has_value());          // lowercased like VNSuggest
    CHECK(!ix.frequency(U("tpoi")).has_value());
    CHECK(!ix.frequency(U("toi")).has_value() || ix.contains(U("toi")));
    CHECK(ix.hasCompletion(U("t")));                    // one key: top-32 bucket
    CHECK(ix.hasCompletion(U("kh")));
    CHECK(ix.hasCompletion(U("khô")));
    CHECK(!ix.hasCompletion(U("tp")));
    CHECK(!ix.hasCompletion(U("hello!")));              // not Vietnamese letters
    CHECK_EQ(S(typo::stripTones(U("cũm"))), std::string("cum"));
    CHECK_EQ(S(typo::stripTones(U("được"))), std::string("đươc"));
}

TEST(typo_physical_neighbours) {
    auto g = typo::physicalNeighbors(U'g');
    CHECK((g == std::vector<char32_t>{U'b', U'f', U'h', U't', U'v', U'y'}));
    auto z = typo::physicalNeighbors(U'z');
    CHECK((z == std::vector<char32_t>{U'a', U's', U'x'}));
    auto p = typo::physicalNeighbors(U'p');
    CHECK((p == std::vector<char32_t>{U'l', U'o'}));
}

// ---------------------------------------------------------------- CaretSuggestionsTests (typo)

TEST(typo_fixes_adjacent_key_and_swap) {
    CHECK_EQ(fix("tpoi"), std::string("tôi"));      // p next to o
    CHECK_EQ(fix("Tpoi"), std::string("Tôi"));
    CHECK_EQ(fix("khoong"), std::string("-"));      // already right (không)
    CHECK_EQ(fix("khpong"), std::string("không"));  // p next to o
    CHECK_EQ(fix("nhuwng"), std::string("-"));      // right: nhưng
}

TEST(typo_leaves_known_words_alone) {
    CHECK_EQ(fix("github"), std::string("-"));      // English
    CHECK_EQ(fix("hello"), std::string("-"));
    CHECK_EQ(fix("toi"), std::string("-"));         // unaccented = a valid form
    CHECK_EQ(fix("tooi"), std::string("-"));
    CHECK(source().isKnown(U("the")));
    CHECK(!source().isKnown(U("tpoi")));
    CHECK(source().isChatWord(U("ko")) && source().isChatWord(U("dc")));
    CHECK(!source().isChatWord(U("anh")));          // a Vietnamese syllable is not a chat word
}

TEST(typo_pick_needs_margin_including_rivals) {
    using typo::Cand;
    using typo::Edit;
    const typo::Params p;
    CHECK(typo::pick({Cand{U("tôi"), 255, Edit::Sub}}, p)->word == U("tôi"));
    CHECK(!typo::pick({Cand{U("tôi"), 140, Edit::Sub}}, p));                              // not common enough
    CHECK(!typo::pick({Cand{U("tôi"), 255, Edit::Sub}, Cand{U("tới"), 200, Edit::Sub}}, p));  // too close
    CHECK(!typo::pick({Cand{U("tội"), 175, Edit::Sub}, Cand{U("tôi"), 255, Edit::Del}}, p));  // the rival wins
    CHECK(typo::pick({Cand{U("tôi"), 255, Edit::Sub}, Cand{U("tối"), 150, Edit::Ins}}, p)->word == U("tôi"));
}

TEST(hint_jobs_answer_typo_and_tones) {
    HintJobs jobs(&data().d);
    HintMessage m;
    m.request = 7;
    m.job = static_cast<uint32_t>(HintJob::Typo);
    m.flags = macDefaultFlags();
    m.text = u"tpoi";
    CHECK(jobs.answer(m) == u"tôi");
    m.text = u"hello";
    CHECK(jobs.answer(m).empty());
    m.job = static_cast<uint32_t>(HintJob::Tones);
    m.text = u"toi di hoc ";
    CHECK(jobs.answer(m) == u"tôi đi học ");
    // End to end with the TIP's screen logic: run -> restored -> suggestion.
    auto run = hints::toneRun(hints::toU32(u"Chiều nào toi di hoc hom nay "));
    CHECK(run.has_value());
    m.text = hints::toU16(*run);
    auto s = hints::toneSuggestion(*run, hints::toU32(jobs.answer(m)));
    CHECK(s && s->display == u"tôi đi học hôm nay" && s->replace == u"toi di hoc hom nay ");
    HintJobs none(nullptr);
    CHECK(none.answer(m).empty());
}

// Memory (GitHub #153): the language data is loaded by the first job that needs it, never by the
// app's start sequence (construction + setLearned / setFilterSensitive), so a portable copy — no
// TIP, no job — never loads it; and the loader runs once.
TEST(hint_jobs_load_language_data_on_first_job_only) {
    int loads = 0;
    HintJobs jobs([&]() -> const addtones::LanguageData* {
        ++loads;
        return &data().d;
    });
    jobs.setLearned(nullptr);  // = textActionsConfigure -> learnedSettingsChanged at start
    jobs.setFilterSensitive(false);
    jobs.setFilterSensitive(true);
    CHECK(loads == 0 && !jobs.dataLoaded() && !jobs.predictionLoaded());
    HintMessage m;
    m.job = static_cast<uint32_t>(HintJob::Typo);
    m.flags = macDefaultFlags();
    CHECK(jobs.answer(m).empty());  // empty text: nothing to do, nothing loaded
    CHECK(loads == 0 && !jobs.dataLoaded());
    m.text = u"tpoi";
    CHECK(jobs.answer(m) == u"tôi");
    CHECK(loads == 1 && jobs.dataLoaded() && !jobs.predictionLoaded());
    m.job = static_cast<uint32_t>(HintJob::Tones);
    m.text = u"toi di hoc ";
    CHECK(jobs.answer(m) == u"tôi đi học ");
    CHECK(jobs.knownWord("tôi"));
    CHECK(loads == 1 && jobs.predictionLoaded());

    // knownWord (the learned model's test) loads too; a failed load is not retried per job
    int tries = 0;
    HintJobs missing([&]() -> const addtones::LanguageData* {
        ++tries;
        return nullptr;
    });
    CHECK(!missing.knownWord("tôi"));
    CHECK(missing.answer(m).empty());
    CHECK(tries == 1 && missing.dataLoaded());
}

// ---------------------------------------------------------------- TypoFixEvalTests (precision floor)

namespace {

struct Rng {
    uint64_t s;
    uint64_t next() {
        s += 0x9E3779B97F4A7C15ull;
        uint64_t z = s;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
        return z ^ (z >> 31);
    }
    double unit() { return static_cast<double>(next() >> 11) / static_cast<double>(1ull << 53); }
    int integer(int n) { return static_cast<int>(next() % static_cast<uint64_t>(n)); }
};

// SyllableLM.normalize: NFC, lowercase, old-style tone placement like vnlexicon (hoà -> hòa).
std::u32string normalize(const std::u32string& w) {
    std::u32string s = text::nfc(text::lower(w));
    if (s.size() < 2) return s;
    static const std::map<std::u32string, std::u32string> oldStyle = {
        {U("oà"), U("òa")}, {U("oá"), U("óa")}, {U("oả"), U("ỏa")}, {U("oã"), U("õa")}, {U("oạ"), U("ọa")},
        {U("oè"), U("òe")}, {U("oé"), U("óe")}, {U("oẻ"), U("ỏe")}, {U("oẽ"), U("õe")}, {U("oẹ"), U("ọe")},
        {U("uỳ"), U("ùy")}, {U("uý"), U("úy")}, {U("uỷ"), U("ủy")}, {U("uỹ"), U("ũy")}, {U("uỵ"), U("ụy")}};
    const std::u32string pair = s.substr(s.size() - 2);
    auto it = oldStyle.find(pair);
    if (it == oldStyle.end()) return s;
    if (pair[0] == U'u' && s.size() >= 3 && s[s.size() - 3] == U'q') return s;
    return s.substr(0, s.size() - 2) + it->second;
}

std::u32string screen(const std::u32string& raw) {
    vtx_engine* e = vtx_create();
    vtx_set_flags(e, macDefaultFlags());
    vtx_action a;
    for (char32_t c : raw) vtx_feed(e, c, &a);
    uint16_t buf[VTX_MAX_TEXT + 1];
    const int32_t n = vtx_commit_text(e, 1, buf, VTX_MAX_TEXT + 1);
    vtx_destroy(e);
    std::u16string s;
    if (n > 0) s.assign(reinterpret_cast<const char16_t*>(buf), static_cast<size_t>(n));
    return text::fromUtf16(s);
}

struct Variant {
    std::u32string keys;
    double share;
};

std::vector<Variant> variants(const std::u32string& syllable) {
    std::vector<std::u32string> chars;
    char32_t tone = 0;
    for (char32_t u : text::nfd(text::lower(syllable))) {
        switch (u) {
            case 0x302:
                if (chars.empty()) return {};
                chars.back() += chars.back();
                break;
            case 0x306: case 0x31B:
                if (chars.empty()) return {};
                chars.back() += U'w';
                break;
            case 0x301: tone = U's'; break;
            case 0x300: tone = U'f'; break;
            case 0x309: tone = U'r'; break;
            case 0x303: tone = U'x'; break;
            case 0x323: tone = U'j'; break;
            case 0x111: chars.push_back(U"dd"); break;
            default:
                if (u >= U'a' && u <= U'z') chars.push_back(std::u32string(1, u));
                else return {};
        }
    }
    if (chars.empty()) return {};
    std::u32string all;
    for (auto& c : chars) all += c;
    if (!tone) return {{all, 1}};
    int lastVowel = -1;
    for (size_t i = 0; i < chars.size(); ++i)
        if (std::u32string(U"aeiouy").find(chars[i][0]) != std::u32string::npos) lastVowel = static_cast<int>(i);
    if (lastVowel < 0 || lastVowel >= static_cast<int>(chars.size()) - 1) return {{all + tone, 1}};
    std::u32string head, coda;
    for (int i = 0; i <= lastVowel; ++i) head += chars[static_cast<size_t>(i)];
    for (size_t i = static_cast<size_t>(lastVowel) + 1; i < chars.size(); ++i) coda += chars[i];
    return {{all + tone, 0.6}, {head + tone + coda, 0.4}};
}

const std::vector<Variant>& validVariants(const std::u32string& s) {
    static std::map<std::u32string, std::vector<Variant>> cache;
    auto it = cache.find(s);
    if (it != cache.end()) return it->second;
    const std::u32string want = normalize(s);
    std::vector<Variant> v;
    for (const Variant& x : variants(s))
        if (normalize(source().compose(x.keys)) == want) v.push_back(x);
    return cache[s] = v;
}

std::u32string toneless(const std::u32string& s) {
    std::u32string t;
    for (char32_t c : s) t.push_back(c == 0x111 ? U'd' : c);
    std::u32string out;
    for (char32_t c : text::nfd(t))
        if (c < 0x300 || c > 0x36F) out.push_back(c);
    return out;
}

std::u32string slip(const std::u32string& keys, Rng& rng) {
    std::u32string c = keys;
    const double r = rng.unit();
    const int i = rng.integer(static_cast<int>(c.size()));
    auto neighbor = [&](char32_t k, char32_t& out) {
        const auto& n = typo::physicalNeighbors(k);
        if (n.empty()) return false;
        out = n[static_cast<size_t>(rng.integer(static_cast<int>(n.size())))];
        return true;
    };
    char32_t n = 0;
    const size_t ui = static_cast<size_t>(i);
    if (r < 0.45) {
        if (neighbor(c[ui], n)) c[ui] = n;
    } else if (r < 0.65) {
        if (c.size() > 1) c.erase(ui, 1);
    } else if (r < 0.80) {
        if (neighbor(c[ui], n)) c.insert(c.begin() + (rng.integer(2) == 0 ? i : i + 1), n);
    } else if (r < 0.95) {
        if (c.size() > 1) {
            const size_t j = std::min(ui, c.size() - 2);
            std::swap(c[j], c[j + 1]);
        }
    } else {
        c.insert(c.begin() + i, c[ui]);
    }
    return c;
}

struct Rec {
    std::u32string typed;
    bool gated = false;  // passed the production gate
    std::vector<typo::Cand> cands;
    bool ok = false;
    std::u32string want;
    std::vector<typo::Cand> en;  // English candidates (raw keys, enlexicon)
};

Rec rec(const std::u32string& typed, bool ok, const std::u32string& want) {
    Rec r{typed, false, {}, ok, want, {}};
    const std::u32string word = screen(typed);
    if (!hints::typoWorthChecking(U' ', typed, word, 3)) return r;
    const std::u32string lower = text::lower(typed);
    const std::u32string cur = source().compose(lower);
    if (source().isKnown(lower) || (cur != lower && source().isKnown(text::lower(cur))) || source().frequency(cur) ||
        source().hasCompletion(cur))
        return r;
    r.gated = true;
    r.cands = typo::candidates(lower, source());
    r.en = typo::englishCandidates(lower, source());
    return r;
}

// English Tatoeba sentences (iOS/KeyboardTests/Fixtures/swipe-lang-sentences.txt), set dev|test.
std::vector<std::u32string> englishSentenceWords(const char* set) {
    std::vector<std::u32string> out;
    std::ifstream f(std::string(VTX_FIXTURES) + "/swipe-lang-sentences.txt");
    std::string line;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty() || line[0] == '#') continue;
        const size_t a = line.find('\t'), b = a == std::string::npos ? a : line.find('\t', a + 1);
        if (b == std::string::npos || line.compare(0, a, set) != 0 || line.compare(a + 1, b - a - 1, "en") != 0) continue;
        std::u32string w;
        for (size_t i = b + 1; i <= line.size(); ++i) {
            char c = i < line.size() ? line[i] : ' ';
            if (c >= 'A' && c <= 'Z') c = static_cast<char>(c + 32);
            if (c >= 'a' && c <= 'z') w.push_back(static_cast<char32_t>(c));
            else if (!w.empty()) { out.push_back(w); w.clear(); }
        }
    }
    return out;
}

std::vector<std::vector<std::u32string>> heldout() {
    std::vector<std::vector<std::u32string>> out;
    std::ifstream f(std::string(VTX_FIXTURES) + "/bigram-heldout.txt");
    std::string line;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty() || line[0] == '#') continue;
        std::vector<std::u32string> sent;
        std::istringstream ss(line);
        std::string w;
        while (ss >> w) sent.push_back(U(w.c_str()));
        out.push_back(sent);
    }
    return out;
}

std::vector<Rec> collectVn(const std::vector<std::vector<std::u32string>>& sents, double rate, uint64_t seed) {
    Rng rng{seed};
    std::vector<Rec> out;
    for (const auto& sent : sents) {
        for (const auto& syl : sent) {
            const auto& v = validVariants(syl);
            if (v.empty()) continue;
            double tot = 0;
            for (const auto& x : v) tot += x.share;
            double x = rng.unit() * tot;
            std::u32string keys = v.back().keys;
            for (const auto& k : v) {
                x -= k.share;
                if (x <= 0) {
                    keys = k.keys;
                    break;
                }
            }
            const std::u32string typed = rng.unit() < rate ? slip(keys, rng) : keys;
            const std::u32string want = normalize(syl);
            out.push_back(rec(typed, normalize(source().compose(typed)) == want, want));
        }
    }
    return out;
}

std::vector<Rec> collectKeep(const std::vector<std::u32string>& words, double rate, uint64_t seed) {
    Rng rng{seed};
    std::vector<Rec> out;
    for (const auto& w : words) {
        bool asciiLower = !w.empty();
        for (char32_t c : w)
            if (!(c >= U'a' && c <= U'z')) asciiLower = false;
        if (!asciiLower) continue;
        const std::u32string typed = rng.unit() < rate ? slip(w, rng) : w;
        out.push_back(rec(typed, typed == w, w));
    }
    return out;
}

std::vector<std::u32string> englishWords(int n, uint64_t seed) {
    // enlexicon.bin in file order ("VTE1" | count | [len][freq][a–z]…), like SwipeEnglish.
    const std::vector<uint8_t>& b = data().el;
    std::vector<std::u32string> words;
    std::vector<double> w;
    if (b.size() >= 8) {
        const uint32_t count = b[4] | b[5] << 8 | b[6] << 16 | static_cast<uint32_t>(b[7]) << 24;
        size_t p = 8;
        for (uint32_t i = 0; i < count && p + 2 <= b.size(); ++i) {
            const size_t len = b[p];
            words.push_back(std::u32string(b.begin() + static_cast<std::ptrdiff_t>(p + 2),
                                           b.begin() + static_cast<std::ptrdiff_t>(p + 2 + len)));
            w.push_back(std::exp(0.06 * (static_cast<double>(b[p + 1]) - 255)));
            p += 2 + len;
        }
    }
    double tot = 0;
    for (double x : w) tot += x;
    Rng rng{seed};
    std::vector<std::u32string> out;
    for (int k = 0; k < n; ++k) {
        double r = rng.unit() * tot;
        size_t i = 0;
        while (i + 1 < w.size() && r > w[i]) {
            r -= w[i];
            ++i;
        }
        out.push_back(words[i]);
    }
    return out;
}

const char* const kOov[] = {"khum", "mng", "nma", "nhma", "tks", "thx", "pls", "plz", "omg", "hcm", "tphcm",
    "kpop", "hic", "hix", "ntn", "trc", "bik", "thik", "zui", "kkk", "hjhj", "vcd", "hqua", "hnay", "nguoi",
    "ngta", "vch", "cty", "sdt", "cmnd", "gplx", "atm", "iphone", "macbook", "zalo", "shopee", "tiktok",
    "grab", "momo", "vnexpress", "hanoi", "saigon", "danang", "nguyen", "tran", "pham", "huynh"};

struct Score {
    int fix = 0, good = 0, wrong = 0, falseFix = 0, err = 0, words = 0;
    double precision() const { return fix == 0 ? 1 : static_cast<double>(good) / fix; }
    double recall() const { return err == 0 ? 0 : static_cast<double>(good) / err; }
    void add(const Score& o) {
        fix += o.fix; good += o.good; wrong += o.wrong; falseFix += o.falseFix; err += o.err; words += o.words;
    }
};

// = typo::correction: the Vietnamese fix, else the English one (`english` false = VN only).
Score score(const std::vector<Rec>& recs, const typo::Params& p, bool english = true) {
    Score s;
    for (const Rec& r : recs) {
        ++s.words;
        if (!r.ok) ++s.err;
        if (static_cast<int>(r.typed.size()) < p.minLen || !r.gated) continue;
        auto c = typo::pick(r.cands, p);
        if (!c && english) c = typo::englishPick(r.en, r.cands, static_cast<int>(r.typed.size()));
        if (!c) continue;
        ++s.fix;
        if (r.ok) ++s.falseFix;
        else if (normalize(c->word) == r.want) ++s.good;
        else ++s.wrong;
    }
    return s;
}

}  // namespace

// Regression: precision ≥ 97% on TEST (VN 2 seeds × 10%/20% slips + keep-as-is sets),
// recall with a floor — the same bar as macOS testPrecisionFloorOnHeldout.
TEST(typo_eval_precision_floor) {
    const auto all = heldout();
    CHECK(all.size() > 1000);
    std::vector<std::vector<std::u32string>> test;
    for (size_t i = 1; i < all.size(); i += 2) test.push_back(all[i]);
    const typo::Params p;
    Score tot;
    for (uint64_t sd : {11ull, 22ull})
        for (double rate : {0.1, 0.2}) tot.add(score(collectVn(test, rate, sd), p));
    std::vector<std::u32string> chat(source().chatWords().begin(), source().chatWords().end());
    std::sort(chat.begin(), chat.end());
    std::vector<std::u32string> chat3, oov5, tl;
    for (int k = 0; k < 3; ++k) chat3.insert(chat3.end(), chat.begin(), chat.end());
    for (int k = 0; k < 5; ++k)
        for (const char* w : kOov) oov5.push_back(U(w));
    for (size_t i = 0; i < test.size() && i < 400; ++i)
        for (const auto& s : test[i]) tl.push_back(toneless(s));
    const std::vector<std::vector<std::u32string>> keep = {englishWords(1500, 7), chat3, oov5, tl};
    for (const auto& w : keep) {
        tot.add(score(collectKeep(w, 0, 1), p));
        tot.add(score(collectKeep(w, 0.2, 3), p));
    }
    std::printf("  TYPOFIX TEST: words %d | wrong-typed %d | fixes %d (good %d, wrong %d, false %d) | P=%.1f%% R=%.1f%%\n",
                tot.words, tot.err, tot.fix, tot.good, tot.wrong, tot.falseFix, 100 * tot.precision(),
                100 * tot.recall());
    CHECK(tot.precision() >= 0.97);
    CHECK(tot.recall() >= 0.10);
}

// English fixes (= macOS TypoFixEvalTests.testEnglishPrecisionOnHeldout): Tatoeba TEST words with
// 15% hardware-keyboard slips (2 seeds) — P ≥ 95%, R ≥ 30%.
TEST(typo_eval_english_precision) {
    const auto words = englishSentenceWords("test");
    CHECK(words.size() > 3000);
    const typo::Params p;
    Score en = score(collectKeep(words, 0.15, 1), p);
    en.add(score(collectKeep(words, 0.15, 2), p));
    Score base = score(collectKeep(words, 0.15, 1), p, false);
    base.add(score(collectKeep(words, 0.15, 2), p, false));
    std::printf("  TYPOFIX EN TEST: words %d | wrong-typed %d | fixes %d (good %d, wrong %d, false %d) | P=%.1f%% R=%.1f%%"
                " (VN only: R=%.1f%%)\n", en.words, en.err, en.fix, en.good, en.wrong, en.falseFix,
                100 * en.precision(), 100 * en.recall(), 100 * base.recall());
    CHECK(en.precision() >= 0.95);
    CHECK(en.recall() >= 0.30);
}

TEST(typo_fixes_english) {
    CHECK_EQ(fix("spellnig"), std::string("spelling"));
    CHECK_EQ(fix("Spellnig"), std::string("Spelling"));
    CHECK_EQ(fix("teh"), std::string("the"));
    CHECK_EQ(fix("becuase"), std::string("because"));
    CHECK_EQ(fix("recieve"), std::string("receive"));
    CHECK_EQ(fix("goverment"), std::string("government"));
    CHECK_EQ(fix("hte"), std::string("-"));      // the 255 vs he 245: too close
    CHECK_EQ(fix("kubectl"), std::string("-"));
    CHECK_EQ(fix("tpoi"), std::string("tôi"));   // Vietnamese first
}
