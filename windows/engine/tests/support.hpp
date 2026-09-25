// Test helpers (heap use is fine here — tests only).
#pragma once
#include <cstdio>
#include <string>
#include "viettelex/telex_engine.hpp"

namespace vt {

inline std::u32string fromUtf8(const std::string& s) {
    std::u32string o;
    for (size_t i = 0; i < s.size();) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        char32_t cp; int n;
        if (c < 0x80) { cp = c; n = 1; }
        else if ((c >> 5) == 6) { cp = c & 0x1F; n = 2; }
        else if ((c >> 4) == 14) { cp = c & 0x0F; n = 3; }
        else { cp = c & 0x07; n = 4; }
        for (int k = 1; k < n && i + k < s.size(); ++k) cp = (cp << 6) | (static_cast<unsigned char>(s[i + k]) & 0x3F);
        o.push_back(cp);
        i += n;
    }
    return o;
}
inline void appendUtf8(std::string& o, char32_t cp) {
    if (cp < 0x80) o.push_back(static_cast<char>(cp));
    else if (cp < 0x800) { o.push_back(static_cast<char>(0xC0 | (cp >> 6))); o.push_back(static_cast<char>(0x80 | (cp & 0x3F))); }
    else if (cp < 0x10000) {
        o.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        o.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        o.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
        o.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        o.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        o.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        o.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}
inline std::string toUtf8(const std::u32string& s) { std::string o; for (char32_t c : s) appendUtf8(o, c); return o; }
inline std::string toUtf8(const char16_t* s, int n) {   // engine output is BMP-only
    std::string o;
    for (int i = 0; i < n; ++i) appendUtf8(o, s[i]);
    return o;
}

inline std::string composed(const vtx::TelexEngine& e) { char16_t b[vtx::kMaxText]; int n = e.composed(b, vtx::kMaxText); return toUtf8(b, n); }
inline std::string raw(const vtx::TelexEngine& e) { char16_t b[vtx::kMaxText]; int n = e.rawKeystrokes(b, vtx::kMaxText); return toUtf8(b, n); }
inline std::string commitText(vtx::TelexEngine& e, bool a) { char16_t b[vtx::kMaxText]; int n = e.commitText(a, b, vtx::kMaxText); return toUtf8(b, n); }
inline std::string peek(const vtx::TelexEngine& e, bool a) { char16_t b[vtx::kMaxText]; int n = e.peekCommitText(a, b, vtx::kMaxText); return toUtf8(b, n); }
inline std::string text(const vtx::Action& a) { return toUtf8(a.text, a.length); }
inline void feedStr(vtx::TelexEngine& e, const std::string& keys) {
    vtx::Action a;
    for (char32_t c : fromUtf8(keys)) e.feed(c, a);
}
inline bool seed(vtx::TelexEngine& e, const std::string& w) { auto u = fromUtf8(w); return e.seed(u.data(), static_cast<int>(u.size())); }

/// Golden flag letters (see TelexCore/Sources/GenGolden/main.swift). Returns autoRestore.
inline bool toggleFlag(vtx::TelexEngine& e, char c, bool autoRestore) {
    switch (c) {
    case 'A': return !autoRestore;
    case 'F': e.freeMarking = !e.freeMarking; break;
    case 'M': e.modernTone = !e.modernTone; break;
    case 'L': e.liveSpellCheck = !e.liveSpellCheck; break;
    case 'S': e.simpleTelex = !e.simpleTelex; break;
    case 't': e.teencode = !e.teencode; break;
    case 'Q': e.quickTelex = !e.quickTelex; break;
    case 'B': e.bracketVowels = !e.bracketVowels; break;
    case 'V': e.vniMode = !e.vniMode; break;
    case 'C': e.contextualEnglish = !e.contextualEnglish; break;
    case 'e': e.englishWordRestore = !e.englishWordRestore; break;
    case 'P': e.collisionPrefersVietnamese = !e.collisionPrefersVietnamese; break;
    default: break;
    }
    return autoRestore;
}
/// Flags applied to a fresh engine (GenGolden `configure`: letters SET, never toggle).
inline bool configure(vtx::TelexEngine& e, const std::string& flags) {
    bool a = false;
    for (char c : flags) {
        switch (c) {
        case 'A': a = true; break;
        case 'F': e.freeMarking = true; break;
        case 'M': e.modernTone = true; break;
        case 'L': e.liveSpellCheck = true; break;
        case 'S': e.simpleTelex = true; break;
        case 't': e.teencode = false; break;
        case 'Q': e.quickTelex = true; break;
        case 'B': e.bracketVowels = true; break;
        case 'V': e.vniMode = true; break;
        case 'C': e.contextualEnglish = true; break;
        case 'e': e.englishWordRestore = false; break;
        case 'P': e.collisionPrefersVietnamese = true; break;
        default: break;
        }
    }
    return a;
}

struct Counter { int pass = 0, fail = 0; };

} // namespace vt
