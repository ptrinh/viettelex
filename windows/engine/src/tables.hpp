// Port of TelexCore/Sources/TelexCore/Tables.swift — constant lookup tables.
#pragma once
#include <cstdint>
#include <string_view>
#include "viettelex/telex_engine.hpp"

namespace vtx { namespace tables {

// Each group: base (toneless), acute, grave, hook, tilde, dot. Rows 0-11 lower,
// 12-23 upper (same order), so row r's lowercase twin is r - 12.
constexpr char16_t kTonedGroups[24][6] = {
    {u'a', u'á', u'à', u'ả', u'ã', u'ạ'}, {u'ă', u'ắ', u'ằ', u'ẳ', u'ẵ', u'ặ'},
    {u'â', u'ấ', u'ầ', u'ẩ', u'ẫ', u'ậ'}, {u'e', u'é', u'è', u'ẻ', u'ẽ', u'ẹ'},
    {u'ê', u'ế', u'ề', u'ể', u'ễ', u'ệ'}, {u'i', u'í', u'ì', u'ỉ', u'ĩ', u'ị'},
    {u'o', u'ó', u'ò', u'ỏ', u'õ', u'ọ'}, {u'ô', u'ố', u'ồ', u'ổ', u'ỗ', u'ộ'},
    {u'ơ', u'ớ', u'ờ', u'ở', u'ỡ', u'ợ'}, {u'u', u'ú', u'ù', u'ủ', u'ũ', u'ụ'},
    {u'ư', u'ứ', u'ừ', u'ử', u'ữ', u'ự'}, {u'y', u'ý', u'ỳ', u'ỷ', u'ỹ', u'ỵ'},
    {u'A', u'Á', u'À', u'Ả', u'Ã', u'Ạ'}, {u'Ă', u'Ắ', u'Ằ', u'Ẳ', u'Ẵ', u'Ặ'},
    {u'Â', u'Ấ', u'Ầ', u'Ẩ', u'Ẫ', u'Ậ'}, {u'E', u'É', u'È', u'Ẻ', u'Ẽ', u'Ẹ'},
    {u'Ê', u'Ế', u'Ề', u'Ể', u'Ễ', u'Ệ'}, {u'I', u'Í', u'Ì', u'Ỉ', u'Ĩ', u'Ị'},
    {u'O', u'Ó', u'Ò', u'Ỏ', u'Õ', u'Ọ'}, {u'Ô', u'Ố', u'Ồ', u'Ổ', u'Ỗ', u'Ộ'},
    {u'Ơ', u'Ớ', u'Ờ', u'Ở', u'Ỡ', u'Ợ'}, {u'U', u'Ú', u'Ù', u'Ủ', u'Ũ', u'Ụ'},
    {u'Ư', u'Ứ', u'Ừ', u'Ử', u'Ữ', u'Ự'}, {u'Y', u'Ý', u'Ỳ', u'Ỷ', u'Ỹ', u'Ỵ'},
};

constexpr int kTonelessLimit = 0x200;

struct TonedRowTable {
    int8_t row[kTonelessLimit];
    constexpr TonedRowTable() : row() {
        for (int i = 0; i < kTonelessLimit; ++i) row[i] = -1;
        for (int r = 0; r < 24; ++r) row[kTonedGroups[r][0]] = static_cast<int8_t>(r);
    }
};
constexpr TonedRowTable kTonedRow{};

/// Apply a tone to a toneless (possibly marked) vowel scalar.
inline char32_t applyTone(char32_t scalar, Tone tone) {
    if (tone == Tone::None || scalar >= static_cast<char32_t>(kTonelessLimit)) return scalar;
    int r = kTonedRow.row[scalar];
    if (r < 0) return scalar;
    return kTonedGroups[r][static_cast<int>(tone)];
}

/// Detone: toned (or toneless) vowel -> row + tone. false if not a table vowel.
inline bool detone(char32_t scalar, int& row, Tone& tone) {
    if (scalar > 0x1EF9) return false;
    for (int r = 0; r < 24; ++r)
        for (int t = 0; t < 6; ++t)
            if (static_cast<char32_t>(kTonedGroups[r][t]) == scalar) { row = r; tone = static_cast<Tone>(t); return true; }
    return false;
}

/// Lowercase for every letter the engine can emit (ascii, table vowels, Đ).
inline char32_t lowerVi(char32_t c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    if (c < 0x80) return c;
    if (c == 0x110) return 0x111;   // Đ -> đ
    int row; Tone t;
    if (detone(c, row, t) && row >= 12) return kTonedGroups[row - 12][static_cast<int>(t)];
    return c;
}
inline bool isUpperVi(char32_t c) {
    if (c >= 'A' && c <= 'Z') return true;
    if (c == 0x110) return true;
    int row; Tone t;
    return c >= 0x80 && detone(c, row, t) && row >= 12;
}

/// Compose a base ascii letter (lowercase) + mark into a toneless scalar value.
inline char32_t markedScalar(uint8_t base, Mark mark, bool upper) {
    if (mark != Mark::None) {
        switch (base) {
        case 'a':
            if (mark == Mark::Circumflex) return upper ? U'Â' : U'â';
            if (mark == Mark::Breve) return upper ? U'Ă' : U'ă';
            break;
        case 'e': if (mark == Mark::Circumflex) return upper ? U'Ê' : U'ê'; break;
        case 'o':
            if (mark == Mark::Circumflex) return upper ? U'Ô' : U'ô';
            if (mark == Mark::Horn) return upper ? U'Ơ' : U'ơ';
            break;
        case 'u': if (mark == Mark::Horn) return upper ? U'Ư' : U'ư'; break;
        case 'd': if (mark == Mark::Bar) return upper ? U'Đ' : U'đ'; break;
        default: break;
        }
    }
    return static_cast<char32_t>(static_cast<uint8_t>(upper ? base - 32 : base));
}

/// 0-25 = bare a-z; 26-32 = â ă ê ô ơ ư đ. Wraps like Swift `&-` for non-letters.
inline uint8_t letterClass(uint8_t base, Mark mark) {
    if (mark != Mark::None) {
        switch (base) {
        case 'a':
            if (mark == Mark::Circumflex) return 26;
            if (mark == Mark::Breve) return 27;
            break;
        case 'e': if (mark == Mark::Circumflex) return 28; break;
        case 'o':
            if (mark == Mark::Circumflex) return 29;
            if (mark == Mark::Horn) return 30;
            break;
        case 'u': if (mark == Mark::Horn) return 31; break;
        case 'd': if (mark == Mark::Bar) return 32; break;
        default: break;
        }
    }
    return static_cast<uint8_t>(base - 'a');
}

/// Character -> class (lowercase toneless letters only), -1 = unmappable.
inline int charClass(char32_t c) {
    if (c >= 'a' && c <= 'z') return static_cast<int>(c - 'a');
    switch (c) {
    case U'â': return 26; case U'ă': return 27; case U'ê': return 28; case U'ô': return 29;
    case U'ơ': return 30; case U'ư': return 31; case U'đ': return 32;
    default: return -1;
    }
}

constexpr uint64_t kVowelClassMask =
    (1ull << 0) | (1ull << 4) | (1ull << 8) | (1ull << 14) | (1ull << 20) | (1ull << 24) |
    (1ull << 26) | (1ull << 27) | (1ull << 28) | (1ull << 29) | (1ull << 30) | (1ull << 31);

inline bool isVowelClass(uint8_t c) { return c < 64 && ((kVowelClassMask >> c) & 1u); }

constexpr uint32_t kAsciiVowelMask =
    (1u << 0) | (1u << 4) | (1u << 8) | (1u << 14) | (1u << 20) | (1u << 24);

inline bool isVowelAscii(uint8_t c) {
    uint8_t i = static_cast<uint8_t>(c - 'a');
    return i < 26 && ((kAsciiVowelMask >> i) & 1u);
}

inline Tone toneForKey(uint8_t c) {
    switch (c) {
    case 's': return Tone::Acute; case 'f': return Tone::Grave; case 'r': return Tone::Hook;
    case 'x': return Tone::Tilde; case 'j': return Tone::Dot;
    default: return Tone::None;
    }
}

inline bool isLetter(uint8_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
inline bool isDigit(uint8_t c) { return c >= '0' && c <= '9'; }
inline bool isUpperAscii(uint8_t c) { return c >= 'A' && c <= 'Z'; }
inline uint8_t lowercased(uint8_t c) { return isUpperAscii(c) ? static_cast<uint8_t>(c + 32) : c; }

/// Binary search a sorted word table with a lowercase ascii buffer.
template <size_t N>
inline bool contains(const std::string_view (&set)[N], const char* w, int len) {
    std::string_view key(w, static_cast<size_t>(len));
    size_t lo = 0, hi = N;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        int c = set[mid].compare(key);
        if (c == 0) return true;
        if (c < 0) lo = mid + 1; else hi = mid;
    }
    return false;
}

}} // namespace vtx::tables
