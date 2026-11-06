// typo_fix.h — "Gợi ý sửa lỗi gõ sai" for a PHYSICAL keyboard (macOS 1.8.2 TypoFixLogic in
// App/Sources/CaretSuggestions.swift, on iOS/Keyboard/AdjacentKeyFixer.swift +
// AutoCorrect.swift). Runs in VietTelex.exe only: it needs vnlexicon / enlexicon (already
// embedded for Công cụ văn bản); the TIP asks over caret_hint_ipc.h after its cheap gate
// (caret_hints.h typoWorthChecking).
//
// One edit away from a lexicon word: a key replaced by a NEIGHBOUR on the physical keyboard
// (ANSI/ISO stagger) or two adjacent keys swapped; a dropped / extra key only counts as a
// RIVAL. Suggested only when the candidate is common (≥ minFreq) and beats the runner-up
// by ≥ margin — thresholds tuned on macOS (TypoFixEvalTests, DEV P 98.5% R 17.6%); the
// same eval runs here (app_tests typo_eval_precision_floor).
#pragma once
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

struct vtx_engine;

namespace vtx { namespace addtones { class Lexicon; struct LanguageData; } }

namespace vtx::app::typo {

enum class Edit : uint8_t { Sub = 1, Swap = 2, Del = 4, Ins = 8 };
constexpr uint8_t kAllEdits = 15;

struct Cand {
    std::u32string word;
    int freq = 0;
    Edit edit = Edit::Sub;
    bool operator==(const Cand& o) const { return word == o.word && freq == o.freq && edit == o.edit; }
};

struct Params {
    int minLen = 3;
    int minFreq = 150;
    int margin = 80;
    uint8_t edits = static_cast<uint8_t>(Edit::Sub) | static_cast<uint8_t>(Edit::Swap);
    uint8_t rivals = static_cast<uint8_t>(Edit::Del) | static_cast<uint8_t>(Edit::Ins);
};
// = TypoFixLogic.defaults (keep identical to macOS).
inline Params defaults() { return Params{}; }

// English fixes ("spellnig" -> spelling, TypoFixLogic.EnglishParams): only when there is no
// Vietnamese fix. One edit on the RAW keys (no Telex) that is an enlexicon word: adjacent-key
// substitution / swap always proposable, a dropped / extra key only from insDelMinLen letters
// (rivals below that); Vietnamese candidates (every edit) are rivals — both lexicons share the
// 0–255 frequency scale. Words of longMinLen+ letters: a lower frequency floor (longMinFreq).
struct EnglishParams {
    int minFreq = 135;  // 140 → 135 on 2026-10-18 (new vnlexicon frequencies; = macOS englishDefaults)
    int margin = 60;
    int insDelMinLen = 5;
    int longMinLen = 7;
    int longMinFreq = 60;
};
// = TypoFixLogic.englishDefaults (keep identical to macOS; tuned by TypoFixEvalTests).
inline EnglishParams englishDefaults() { return EnglishParams{}; }

// AdjacentKeyFixer.physicalNeighbors: "g" -> f h t y v b, "z" -> a s x.
const std::vector<char32_t>& physicalNeighbors(char32_t key);

// Lexicon / engine / known-word lookups (injected: tests use fakes).
class Source {
public:
    virtual ~Source() = default;
    virtual std::u32string compose(const std::u32string& raw) const = 0;       // raw -> screen text
    virtual std::optional<int> frequency(const std::u32string& word) const = 0;  // nullopt = not a word
    virtual bool hasCompletion(const std::u32string& prefix) const = 0;          // still a prefix of a word
    virtual bool isKnown(const std::u32string& lower) const = 0;                 // English / chat / declined
    // enlexicon frequency of a lowercase a–z word (nullopt = not a word / no English fixes).
    virtual std::optional<int> englishFrequency(const std::u32string&) const { return std::nullopt; }
};

// "cũm" -> "cum": drop the five tone marks, keep letter marks (ư, â, đ…).
std::u32string stripTones(const std::u32string& s);

// Every ONE-edit candidate that is a lexicon word (≠ current text). `edits` = Edit bits.
std::vector<Cand> candidates(const std::u32string& lower, const Source& src, uint8_t edits = kAllEdits);
// The top candidate by frequency, if it comes from a proposable edit, is common enough and
// beats the runner-up (counted over edits ∪ rivals) by the margin.
std::optional<Cand> pick(const std::vector<Cand>& cands, const Params& p = defaults());
// TypoFixLogic.englishCandidates: every one-edit string of `lower` that is an English word.
std::vector<Cand> englishCandidates(const std::u32string& lower, const Source& src);
// TypoFixLogic.englishPick: the top of en ∪ rivals, if English, proposable, common, ahead.
std::optional<Cand> englishPick(const std::vector<Cand>& en, const std::vector<Cand>& rivals, int typedLen,
                                const EnglishParams& p = englishDefaults());
// The fix for the word typed as `raw`, or nullopt. Capital first kept. A Vietnamese fix first,
// else an English one; `filterSensitive` ("Lọc từ nhạy cảm") drops a fix that is a
// SensitiveWords word.
std::optional<std::u32string> correction(const std::u32string& raw, const Source& src, const Params& p = defaults(),
                                         bool filterSensitive = true, const EnglishParams& ep = englishDefaults());

// (frequency, id) pairs: frequency desc, then id asc (VNSuggest / EnglishLite order).
void sortByFreqThenId(std::vector<std::pair<int, int>>& v);

// ---------------------------------------------------------------- the real data
// VNSuggest over vnlexicon.bin: exact frequency, and "matches(prefix, poolLimit: 1)".
class LexiconIndex {
public:
    explicit LexiconIndex(const addtones::Lexicon& lx);
    std::optional<int> frequency(const std::u32string& word) const;
    bool contains(const std::u32string& word) const { return frequency(word).has_value(); }
    bool hasCompletion(const std::u32string& typed) const;
    // VNSuggest.matches: syllables compatible with the word being typed (marks typed must
    // match, marks not yet typed match anything), frequency desc then id, `excluding`
    // (lowercase UTF-8) skipped, at most `poolLimit`.
    struct Match {
        std::string_view word;  // lexicon display form (lowercase UTF-8)
        int freq = 0;
        int id = -1;
    };
    std::vector<Match> matches(const std::u32string& typed, int poolLimit, std::string_view excluding) const;
    // VNSuggest.lexiconId: id of exactly this syllable after SyllableLM.normalize
    // (lowercase, NFC, old-style tone placement "hoà" -> "hòa"); -1 if none.
    int lexiconId(const std::u32string& word) const;
    const addtones::Lexicon& lexicon() const { return lx_; }

private:
    struct Dec {
        uint8_t base, attr;
    };
    bool decompose(const std::u32string& s, std::vector<Dec>& out) const;
    void range(const std::string& prefix, int& lo, int& hi) const;
    const addtones::Lexicon& lx_;
    std::unordered_map<char32_t, Dec> table_;
    std::vector<std::vector<int>> firstTop_;  // VNLexicon2Data.firstCharTop, per 'a'..'z'
};

// Engine + lexicon + English + chat words, composing with `engineFlags` (the typist's).
class LexiconSource final : public Source {
public:
    LexiconSource(const addtones::LanguageData& data, uint32_t engineFlags);
    ~LexiconSource() override;
    LexiconSource(const LexiconSource&) = delete;
    LexiconSource& operator=(const LexiconSource&) = delete;

    std::u32string compose(const std::u32string& raw) const override;
    std::optional<int> frequency(const std::u32string& w) const override { return index_.frequency(w); }
    bool hasCompletion(const std::u32string& p) const override { return index_.hasCompletion(p); }
    bool isKnown(const std::u32string& lower) const override;
    std::optional<int> englishFrequency(const std::u32string& lower) const override;
    bool isEnglish(const std::u32string& lower) const;
    bool isChatWord(const std::u32string& lower) const { return chat_.count(lower) != 0; }
    const std::unordered_set<std::u32string>& chatWords() const { return chat_; }

private:
    const addtones::LanguageData& data_;
    LexiconIndex index_;
    vtx_engine* engine_ = nullptr;
    std::unordered_set<std::u32string> chat_;
};

// TypoFixLogic.chatWords source: the ASCII seed unigrams (iOS SeedData.swift); the ones
// that are Vietnamese syllables are dropped at load (LexiconSource).
const std::vector<const char*>& seedAsciiWords();

}  // namespace vtx::app::typo

namespace vtx { struct HintMessage; }
namespace vtx::app::predict { class Model; }
namespace vtx::app::learn { class Model; }

namespace vtx::app {

// VietTelex.exe's answer to a caret-hint job from the TIP (caret_hint_ipc.h): the typo fix
// for the raw keys, Thêm dấu for the unaccented run, or word prediction (word_prediction.h,
// candidates joined by kPredictSep). "" = nothing to suggest (also without language data).
// The lexicon source is rebuilt only when the engine flags change; the prediction model is
// built on the first Predict job (the Windows setting is off ⇒ never).
// Memory: with a loader, the language data itself is loaded on the first job that needs it
// (a non-empty answer() / knownWord()), never by construction or the setters — the app's
// start sequence touches this object, and a portable copy (no TIP) never sends a job.
class HintJobs {
public:
    using DataLoader = std::function<const addtones::LanguageData*()>;
    explicit HintJobs(const addtones::LanguageData* data) : data_(data), loaded_(true) {}
    explicit HintJobs(DataLoader load) : load_(std::move(load)) {}
    ~HintJobs();
    HintJobs(const HintJobs&) = delete;
    HintJobs& operator=(const HintJobs&) = delete;
    std::u16string answer(const HintMessage& m);
    bool predictionLoaded() const { return model_ != nullptr; }
    // The loader ran (or data was given at construction).
    bool dataLoaded() const { return loaded_; }
    // "Lọc từ nhạy cảm" (Settings::filterSensitive) for the next answers.
    void setFilterSensitive(bool on) { filterSensitive_ = on; }
    // "Học từ bạn gõ" (learned_words.h) for the next Predict answers; nullptr = off.
    void setLearned(const learn::Model* m) { learned_ = m; }
    // VNSuggest.contains — the learned model's "known word" test (loads the predictor).
    bool knownWord(const std::string& lowerUtf8);

private:
    const addtones::LanguageData* data();  // runs the loader once
    const addtones::LanguageData* data_ = nullptr;
    DataLoader load_;
    bool loaded_ = false;
    typo::LexiconSource* source_ = nullptr;
    predict::Model* model_ = nullptr;
    const learn::Model* learned_ = nullptr;
    uint32_t flags_ = 0;
    bool filterSensitive_ = true;
};

}  // namespace vtx::app
