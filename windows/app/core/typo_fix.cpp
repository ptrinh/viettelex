// typo_fix.cpp — see typo_fix.h. Same names and order as the Swift sources (TypoFixLogic,
// AdjacentKeyFixer.oneEditCandidates, VNSuggest.frequency / matches).
#include "typo_fix.h"

#include <algorithm>
#include <map>
#include <new>

#include "caret_hint_ipc.h"
#include "text_action_logic.h"
#include "word_prediction.h"

#include <viettelex/add_tones.hpp>
#include <viettelex/telex_engine.hpp>
#include <viettelex/text_tools.hpp>
#include <viettelex/vtx_engine.h>

namespace vtx::app::typo {

namespace {

bool isAsciiLetter(char32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool has(uint8_t mask, Edit e) { return (mask & static_cast<uint8_t>(e)) != 0; }

// Physical keyboard: middle row offset 0.25 key, bottom row 0.75; a key on the next row
// within 0.8 key is a neighbour (both diagonals).
std::map<char32_t, std::vector<char32_t>> buildNeighbors() {
    struct Row {
        const char* keys;
        double offset;
    };
    const Row rows[3] = {{"qwertyuiop", 0}, {"asdfghjkl", 0.25}, {"zxcvbnm", 0.75}};
    struct Pos {
        int row;
        double x;
    };
    std::map<char32_t, Pos> pos;
    for (int r = 0; r < 3; ++r)
        for (int i = 0; rows[r].keys[i]; ++i) pos[static_cast<char32_t>(rows[r].keys[i])] = {r, rows[r].offset + i};
    std::map<char32_t, std::vector<char32_t>> out;
    for (const auto& [k, p] : pos) {
        std::vector<char32_t> n;
        for (const auto& [o, q] : pos) {
            if (o == k) continue;
            const double dx = q.x > p.x ? q.x - p.x : p.x - q.x;
            const int dr = q.row > p.row ? q.row - p.row : p.row - q.row;
            if ((dr == 0 && dx <= 1.01) || (dr == 1 && dx <= 0.8)) n.push_back(o);
        }
        std::sort(n.begin(), n.end());
        out[k] = std::move(n);
    }
    return out;
}

std::u32string utf32(std::string_view s) { return text::fromUtf8(s.data(), s.size()); }
std::string utf8(const std::u32string& s) { return text::toUtf8(s); }

}  // namespace

const std::vector<char32_t>& physicalNeighbors(char32_t key) {
    static const std::map<char32_t, std::vector<char32_t>> table = buildNeighbors();
    static const std::vector<char32_t> none;
    auto it = table.find(key);
    return it == table.end() ? none : it->second;
}

std::u32string stripTones(const std::u32string& s) {
    std::u32string d = text::nfd(s), out;
    for (char32_t c : d)
        if (c != 0x300 && c != 0x301 && c != 0x303 && c != 0x309 && c != 0x323) out.push_back(c);
    return text::nfc(out);
}

std::vector<Cand> candidates(const std::u32string& lower, const Source& src, uint8_t edits) {
    std::vector<Cand> out;
    const std::u32string& c0 = lower;
    const std::u32string current = src.compose(lower);
    if (has(edits, Edit::Sub)) {
        // AdjacentKeyFixer.oneEditCandidates: only up to the first DEAD prefix.
        size_t k = 0;
        while (k < c0.size() && src.hasCompletion(stripTones(src.compose(c0.substr(0, k + 1))))) ++k;
        for (size_t i = 0; i < c0.size() && i <= k; ++i) {
            for (char32_t n : physicalNeighbors(c0[i])) {
                std::u32string c = c0;
                c[i] = n;
                const std::u32string w = src.compose(c);
                if (w == current) continue;
                if (auto f = src.frequency(w)) out.push_back({w, *f, Edit::Sub});
            }
        }
    }
    auto consider = [&](const std::u32string& c, Edit e) {
        const std::u32string w = src.compose(c);
        if (w == current) return;
        if (auto f = src.frequency(w)) out.push_back({w, *f, e});
    };
    if (has(edits, Edit::Swap)) {
        for (size_t i = 0; i + 1 < c0.size(); ++i) {
            if (c0[i] == c0[i + 1]) continue;
            std::u32string c = c0;
            std::swap(c[i], c[i + 1]);
            consider(c, Edit::Swap);
        }
    }
    if (has(edits, Edit::Del) && c0.size() > 2) {
        for (size_t i = 0; i < c0.size(); ++i) {
            if (i > 0 && c0[i] == c0[i - 1]) continue;  // dropping either of two equal letters is the same
            std::u32string c = c0;
            c.erase(i, 1);
            consider(c, Edit::Del);
        }
    }
    if (has(edits, Edit::Ins) && c0.size() < 10) {
        for (size_t i = 0; i <= c0.size(); ++i) {
            for (char32_t l = U'a'; l <= U'z'; ++l) {
                if (i > 0 && c0[i - 1] == l) continue;  // after an equal letter = before it
                std::u32string c = c0;
                c.insert(c.begin() + static_cast<std::ptrdiff_t>(i), l);
                consider(c, Edit::Ins);
            }
        }
    }
    return out;
}

std::optional<Cand> pick(const std::vector<Cand>& cands, const Params& p) {
    std::map<std::u32string, Cand> best;
    std::unordered_set<std::u32string> proposable;
    for (const Cand& c : cands) {
        if (!has(p.edits, c.edit) && !has(p.rivals, c.edit)) continue;
        if (has(p.edits, c.edit)) proposable.insert(c.word);
        auto it = best.find(c.word);
        if (it != best.end() && it->second.freq >= c.freq) continue;
        best[c.word] = c;
    }
    std::vector<Cand> sorted;
    for (auto& kv : best) sorted.push_back(kv.second);
    std::sort(sorted.begin(), sorted.end(), [](const Cand& a, const Cand& b) {
        return a.freq != b.freq ? a.freq > b.freq : a.word < b.word;
    });
    if (sorted.empty() || !proposable.count(sorted[0].word) || sorted[0].freq < p.minFreq) return std::nullopt;
    if (sorted.size() > 1 && sorted[0].freq - sorted[1].freq < p.margin) return std::nullopt;
    return sorted[0];
}

std::vector<Cand> englishCandidates(const std::u32string& lower, const Source& src) {
    std::vector<Cand> out;
    auto consider = [&](const std::u32string& w, Edit e) {
        if (w == lower) return;
        if (auto f = src.englishFrequency(w)) out.push_back(Cand{w, *f, e});
    };
    const size_t n = lower.size();
    for (size_t i = 0; i < n; ++i)
        for (char32_t k : physicalNeighbors(lower[i])) {
            if (k == lower[i]) continue;
            std::u32string c = lower;
            c[i] = k;
            consider(c, Edit::Sub);
        }
    for (size_t i = 0; i + 1 < n; ++i) {
        if (lower[i] == lower[i + 1]) continue;
        std::u32string c = lower;
        std::swap(c[i], c[i + 1]);
        consider(c, Edit::Swap);
    }
    if (n > 2)
        for (size_t i = 0; i < n; ++i) {
            if (i > 0 && lower[i] == lower[i - 1]) continue;
            std::u32string c = lower;
            c.erase(i, 1);
            consider(c, Edit::Del);
        }
    for (size_t i = 0; i <= n; ++i)
        for (char32_t l = U'a'; l <= U'z'; ++l) {
            if (i > 0 && lower[i - 1] == l) continue;
            std::u32string c = lower;
            c.insert(c.begin() + static_cast<std::ptrdiff_t>(i), l);
            consider(c, Edit::Ins);
        }
    return out;
}

std::optional<Cand> englishPick(const std::vector<Cand>& en, const std::vector<Cand>& rivals, int typedLen,
                                const EnglishParams& p) {
    std::map<std::u32string, Cand> best;
    std::unordered_set<std::u32string> proposable;
    const bool insDel = typedLen >= p.insDelMinLen;
    auto keep = [&](const Cand& c) {
        auto it = best.find(c.word);
        if (it != best.end() && it->second.freq >= c.freq) return;
        best[c.word] = c;
    };
    for (const Cand& c : en) {
        if (c.edit == Edit::Sub || c.edit == Edit::Swap || insDel) proposable.insert(c.word);
        keep(c);
    }
    for (const Cand& c : rivals) keep(c);
    std::vector<Cand> sorted;
    for (auto& kv : best) sorted.push_back(kv.second);
    std::sort(sorted.begin(), sorted.end(), [](const Cand& a, const Cand& b) {
        return a.freq != b.freq ? a.freq > b.freq : a.word < b.word;
    });
    const int minFreq = typedLen >= p.longMinLen ? std::min(p.minFreq, p.longMinFreq) : p.minFreq;
    if (sorted.empty() || !proposable.count(sorted[0].word) || sorted[0].freq < minFreq) return std::nullopt;
    if (sorted.size() > 1 && sorted[0].freq - sorted[1].freq < p.margin) return std::nullopt;
    return sorted[0];
}

std::optional<std::u32string> correction(const std::u32string& raw, const Source& src, const Params& p,
                                         bool filterSensitive, const EnglishParams& ep) {
    if (static_cast<int>(raw.size()) < p.minLen || raw.size() > 10) return std::nullopt;
    for (char32_t c : raw)
        if (!isAsciiLetter(c)) return std::nullopt;
    const std::u32string lower = text::lower(raw);
    if (src.isKnown(lower)) return std::nullopt;
    const std::u32string current = src.compose(lower);
    if (current != lower && src.isKnown(text::lower(current))) return std::nullopt;
    if (src.frequency(current) || src.hasCompletion(current)) return std::nullopt;
    const std::vector<Cand> vn = candidates(lower, src, p.edits | p.rivals);
    auto best = pick(vn, p);
    if (!best) best = englishPick(englishCandidates(lower, src), vn, static_cast<int>(lower.size()), ep);
    if (!best) return std::nullopt;
    // "Lọc từ nhạy cảm": never offer a swear word (no fallback to the runner-up).
    if (filterSensitive && predict::isSensitive(best->word)) return std::nullopt;
    std::u32string w = best->word;
    if (!raw.empty() && raw[0] >= 'A' && raw[0] <= 'Z' && !w.empty()) w = text::upper(w[0]) + w.substr(1);
    return w;
}

// ================================================================ LexiconIndex (VNSuggest)

namespace {
extern const int16_t kFirstCharTop[26][32];  // generated below
}

LexiconIndex::LexiconIndex(const addtones::Lexicon& lx) : lx_(lx) {
    // char -> (base, quality << 3 | tone); tone ids 1..5 = sắc huyền hỏi ngã nặng.
    struct Base {
        char32_t base;
        char32_t variants[3];  // none, circumflex, horn/breve (0 = n/a)
    };
    const Base bases[] = {{U'a', {U'a', 0xE2, 0x103}}, {U'e', {U'e', 0xEA, 0}}, {U'o', {U'o', 0xF4, 0x1A1}},
                          {U'u', {U'u', 0, 0x1B0}},    {U'i', {U'i', 0, 0}},    {U'y', {U'y', 0, 0}}};
    const char32_t tones[5] = {0x301, 0x300, 0x309, 0x303, 0x323};
    for (const Base& b : bases) {
        for (int q = 0; q < 3; ++q) {
            const char32_t v = b.variants[q];
            if (!v) continue;
            table_[v] = {static_cast<uint8_t>(b.base), static_cast<uint8_t>(q << 3)};
            for (int t = 0; t < 5; ++t) {
                const std::u32string nfc = text::nfc(std::u32string{v, tones[t]});
                if (nfc.size() == 1) table_[nfc[0]] = {static_cast<uint8_t>(b.base), static_cast<uint8_t>(q << 3 | (t + 1))};
            }
        }
    }
    table_[0x111] = {static_cast<uint8_t>('d'), static_cast<uint8_t>(3 << 3)};
    for (char32_t c = U'a'; c <= U'z'; ++c)
        if (!table_.count(c)) table_[c] = {static_cast<uint8_t>(c), 0};
    firstTop_.resize(26);
    for (int c = 0; c < 26; ++c)
        for (int k = 0; k < 32; ++k)
            if (kFirstCharTop[c][k] >= 0 && kFirstCharTop[c][k] < lx_.count()) firstTop_[c].push_back(kFirstCharTop[c][k]);
}

bool LexiconIndex::decompose(const std::u32string& s, std::vector<Dec>& out) const {
    out.clear();
    for (char32_t c : text::lower(text::nfc(s))) {
        auto it = table_.find(c);
        if (it == table_.end()) return false;
        out.push_back(it->second);
    }
    return !out.empty();
}

void LexiconIndex::range(const std::string& prefix, int& lo, int& hi) const {
    auto cmp = [&](int id) {  // folded[id] vs prefix: -1 <, 0 has the prefix, 1 >
        const std::string_view f = lx_.folded(id);
        for (size_t i = 0; i < prefix.size(); ++i) {
            if (i == f.size()) return -1;
            if (f[i] != prefix[i]) return static_cast<unsigned char>(f[i]) < static_cast<unsigned char>(prefix[i]) ? -1 : 1;
        }
        return 0;
    };
    int a = 0, b = lx_.count();
    while (a < b) {
        const int mid = (a + b) / 2;
        if (cmp(mid) < 0) a = mid + 1;
        else b = mid;
    }
    lo = a;
    b = lx_.count();
    while (a < b) {
        const int mid = (a + b) / 2;
        if (cmp(mid) <= 0) a = mid + 1;
        else b = mid;
    }
    hi = a;
}

std::optional<int> LexiconIndex::frequency(const std::u32string& word) const {
    std::vector<Dec> dec;
    if (!lx_.ok() || !decompose(word, dec)) return std::nullopt;
    std::string prefix;
    for (const Dec& d : dec) prefix.push_back(static_cast<char>(d.base));
    const std::string w = utf8(text::lower(word));
    const int f = lx_.formIndex(prefix);
    if (f < 0) return std::nullopt;
    for (int id = lx_.formFirstId(f); id < lx_.formEndId(f); ++id)
        if (lx_.display(id) == w) return lx_.freq(id);
    return std::nullopt;
}

bool LexiconIndex::hasCompletion(const std::u32string& typed) const {
    std::vector<Dec> dec;
    if (!lx_.ok() || !decompose(typed, dec)) return false;
    std::string prefix;
    for (const Dec& d : dec) prefix.push_back(static_cast<char>(d.base));
    auto matches = [&](int id) {
        const std::string_view f = lx_.folded(id);
        if (f.size() < prefix.size()) return false;
        for (size_t i = 0; i < dec.size(); ++i) {
            if (static_cast<uint8_t>(f[i]) != dec[i].base) return false;
            const uint8_t cand = lx_.attr(id, static_cast<int>(i));
            const uint8_t q = dec[i].attr >> 3, t = dec[i].attr & 7;
            if (q != 0 && q != cand >> 3) return false;
            if (t != 0 && t != (cand & 7)) return false;
        }
        return true;
    };
    if (prefix.size() == 1) {  // VNSuggest: one key goes through the precomputed top-32 bucket
        const int c = prefix[0] - 'a';
        if (c < 0 || c >= 26) return false;
        for (int id : firstTop_[static_cast<size_t>(c)])
            if (matches(id)) return true;
        return false;
    }
    int lo = 0, hi = 0;
    range(prefix, lo, hi);
    for (int id = lo; id < hi; ++id)
        if (matches(id)) return true;
    return false;
}

void sortByFreqThenId(std::vector<std::pair<int, int>>& v) {
    std::sort(v.begin(), v.end(), [](const std::pair<int, int>& a, const std::pair<int, int>& b) {
        return a.first != b.first ? a.first > b.first : a.second < b.second;
    });
}

std::vector<LexiconIndex::Match> LexiconIndex::matches(const std::u32string& typed, int poolLimit,
                                                      std::string_view excluding) const {
    std::vector<Match> out;
    std::vector<Dec> dec;
    if (!lx_.ok() || poolLimit <= 0 || !decompose(typed, dec)) return out;
    std::string prefix;
    for (const Dec& d : dec) prefix.push_back(static_cast<char>(d.base));
    std::vector<std::pair<int, int>> pool;  // (freq, id)
    auto consider = [&](int id) {
        const std::string_view f = lx_.folded(id);
        if (f.size() < prefix.size()) return;
        for (size_t i = 0; i < dec.size(); ++i) {
            if (static_cast<uint8_t>(f[i]) != dec[i].base) return;
            const uint8_t cand = lx_.attr(id, static_cast<int>(i));
            const uint8_t q = dec[i].attr >> 3, t = dec[i].attr & 7;
            if (q != 0 && q != cand >> 3) return;
            if (t != 0 && t != (cand & 7)) return;
        }
        pool.emplace_back(lx_.freq(id), id);
    };
    if (prefix.size() == 1) {  // one key: the precomputed top-32 bucket (VNLexicon2Data.firstCharTop)
        const int c = prefix[0] - 'a';
        if (c < 0 || c >= 26) return out;
        for (int id : firstTop_[static_cast<size_t>(c)]) consider(id);
    } else {
        int lo = 0, hi = 0;
        range(prefix, lo, hi);
        for (int id = lo; id < hi; ++id) consider(id);
    }
    sortByFreqThenId(pool);
    for (const auto& [f, id] : pool) {
        const std::string_view w = lx_.display(id);
        if (w == excluding) continue;
        out.push_back(Match{w, f, id});
        if (static_cast<int>(out.size()) >= poolLimit) break;
    }
    return out;
}

namespace {
// SyllableLM.normalize: lowercase NFC, then the old tone placement vnlexicon uses
// ("hoà" -> "hòa", "thuý" -> "thúy"; "quý" stays).
std::u32string normalizeSyllable(const std::u32string& w) {
    std::u32string s = text::nfc(text::lower(w));
    if (s.size() < 2) return s;
    static const struct {
        char32_t a, b, ra, rb;
    } kOld[] = {
        {U'o', 0xE0, 0xF2, U'a'},   {U'o', 0xE1, 0xF3, U'a'},   {U'o', 0x1EA3, 0x1ECF, U'a'}, {U'o', 0xE3, 0xF5, U'a'},
        {U'o', 0x1EA1, 0x1ECD, U'a'}, {U'o', 0xE8, 0xF2, U'e'}, {U'o', 0xE9, 0xF3, U'e'},   {U'o', 0x1EBB, 0x1ECF, U'e'},
        {U'o', 0x1EBD, 0xF5, U'e'}, {U'o', 0x1EB9, 0x1ECD, U'e'}, {U'u', 0x1EF3, 0xF9, U'y'}, {U'u', 0xFD, 0xFA, U'y'},
        {U'u', 0x1EF7, 0x1EE7, U'y'}, {U'u', 0x1EF9, 0x169, U'y'}, {U'u', 0x1EF5, 0x1EE5, U'y'},
    };
    const char32_t a = s[s.size() - 2], b = s[s.size() - 1];
    for (const auto& o : kOld) {
        if (o.a != a || o.b != b) continue;
        if (a == U'u' && s.size() >= 3 && s[s.size() - 3] == U'q') return s;
        s[s.size() - 2] = o.ra;
        s[s.size() - 1] = o.rb;
        return s;
    }
    return s;
}
}  // namespace

int LexiconIndex::lexiconId(const std::u32string& word) const {
    const std::u32string w = normalizeSyllable(word);
    std::vector<Dec> dec;
    if (!lx_.ok() || !decompose(w, dec)) return -1;
    std::string prefix;
    for (const Dec& d : dec) prefix.push_back(static_cast<char>(d.base));
    const std::string u = utf8(w);
    int lo = 0, hi = 0;
    range(prefix, lo, hi);
    for (int id = lo; id < hi; ++id)
        if (lx_.folded(id).size() == prefix.size() && lx_.display(id) == u) return id;
    return -1;
}

// ================================================================ LexiconSource

LexiconSource::LexiconSource(const addtones::LanguageData& data, uint32_t engineFlags)
    : data_(data), index_(data.lexicon), engine_(vtx_create()) {
    if (engine_) vtx_set_flags(engine_, engineFlags);
    for (const char* w : seedAsciiWords()) {
        const std::u32string u = utf32(w);
        if (!index_.contains(u)) chat_.insert(u);
    }
}

LexiconSource::~LexiconSource() {
    if (engine_) vtx_destroy(engine_);
}

std::u32string LexiconSource::compose(const std::u32string& raw) const {
    if (!engine_) return raw;
    vtx_reset_context(engine_);  // a fresh engine per word (TypoFixLogic.composer)
    vtx_reset(engine_);
    vtx_action a;
    for (char32_t c : raw) vtx_feed(engine_, c, &a);
    uint16_t buf[VTX_MAX_TEXT + 1];
    const int32_t n = vtx_composed(engine_, buf, VTX_MAX_TEXT + 1);
    std::u16string s;
    if (n > 0) s.assign(reinterpret_cast<const char16_t*>(buf), static_cast<size_t>(n));
    vtx_reset(engine_);
    return text::fromUtf16(s);
}

bool LexiconSource::isEnglish(const std::u32string& w) const {
    const std::string a = utf8(w);
    return data_.english.contains(a) || EnglishContextLookup::opensEnglishRun(a.data(), static_cast<int>(a.size()));
}

bool LexiconSource::isKnown(const std::u32string& w) const { return isEnglish(w) || isChatWord(w); }

std::optional<int> LexiconSource::englishFrequency(const std::u32string& w) const {
    const std::string a = utf8(w);
    const addtones::EnglishLexicon& en = data_.english;
    const size_t i = en.lowerBound(a);
    if (i < en.size() && en.word(i) == a) return en.freq(i);
    return std::nullopt;
}

// ================================================================ generated data

const std::vector<const char*>& seedAsciiWords() {
    // iOS/Keyboard/SeedData.swift unigrams made of ASCII letters only (424, sorted).
    static const std::vector<const char*> words = {
        "a", "add", "admin", "agribank", "ai", "an", "android", "anh", "anthropic", "anti", "app", "apple",
        "arsenal", "asshole", "austin", "avatar", "ba", "baby", "backup", "ban", "bao", "barca", "bastard",
        "bay", "best", "bidv", "binance", "birthday", "bitch", "bitcoin", "blockchain", "blog", "book", "boy",
        "bug", "bullshit", "buscu", "bye", "ca", "cafe", "california", "call", "campuchia", "canada", "cao",
        "care", "cave", "cc", "cha", "chat", "chatgpt", "check", "chelsea", "chi", "chia", "chill", "cho",
        "chrome", "chung", "cl", "claude", "clg", "clgt", "clip", "clm", "cmm", "cmn", "cmnr", "cmt", "code",
        "coi", "coin", "combo", "comment", "con", "confirm", "content", "cool", "covid", "crypto", "cung",
        "da", "daddy", "dallas", "damn", "danh", "data", "date", "dc", "dcm", "dcmm", "deadline", "demo",
        "di", "dick", "dickhead", "dkm", "dm", "dmm", "do", "doanh", "down", "download", "drama", "du",
        "dubai", "dumbass", "dume", "dung", "duy", "em", "email", "eth", "ethereum", "excel", "face",
        "facebook", "fake", "fan", "feedback", "fiat", "file", "fix", "flag", "flex", "follow", "form", "fpt",
        "francisco", "free", "fuck", "fuckboy", "fucked", "fucker", "fucking", "full", "game", "gen", "ghi",
        "gia", "gian", "giao", "github", "gmail", "good", "google", "grab", "green", "gym", "haha", "hai",
        "happy", "hay", "hehe", "hello", "hihi", "hoa", "honda", "hot", "hotmail", "houston", "huhu", "hy",
        "ib", "idol", "inbox", "internet", "ios", "ipad", "iphone", "it", "kaka", "karaoke", "kb", "khi",
        "khoa", "khu", "kia", "kim", "kinh", "ko", "la", "lan", "laptop", "lazada", "like", "linh", "link",
        "linux", "live", "liverpool", "livestream", "lo", "loan", "login", "lol", "london", "long", "louis",
        "love", "loz", "ly", "ma", "macbook", "macos", "mai", "mail", "manchester", "mang", "margin",
        "massage", "mau", "max", "may", "meet", "meeting", "menu", "miami", "minh", "miss", "mn", "momo",
        "mong", "mood", "morning", "motherfucker", "mua", "my", "nam", "nay", "netflix", "new", "nga", "ngay",
        "nghe", "ngon", "ngu", "nguy", "nha", "nhanh", "nhau", "nhi", "nice", "night", "off", "offline", "ok",
        "okay", "oke", "okie", "old", "online", "oops", "openai", "order", "out", "outlook", "page", "part",
        "party", "password", "phan", "phil", "phim", "phone", "phong", "ping", "piss", "plan", "please",
        "post", "printik", "pro", "project", "pussy", "qua", "quan", "quang", "quanh", "quay", "quen", "quy",
        "ra", "red", "relax", "rep", "reply", "report", "review", "safari", "sai", "sale", "samsung", "san",
        "sang", "sao", "sau", "seattle", "see", "senprints", "server", "share", "ship", "shit", "shitty",
        "shop", "shopee", "si", "singapore", "sinh", "size", "sml", "so", "sorry", "spotify", "start", "stfu",
        "stop", "store", "story", "stt", "sub", "sugar", "support", "suy", "sydney", "ta", "tai", "tao",
        "task", "tay", "team", "techcombank", "tesla", "test", "texas", "tha", "tham", "thanh", "thank",
        "thanks", "thay", "theo", "thi", "thu", "tiktok", "tim", "time", "tin", "tinh", "tml", "to", "token",
        "tokyo", "top", "tra", "trai", "trang", "tranh", "trap", "trend", "trip", "trong", "trung", "trym",
        "tuy", "ty", "uhm", "uk", "um", "united", "up", "update", "upload", "usd", "usdt", "var", "vcc",
        "vcl", "vd", "vi", "vibe", "video", "vietcombank", "vietjet", "viettel", "view", "vinfast",
        "vingroup", "vip", "vkl", "vl", "vlog", "vnd", "vnpay", "voucher", "vs", "vui", "vuitton",
        "washington", "web", "welcome", "wifi", "windows", "word", "wow", "wtf", "x", "xa", "xanh", "xe",
        "xem", "xin", "xong", "y", "yahoo", "yeah", "yes", "york", "you", "youtube", "z", "zalo", "zoom",
    };
    return words;
}

namespace {
// VNLexicon2Data.firstCharTop (iOS/Keyboard/VNLexicon2.swift): top-32 ids per first letter;
// -1 = unused slot / no syllable starts with that letter.
const int16_t kFirstCharTop[26][32] = {
    {44, 66, 11, 0, 26, 27, 1, 45, 2, 49, 28, 15, 6, 46, 3, 29, 30, 16, 4, 53, 17, 50, 61, 31, 12, 35, 18, 51, 67, 19, 52, 5},  // a
    {238, 210, 101, 132, 70, 267, 142, 310, 133, 268, 156, 143, 166, 115, 180, 269, 292, 134, 252, 239, 102, 71, 157, 103, 76, 192, 229, 388, 84, 105, 104, 322},  // b
    {883, 980, 836, 884, 703, 932, 497, 433, 878, 653, 933, 422, 1010, 427, 452, 794, 804, 648, 945, 438, 591, 1011, 968, 575, 520, 431, 514, 691, 1018, 805, 885, 873},  // c
    {1306, 1054, 1404, 1667, 1217, 1236, 1140, 1201, 1266, 1218, 1366, 1645, 1646, 1202, 1592, 1685, 1383, 1406, 1405, 1534, 1076, 1535, 1161, 1301, 1237, 1292, 1141, 1572, 1473, 1472, 1343, 1256},  // d
    {1728, 1718, 1719, 1745, 1729, 1726, 1740, 1732, 1741, 1742, 1720, 1724, 1733, 1747, 1730, 1721, 1731, 1748, 1750, 1746, 1743, 1744, 1749, 1722, 1737, 1723, 1725, 1738, 1734, 1739, 1727, 1735},  // e
    {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},  // f
    {1852, 1939, 1800, 1933, 2005, 1985, 1762, 1856, 1962, 1883, 1971, 1953, 1869, 1779, 1857, 1751, 1954, 1858, 1816, 1974, 1898, 1897, 1859, 1865, 2050, 1788, 1845, 1844, 1914, 1915, 1884, 1909},  // g
    {2240, 2101, 2323, 2154, 2155, 2196, 2224, 2084, 2073, 2115, 2300, 2291, 2232, 2126, 2316, 2213, 2347, 2301, 2270, 2260, 2302, 2074, 2225, 2457, 2324, 2277, 2208, 2162, 2370, 2264, 2423, 2255},  // h
    {2462, 2480, 2473, 2471, 2475, 2464, 2463, 2465, 2468, 2481, 2476, 2469, 2466, 2467, 2478, 2474, 2479, 2482, 2472, 2477, 2470, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},  // i
    {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},  // j
    {2721, 2628, 2532, 2704, 2483, 2797, 2523, 2660, 2485, 2484, 2803, 2802, 2717, 2841, 2798, 2831, 2536, 2629, 2733, 2640, 2528, 2817, 2821, 2697, 2679, 2763, 2685, 2514, 2529, 2669, 2842, 2807},  // k
    {2847, 2867, 2859, 2970, 3101, 3199, 2868, 2941, 2880, 3243, 3102, 3279, 2951, 3052, 2933, 3132, 3016, 3145, 3200, 3072, 3198, 2982, 2853, 3030, 2921, 2848, 3248, 3172, 2860, 3183, 3041, 3040},  // l
    {3530, 3582, 3285, 3450, 3368, 3483, 3377, 3484, 3353, 3354, 3369, 3370, 3328, 3459, 3355, 3338, 3567, 3371, 3451, 3297, 3543, 3359, 3485, 3291, 3329, 3360, 3356, 3486, 3286, 3605, 3549, 3515},  // m
    {3991, 3691, 4372, 4348, 3670, 4287, 4256, 4288, 3839, 3734, 4423, 4021, 3809, 3714, 4161, 4089, 3801, 4169, 3802, 3746, 3629, 4051, 3992, 3692, 4052, 4110, 4373, 4095, 3893, 4153, 4075, 4183},  // n
    {4537, 4470, 4527, 4511, 4528, 4512, 4538, 4471, 4472, 4473, 4474, 4539, 4529, 4520, 4504, 4475, 4540, 4530, 4521, 4476, 4513, 4505, 4531, 4550, 4477, 4485, 4493, 4494, 4514, 4478, 4541, 4515},  // o
    {4613, 4750, 4766, 4656, 4628, 4803, 4694, 4720, 4686, 4653, 4775, 4603, 4617, 4710, 4629, 4690, 4795, 4699, 4776, 4630, 4767, 4691, 4768, 4752, 4751, 4631, 4668, 4632, 4618, 4657, 4769, 4777},  // p
    {4862, 4863, 4882, 4920, 4883, 4982, 4876, 4971, 4936, 4864, 4977, 4965, 4906, 4937, 4972, 4884, 4885, 4886, 4865, 4973, 4929, 4897, 4896, 4978, 4974, 4979, 4945, 4975, 4887, 4861, 4921, 4922},  // q
    {5164, 4990, 5053, 5029, 5137, 5278, 5165, 5166, 5116, 5030, 4996, 5167, 5281, 5246, 5195, 5031, 5196, 5138, 5220, 4997, 5017, 5062, 5213, 5070, 5276, 5071, 5072, 5059, 5208, 5221, 5044, 5184},  // r
    {5377, 5347, 5517, 5364, 5497, 5358, 5440, 5410, 5431, 5441, 5333, 5553, 5353, 5319, 5518, 5334, 5300, 5537, 5405, 5298, 5484, 5519, 5572, 5583, 5442, 5443, 5320, 5528, 5365, 5321, 5466, 5299},  // s
    {6158, 5592, 5811, 5812, 6378, 5932, 5847, 5803, 5792, 6159, 5971, 6456, 6201, 6095, 5653, 6099, 6428, 5702, 6285, 5663, 5836, 5605, 5776, 5855, 6116, 5677, 6457, 6074, 6336, 5981, 5933, 5767},  // t
    {6561, 6617, 6562, 6563, 6605, 6633, 6597, 6590, 6581, 6598, 6634, 6632, 6627, 6599, 6571, 6635, 6587, 6600, 6626, 6629, 6618, 6582, 6612, 6631, 6572, 6564, 6588, 6585, 6565, 6619, 6637, 6601},  // u
    {6642, 6812, 6714, 6724, 6698, 6767, 6757, 6664, 6850, 6680, 6868, 6790, 6758, 6654, 6859, 6770, 6665, 6725, 6726, 6835, 6791, 6706, 6851, 6836, 6813, 6778, 6771, 6666, 6860, 6681, 6752, 6890},  // v
    {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},  // w
    {7016, 6969, 6957, 7146, 6951, 6907, 6901, 7092, 6948, 7119, 7104, 6991, 7120, 6988, 6935, 7021, 6952, 7135, 7136, 7112, 7160, 7147, 7105, 6902, 6916, 7106, 7044, 7061, 7001, 6903, 7078, 6958},  // x
    {7167, 7180, 7168, 7175, 7181, 7172, 7176, 7173, 7182, 7179, 7169, 7170, 7183, 7171, 7177, 7178, 7174, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},  // y
    {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},  // z
};
}  // namespace

}  // namespace vtx::app::typo

// ================================================================ HintJobs

namespace vtx::app {

HintJobs::~HintJobs() {
    delete source_;
    delete model_;
}

const addtones::LanguageData* HintJobs::data() {
    if (!loaded_) {
        loaded_ = true;
        if (load_) data_ = load_();
        load_ = nullptr;
    }
    return data_;
}

bool HintJobs::knownWord(const std::string& w) {
    if (!data() || !data_->ok()) return false;
    if (!model_) model_ = new (std::nothrow) predict::Model(*data_);
    return model_ && model_->knownWord(w);
}

std::u16string HintJobs::answer(const HintMessage& m) {
    if (m.text.empty() || !data() || !data_->ok()) return {};
    if (m.job == static_cast<uint32_t>(HintJob::Typo)) {
        if (!source_ || flags_ != m.flags) {
            delete source_;
            source_ = new (std::nothrow) typo::LexiconSource(*data_, m.flags);
            flags_ = m.flags;
            if (!source_) return {};
        }
        auto fix = typo::correction(text::fromUtf16(m.text), *source_, typo::defaults(), filterSensitive_);
        return fix ? text::toUtf16(*fix) : std::u16string();
    }
    if (m.job == static_cast<uint32_t>(HintJob::Predict)) {
        std::u16string before, typed, raw;
        if (!unpackPredictText(m.text, before, typed, raw)) return {};
        auto r = predict::request(text::fromUtf16(before), text::fromUtf16(typed), (m.flags & kPredictEnglish) != 0);
        if (!r) return {};
        if (!model_) model_ = new (std::nothrow) predict::Model(*data_);
        if (!model_) return {};
        const auto c = model_->candidates(*r, text::fromUtf16(raw), filterSensitive_, learned_);
        return c.empty() ? std::u16string() : text::toUtf16(c[0]);  // one suggestion: the top one
    }
    if (m.job == static_cast<uint32_t>(HintJob::Tones)) {
        std::u16string out;
        return transformText(text::Tool::AddTones, m.text, data_, out) ? out : std::u16string();
    }
    return {};
}

}  // namespace vtx::app
