// VietTelex engine — C++ port of TelexCore/Sources/TelexCore/TelexEngine.swift (1:1,
// behaviour identical, verified against the Swift golden corpus).
//
// Pure C++17, no platform headers, no exceptions, no RTTI, no heap: every buffer is a
// fixed-capacity (32) member array, so a TelexEngine is a plain value (copyable,
// stack-allocatable) and the hot path (feed / backspace / commitBoundary) never
// allocates. Output text is UTF-16 (char16_t); every character the engine emits is a
// precomposed BMP code point, so one UTF-16 unit == one on-screen character.
//
// For the C ABI (TSF TIP / other languages) see vtx_engine.h.
#pragma once
#include <cstddef>
#include <cstdint>
#include <climits>

namespace vtx {

enum class Tone : uint8_t { None = 0, Acute, Grave, Hook, Tilde, Dot };
enum class Mark : uint8_t { None = 0, Circumflex, Breve, Horn, Bar };

/// Max UTF-16 units any engine string can have (32 keys/letters; room to spare).
constexpr int kMaxText = 64;

/// Swift `TelexAction`. `text` is valid (NUL-terminated) for Replace only.
struct Action {
    enum Kind : int32_t { Passthrough = 0, Replace = 1, None = 2 };
    int32_t kind = Passthrough;
    int32_t backspaces = 0;
    int32_t length = 0;             // UTF-16 units in `text`
    char16_t text[kMaxText] = {};
};

class TelexEngine {
public:
    static constexpr int kCapacity = 32;

    // ---- Settings (Swift property names and ENGINE defaults) --------------------
    bool freeMarking = false;
    bool modernTone = false;
    bool liveSpellCheck = false;
    bool simpleTelex = false;
    bool teencode = true;
    bool quickTelex = false;
    bool bracketVowels = false;
    bool vniMode = false;
    bool contextualEnglish = false;
    bool englishWordRestore = true;
    bool collisionPrefersVietnamese = false;

    TelexEngine();

    // ---- Keystrokes --------------------------------------------------------------
    /// Feed one typed character (UTF-32). Only ascii letters compose (+ digits in VNI,
    /// + [ ] { } with bracketVowels); anything else -> Passthrough.
    void feed(char32_t ch, Action& out);
    /// Delete the whole last DISPLAYED character.
    void backspace(Action& out);
    /// Word boundary: optional auto-restore; resets the word.
    void commitBoundary(bool autoRestore, Action& out);
    /// Final text to commit (restore applied); resets the word. Returns UTF-16 length,
    /// writes at most cap-1 units + NUL.
    int commitText(bool autoRestore, char16_t* buf, int cap);
    /// Non-mutating twin of commitText.
    int peekCommitText(bool autoRestore, char16_t* buf, int cap) const;

    // ---- State -------------------------------------------------------------------
    int composed(char16_t* buf, int cap) const;
    int rawKeystrokes(char16_t* buf, int cap) const;
    bool isEmpty() const { return rawCount_ == 0; }
    bool isOverflowed() const { return overflowed_; }
    bool previousWordEnglish() const { return previousWordEnglish_; }

    void reset();
    void resetContext() { previousWordEnglish_ = false; }

    // ---- Re-open / re-edit -------------------------------------------------------
    void forgetLastCommit() { reopenRawCount_ = 0; reopenOutCount_ = 0; }
    bool canReopenLastCommit() const { return rawCount_ == 0 && reopenRawCount_ > 0; }
    /// Re-open the last committed word. Returns its UTF-16 length, or -1 (nil).
    int reopenLastCommit(char16_t* buf, int cap);
    /// Rebuild state from a word already on screen; true only on exact round-trip.
    bool seed(const char32_t* word, int length);
    bool seed(const char16_t* word, int length);   // UTF-16 (surrogates rejected)

    // ---- Test-only introspection (mirrors the Swift internal debug accessors) ------
    struct CancelState { bool cancelled; int at; int span; };
    CancelState debugCancelSnapshot() const { return {markCancelled_, toneCancelAt_, toneCancelSpan_}; }
    CancelState debugParseCancelState() const { return {pCancelled_, pToneCancelAt_, pToneCancelSpan_}; }
    int debugFreezeAt() const { return disabledAtCount_; }

private:
    struct Letter { uint8_t base = 0; Mark mark = Mark::None; bool upper = false; };
    static constexpr int kNotDisabled = INT_MAX;

    // raw keystrokes (ascii, case preserved)
    uint8_t raw_[kCapacity];
    int rawCount_ = 0;
    bool overflowed_ = false;

    // on-screen composition (scalar values)
    char32_t out_[kCapacity];
    int outCount_ = 0;

    // scratch
    char32_t scratch_[kCapacity];
    Letter renderLetters_[kCapacity];
    uint8_t basesScratch_[kCapacity];
    int rawLetter_[kCapacity];
    int toneKeys_[kCapacity];
    int vowelIdx_[kCapacity];

    // incremental parse state
    Letter letters_[kCapacity];
    int pCount_ = 0;
    Tone pTone_ = Tone::None;
    int pToneKeyCount_ = 0;
    bool pCancelled_ = false;
    int pToneCancelSpan_ = 0;
    int pToneCancelAt_ = -1;
    int pProcessed_ = 0;
    bool pFreeMarking_ = false;
    bool pSimpleTelex_ = false;
    bool pQuickTelex_ = false;
    bool pVniMode_ = false;
    bool pBracketVowels_ = false;
    bool pLiveSpellCheck_ = false;

    int disabledAtCount_ = kNotDisabled;
    bool markCancelled_ = false;
    int toneCancelAt_ = -1;
    int toneCancelSpan_ = 0;
    bool pFoldTones_ = false;
    Tone lastEffTone_ = Tone::None;
    bool upperToneKey_ = false;

    bool previousWordEnglish_ = false;

    // re-open snapshot
    uint8_t reopenRaw_[kCapacity];
    char32_t reopenOut_[kCapacity];
    int reopenRawCount_ = 0;
    int reopenOutCount_ = 0;
    bool reopenPrevEnglish_ = false;

    // ---- internals (names follow the Swift source) --------------------------------
    void feedAscii(uint8_t ascii, Action& out);
    void takeSnapshots();
    void captureReopen(bool restored);
    bool shouldRestoreRaw() const;
    bool composedHasDiacritic() const;
    bool composedIsRecognizedEnglish() const;
    bool isRecognizedEnglish() const;
    enum class WordContext { English, Vietnamese, Neutral };
    WordContext classifyWordContext(bool restored) const;
    bool rawIsNeutralLoanword() const;
    void updateContext(bool restored);
    bool rawIsEnglishContextWord(bool includingRestoreOnly = false) const;
    bool rawIsEnglishCollision() const;
    bool rawIsEnglishException() const;
    int teencodeOnset() const;        // 0 none, 1 w->qu, 2 z->d, 3 dz->d
    bool isAbbreviationPrefix(bool upper) const;
    bool abbreviationDoublerException(uint8_t lower, bool upper) const;
    bool composedIsValidSyllable() const;
    int elongationHeadCount(int count, Tone tone) const;
    bool isValidHead(int k, Tone tone) const;
    bool isTeencodeKeep() const { return elongationHeadCount(pCount_, lastEffTone_) > 0; }
    bool compositionDiffersFromRaw() const;
    bool compositionHasDiacritic() const;
    bool letterCreatedByW(int idx) const;
    bool uaUuPredecessorAllowsRetarget(int pred) const;
    bool hasLowercaseBefore(int at) const;
    void resetWord();
    bool prefixIsValid(int n);
    void copyOut(int n);
    int render();
    void rebuildFrozenAware();
    void recomputeFreeze();
    void rebuildParseState();
    void parseStep(int at);
    void parseStepVNI(int at, uint8_t key, uint8_t lower, bool upper);
    int toneVowelIndex(int count);
    void diff(int newCount, Action& out) const;
    bool standaloneHornUAllowed(int count) const;
    bool hasVowel(int count) const;
    bool isUkRime(int count) const;
    bool hasStopCoda(int count) const;
    bool lettersHaveStopCoda(int count) const;
    bool lettersAreUkRime(int count) const;
    bool stopCodaRejectsTone(Tone tone) const;
    void appendLetter(uint8_t base, Mark mark, bool upper);
    bool composedEquals(const char32_t* word, int length) const;
};

/// SyllableValidator (Swift public API) — string façades over UTF-32 input.
namespace SyllableValidator {
bool isValidSyllable(const char32_t* word, int length, bool teencode = true);
bool isValidPrefix(const char32_t* word, int length, bool teencode = true);
bool isValidSyllable(const uint8_t* classes, int n, Tone tone, bool teencode);
bool isValidPrefix(const uint8_t* bases, int n, bool teencode);
} // namespace SyllableValidator

} // namespace vtx
