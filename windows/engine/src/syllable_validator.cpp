// Port of TelexCore/Sources/TelexCore/SyllableValidator.swift. Rule tables are
// compiled offline (tools/gen_tables.py) into flat class tries; the checks below walk
// them over byte buffers — no strings, no hashing, no heap.
#include "viettelex/telex_engine.hpp"
#include "generated_tables.hpp"
#include "tables.hpp"

namespace vtx { namespace SyllableValidator {

using namespace tables;

namespace {
inline uint8_t cA(char c) { return static_cast<uint8_t>(c - 'a'); }

/// Standard spelling: onset `k` only before i / e / ê / y.
inline bool kOnsetAllows(uint8_t c) { return c == cA('i') || c == cA('e') || c == 28 || c == cA('y'); }

struct Accept {
    const uint8_t* classes; int n; Tone tone; bool teencode;
    const ClassTrie& onsetT; const ClassTrie& rimeT;
    bool operator()(int onsetEnd, int rimeStart) const {
        int32_t node = 0;
        for (int k = 0; k < onsetEnd; ++k) {
            node = onsetT.step(node, classes[k]);
            if (node < 0) return false;
        }
        if (onsetT.mask(node) == 0) return false;
        if (!teencode && onsetEnd == 1 && classes[0] == cA('k') && rimeStart < n &&
            !kOnsetAllows(classes[rimeStart])) return false;
        int32_t rnode = 0;
        for (int k = rimeStart; k < n; ++k) {
            rnode = rimeT.step(rnode, classes[k]);
            if (rnode < 0) return false;
        }
        return ((rimeT.mask(rnode) >> static_cast<int>(tone)) & 1) == 1;
    }
};
} // namespace

bool isValidSyllable(const uint8_t* classes, int n, Tone tone, bool teencode) {
    if (n == 0) return false;
    // TEENCODE "òy": zero onset only.
    if (teencode && n == 2 && classes[0] == cA('o') && classes[1] == cA('y')) return true;
    // TEENCODE "-òy", huyền only, onsets g/r/z/h (n==3) or dz/ch (n==4).
    if (teencode && n >= 3 && tone == Tone::Grave && classes[n - 2] == cA('o') &&
        classes[n - 1] == cA('y')) {
        if (n == 3 && (classes[0] == cA('g') || classes[0] == cA('r') || classes[0] == cA('z') ||
                       classes[0] == cA('h'))) return true;
        if (n == 4 && ((classes[0] == cA('d') && classes[1] == cA('z')) ||
                       (classes[0] == cA('c') && classes[1] == cA('h')))) return true;
    }
    // TEENCODE "đou" (exactly one word).
    if (teencode && n == 3 && tone == Tone::None && classes[0] == 32 && classes[1] == cA('o') &&
        classes[2] == cA('u')) return true;

    const ClassTrie& onsetT = teencode ? gen::kOnsetExact : gen::kOnsetExactStd;
    const ClassTrie& rimeT = teencode ? gen::kRimeExact : gen::kRimeExactStd;

    int pos = 0;
    while (pos < n && !isVowelClass(classes[pos])) ++pos;
    int onsetEnd = pos;
    bool quGlide = false;
    if (pos >= 1 && classes[0] == cA('q') && pos < n && classes[pos] == cA('u') && pos + 1 < n &&
        isVowelClass(classes[pos + 1])) {
        onsetEnd = pos + 1;
        quGlide = true;
    } else if (n >= 3 && classes[0] == cA('g') && classes[1] == cA('i') && isVowelClass(classes[2])) {
        onsetEnd = 2;
    }
    Accept accepts{classes, n, tone, teencode, onsetT, rimeT};
    if (accepts(onsetEnd, onsetEnd)) return true;
    if (quGlide && accepts(onsetEnd, pos)) return true;
    return onsetEnd != pos && accepts(pos, pos);
}

bool isValidSyllable(const char32_t* word, int length, bool teencode) {
    if (length <= 0) return false;
    if (length > 64) return false;   // far beyond any syllable; keeps the buffer bounded
    uint8_t classes[64];
    Tone tone = Tone::None;
    for (int i = 0; i < length; ++i) {
        char32_t ch = lowerVi(word[i]);
        char32_t toneless = ch;
        int row; Tone t;
        if (detone(ch, row, t)) {
            toneless = kTonedGroups[row][0];
            if (t != Tone::None) {
                if (tone != Tone::None) return false;   // two tones
                tone = t;
            }
        }
        int cls = charClass(toneless);
        if (cls < 0) return false;
        classes[i] = static_cast<uint8_t>(cls);
    }
    return isValidSyllable(classes, length, tone, teencode);
}

bool isValidPrefix(const uint8_t* bases, int n, bool teencode) {
    if (n == 0) return true;
    const ClassTrie& onsetF = teencode ? gen::kOnsetFolded : gen::kOnsetFoldedStd;
    const ClassTrie& rimeF = teencode ? gen::kRimeFolded : gen::kRimeFoldedStd;
    auto cls = [&](int i) { return static_cast<uint8_t>((bases[i] & 0x7F) - 'a'); };
    for (int i = 0; i < n; ++i)
        if (!isLetter(bases[i] & 0x7F)) return false;

    int pos = 0;
    while (pos < n && !isVowelAscii(bases[pos] & 0x7F)) ++pos;
    if (pos == n) {
        int32_t node = 0;
        for (int i = 0; i < n; ++i) {
            node = onsetF.step(node, cls(i));
            if (node < 0) return false;
        }
        return true;
    }
    if (teencode && n == 2 && bases[0] == 'o' && bases[1] == 'y') return true;
    if (teencode && n >= 3 && bases[n - 2] == 'o' && bases[n - 1] == 'y') {
        uint8_t b0 = bases[0] & 0x7F, b1 = bases[1] & 0x7F;
        if (n == 3 && (b0 == 'g' || b0 == 'r' || b0 == 'z' || b0 == 'd' || b0 == 'h')) return true;
        if (n == 4 && ((b0 == 'd' && b1 == 'z') || (b0 == 'c' && b1 == 'h'))) return true;
    }
    if (teencode && n == 3 && (bases[0] & 0x7F) == 'd' && bases[1] == 'o' && bases[2] == 'u') return true;

    int quAlt = ((bases[0] & 0x7F) == 'q' && bases[pos] == 'u') ? pos + 1 : -1;
    int giAlt = ((bases[0] & 0x7F) == 'g' && n >= 2 && bases[1] == 'i') ? 2 : -1;
    const int cand[4][2] = {{pos, pos}, {quAlt, quAlt}, {giAlt, giAlt}, {quAlt, pos}};
    for (const auto& c : cand) {
        int onsetEnd = c[0], rimeStart = c[1];
        if (onsetEnd < 0 || onsetEnd > n) continue;
        int32_t node = 0;
        bool ok = true;
        for (int i = 0; i < onsetEnd; ++i) {
            node = onsetF.step(node, cls(i));
            if (node < 0) { ok = false; break; }
        }
        if (!ok || onsetF.mask(node) == 0) continue;
        int32_t rnode = 0;
        ok = true;
        for (int i = rimeStart; i < n; ++i) {
            rnode = rimeF.step(rnode, cls(i));
            if (rnode < 0) { ok = false; break; }
        }
        if (ok) return true;
    }
    return false;
}

bool isValidPrefix(const char32_t* word, int length, bool teencode) {
    if (length <= 0) return true;
    if (length > 64) return false;
    uint8_t bases[64];
    for (int i = 0; i < length; ++i) {
        char32_t ch = lowerVi(word[i]);
        char32_t toneless = ch;
        int row; Tone t;
        if (detone(ch, row, t)) toneless = kTonedGroups[row][0];
        if (charClass(toneless) < 0) return false;
        char32_t folded = toneless;
        switch (toneless) {
        case U'ă': case U'â': folded = 'a'; break;
        case U'ê': folded = 'e'; break;
        case U'ô': case U'ơ': folded = 'o'; break;
        case U'ư': folded = 'u'; break;
        case U'đ': folded = 'd'; break;
        default: break;
        }
        bases[i] = static_cast<uint8_t>(folded | (folded == toneless ? 0 : 0x80));
    }
    return isValidPrefix(bases, length, teencode);
}

}} // namespace vtx::SyllableValidator
