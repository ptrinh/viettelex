// Port of TelexCore/Sources/TelexCore/TelexEngine.swift — 1:1, same names, same
// order. See the Swift source for the WHY of every rule (field reports, decisions);
// comments here are kept short on purpose and point at the behaviour only.
#include "viettelex/telex_engine.hpp"
#include "generated_tables.hpp"
#include "tables.hpp"

namespace vtx {

using namespace tables;

namespace {

// English word-list lookup (collisions, context words, restore-only, neutral loanwords).
// -DVTX_NO_ENGLISH_TABLES ("lite" build, e.g. the web SDK's @viettelex/core/lite): every
// lookup misses, so the lists are dropped by the linker. Dictionary features become
// no-ops; Telex/VNI, tones, the syllable validator and validator-based auto-restore are
// untouched. The default build is unchanged.
template <size_t N>
inline bool inEnglishList(const std::string_view (&set)[N], const char* w, int len) {
#ifdef VTX_NO_ENGLISH_TABLES
    (void)set; (void)w; (void)len;
    return false;
#else
    return contains(set, w, len);
#endif
}

inline int emit(const char32_t* src, int n, char16_t* buf, int cap) {
    if (!buf || cap <= 0) return n;
    int w = n < cap - 1 ? n : cap - 1;
    for (int i = 0; i < w; ++i) buf[i] = static_cast<char16_t>(src[i]);
    buf[w] = 0;
    return n;
}
inline int emitRaw(const uint8_t* src, int n, char16_t* buf, int cap) {
    if (!buf || cap <= 0) return n;
    int w = n < cap - 1 ? n : cap - 1;
    for (int i = 0; i < w; ++i) buf[i] = static_cast<char16_t>(src[i]);
    buf[w] = 0;
    return n;
}
inline void setReplace(Action& a, int backspaces, const char32_t* s, int n) {
    a.kind = Action::Replace;
    a.backspaces = backspaces;
    a.length = n;
    for (int i = 0; i < n; ++i) a.text[i] = static_cast<char16_t>(s[i]);
    a.text[n] = 0;
}
inline void setSimple(Action& a, int32_t kind) {
    a.kind = kind;
    a.backspaces = 0;
    a.length = 0;
    a.text[0] = 0;
}

/// Lowercase ascii-letter word of `src[0..<count]` into `w`; -1 when some char is not
/// an ascii letter or count is out of (0, maxLen].
template <typename T>
inline int lowerAsciiInto(const T* src, int count, int maxLen, char* w) {
    if (count <= 0 || count > maxLen) return -1;
    for (int i = 0; i < count; ++i) {
        uint32_t b = static_cast<uint32_t>(src[i]);
        if (b >= 'A' && b <= 'Z') b |= 0x20;
        if (b < 'a' || b > 'z') return -1;
        w[i] = static_cast<char>(b);
    }
    return count;
}

// Bracket -> horned vowel it types (base, upper); base 0 = not a bracket.
inline uint8_t bracketBase(uint8_t key, bool& upper) {
    switch (key) {
    case '[': upper = false; return 'o';
    case ']': upper = false; return 'u';
    case '{': upper = true; return 'o';
    case '}': upper = true; return 'u';
    default: return 0;
    }
}

inline Tone vniTone(uint8_t d) {
    switch (d) {
    case '1': return Tone::Acute; case '2': return Tone::Grave; case '3': return Tone::Hook;
    case '4': return Tone::Tilde; case '5': return Tone::Dot;
    default: return Tone::None;
    }
}
inline Mark vniMark(uint8_t d) {
    switch (d) {
    case '6': return Mark::Circumflex; case '7': return Mark::Horn;
    case '8': return Mark::Breve; case '9': return Mark::Bar;
    default: return Mark::None;
    }
}
inline bool vniMarkAccepts(uint8_t base, Mark mark) {
    switch (mark) {
    case Mark::Circumflex: return base == 'a' || base == 'e' || base == 'o';
    case Mark::Horn: return base == 'o' || base == 'u';
    case Mark::Breve: return base == 'a';
    case Mark::Bar: return base == 'd';
    default: return false;
    }
}
inline uint8_t quickTelexSecond(uint8_t c) {
    switch (c) {
    case 'c': case 'k': case 'p': case 't': return 'h';
    case 'g': return 'i';
    case 'n': return 'g';
    case 'q': return 'u';
    default: return 0;
    }
}
inline char telexToneKey(Tone t) {
    switch (t) {
    case Tone::Acute: return 's'; case Tone::Grave: return 'f'; case Tone::Hook: return 'r';
    case Tone::Tilde: return 'x'; case Tone::Dot: return 'j'; default: return 0;
    }
}
inline char vniToneKey(Tone t) {
    switch (t) {
    case Tone::Acute: return '1'; case Tone::Grave: return '2'; case Tone::Hook: return '3';
    case Tone::Tilde: return '4'; case Tone::Dot: return '5'; default: return 0;
    }
}
/// Telex / VNI mark expansion of a toneless lowercase letter, nullptr if none.
inline const char* markExpansion(char32_t c, bool vni) {
    switch (c) {
    case U'â': return vni ? "a6" : "aa";
    case U'ă': return vni ? "a8" : "aw";
    case U'ê': return vni ? "e6" : "ee";
    case U'ô': return vni ? "o6" : "oo";
    case U'ơ': return vni ? "o7" : "ow";
    case U'ư': return vni ? "u7" : "uw";
    case U'đ': return vni ? "d9" : "dd";
    default: return nullptr;
    }
}

inline int commonPrefixLength(const char32_t* a, const char32_t* b, int limit) {
    int i = 0;
    while (i < limit && a[i] == b[i]) ++i;
    return i;
}

const uint8_t kEnglishExceptions[3][4] = {{'w', 'a', 's', 0}, {'w', 'o', 'w', 0}, {'y', 'e', 's', 0}};

} // namespace

TelexEngine::TelexEngine() {
    for (int i = 0; i < kCapacity; ++i) {
        raw_[i] = 0; reopenRaw_[i] = 0; reopenOut_[i] = 0; out_[i] = 0; scratch_[i] = 0;
        basesScratch_[i] = 0; rawLetter_[i] = -1; toneKeys_[i] = 0; vowelIdx_[i] = 0;
    }
}

// MARK: - Public entry points

bool TelexEngine::seed(const char16_t* word, int length) {
    char32_t cps[kCapacity];
    int n = 0;
    for (int i = 0; i < length; ++i) {
        char16_t u = word[i];
        if (u >= 0xD800 && u <= 0xDFFF) { reset(); return false; }   // never typeable
        if (n == kCapacity) { reset(); return false; }
        cps[n++] = u;
    }
    return seed(cps, n);
}

bool TelexEngine::seed(const char32_t* word, int length) {
    reset();
    if (length <= 0 || length > kCapacity / 2) return false;
    // seedKeystrokes: detone -> mark expansion -> trailing tone key.
    // Swift compares `composed == word` under canonical equivalence; the only
    // precomposed code point that is canonically an engine letter is KELVIN SIGN ≡ K.
    char32_t norm[kCapacity / 2];
    for (int i = 0; i < length; ++i) norm[i] = word[i] == 0x212A ? U'K' : word[i];
    word = norm;
    char keys[kCapacity * 2 + 2];
    int k = 0;
    char toneKey = 0;
    for (int i = 0; i < length; ++i) {
        char32_t ch = word[i];
        bool isUpper = isUpperVi(ch);
        char32_t lower = lowerVi(ch);
        char32_t toneless = lower;
        int row; Tone t;
        if (detone(lower, row, t)) {
            if (t != Tone::None) {
                if (toneKey != 0) return false;             // two tones in one syllable
                toneKey = vniMode ? vniToneKey(t) : telexToneKey(t);
            }
            toneless = kTonedGroups[row][0];
        }
        char exp[3] = {0, 0, 0};
        if (const char* e = markExpansion(toneless, vniMode)) {
            exp[0] = e[0]; exp[1] = e[1];
        } else {
            if (toneless < 'a' || toneless > 'z') return false;
            exp[0] = static_cast<char>(toneless);
        }
        for (int j = 0; exp[j]; ++j) {
            char c = exp[j];
            // A mark digit is never uppercased; a mark LETTER follows the letter's case.
            if (isUpper && c >= 'a' && c <= 'z' && (!vniMode || j == 0)) c = static_cast<char>(c - 32);
            keys[k++] = c;
        }
    }
    if (toneKey) keys[k++] = toneKey;
    if (k > kCapacity) { reset(); return false; }
    Action a;
    for (int i = 0; i < k; ++i) feedAscii(static_cast<uint8_t>(keys[i]), a);
    if (!composedEquals(word, length)) { reset(); return false; }
    return true;
}

bool TelexEngine::composedEquals(const char32_t* word, int length) const {
    if (length != outCount_) return false;
    for (int i = 0; i < length; ++i)
        if (out_[i] != word[i]) return false;
    return true;
}

void TelexEngine::feed(char32_t ch, Action& out) {
    if (ch >= 128) { setSimple(out, Action::Passthrough); return; }
    feedAscii(static_cast<uint8_t>(ch), out);
}

void TelexEngine::takeSnapshots() {
    markCancelled_ = pCancelled_;
    toneCancelAt_ = pToneCancelAt_;
    toneCancelSpan_ = pToneCancelSpan_;
}

void TelexEngine::feedAscii(uint8_t ascii, Action& out) {
    bool bu;
    if (!(isLetter(ascii) || (vniMode && isDigit(ascii)) || (bracketVowels && bracketBase(ascii, bu) != 0))) {
        setSimple(out, Action::Passthrough);
        return;
    }
    if (rawCount_ >= kCapacity) { overflowed_ = true; setSimple(out, Action::Passthrough); return; }

    if (rawCount_ == 0) { reopenRawCount_ = 0; reopenOutCount_ = 0; }

    raw_[rawCount_] = ascii;
    rawCount_ += 1;

    if (pLiveSpellCheck_ != liveSpellCheck) {
        recomputeFreeze();
        rebuildFrozenAware();
    } else if (pProcessed_ != rawCount_ - 1 || pFreeMarking_ != freeMarking ||
               pSimpleTelex_ != simpleTelex || pQuickTelex_ != quickTelex || pVniMode_ != vniMode ||
               pBracketVowels_ != bracketVowels) {
        rebuildFrozenAware();
    } else {
        parseStep(rawCount_ - 1);
        pProcessed_ = rawCount_;
    }

    int newCount = render();
    takeSnapshots();

    // Uppercase tone key in a mixed-case word: freeze the whole word to raw now.
    if (disabledAtCount_ == kNotDisabled && upperToneKey_) {
        disabledAtCount_ = 0;
        rebuildParseState();
        tonesFolded_ = false;
        newCount = render();
        takeSnapshots();
    }

    // Live spell-check freeze (with the teencode elongation escape).
    if (liveSpellCheck && disabledAtCount_ == kNotDisabled && !prefixIsValid(newCount) &&
        elongationHeadCount(newCount, pTone_) <= 0) {
        disabledAtCount_ = rawCount_;
        if (pTone_ != Tone::None) {
            pFoldTones_ = true;
            rebuildParseState();
            pFoldTones_ = false;
            tonesFolded_ = true;
            newCount = render();
            takeSnapshots();
        }
    }

    // Elongation unfreeze.
    if (liveSpellCheck && disabledAtCount_ != kNotDisabled && !upperToneKey_ && rawCount_ >= 2 &&
        raw_[rawCount_ - 1] == raw_[rawCount_ - 2]) {
        recomputeFreeze();
        rebuildFrozenAware();
        newCount = render();
        takeSnapshots();
    }

    // No-transform fast path.
    if (newCount == outCount_ + 1 && scratch_[newCount - 1] == static_cast<char32_t>(ascii) &&
        commonPrefixLength(scratch_, out_, outCount_) == outCount_) {
        copyOut(newCount);
        setSimple(out, Action::Passthrough);
        return;
    }

    diff(newCount, out);
    copyOut(newCount);
}

void TelexEngine::backspace(Action& out) {
    if (rawCount_ <= 0) { setSimple(out, Action::Passthrough); return; }
    if (overflowed_) { setSimple(out, Action::Passthrough); return; }

    rebuildFrozenAware();
    (void)render();

    if (pCount_ == 0) {
        rawCount_ -= 1;
    } else {
        int last = pCount_ - 1;
        int w = 0;
        for (int r = 0; r < rawCount_; ++r)
            if (rawLetter_[r] != last) raw_[w++] = raw_[r];
        rawCount_ = w;
    }

    recomputeFreeze();
    rebuildFrozenAware();
    int newCount = render();
    takeSnapshots();
    diff(newCount, out);
    copyOut(newCount);
}

void TelexEngine::commitBoundary(bool autoRestore, Action& out) {
    setSimple(out, Action::None);
    if (rawCount_ <= 0) { reopenRawCount_ = 0; reopenOutCount_ = 0; resetWord(); return; }
    if (overflowed_) {
        if (contextualEnglish) previousWordEnglish_ = false;
        reopenRawCount_ = 0; reopenOutCount_ = 0;
        resetWord();
        return;
    }
    bool wantsRestore = autoRestore && outCount_ > 0 && shouldRestoreRaw();
    if (wantsRestore && compositionDiffersFromRaw()) {
        int limit = rawCount_ < outCount_ ? rawCount_ : outCount_;
        int lcp = 0;
        while (lcp < limit && static_cast<char32_t>(raw_[lcp]) == out_[lcp]) ++lcp;
        out.kind = Action::Replace;
        out.backspaces = outCount_ - lcp;
        out.length = rawCount_ - lcp;
        for (int i = lcp; i < rawCount_; ++i) out.text[i - lcp] = raw_[i];
        out.text[out.length] = 0;
    }
    captureReopen(wantsRestore);
    updateContext(wantsRestore);
    resetWord();
}

void TelexEngine::captureReopen(bool restored) {
    if (restored || rawCount_ <= 0) { reopenRawCount_ = 0; reopenOutCount_ = 0; return; }
    for (int i = 0; i < rawCount_; ++i) reopenRaw_[i] = raw_[i];
    for (int i = 0; i < outCount_; ++i) reopenOut_[i] = out_[i];
    reopenRawCount_ = rawCount_;
    reopenOutCount_ = outCount_;
    reopenPrevEnglish_ = previousWordEnglish_;
}

int TelexEngine::reopenLastCommit(char16_t* buf, int cap) {
    if (!canReopenLastCommit()) return -1;
    int n = reopenRawCount_;
    int expected = reopenOutCount_;
    bool prevEnglish = reopenPrevEnglish_;
    uint8_t keys[kCapacity];
    char32_t want[kCapacity];
    for (int i = 0; i < n; ++i) keys[i] = reopenRaw_[i];
    for (int i = 0; i < expected; ++i) want[i] = reopenOut_[i];
    reset();
    previousWordEnglish_ = prevEnglish;
    Action a;
    for (int i = 0; i < n; ++i) feedAscii(keys[i], a);
    if (rawCount_ != n || outCount_ != expected) { reset(); return -1; }
    for (int i = 0; i < outCount_; ++i)
        if (out_[i] != want[i]) { reset(); return -1; }
    return emit(out_, outCount_, buf, cap);
}

bool TelexEngine::shouldRestoreRaw() const {
    if (rawCount_ >= 3) {
        bool allW = true;
        for (int i = 0; i < rawCount_; ++i)
            if ((raw_[i] | 0x20) != 'w') { allW = false; break; }
        if (allW) return true;
    }
    if (markCancelled_) {
        if (composedIsValidSyllable()) return false;
        if (toneCancelSpan_ > 1) return !composedIsRecognizedEnglish() || rawIsEnglishContextWord();
        if (toneCancelAt_ >= 0 && toneCancelAt_ < rawCount_ - 1 && rawIsEnglishCollision()) return true;
        if (isTeencodeKeep()) return false;
        // Mark doubler + tone folded at the freeze ("cheese" -> "chese"): restore raw.
        if (toneCancelAt_ < 0 && tonesFolded_) return true;
        return composedHasDiacritic();
    }
    if (rawIsEnglishCollision() && !(collisionPrefersVietnamese && composedIsValidSyllable())) return true;
    if (upperToneKey_ || rawIsEnglishException() || (!composedIsValidSyllable() && !isTeencodeKeep()))
        return true;
    if (contextualEnglish && previousWordEnglish_ &&
        (rawIsEnglishContextWord(true) || (collisionPrefersVietnamese && rawIsEnglishCollision())))
        return true;
    return false;
}

bool TelexEngine::composedHasDiacritic() const {
    if (pTone_ != Tone::None) return true;
    for (int k = 0; k < pCount_; ++k)
        if (letters_[k].mark != Mark::None) return true;
    return false;
}

bool TelexEngine::composedIsRecognizedEnglish() const {
    if (outCount_ < 2 || outCount_ > 12) return false;
    char w[kCapacity];
    int n = lowerAsciiInto(out_, outCount_, 12, w);
    if (n < 0) return false;
    return inEnglishList(gen::kEnglishCollisions, w, n) || inEnglishList(gen::kEnglishContextWords, w, n);
}

bool TelexEngine::isRecognizedEnglish() const {
    return rawIsEnglishContextWord() || rawIsEnglishCollision() || rawIsEnglishException();
}

TelexEngine::WordContext TelexEngine::classifyWordContext(bool restored) const {
    if (!restored && compositionHasDiacritic()) return WordContext::Vietnamese;
    if (isRecognizedEnglish()) return WordContext::English;
    {   // composedAsciiWord
        char w[kCapacity];
        int n = -1;
        if (outCount_ > 0 && outCount_ <= gen::kEnglishContextMaxLength) {
            n = outCount_;
            for (int i = 0; i < outCount_; ++i) {
                char32_t c = out_[i];
                if (c > 127) { n = -1; break; }
                if (c >= 'A' && c <= 'Z') c |= 0x20;
                if (c < 'a' || c > 'z') { n = -1; break; }
                w[i] = static_cast<char>(c);
            }
        }
        if (n > 0) {
            bool neutral = inEnglishList(gen::kNeutralLoanwords, w, n);
            if (inEnglishList(gen::kEnglishContextWords, w, n) || inEnglishList(gen::kEnglishCollisions, w, n) || neutral)
                return neutral ? WordContext::Neutral : WordContext::English;
        }
    }
    if (rawIsNeutralLoanword() || rawIsEnglishContextWord(true)) return WordContext::Neutral;
    if (!restored && SyllableValidator::isValidSyllable(out_, outCount_, teencode)) return WordContext::Vietnamese;
    if (rawCount_ <= 2) return WordContext::Neutral;
    return WordContext::English;
}

bool TelexEngine::rawIsNeutralLoanword() const {
    char w[kCapacity];
    int n = lowerAsciiInto(raw_, rawCount_, gen::kEnglishContextMaxLength, w);
    return n > 0 && inEnglishList(gen::kNeutralLoanwords, w, n);
}

void TelexEngine::updateContext(bool restored) {
    if (!contextualEnglish || rawCount_ <= 0) return;
    switch (classifyWordContext(restored)) {
    case WordContext::English: previousWordEnglish_ = true; break;
    case WordContext::Vietnamese: previousWordEnglish_ = false; break;
    case WordContext::Neutral: break;
    }
}

bool TelexEngine::rawIsEnglishContextWord(bool includingRestoreOnly) const {
    char w[kCapacity];
    int n = lowerAsciiInto(raw_, rawCount_, gen::kEnglishContextMaxLength, w);
    if (n <= 0) return false;
    if (inEnglishList(gen::kEnglishContextWords, w, n)) return true;
    return includingRestoreOnly && inEnglishList(gen::kEnglishRestoreOnly, w, n);
}

void TelexEngine::reset() {
    if (rawCount_ > 0) previousWordEnglish_ = false;
    resetWord();
    reopenRawCount_ = 0;
    reopenOutCount_ = 0;
}

int TelexEngine::commitText(bool autoRestore, char16_t* buf, int cap) {
    int n;
    if (overflowed_) {
        if (contextualEnglish) previousWordEnglish_ = false;
        reopenRawCount_ = 0; reopenOutCount_ = 0;
        n = emit(out_, outCount_, buf, cap);
        resetWord();
        return n;
    }
    bool wantsRestore = autoRestore && outCount_ > 0 && shouldRestoreRaw();
    captureReopen(wantsRestore);
    updateContext(wantsRestore);
    n = wantsRestore ? emitRaw(raw_, rawCount_, buf, cap) : emit(out_, outCount_, buf, cap);
    resetWord();
    return n;
}

int TelexEngine::peekCommitText(bool autoRestore, char16_t* buf, int cap) const {
    if (overflowed_) return emit(out_, outCount_, buf, cap);
    if (autoRestore && outCount_ > 0 && shouldRestoreRaw()) return emitRaw(raw_, rawCount_, buf, cap);
    return emit(out_, outCount_, buf, cap);
}

bool TelexEngine::rawIsEnglishCollision() const {
    if (!englishWordRestore) return false;
    if (rawCount_ < 2 || rawCount_ > 12) return false;
    if (!compositionDiffersFromRaw()) return false;
    if ((raw_[0] | 0x20) == 'w') {
        bool wTransformed = pCount_ > 0 && renderLetters_[0].base == 'u' && renderLetters_[0].mark == Mark::Horn;
        if (!wTransformed) return false;
    }
    char w[kCapacity];
    int n = lowerAsciiInto(raw_, rawCount_, 12, w);
    return n > 0 && inEnglishList(gen::kEnglishCollisions, w, n);
}

bool TelexEngine::rawIsEnglishException() const {
    if (pCount_ <= 0) return false;
    bool wTransformed = renderLetters_[0].base == 'u' && renderLetters_[0].mark == Mark::Horn;
    for (const auto& word : kEnglishExceptions) {
        if (rawCount_ != 3) continue;
        if (word[0] == 'w' && !wTransformed) continue;
        bool match = true;
        for (int i = 0; i < rawCount_; ++i)
            if (lowercased(raw_[i]) != word[i]) { match = false; break; }
        if (match) return true;
    }
    return false;
}

int TelexEngine::teencodeOnset() const {
    if (!teencode || pCount_ < 2 || renderLetters_[0].mark != Mark::None) return 0;
    switch (renderLetters_[0].base) {
    case 'w': return 1;
    case 'z': return 2;
    case 'd':
        if (pCount_ >= 3 && renderLetters_[1].base == 'z' && renderLetters_[1].mark == Mark::None) return 3;
        return 0;
    default: return 0;
    }
}

namespace {
inline int onsetSkip(int code) { return code == 3 ? 2 : 1; }
inline int writeCanon(int code, uint8_t* buf) {
    if (code == 1) { buf[0] = 'q' - 'a'; buf[1] = 'u' - 'a'; return 2; }
    buf[0] = 'd' - 'a';
    return 1;
}
} // namespace

bool TelexEngine::isAbbreviationPrefix(bool upper) const {
    if (pCount_ <= 0) return false;
    for (int k = 0; k < pCount_; ++k) {
        const Letter& l = letters_[k];
        if (isVowelAscii(l.base) || l.upper != upper) return false;
    }
    return true;
}

bool TelexEngine::abbreviationDoublerException(uint8_t lower, bool upper) const {
    return !pVniMode_ && lower == 'd' && isAbbreviationPrefix(upper);
}

bool TelexEngine::composedIsValidSyllable() const {
    if (pCount_ >= 1 && lastEffTone_ == Tone::None && renderLetters_[0].base == 'd' &&
        renderLetters_[0].mark == Mark::Bar) {
        bool bareConsonantsOnly = true;
        for (int k = 1; k < pCount_; ++k) {
            const Letter& l = renderLetters_[k];
            if (l.mark != Mark::None || isVowelAscii(l.base)) { bareConsonantsOnly = false; break; }
        }
        if (bareConsonantsOnly) return true;
    }
    if (lastEffTone_ == Tone::None && rawCount_ >= 2) {
        bool sameCase = true;
        bool firstIsUpper = isUpperAscii(raw_[0]);
        for (int i = 0; i < rawCount_; ++i)
            if (isUpperAscii(raw_[i]) != firstIsUpper) { sameCase = false; break; }
        if (sameCase) {
            bool hasBar = false, onlyBar = true;
            for (int k = 0; k < pCount_; ++k) {
                const Letter& l = renderLetters_[k];
                if (isVowelAscii(l.base)) { onlyBar = false; break; }
                if (l.base == 'd' && l.mark == Mark::Bar) hasBar = true;
                else if (l.mark != Mark::None) { onlyBar = false; break; }
            }
            if (hasBar && onlyBar) return true;
        }
    }
    uint8_t buf[kCapacity + 1];
    int onset = teencodeOnset();
    bool stacksTeencodeRime = pCount_ >= 3 && renderLetters_[pCount_ - 2].base == 'i' &&
                              renderLetters_[pCount_ - 2].mark == Mark::None &&
                              renderLetters_[pCount_ - 1].base == 'e' &&
                              renderLetters_[pCount_ - 1].mark == Mark::None && onset != 0 &&
                              onsetSkip(onset) == pCount_ - 2;
    if (!stacksTeencodeRime && pCount_ < kCapacity - 1 && onset != 0) {
        int n = writeCanon(onset, buf);
        for (int k = onsetSkip(onset); k < pCount_; ++k)
            buf[n++] = letterClass(renderLetters_[k].base, renderLetters_[k].mark);
        if (SyllableValidator::isValidSyllable(buf, n, lastEffTone_, teencode)) return true;
    }
    for (int k = 0; k < pCount_; ++k) buf[k] = letterClass(renderLetters_[k].base, renderLetters_[k].mark);
    return SyllableValidator::isValidSyllable(buf, pCount_, lastEffTone_, teencode);
}

int TelexEngine::elongationHeadCount(int count, Tone tone) const {
    const int minRun = 3;
    if (count < minRun + 1) return -1;
    const Letter& last = renderLetters_[count - 1];
    for (int j = count - minRun; j < count - 1; ++j)
        if (renderLetters_[j].base != last.base || renderLetters_[j].mark != last.mark) return -1;
    int runStart = count - minRun;
    while (runStart > 0 && renderLetters_[runStart - 1].base == last.base &&
           renderLetters_[runStart - 1].mark == last.mark) --runStart;
    if (runStart < 1) runStart = 1;
    for (int k = runStart; k <= count - minRun; ++k)
        if (isValidHead(k, tone)) return k;
    return -1;
}

bool TelexEngine::isValidHead(int k, Tone tone) const {
    if (k < 1 || k > kCapacity) return false;
    Tone t = tone;
    if ((t == Tone::Grave || t == Tone::Hook || t == Tone::Tilde) && hasStopCoda(k) &&
        !(t == Tone::Grave && isUkRime(k))) t = Tone::None;
    uint8_t buf[kCapacity + 1];
    int onset = teencodeOnset();
    if (onset != 0 && onsetSkip(onset) < k) {
        int n = writeCanon(onset, buf);
        for (int j = onsetSkip(onset); j < k; ++j)
            buf[n++] = letterClass(renderLetters_[j].base, renderLetters_[j].mark);
        if (SyllableValidator::isValidSyllable(buf, n, t, teencode)) return true;
    }
    for (int j = 0; j < k; ++j) buf[j] = letterClass(renderLetters_[j].base, renderLetters_[j].mark);
    return SyllableValidator::isValidSyllable(buf, k, t, teencode);
}

bool TelexEngine::compositionDiffersFromRaw() const {
    if (outCount_ != rawCount_) return true;
    for (int i = 0; i < outCount_; ++i)
        if (out_[i] != static_cast<char32_t>(raw_[i])) return true;
    return false;
}

bool TelexEngine::compositionHasDiacritic() const {
    for (int i = 0; i < outCount_; ++i)
        if (out_[i] > 127) return true;
    return false;
}

bool TelexEngine::letterCreatedByW(int idx) const {
    for (int i = 0; i < rawCount_; ++i)
        if (rawLetter_[i] == idx) return raw_[i] == 'w' || raw_[i] == 'W';
    return false;
}

bool TelexEngine::uaUuPredecessorAllowsRetarget(int pred) const {
    Mark m = letters_[pred].mark;
    return m == Mark::None || (m == Mark::Horn && !letterCreatedByW(pred));
}

bool TelexEngine::hasLowercaseBefore(int at) const {
    for (int i = 0; i < at; ++i)
        if (raw_[i] >= 'a' && raw_[i] <= 'z') return true;
    return false;
}

void TelexEngine::resetWord() {
    rawCount_ = 0;
    outCount_ = 0;
    markCancelled_ = false;
    toneCancelAt_ = -1;
    toneCancelSpan_ = 0;
    upperToneKey_ = false;
    overflowed_ = false;
    disabledAtCount_ = kNotDisabled;
    tonesFolded_ = false;
    pCount_ = 0;
    pTone_ = Tone::None;
    pToneKeyCount_ = 0;
    pCancelled_ = false;
    pToneCancelAt_ = -1;
    pToneCancelSpan_ = 0;
    pProcessed_ = 0;
}

bool TelexEngine::prefixIsValid(int n) {
    int o = 0, start = 0;
    if (teencode && n >= 1 && letters_[0].mark == Mark::None && n < kCapacity - 1) {
        switch (letters_[0].base) {
        case 'w': basesScratch_[0] = 'q'; basesScratch_[1] = 'u'; o = 2; start = 1; break;
        case 'z': basesScratch_[0] = 'd'; o = 1; start = 1; break;
        case 'd':
            if (n >= 2 && letters_[1].base == 'z' && letters_[1].mark == Mark::None) {
                basesScratch_[0] = 'd'; o = 1; start = 2;
            }
            break;
        default: break;
        }
    }
    for (int k = start; k < n; ++k)
        basesScratch_[o++] = static_cast<uint8_t>(letters_[k].base | (letters_[k].mark != Mark::None ? 0x80 : 0));
    return SyllableValidator::isValidPrefix(basesScratch_, o, teencode);
}

int TelexEngine::composed(char16_t* buf, int cap) const { return emit(out_, outCount_, buf, cap); }
int TelexEngine::rawKeystrokes(char16_t* buf, int cap) const { return emitRaw(raw_, rawCount_, buf, cap); }

// MARK: - Rendering

void TelexEngine::copyOut(int n) {
    for (int i = 0; i < n; ++i) out_[i] = scratch_[i];
    outCount_ = n;
}

int TelexEngine::render() {
    const int count = pCount_;
    for (int k = 0; k < count; ++k) renderLetters_[k] = letters_[k];

    // ươ propagation.
    for (int k = 1; k < (count > 1 ? count : 1); ++k) {
        if (renderLetters_[k - 1].base != 'u' || renderLetters_[k].base != 'o') continue;
        bool prevHorn = renderLetters_[k - 1].mark == Mark::Horn;
        bool curHorn = renderLetters_[k].mark == Mark::Horn;
        if (prevHorn == curHorn) continue;
        bool oIsLast = (k == count - 1);
        bool isQuGlide = (k >= 2 && renderLetters_[k - 2].base == 'q');
        if (!oIsLast && !isQuGlide) {
            renderLetters_[k - 1].mark = Mark::Horn;
            renderLetters_[k].mark = Mark::Horn;
        }
    }

    Tone effTone = pTone_;
    int toneScope = count;
    if (pTone_ != Tone::None) {
        int head = elongationHeadCount(count, pTone_);
        if (head > 0) toneScope = head;
    }
    int toneIdx = pTone_ == Tone::None ? -1 : toneVowelIndex(toneScope);
    if (toneIdx >= 0 && (effTone == Tone::Grave || effTone == Tone::Hook || effTone == Tone::Tilde) &&
        hasStopCoda(toneScope) && !(effTone == Tone::Grave && isUkRime(toneScope))) {
        effTone = Tone::None;
        toneIdx = -1;
    }
    int target = toneIdx >= 0 ? toneIdx : (count - 1 > 0 ? count - 1 : 0);
    for (int j = 0; j < pToneKeyCount_; ++j) rawLetter_[toneKeys_[j]] = target;
    lastEffTone_ = effTone;

    for (int k = 0; k < count; ++k) {
        const Letter& u = renderLetters_[k];
        char32_t scalar = markedScalar(u.base, u.mark, u.upper);
        if (k == toneIdx) scalar = applyTone(scalar, effTone);
        scratch_[k] = scalar;
    }
    return count;
}

// MARK: - Incremental parse

void TelexEngine::rebuildFrozenAware() {
    rebuildParseState();
    tonesFolded_ = false;
    if (disabledAtCount_ != kNotDisabled && pTone_ != Tone::None) {
        pFoldTones_ = true;
        rebuildParseState();
        pFoldTones_ = false;
        tonesFolded_ = true;
    }
}

// Circumflex the doubler target; an o inside ươ also un-horns the u (ươ -> uô, UniKey).
void TelexEngine::setCircumflex(int k) {
    letters_[k].mark = Mark::Circumflex;
    if (letters_[k].base == 'o' && k >= 1 && letters_[k - 1].base == 'u' &&
        letters_[k - 1].mark == Mark::Horn)
        letters_[k - 1].mark = Mark::None;
}

void TelexEngine::recomputeFreeze() {
    if (disabledAtCount_ == 0 && upperToneKey_ && !liveSpellCheck) return;
    const int full = rawCount_;
    disabledAtCount_ = kNotDisabled;
    if (!liveSpellCheck) return;
    for (int r = 1; r <= full; ++r) {
        rawCount_ = r;
        rebuildParseState();
        if (disabledAtCount_ == kNotDisabled && pCount_ > 0 && !prefixIsValid(pCount_)) {
            (void)render();
            if (elongationHeadCount(pCount_, pTone_) <= 0) disabledAtCount_ = r;
        }
    }
    rawCount_ = full;
    if (disabledAtCount_ != kNotDisabled) {
        int frozenAt = disabledAtCount_;
        disabledAtCount_ = kNotDisabled;
        rebuildParseState();
        (void)render();
        if (elongationHeadCount(pCount_, pTone_) <= 0) disabledAtCount_ = frozenAt;
    }
}

void TelexEngine::rebuildParseState() {
    pCount_ = 0;
    pTone_ = Tone::None;
    pToneKeyCount_ = 0;
    pCancelled_ = false;
    pToneCancelAt_ = -1;
    pToneCancelSpan_ = 0;
    upperToneKey_ = false;
    pFreeMarking_ = freeMarking;
    pSimpleTelex_ = simpleTelex;
    pQuickTelex_ = quickTelex;
    pVniMode_ = vniMode;
    pBracketVowels_ = bracketVowels;
    pLiveSpellCheck_ = liveSpellCheck;
    for (int i = 0; i < rawCount_; ++i) rawLetter_[i] = -1;
    for (int i = 0; i < rawCount_; ++i) parseStep(i);
    pProcessed_ = rawCount_;
}

void TelexEngine::parseStep(int at) {
    const uint8_t key = raw_[at];
    const uint8_t lower = lowercased(key);
    const bool upper = isUpperAscii(key);

    if (pCancelled_ || (at >= disabledAtCount_ && !abbreviationDoublerException(lower, upper))) {
        appendLetter(lower, Mark::None, upper);
        rawLetter_[at] = pCount_ - 1;
        return;
    }

    bool bUpper = false;
    if (pBracketVowels_) {
        uint8_t b = bracketBase(key, bUpper);
        if (b != 0) {
            appendLetter(b, Mark::Horn, bUpper);
            rawLetter_[at] = pCount_ - 1;
            return;
        }
    }

    if (pVniMode_) { parseStepVNI(at, key, lower, upper); return; }

    // Tone keys: s f r x j
    Tone t = toneForKey(lower);
    if (t != Tone::None) {
        if (pFoldTones_) {
            appendLetter(lower, Mark::None, upper);
            rawLetter_[at] = pCount_ - 1;
            return;
        }
        if (hasVowel(pCount_)) {
            if (pTone_ == t) {
                pTone_ = Tone::None;
                pCancelled_ = true;
                pToneCancelAt_ = at;
                pToneCancelSpan_ = pToneKeyCount_ > 0 ? at - toneKeys_[pToneKeyCount_ - 1] : 1;
                appendLetter(lower, Mark::None, upper);
                rawLetter_[at] = pCount_ - 1;
                for (int j = 0; j < pToneKeyCount_; ++j)
                    if (rawLetter_[toneKeys_[j]] == -1) rawLetter_[toneKeys_[j]] = pCount_ - 1;
                pToneKeyCount_ = 0;
            } else if (stopCodaRejectsTone(t)) {
                appendLetter(lower, Mark::None, upper);
                rawLetter_[at] = pCount_ - 1;
            } else {
                pTone_ = t;
                if (upper && hasLowercaseBefore(at)) upperToneKey_ = true;
                rawLetter_[at] = -1;
                toneKeys_[pToneKeyCount_++] = at;
            }
        } else {
            appendLetter(lower, Mark::None, upper);
            rawLetter_[at] = pCount_ - 1;
        }
        return;
    }

    // z: clear tone if there is one; otherwise literal.
    if (lower == 'z') {
        if (pTone_ != Tone::None) {
            pToneCancelAt_ = at;
            pToneCancelSpan_ = pToneKeyCount_ > 0 ? at - toneKeys_[pToneKeyCount_ - 1] : 1;
            pTone_ = Tone::None;
            if (upper && hasLowercaseBefore(at)) upperToneKey_ = true;
            rawLetter_[at] = -1;
            toneKeys_[pToneKeyCount_++] = at;
        } else {
            appendLetter(lower, Mark::None, upper);
            rawLetter_[at] = pCount_ - 1;
        }
        return;
    }

    // w: breve / horn modifier, or standalone ư.
    if (lower == 'w') {
        int tIdx = -1;
        for (int k = pCount_ - 1; k >= 0; --k) {
            uint8_t b = letters_[k].base;
            if (b == 'a' || b == 'o' || b == 'u') { tIdx = k; break; }
            if (!freeMarking && !isVowelAscii(b)) break;
        }
        if (tIdx >= 1 && letters_[tIdx].base == 'a' && letters_[tIdx].mark == Mark::None &&
            letters_[tIdx - 1].base == 'u' && uaUuPredecessorAllowsRetarget(tIdx - 1) &&
            !(tIdx >= 2 && letters_[tIdx - 2].base == 'q'))
            tIdx -= 1;
        if (tIdx >= 1 && letters_[tIdx].base == 'u' && letters_[tIdx].mark == Mark::None &&
            letters_[tIdx - 1].base == 'u' && uaUuPredecessorAllowsRetarget(tIdx - 1) &&
            !(tIdx >= 2 && letters_[tIdx - 2].base == 'q'))
            tIdx -= 1;
        if (tIdx >= 0) {
            const Letter p = letters_[tIdx];
            if (p.mark == Mark::None && p.base == 'a') {
                letters_[tIdx].mark = Mark::Breve; rawLetter_[at] = tIdx; return;
            }
            if (p.mark == Mark::None && (p.base == 'o' || p.base == 'u')) {
                letters_[tIdx].mark = Mark::Horn; rawLetter_[at] = tIdx; return;
            }
            if (p.mark == Mark::Breve && p.base == 'a') {
                letters_[tIdx].mark = Mark::None;
                pCancelled_ = true;
                appendLetter('w', Mark::None, upper);
                rawLetter_[at] = pCount_ - 1; return;
            }
            if (p.mark == Mark::Horn && (p.base == 'o' || p.base == 'u')) {
                letters_[tIdx].mark = Mark::None;
                pCancelled_ = true;
                if (p.base == 'u' && letterCreatedByW(tIdx)) {
                    letters_[tIdx].base = 'w';
                    rawLetter_[at] = tIdx;
                    return;
                }
                appendLetter('w', Mark::None, upper);
                rawLetter_[at] = pCount_ - 1; return;
            }
        }
        if (!simpleTelex && standaloneHornUAllowed(pCount_)) appendLetter('u', Mark::Horn, upper);
        else appendLetter('w', Mark::None, upper);
        rawLetter_[at] = pCount_ - 1;
        return;
    }

    // circumflex doublers: a e o
    if (lower == 'a' || lower == 'e' || lower == 'o') {
        if (pCount_ > 0) {
            int pIdx = pCount_ - 1;
            const Letter p = letters_[pIdx];
            if (p.base == lower && p.mark == Mark::None) {
                setCircumflex(pIdx); rawLetter_[at] = pIdx; return;
            }
            // `o` on ơ (ươ cluster): hook -> hat ("mơ"+o -> mô).
            if (lower == 'o' && p.base == lower && p.mark == Mark::Horn) {
                setCircumflex(pIdx); rawLetter_[at] = pIdx; return;
            }
            if (p.base == lower && p.mark == Mark::Circumflex) {
                letters_[pIdx].mark = Mark::None;
                pCancelled_ = true;
                appendLetter(lower, Mark::None, upper);
                rawLetter_[at] = pCount_ - 1; return;
            }
        }
        if (freeMarking) {
            int k = pCount_ - 1;
            while (k >= 0 && !isVowelAscii(letters_[k].base)) --k;
            const int nucleusEnd = k;
            while (k >= 0 && isVowelAscii(letters_[k].base)) {
                // "lươn" + o -> "luôn": the reach-back also retargets a horned o.
                if (letters_[k].base == lower &&
                    (letters_[k].mark == Mark::None || (lower == 'o' && letters_[k].mark == Mark::Horn))) {
                    if (lower == 'o' && nucleusEnd == pCount_ - 1 && k == pCount_ - 2 &&
                        letters_[k + 1].mark == Mark::None &&
                        (letters_[k + 1].base == 'e' || letters_[k + 1].base == 'a'))
                        break;   // -> literal o ("oeo"/"oao" rimes)
                    setCircumflex(k); rawLetter_[at] = k; return;
                }
                if (letters_[k].base == lower && letters_[k].mark == Mark::Circumflex) {
                    letters_[k].mark = Mark::None;
                    pCancelled_ = true;
                    appendLetter(lower, Mark::None, upper);
                    rawLetter_[at] = pCount_ - 1; return;
                }
                --k;
            }
        }
        appendLetter(lower, Mark::None, upper);
        rawLetter_[at] = pCount_ - 1;
        return;
    }

    // d doubler -> đ
    if (lower == 'd') {
        if (pCount_ > 0) {
            int pIdx = pCount_ - 1;
            const Letter p = letters_[pIdx];
            if (p.base == 'd' && p.mark == Mark::None) {
                letters_[pIdx].mark = Mark::Bar; rawLetter_[at] = pIdx; return;
            }
            if (p.base == 'd' && p.mark == Mark::Bar) {
                letters_[pIdx].mark = Mark::None;
                pCancelled_ = true;
                appendLetter('d', Mark::None, upper);
                rawLetter_[at] = pCount_ - 1; return;
            }
        }
        if (freeMarking && pCount_ > 1 && letters_[0].base == 'd' && letters_[0].mark == Mark::None) {
            letters_[0].mark = Mark::Bar; rawLetter_[at] = 0; return;
        }
        if (freeMarking && pCount_ > 1 && letters_[0].base == 'd' && letters_[0].mark == Mark::Bar &&
            letters_[pCount_ - 1].base != 'd') {
            letters_[0].mark = Mark::None;
            pCancelled_ = true;
            appendLetter('d', Mark::None, upper);
            rawLetter_[at] = pCount_ - 1; return;
        }
        appendLetter('d', Mark::None, upper);
        rawLetter_[at] = pCount_ - 1;
        return;
    }

    // Quick Telex: word-initial doubled onset consonant -> digraph.
    if (quickTelex && pCount_ == 1 && letters_[0].base == lower && letters_[0].mark == Mark::None) {
        uint8_t second = quickTelexSecond(lower);
        if (second != 0) {
            appendLetter(second, Mark::None, upper);
            rawLetter_[at] = pCount_ - 1;
            return;
        }
    }

    appendLetter(lower, Mark::None, upper);
    rawLetter_[at] = pCount_ - 1;
}

void TelexEngine::parseStepVNI(int at, uint8_t key, uint8_t lower, bool upper) {
    if (!isDigit(key)) {
        appendLetter(lower, Mark::None, upper);
        rawLetter_[at] = pCount_ - 1;
        return;
    }
    const Tone t = vniTone(key);
    if (pFoldTones_ && t != Tone::None) {
        appendLetter(key, Mark::None, false);
        rawLetter_[at] = pCount_ - 1;
        return;
    }
    if (t != Tone::None) {
        if (hasVowel(pCount_)) {
            if (pTone_ == t) {
                pTone_ = Tone::None;
                pCancelled_ = true;
                pToneCancelAt_ = at;
                pToneCancelSpan_ = pToneKeyCount_ > 0 ? at - toneKeys_[pToneKeyCount_ - 1] : 1;
                appendLetter(key, Mark::None, false);
                rawLetter_[at] = pCount_ - 1;
                for (int j = 0; j < pToneKeyCount_; ++j)
                    if (rawLetter_[toneKeys_[j]] == -1) rawLetter_[toneKeys_[j]] = pCount_ - 1;
                pToneKeyCount_ = 0;
            } else if (stopCodaRejectsTone(t)) {
                appendLetter(key, Mark::None, false);
                rawLetter_[at] = pCount_ - 1;
            } else {
                pTone_ = t;
                rawLetter_[at] = -1;
                toneKeys_[pToneKeyCount_++] = at;
            }
        } else {
            appendLetter(key, Mark::None, false);
            rawLetter_[at] = pCount_ - 1;
        }
        return;
    }
    if (key == '0') {
        if (pTone_ != Tone::None) {
            pToneCancelAt_ = at;
            pToneCancelSpan_ = pToneKeyCount_ > 0 ? at - toneKeys_[pToneKeyCount_ - 1] : 1;
            pTone_ = Tone::None;
            rawLetter_[at] = -1;
            toneKeys_[pToneKeyCount_++] = at;
        } else {
            appendLetter(key, Mark::None, false);
            rawLetter_[at] = pCount_ - 1;
        }
        return;
    }
    const Mark mark = vniMark(key);
    if (mark != Mark::None) {
        for (int k = pCount_ - 1; k >= 0; --k) {
            if (vniMarkAccepts(letters_[k].base, mark)) {
                int target = k;
                if (mark == Mark::Horn && target >= 1 && letters_[target].base == 'u' &&
                    letters_[target].mark == Mark::None && letters_[target - 1].base == 'u' &&
                    !(target >= 2 && letters_[target - 2].base == 'q'))
                    target -= 1;
                if (letters_[target].mark == Mark::None) {
                    letters_[target].mark = mark;
                    rawLetter_[at] = target;
                    return;
                }
                if (letters_[target].mark == mark) {
                    letters_[target].mark = Mark::None;
                    pCancelled_ = true;
                    appendLetter(key, Mark::None, false);
                    rawLetter_[at] = pCount_ - 1;
                    return;
                }
                break;   // conflicting mark -> literal digit
            }
        }
        appendLetter(key, Mark::None, false);
        rawLetter_[at] = pCount_ - 1;
        return;
    }
    appendLetter(key, Mark::None, false);
    rawLetter_[at] = pCount_ - 1;
}

// MARK: - Tone placement (old style: òa, úy)

int TelexEngine::toneVowelIndex(int count) {
    int vcount = 0;
    int start = 0;
    if (count >= 2 && renderLetters_[0].base == 'q' && renderLetters_[1].base == 'u' &&
        renderLetters_[1].mark == Mark::None) {
        start = 2;
    } else if (count >= 3 && renderLetters_[0].base == 'g' && renderLetters_[1].base == 'i' &&
               renderLetters_[1].mark == Mark::None && isVowelAscii(renderLetters_[2].base)) {
        start = 2;
    }
    for (int k = start; k < count; ++k)
        if (isVowelAscii(renderLetters_[k].base)) vowelIdx_[vcount++] = k;
    if (vcount == 0) {
        for (int k = 0; k < count; ++k)
            if (isVowelAscii(renderLetters_[k].base)) return k;
        return count - 1;
    }
    int lastMarked = -1;
    for (int j = 0; j < vcount; ++j)
        if (renderLetters_[vowelIdx_[j]].mark != Mark::None) lastMarked = vowelIdx_[j];
    if (lastMarked >= 0) return lastMarked;
    if (vcount == 1) return vowelIdx_[0];
    const bool hasCoda = vowelIdx_[vcount - 1] < (count - 1);
    if (vcount == 2) {
        if (hasCoda) return vowelIdx_[1];
        if (modernTone) {
            uint8_t a = renderLetters_[vowelIdx_[0]].base, b = renderLetters_[vowelIdx_[1]].base;
            bool glideInitial = (a == 'o' && (b == 'a' || b == 'e')) || (a == 'u' && b == 'y');
            if (glideInitial) return vowelIdx_[1];
        }
        return vowelIdx_[0];
    }
    return vowelIdx_[1];
}

// MARK: - Diffing

void TelexEngine::diff(int newCount, Action& out) const {
    int lcp = commonPrefixLength(scratch_, out_, newCount < outCount_ ? newCount : outCount_);
    int backspaces = outCount_ - lcp;
    if (backspaces == 0 && lcp == newCount) { setReplace(out, 0, scratch_, 0); return; }
    setReplace(out, backspaces, scratch_ + lcp, newCount - lcp);
}

// MARK: - Small helpers

bool TelexEngine::standaloneHornUAllowed(int count) const {
    int32_t node = 0;
    for (int k = 0; k < count; ++k) {
        node = gen::kStandaloneU.step(node, static_cast<uint8_t>(letters_[k].base - 'a'));
        if (node < 0) return false;
    }
    return gen::kStandaloneU.mask(node) != 0;
}

bool TelexEngine::hasVowel(int count) const {
    for (int k = 0; k < count; ++k)
        if (isVowelAscii(letters_[k].base)) return true;
    return false;
}

bool TelexEngine::isUkRime(int count) const {
    return count >= 2 && renderLetters_[count - 1].base == 'k' && renderLetters_[count - 2].base == 'u' &&
           renderLetters_[count - 2].mark == Mark::Horn;
}

bool TelexEngine::hasStopCoda(int count) const {
    if (count <= 0) return false;
    uint8_t last = renderLetters_[count - 1].base;
    if (last == 'p' || last == 't' || last == 'c' || last == 'k') return true;
    return last == 'h' && count >= 2 && renderLetters_[count - 2].base == 'c';
}

bool TelexEngine::lettersHaveStopCoda(int count) const {
    if (count <= 0) return false;
    uint8_t last = letters_[count - 1].base;
    if (last == 'p' || last == 't' || last == 'c' || last == 'k') return true;
    return last == 'h' && count >= 2 && letters_[count - 2].base == 'c';
}

bool TelexEngine::lettersAreUkRime(int count) const {
    return count >= 2 && letters_[count - 1].base == 'k' && letters_[count - 2].base == 'u' &&
           letters_[count - 2].mark == Mark::Horn;
}

bool TelexEngine::stopCodaRejectsTone(Tone tone) const {
    if (!(tone == Tone::Grave || tone == Tone::Hook || tone == Tone::Tilde)) return false;
    if (!lettersHaveStopCoda(pCount_)) return false;
    if (tone == Tone::Grave && lettersAreUkRime(pCount_)) return false;
    return true;
}

void TelexEngine::appendLetter(uint8_t base, Mark mark, bool upper) {
    if (pCount_ >= kCapacity) return;
    letters_[pCount_] = Letter{base, mark, upper};
    pCount_ += 1;
}

} // namespace vtx
