// add_tones.hpp — THÊM DẤU ("toi di hoc hom nay" → "tôi đi học hôm nay") for Windows.
// Port of iOS/Keyboard/AddTones.swift (twin of android AddTones.kt) + the readers it
// needs: vnlexicon.bin (VNLexicon2.swift / SwipeLexicon.swift), enlexicon.bin
// (SwipeEnglish.swift) and the syllable LM vnlm.bin v3 (SyllableLM.swift — format at the
// top of that file and in Scripts/gen-syllable-lm.py). Parity: the shared fixtures
// iOS/KeyboardTests/Fixtures/add-tones.txt and vnlm-parity.txt (tests/text_tests.cpp).
//
// The readers never copy the files: they read in place from a caller-owned byte range —
// on Windows the RCDATA resources of VietTelex.exe (image-mapped, demand-paged, shared).
// The bytes must outlive the reader. Read-only after load ⇒ thread-safe.
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

namespace vtx { namespace addtones {

uint32_t fnv1a(const uint8_t* p, size_t n);

/// vnlexicon.bin ("VNL2" v1): 7184 syllables sorted by folded key, then frequency.
class Lexicon {
public:
    bool load(const uint8_t* data, size_t size);
    bool ok() const { return data_ != nullptr; }
    int count() const { return count_; }
    uint32_t hash() const { return hash_; }
    /// Display form (lowercase Vietnamese, UTF-8) of syllable `id`.
    std::string_view display(int id) const;
    int freq(int id) const { return data_[freqs_ + id]; }
    /// Unaccented forms (SwipeLexicon.forms): index of `folded` (lowercase a–z), -1 if none.
    int formIndex(std::string_view folded) const;
    int formFirstId(int f) const { return formStart_[static_cast<size_t>(f)]; }
    int formEndId(int f) const { return formStart_[static_cast<size_t>(f) + 1]; }
    int formCount() const { return formStart_.empty() ? 0 : static_cast<int>(formStart_.size()) - 1; }
    /// Folded key (lowercase a–z bases) of syllable `id`, and the per-letter attribute
    /// byte (quality << 3 | tone, VNSuggest.decompose) of its letter `i`.
    std::string_view folded(int id) const;
    uint8_t attr(int id, int i) const;

private:
    uint32_t u32(size_t off) const;
    const uint8_t* data_ = nullptr;
    size_t size_ = 0;
    int count_ = 0;
    uint32_t hash_ = 0;
    size_t folded_ = 0, display_ = 0, attrs_ = 0, offsets_ = 0, dispOffsets_ = 0, freqs_ = 0;
    // First id of each form (+ count_ at the end); the form's key is folded(formStart_[f]).
    // 4 bytes per form, no string_view copy of the keys (heap: ~7 KB, not ~40 KB).
    std::vector<int> formStart_;
};

/// enlexicon.bin ("VTE1" | count | [len][freq][a–z]…, sorted): English words.
class EnglishLexicon {
public:
    bool load(const uint8_t* data, size_t size);
    bool contains(std::string_view word) const;
    size_t size() const { return offs_.size(); }
    /// Word `i` (file order = sorted) and its frequency byte (0–255).
    std::string_view word(size_t i) const {
        return std::string_view(reinterpret_cast<const char*>(data_ + offs_[i] + 2), data_[offs_[i]]);
    }
    int freq(size_t i) const { return data_[offs_[i] + 1]; }
    /// Index of the first word not less than `w` (byte order).
    size_t lowerBound(std::string_view w) const;

private:
    // Offset of each record ([len][freq][a–z]…) in the caller's bytes: 4 bytes per word
    // (20k words ⇒ ~80 KB of heap, not the ~320 KB a string_view per word took).
    const uint8_t* data_ = nullptr;
    std::vector<uint32_t> offs_;
};

/// vnlm.bin v3 — Kneser–Ney trigram syllable LM, Elias–Fano, read in place.
class SyllableLM {
public:
    /// Validates header, lexicon match and section sizes (never scans the body). false =
    /// missing / corrupt / built for another lexicon: Thêm dấu then runs without the LM.
    bool load(const uint8_t* data, size_t size, uint32_t lexiconHash, int lexiconCount);
    bool ok() const { return d_ != nullptr; }
    int count() const { return count_; }

    using NextFn = void (*)(void* ctx, int next, float pmi);
    struct Row {  // one bigram row (per-row Elias–Fano)
        int lo = 0, hi = 0, l = 0, zero = 0, lowOff = 0;
        int start() const { return lo + zero; }
    };
    /// Bigram band of the previous syllable (SyllableLM.Bigram).
    class Bigram {
    public:
        int size() const { return row_.hi - row_.lo; }
        /// PMI (nat) of the next syllable; missing entry ⇒ γ2(prev) + uniAdj; empty band ⇒ 0.
        float pmi(int next) const;
        /// PMI of an explicit entry; 0 if missing.
        float explicitPmi(int next) const;
        /// Every explicit entry in increasing id: body(next, pmi) (SyllableLM.Bigram.forEach).
        template <class F> void forEach(F&& body) const {
            forEachImpl([](void* f, int c, float v) { (*static_cast<std::remove_reference_t<F>*>(f))(c, v); },
                const_cast<void*>(static_cast<const void*>(&body)));
        }

    private:
        friend class SyllableLM;
        void forEachImpl(NextFn fn, void* ctx) const;
        const SyllableLM* lm_ = nullptr;
        float g2_ = 0;
        Row row_;
    };
    Bigram bigram(int prev) const;

    /// SyllableLM.Context — one position after (prev2, prev1): the trigram row is located
    /// once. Word prediction (app/core/word_prediction.h) ranks with it.
    class Context {
    public:
        bool hasTrigram() const { return triBase_ >= 0; }
        int bigramSize() const { return bi_.hi - bi_.lo; }
        /// Explicit trigram entry (prev2, prev1, w) only: true + pmi = s3 + uniAdj
        /// (Swift SyllableLM.forEachTrigram — Thêm dấu's second-order Viterbi).
        bool trigramPmi(int w, float& pmi) const;
        /// PMI of an EXPLICIT entry: trigram s3 + uniAdj, else bigram s2 + uniAdj, else 0
        /// (Context.explicit / explicitAll).
        float explicitPmi(int w) const;
        /// Only the explicit trigram entries, increasing id: body(id, s3 + uniAdj). Returns
        /// the number of entries (0 without a trigram row).
        template <class F> int forEachTrigram(F&& body) const {
            return forEachTrigramImpl([](void* f, int c, float v) { (*static_cast<std::remove_reference_t<F>*>(f))(c, v); },
                const_cast<void*>(static_cast<const void*>(&body)));
        }
        /// Bigram row ∪ trigram row, increasing id (Context.forEachNext): a bigram-only entry
        /// backs off to γ3 + s2.
        template <class F> void forEachNext(F&& body) const {
            forEachNextImpl([](void* f, int c, float v) { (*static_cast<std::remove_reference_t<F>*>(f))(c, v); },
                const_cast<void*>(static_cast<const void*>(&body)));
        }

    private:
        friend class SyllableLM;
        int forEachTrigramImpl(NextFn fn, void* ctx) const;
        void forEachNextImpl(NextFn fn, void* ctx) const;
        const SyllableLM* lm_ = nullptr;
        float g2_ = 0, g3_ = 0;
        Row bi_;
        int64_t triBase_ = -1, triLo_ = 0, triPos_ = 0;
    };
    /// nil (false) when prev1 is not a valid id.
    bool context(int prev2, int prev1, Context& out) const;
    /// s (nat) of `w` after (`prev2`, `prev1`); 0 without a context.
    float score(int prev2, int prev1, int w) const;
    float uniAdj(int w) const;
    /// FNV-1a over the whole decoded model (= CHECKSUM of vnlm-parity.txt). Tests only.
    uint32_t modelChecksum() const;
    bool payloadHashOK() const;

private:
    struct EF {
        int n = 0, l = 0, low = 0, high = 0, sel = 0, words = 0, selShift = 0;
        int64_t mask() const { return (int64_t{1} << l) - 1; }
    };
    uint64_t u64(int base, int64_t wi) const;
    int u32At(int base, int64_t i) const;
    int bits(int base, int64_t pos, int width) const;
    bool bit(int base, int64_t p) const;
    int low(const EF& e, int m) const { return bits(e.low, static_cast<int64_t>(m) * e.l, e.l); }
    int select0(const EF& e, int64_t r) const;
    void bucket(const EF& e, int64_t h, int64_t& pos, int64_t& idx) const;
    int runLength(const EF& e, int64_t pos) const;
    int find(const EF& e, int64_t x) const;
    void lowerBound(const EF& e, int64_t x, int64_t& idx, int64_t& pos) const;
    int scanFind(const EF& e, int64_t lo, int64_t pos, int64_t x) const;
    Row rowAt(int b) const;
    int rowLow(const Row& r, int m) const { return bits(biLow_, static_cast<int64_t>(r.lowOff) + static_cast<int64_t>(m - r.lo) * r.l, r.l); }
    int biFind(const Row& r, int c) const;
    int context(int j) const;
    float q(int v) const { return static_cast<float>(v) / qPerNat_; }
    float biScoreAt(int j) const { return q(static_cast<int8_t>(d_[biScore_ + j])); }
    float adj(int w) const { return q(static_cast<int8_t>(d_[adjBase_ + w])); }
    int cbValue(int cb, int base, int64_t i, int w) const {
        return static_cast<int8_t>(d_[cb + bits(base, i * w, w)]);
    }
    template <class F> void biScan(const Row& r, F&& body) const;
    template <class F> void scan(const EF& e, int lo, int64_t pos, int n, F&& body) const;
    // Sequential walk of one trigram row (SyllableLM.TriCursor): c = next id (kEnd = done).
    static constexpr int kEnd = 0x7FFFFFFF;
    struct TriCursor {
        int64_t m = 0, base = 0, end = 0, wi = 0;
        uint64_t w = 0;
        int c = kEnd;
        float v = 0;
    };
    TriCursor triStart(int64_t lo, int64_t pos, int64_t base) const;
    void triNext(TriCursor& t) const;

    const uint8_t* d_ = nullptr;
    size_t size_ = 0;
    int count_ = 0, biEntries_ = 0, triContexts_ = 0, triEntries_ = 0;
    float qPerNat_ = 1;
    int bits3_ = 0, bitsG_ = 0;
    int g2Base_ = 0, adjBase_ = 0, cb3Base_ = 0, cbgBase_ = 0;
    int biRow_ = 0, biZero_ = 0, biLowOff_ = 0, biLow_ = 0;
    int biScore_ = 0, hasTri_ = 0, triRank_ = 0, g3Base_ = 0, triScore_ = 0;
    EF bi_, tri_;
};

/// The three data files, loaded once (VietTelex.exe keeps one for the process).
struct LanguageData {
    Lexicon lexicon;
    EnglishLexicon english;
    SyllableLM lm;
    /// Lexicon required; English list and LM optional (a missing/corrupt one is skipped).
    bool load(const uint8_t* vnlexicon, size_t vnlexiconSize, const uint8_t* enlexicon, size_t enlexiconSize,
              const uint8_t* vnlm, size_t vnlmSize);
    bool ok() const { return lexicon.ok(); }
};

/// Weights — KEEP identical to AddTones.swift / AddTones.kt.
struct Params {
    double freqW = 10.0;
    double bigramW = 1.0;
    double floor = -2.5;
    /// Second-order Viterbi: an explicit trigram entry (prev2, prev1, next) overrides the bigram
    /// PMI of the transition; false = first-order bigram only (measurement baseline).
    bool trigram = true;
    /// Hand-curated pairs (curated_pairs.inc, Scripts/curated-pairs.txt): a transition (r → s) or
    /// (q, r → s) in the table scores at least curatedW (no personal model on Windows, so the
    /// "user wins" yield of the Swift/Kotlin code never triggers here). false = measurement baseline.
    bool curated = true;
    double curatedW = 8.0;
};

struct Result {
    std::u32string text;
    int vnTokens = 0;
    int enTokens = 0;
    int changed = 0;
};

/// AddTones.restore (static data only, no personal model): same length in code points,
/// case and punctuation kept, non-Vietnamese tokens untouched.
Result restore(const std::u32string& text, const LanguageData& data, const Params& p = Params());

}}  // namespace vtx::addtones
