// caret_hints.h — suggestions next to the caret (macOS 1.8.2 App/Sources/MathHint.swift +
// CaretSuggestions.swift; shared rules iOS/Keyboard/MathResults.swift + NumberChips.swift,
// fixtures iOS/KeyboardTests/Fixtures/math-results.txt + number-chips.txt). Portable and
// pure: the TIP (text_service.cpp) feeds keys and screen text in, shows the result in a
// non-activating window at the caret, and applies it on Tab.
//
//   1. Math results (default ON):  "12*3="            -> "= 36", Tab / Enter inserts "36".
//   2. Number chips (default ON):  "1tr2 "            -> "1.200.000 ₫", Tab replaces (money only).
//   3. Typo fixes (default ON):    "tpoi "            -> "tôi" (the lexicon lookup runs in
//                                  VietTelex.exe, app/core/typo_fix.h), Tab replaces, Esc =
//                                  never suggest that word again (this session).
//   4. Tones (default OFF):        "toi di hoc." / pause 0.9 s after a space -> "tôi đi học"
//                                  (Thêm dấu runs in VietTelex.exe, as the text tools do).
//   5. Date/time (default ON):     "hôm nay " -> "28/09/2026", "bây giờ " -> "21:35"; English
//                                  today/tomorrow/yesterday/now only after an English word.
//   7. Retro English (offer mode of "Tự sửa từ phía trước", retro_english.h): "Hí cả í very
//                                  fast " -> "His car is", Tab rewrites the words. The
//                                  session decides and verifies; it wins over every other hint.
//
// Never auto-replaces. Only Tab applies (Enter too for math); Esc dismisses (and declines
// typo/tones); every other key dismisses and goes through. Off in password fields. A key
// costs nothing beyond one flag read when all five are off (HintTracker is never fed).
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace vtx::hints {

// ---------------------------------------------------------------- strings
std::u32string toU32(const std::u16string& s);
std::u16string toU16(const std::u32string& s);
bool isWhitespace(char32_t c);   // Swift Character.isWhitespace (incl. newlines)
bool isNewline(char32_t c);
bool isLetter(char32_t c);       // Latin/Vietnamese letters (+ other scripts, roughly)
bool isDigit(char32_t c);        // ASCII 0-9 (Character.isNumber for our inputs)
char32_t lowerChar(char32_t c);  // ASCII + Latin-1/Ext-A/B + Vietnamese block
std::u32string lower(const std::u32string& s);

// ---------------------------------------------------------------- the suggestion
enum class Kind : uint8_t { Math, Number, Typo, Tones, Date, Predict, Email, Retro };

// `replace` = tail of the text before the caret that gets replaced ("" = insert only,
// the math result), `insert` = what goes there, `display` = what the window shows.
struct Suggestion {
    Kind kind = Kind::Math;
    std::u16string display, replace, insert;
    bool operator==(const Suggestion& o) const {
        return kind == o.kind && display == o.display && replace == o.replace && insert == o.insert;
    }
};

// Which of the five are on (Settings mathResults / numberChips / typoHints / toneHints /
// dateHints).
struct Enabled {
    bool math = true, number = true, typo = true, tones = false, date = true;
    bool any() const { return math || number || typo || tones || date; }
};

// ---------------------------------------------------------------- keys while shown
enum class KeyAction : uint8_t {
    Accept,          // apply, eat the key
    DismissConsume,  // Esc: hide (and decline typo/tones), eat the key
    DismissPass,     // anything else: hide, the key goes on as usual
};
constexpr uint32_t kVkTab = 0x09, kVkReturn = 0x0D, kVkEscape = 0x1B;
// `plain` = no Shift/Ctrl/Alt/Win. Tab accepts every kind, Enter only math ("50k␣" then
// Enter sends the message); digits never pick ("5+5=" then typing "10" stays "10").
KeyAction action(Kind kind, uint32_t vk, bool plain);

// ---------------------------------------------------------------- 1. math (MathResults)
constexpr int kMathMaxLength = 64;
// Expression without "=" -> result text, nullopt if not a calculation (fixture `eval`).
std::optional<std::u32string> mathResult(const std::u32string& expr);
// Text before the caret ending in "=" -> the text to insert after it (fixture `chip`).
std::optional<std::u32string> mathChip(const std::u32string& before);
// "= 36"
std::u32string mathLabel(const std::u32string& result);

// ---------------------------------------------------------------- 2. numbers (NumberChips)
struct NumberChip {
    std::u32string display, replace, insert;
    bool operator==(const NumberChip& o) const {
        return display == o.display && replace == o.replace && insert == o.insert;
    }
};
// Canonical "-1250000,5" -> words (fixture spell/spellLe).
std::optional<std::u32string> spellNumber(const std::u32string& canonical, bool le = false);
// The chip iOS/Android show (fixture `chip`): money format or the number in words.
std::optional<NumberChip> numberChip(const std::u32string& before, bool le = false);
// Windows / macOS: money formats only ("1.200.000 ₫", "1.250.000đ"); `before` must end in
// exactly the space just typed.
std::optional<Suggestion> moneyChip(const std::u32string& before);
bool isMoneyFormat(const std::u32string& display);

// ---------------------------------------------------------------- 3. typo gate (the fix is in the app)
// Boundaries that may carry a typo fix: space, NBSP , ; ! ? ) — never . : ' (domains,
// times, "don't") and never Enter (the message may be gone).
bool typoTriggers(char32_t boundary);
bool isSentenceStart(const std::u32string& before);
bool caseAllows(const std::u32string& raw, bool sentenceStart);
// Cheap gate before asking the app: boundary ok, raw 3–10 ASCII letters, word all letters
// and not a valid Vietnamese syllable.
bool typoWorthChecking(char32_t boundary, const std::u32string& raw, const std::u32string& word, int minLen = 3);
// The screen (`before`, ending at the caret) must end in word + boundary standing alone,
// capitals only at a sentence start.
std::optional<Suggestion> typoSuggestion(const std::u32string& before, const std::u32string& word,
                                         char32_t boundary, const std::u32string& raw, const std::u32string& fix);

// Words the user declined with Esc (lowercase, most recent `cap`) — AutoCorrect.Rejected.
class Rejected {
public:
    explicit Rejected(size_t cap = 300) : cap_(cap) {}
    bool contains(const std::u32string& w) const;
    bool add(const std::u32string& w);
    size_t size() const { return order_.size(); }

private:
    std::vector<std::u32string> order_;  // oldest first; linear scan (≤ cap, only at a trigger)
    size_t cap_;
};

// ---------------------------------------------------------------- 4. tones for unaccented runs
constexpr int kToneMinSyllables = 3;
constexpr int kToneMaxSyllables = 40;
constexpr int kTonePauseMs = 900;
constexpr int kToneWindow = 320;  // UTF-16 units read before the caret
enum class ToneTrigger : uint8_t { None, SentenceEnd, Pause };

// A chunk (no whitespace) is an UNACCENTED valid syllable: edge punctuation stripped,
// a–z (capital first allowed), not an English run opener.
bool isUnaccentedSyllable(const std::u32string& chunk);

// Counts unaccented syllables at boundaries from the key stream (never reads the screen).
class ToneTracker {
public:
    void reset() { count_ = 0; }
    int count() const { return count_; }
    // `chunk` = what was typed since the last whitespace, `boundary` = the key just typed.
    ToneTrigger feed(const std::u32string& chunk, char32_t boundary);

private:
    int count_ = 0;
};

// The run to add tones to at the end of `before` (chunks from the end, trailing
// whitespace/punctuation included; stops at a newline, another chunk or the end of the
// previous sentence). nullopt if fewer than kToneMinSyllables.
std::optional<std::u32string> toneRun(const std::u32string& before);
// From the Thêm dấu result (same length in code points).
std::optional<Suggestion> toneSuggestion(const std::u32string& run, const std::u32string& restored);

// ---------------------------------------------------------------- 5. date / time
enum class Phrase : uint8_t { Today, Tomorrow, Yesterday, Now };
struct LocalTime {
    int year = 2000, month = 1, day = 1, hour = 0, minute = 0;
};
// `isEnglish(prev)`: English only after an English word ("see you tomorrow ").
std::optional<Phrase> detectDate(char32_t boundary, const std::u32string& prevRun, const std::u32string& run,
                                 bool (*isEnglish)(const std::u32string&));
std::u32string formatDate(Phrase p, const LocalTime& now);  // "28/09/2026" / "21:35"
std::optional<Suggestion> dateSuggestion(const std::u32string& before, const std::u32string& prevRun,
                                         const std::u32string& run, Phrase phrase, const LocalTime& now);
// The last two whitespace-separated chunks before the final space ("Hẹn hôm nay " ->
// "hôm", "nay"). False unless `before` ends in exactly one space after a chunk.
bool lastRuns(const std::u32string& before, std::u32string& prevRun, std::u32string& run);
// The TIP's English test for dates: engine's English-run openers (no lexicon in the TIP).
bool opensEnglishRun(const std::u32string& w);

// ---------------------------------------------------------------- shared screen rule
// `before` ends exactly in `token` (UTF-16 compare) and the token stands alone (start of
// text, or whitespace before it) — ShortcutScreen.tokenRange.
bool standsAlone(const std::u32string& before, const std::u32string& token);

// ---------------------------------------------------------------- 6. word prediction (gợi ý từ)
// macOS WordPrediction.swift. The ranking and the data live in VietTelex.exe
// (app/core/word_prediction.h, asked over caret_hint_ipc.h HintJob::Predict); the TIP only
// decides when to ask (after a kPredictDelayMs pause, cancelled by the next key) and checks
// the screen before showing and again before replacing. Gate: Settings::systemTextPrediction
// (Windows' "Show text suggestions when typing on the physical keyboard"): off ⇒ one bool
// read per key. ONE suggestion (the top-ranked word; no list, no numbers): Tab or a click
// accepts it, Esc dismisses (and mutes the word being typed until the next word); Enter /
// arrows / digits never accept; never auto-replaces. Next word only after two context words
// with a trigram row (the app decides; "Tên " -> nothing).
constexpr int kPredictDelayMs = 300;
constexpr int kPredictWindow = 64;  // UTF-16 units before the caret (2 context words)
// Code editors / IDEs (Tab indents there, completion is the editor's job) and terminals:
// never. `exe` normalized (lowercase file name).
bool predictionAllowedForApp(const std::string& exe);
// The app's candidate -> the suggestion, if the screen (`before`, ending at the caret) still
// ends with the typed word standing alone ("" = next word: one space after a letter).
// Replaces exactly `typed` with candidate + " ".
std::optional<Suggestion> predictSuggestion(const std::u32string& before, const std::u32string& typed,
                                            const std::u16string& candidate);
// Right before replacing (Tab / click): the text before the caret still ends as `s` expects
// (math: "=", next word: a space after a letter, email: "@" + prefix + `replace` and prefix +
// `insert` still spells the domain, otherwise `replace` standing alone).
bool hintStillValid(const Suggestion& s, const std::u32string& before);
// Esc on a completion mutes it while the typed word still starts with the declined one.
bool predictMuted(const std::u32string& typed, const std::u32string& declined);
// The space WE inserted when a prediction was accepted ("được␣") and the very next key
// (macOS PredictionLogic.acceptSpaceReplacement — iOS AutoSpace rules): . , ? ! ; : and the
// closing ) ] } ” ’ » › -> that key + a space ("được. "); "/" -> "/" alone; anything else ->
// "" (keep the space, the key goes on as usual). Straight quotes are kept (they usually open
// the next word).
std::u32string acceptSpaceReplacement(char32_t key);
// State after an accepted prediction, consumed by the very next key.
struct AcceptedSpace {
    std::u32string inserted;  // "được " (what Tab inserted)
    std::u32string carried;   // ". " after the punctuation moved our space (next space swallowed)
    bool empty() const { return inserted.empty() && carried.empty(); }
};
enum class AcceptSpaceAct : uint8_t { Pass, Replace, Swallow };
// The next key `ch` (0 = not a character key): what to do, `expect` = the screen tail to check
// first (re-read), `replacement` = what replaces the last character (our space). Clears `st`.
AcceptSpaceAct acceptSpaceKey(AcceptedSpace& st, char32_t ch, std::u32string& expect, std::u32string& replacement);

// ---------------------------------------------------------------- 6b. email domains (đuôi mail)
// Same rule as iOS EmailDomains (iOS/Keyboard/DomainPopup.swift) and the macOS / Linux desktop
// ports: right after "user@" (or "user@g") the ONE suggestion is the first provider of
// kEmailProviders the typed part after "@" is a (case-insensitive) prefix of, and not equal to.
// Gate = word prediction (Settings::systemTextPrediction); only a string check on the token, no
// app round trip. `before` = text before the caret (composing word included, as shown), `typed`
// = the composing word as shown ("" = none), `raw` = its raw keys. Telex may have mangled the
// composing word ("yahoo" shown "yahô"): matching uses the raw keys, and then the suggestion
// REPLACES the composing word; otherwise it inserts only the missing part (never "@" again,
// never the typed prefix). The local part before "@" (back to start / whitespace / , ; < ( : " ')
// must be [A-Za-z0-9._%+-]+. Tab inserts raw (no space added, nothing learned, no next word).
extern const char32_t* const kEmailProviders[4];  // gmail.com, icloud.com, yahoo.com, outlook.com
std::optional<Suggestion> emailDomainSuggestion(const std::u32string& before, const std::u32string& typed,
                                                const std::u32string& raw);
// Cheap per-key tracker (no screen read): is the caret still inside "…@domainpart"? '@' arms,
// these keep it, anything else disarms.
inline bool emailTokenChar(char32_t c) {
    return (c >= U'a' && c <= U'z') || (c >= U'A' && c <= U'Z') || (c >= U'0' && c <= U'9') || c == U'.' ||
           c == U'-';
}

// ---------------------------------------------------------------- Học từ bạn gõ
// App/Sources/LearnedModel.swift LearnTracker / learnable, same rules (the model itself lives in
// VietTelex.exe — app/core/learned_words.h; the TIP only tracks committed words and sends them,
// caret_hint_ipc.h HintJob::Learn). learnable: letters only, ≤ 12, no run of ≥ 3 equal letters.
bool learnable(const std::u32string& w);
// Committed words at word boundaries → learning events (lowercase word, the ≤ 2 previous words
// of the same sentence — single spaces apart — and a weight: 1 typed, 2 an accepted prediction).
// Each word is HELD until the next event: ⌫ right after the boundary / a hint replacing it drops
// it, an accepted typo fix learns the fixed form.
class LearnTracker {
public:
    struct Event {
        std::u32string word, prev1, prev2;  // lowercase; empty = none
        int weight = 1;
        // The word exactly as committed (learned casing, 10/2026): this is what the Learn payload
        // carries — the app keys by lowercase anyway (old app builds learn it unchanged) and
        // judges the casing as mid-sentence evidence when prev1 is present.
        std::u32string form;
    };
    // `word` committed by `boundary` (' ' keeps the sentence context, anything else cuts it).
    // true = `out` is the previous held event, final now.
    bool commit(const std::u32string& word, char32_t boundary, bool standsAlone, int weight, Event& out);
    void replacePending(const std::u32string& fixed);
    void discard();
    bool breakContext(Event& out);  // Enter / Tab / caret moved / focus: final, context cut
    bool hasPending() const { return pending_; }
    const Event& pending() const { return held_; }
    const std::u32string& prev1() const { return prev1_; }

private:
    std::u32string prev1_, prev2_;
    bool pending_ = false;
    Event held_;
};

// ---------------------------------------------------------------- key stream -> trigger
enum class TriggerKind : uint8_t { None, Math, Number, Date, Typo, Tones, Retro };
struct Trigger {
    TriggerKind kind = TriggerKind::None;
    int delayMs = 40;            // read the screen after the app inserted the key
    std::u32string raw, word;    // Typo: the committed word's keys / text
    char32_t boundary = 0;
};
// The word the typing session just committed at this key (raw keys + text on screen);
// empty raw = no word (or a shortcut expanded).
struct Commit {
    std::u32string raw, word;
};

// Tracks the chunk being typed (raw printable keys since the last whitespace) and the one
// before it, and decides at each key whether reading the screen is worth it. Fed only
// while some hint is enabled.
class HintTracker {
public:
    void reset();
    // A printable key (after the session handled it).
    Trigger onChar(char32_t ch, const Commit& commit, const Enabled& en);
    void onBackspace();
    const std::u32string& chunk() const { return chunk_; }
    const std::u32string& prevChunk() const { return prev_; }

private:
    std::u32string chunk_, prev_;
    ToneTracker tones_;
};

// ---------------------------------------------------------------- 7. retro English offer
// The session's verified correction (TypingSession::retroOffer(): replace / insert end with
// the boundary key) as a suggestion. The TIP reads the screen once the app typed that key.
Suggestion retroHint(const std::u16string& display, const std::u16string& replace, const std::u16string& insert);
// This key's trigger when the session offered a correction: the retro offer replaces whatever
// the tracker armed (math / number / date / typo / tones) — it wins; word prediction then only
// runs if it misses.
Trigger withRetro(const Trigger& fromTracker, bool retroOffered);
// Shown only when the screen still ends with what it replaces (hintStillValid).
std::optional<Suggestion> retroSuggestion(const std::u32string& before, const Suggestion& offer);

// Cheap pre-filters on RAW keys (the screen decides).
bool numberWorthChecking(const std::u32string& run, const std::u32string& prevRun);
bool dateWorthReading(const std::u32string& prevRaw, const std::u32string& raw);

// ---------------------------------------------------------------- where to show
struct Rect {
    long left = 0, top = 0, right = 0, bottom = 0;
    long width() const { return right - left; }
    long height() const { return bottom - top; }
};
// A caret rectangle worth anchoring to: non-degenerate height, not a whole field (some
// hosts return the field box for an empty range), on screen.
bool plausibleCaret(const Rect& caret, const Rect& screen, int dpi = 96);
// Top-left of a w×h window below the caret (above when it would leave the work area),
// kept inside the work area (TextToolsPanelLogic.origin, Windows y-down).
void popupOrigin(const Rect& caret, long w, long h, const Rect& work, long& x, long& y, int dpi = 96);

}  // namespace vtx::hints
