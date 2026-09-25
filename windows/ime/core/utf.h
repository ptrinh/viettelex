// utf.h — tiny UTF-8 <-> UTF-16 helpers (portable, no Win32).
#pragma once
#include <string>

namespace vtx {

std::u16string utf8ToUtf16(const std::string& s);
std::string utf16ToUtf8(const std::u16string& s);

inline bool isAsciiLetter(char32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
inline bool isAsciiDigit(char32_t c) { return c >= '0' && c <= '9'; }

}  // namespace vtx
