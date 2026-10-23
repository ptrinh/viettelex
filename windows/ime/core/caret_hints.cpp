// caret_hints.cpp — see caret_hints.h. Ports keep the Swift names and order (MathResults,
// NumberChips, CaretHintLogic, TypoFixLogic gate, ToneRunLogic, DateHintLogic) so a rule
// change there maps line by line.
#include "caret_hints.h"
#include "app_policy.h"

#include <algorithm>
#include <clocale>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <viettelex/telex_engine.hpp>

namespace vtx::hints {

// ================================================================ strings

std::u32string toU32(const std::u16string& s) {
    std::u32string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        char32_t c = s[i];
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.size() && s[i + 1] >= 0xDC00 && s[i + 1] <= 0xDFFF) {
            c = 0x10000 + ((c - 0xD800) << 10) + (s[i + 1] - 0xDC00);
            ++i;
        }
        out.push_back(c);
    }
    return out;
}

std::u16string toU16(const std::u32string& s) {
    std::u16string out;
    out.reserve(s.size());
    for (char32_t c : s) {
        if (c >= 0x10000) {
            c -= 0x10000;
            out.push_back(static_cast<char16_t>(0xD800 + (c >> 10)));
            out.push_back(static_cast<char16_t>(0xDC00 + (c & 0x3FF)));
        } else {
            out.push_back(static_cast<char16_t>(c));
        }
    }
    return out;
}

bool isNewline(char32_t c) { return c == '\n' || c == '\r' || c == 0x0B || c == 0x0C || c == 0x85 || c == 0x2028 || c == 0x2029; }

bool isWhitespace(char32_t c) {
    return c == ' ' || c == '\t' || isNewline(c) || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) ||
           c == 0x202F || c == 0x205F || c == 0x3000;
}

bool isDigit(char32_t c) { return c >= '0' && c <= '9'; }

bool isLetter(char32_t c) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) return true;
    if (c < 0xAA) return false;
    if (c == 0xAA || c == 0xB5 || c == 0xBA) return true;
    if (c < 0xC0 || c == 0xD7 || c == 0xF7) return false;
    if (c <= 0x2AF) return true;                       // Latin-1 … IPA
    if (c >= 0x300 && c <= 0x36F) return true;         // combining marks (part of a letter)
    if (c >= 0x370 && c <= 0x52F) return c != 0x37E && c != 0x387;  // Greek, Cyrillic
    if (c >= 0x1E00 && c <= 0x1EFF) return true;       // Latin Extended Additional (Vietnamese)
    if (c >= 0x2000 && c <= 0x2BFF) return false;      // punctuation, symbols, arrows
    if (c >= 0x3000 && c <= 0x303F) return false;      // CJK punctuation
    if (c >= 0xFF00 && c <= 0xFF20) return false;
    return c >= 0x5D0;                                 // other scripts: treat as letters
}

char32_t lowerChar(char32_t c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    if (c < 0xC0) return c;
    if (c <= 0xDE) return c == 0xD7 ? c : c + 32;
    if (c >= 0x100 && c <= 0x137) return c == 0x130 ? U'i' : (c | 1);
    if (c >= 0x139 && c <= 0x148) return (c & 1) ? c + 1 : c;
    if (c >= 0x14A && c <= 0x177) return c | 1;
    if (c == 0x178) return 0xFF;
    if (c >= 0x179 && c <= 0x17E) return (c & 1) ? c + 1 : c;
    if (c == 0x1A0 || c == 0x1AF) return c + 1;         // Ơ Ư
    if (c >= 0x1E00 && c <= 0x1EFF) return c | 1;        // Latin Extended Additional
    if (c >= 0x391 && c <= 0x3AB && c != 0x3A2) return c + 32;
    if (c >= 0x410 && c <= 0x42F) return c + 32;
    return c;
}

namespace {
char32_t upperChar(char32_t c) {
    if (c >= 'a' && c <= 'z') return c - 32;
    if (c >= 0xE0 && c <= 0xFE && c != 0xF7) return c - 32;
    if (c >= 0x101 && c <= 0x137 && (c & 1)) return c - 1;
    if (c >= 0x14B && c <= 0x177 && (c & 1)) return c - 1;
    if (c == 0x1A1 || c == 0x1B0) return c - 1;
    if (c >= 0x1E01 && c <= 0x1EFF && (c & 1)) return c - 1;
    return c;
}

bool hasSuffix(const std::u32string& s, const std::u32string& t) {
    return s.size() >= t.size() && s.compare(s.size() - t.size(), t.size(), t) == 0;
}
bool allOf(const std::u32string& s, bool (*f)(char32_t)) {
    for (char32_t c : s)
        if (!f(c)) return false;
    return true;
}
bool isAsciiLetter(char32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool isUpperAscii(char32_t c) { return c >= 'A' && c <= 'Z'; }
std::u32string U(const char* utf8) {  // literal helper (UTF-8 source)
    std::u32string out;
    const auto* p = reinterpret_cast<const unsigned char*>(utf8);
    while (*p) {
        char32_t c = *p++;
        int extra = 0;
        if (c >= 0xF0) { c &= 0x07; extra = 3; }
        else if (c >= 0xE0) { c &= 0x0F; extra = 2; }
        else if (c >= 0xC0) { c &= 0x1F; extra = 1; }
        while (extra-- > 0 && *p) c = (c << 6) | (*p++ & 0x3F);
        out.push_back(c);
    }
    return out;
}
std::string ascii(const std::u32string& s) {
    std::string o;
    for (char32_t c : s) o.push_back(static_cast<char>(c < 0x80 ? c : '?'));
    return o;
}
std::u32string fromAscii(const std::string& s) { return std::u32string(s.begin(), s.end()); }
}  // namespace

std::u32string lower(const std::u32string& s) {
    std::u32string o(s);
    for (char32_t& c : o) c = lowerChar(c);
    return o;
}

// ================================================================ keys

KeyAction action(Kind kind, uint32_t vk, bool plain) {
    if (vk == kVkEscape && plain) return KeyAction::DismissConsume;
    if (!plain) return KeyAction::DismissPass;
    if (vk == kVkTab) return KeyAction::Accept;
    if (kind == Kind::Math && vk == kVkReturn) return KeyAction::Accept;
    return KeyAction::DismissPass;
}

// ================================================================ NumberChips (numbers)

namespace {

struct Dec {
    bool negative = false;
    std::string intPart = "0";  // no leading zeros; "0" for zero
    std::string frac;           // no trailing zeros
    Dec() = default;
    Dec(bool neg, const std::string& i, const std::string& f) {
        size_t a = 0;
        while (a < i.size() && i[a] == '0') ++a;
        intPart = i.substr(a);
        if (intPart.empty()) intPart = "0";
        frac = f;
        while (!frac.empty() && frac.back() == '0') frac.pop_back();
        negative = neg && !(intPart == "0" && frac.empty());
    }
    Dec shifted(int e) const {
        std::string f = frac;
        if (static_cast<int>(f.size()) < e) f.append(static_cast<size_t>(e) - f.size(), '0');
        return Dec(negative, intPart + f.substr(0, static_cast<size_t>(e)), f.substr(static_cast<size_t>(e)));
    }
};

struct Literal {
    Dec value;
    char32_t groupSep = 0, decSep = 0;
};

constexpr int kMaxDigits = 30;
constexpr int kMaxPlainDigits = 12;

std::optional<Literal> parseNumber(const std::u32string& s) {
    if (s.empty() || !isDigit(s.front()) || !isDigit(s.back())) return std::nullopt;
    int dots = 0, commas = 0;
    for (char32_t c : s) {
        if (c == '.') ++dots;
        else if (c == ',') ++commas;
        else if (!isDigit(c)) return std::nullopt;
    }
    char32_t groupSep = 0, decSep = 0;
    if (dots > 0 && commas > 0) {
        const size_t lastDot = s.rfind(U'.'), lastComma = s.rfind(U',');
        decSep = lastDot > lastComma ? U'.' : U',';
        groupSep = decSep == U'.' ? U',' : U'.';
        if ((decSep == U'.' ? dots : commas) != 1) return std::nullopt;
    } else if (commas > 0) {
        if (commas == 1) decSep = U',';
        else groupSep = U',';
    } else if (dots > 0) {
        if (dots > 1) {
            groupSep = U'.';
        } else {
            const size_t i = s.find(U'.');
            const size_t head = i, tail = s.size() - i - 1;
            if (tail == 3 && head >= 1 && head <= 3 && s[0] != U'0') groupSep = U'.';
            else decSep = U'.';
        }
    }
    std::u32string intPart = s, frac;
    if (decSep) {
        const size_t i = s.find(decSep);
        intPart = s.substr(0, i);
        frac = s.substr(i + 1);
    }
    std::string digits;
    if (groupSep) {
        std::vector<std::u32string> groups;
        size_t a = 0;
        while (true) {
            const size_t b = intPart.find(groupSep, a);
            groups.push_back(intPart.substr(a, b == std::u32string::npos ? std::u32string::npos : b - a));
            if (b == std::u32string::npos) break;
            a = b + 1;
        }
        if (groups[0].size() < 1 || groups[0].size() > 3) return std::nullopt;
        for (size_t k = 1; k < groups.size(); ++k)
            if (groups[k].size() != 3) return std::nullopt;
        for (const auto& g : groups) {
            if (!allOf(g, isDigit)) return std::nullopt;
            digits += ascii(g);
        }
    } else {
        if (!allOf(intPart, isDigit)) return std::nullopt;
        digits = ascii(intPart);
    }
    if (digits.empty() || !allOf(frac, isDigit) || static_cast<int>(digits.size()) > kMaxDigits ||
        static_cast<int>(frac.size()) > kMaxDigits)
        return std::nullopt;
    Literal l;
    l.value = Dec(false, digits, ascii(frac));
    l.groupSep = groupSep;
    l.decSep = decSep;
    return l;
}

const char* const kDigitWords[10] = {"không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"};

void readTriple(int n, bool full, bool le, std::vector<std::string>& w) {
    const int h = n / 100, t = (n / 10) % 10, u = n % 10;
    const size_t start = w.size();
    if (full || h > 0) {
        w.push_back(kDigitWords[h]);
        w.push_back("trăm");
    }
    switch (t) {
        case 0:
            if (u > 0) {
                if (w.size() > start) w.push_back(le ? "lẻ" : "linh");
                w.push_back(kDigitWords[u]);
            }
            break;
        case 1:
            w.push_back("mười");
            if (u == 5) w.push_back("lăm");
            else if (u > 0) w.push_back(kDigitWords[u]);
            break;
        default:
            w.push_back(kDigitWords[t]);
            w.push_back("mươi");
            if (u == 1) w.push_back("mốt");
            else if (u == 5) w.push_back("lăm");
            else if (u > 0) w.push_back(kDigitWords[u]);
            break;
    }
}

void readBelowBillion(int n, bool leading, bool le, std::vector<std::string>& out) {
    bool first = leading;
    const int groups[3] = {n / 1000000, (n / 1000) % 1000, n % 1000};
    const char* const units[3] = {"triệu", "nghìn", ""};
    for (int k = 0; k < 3; ++k) {
        if (groups[k] <= 0) continue;
        readTriple(groups[k], !first, le, out);
        if (*units[k]) out.push_back(units[k]);
        first = false;
    }
}

std::string join(const std::vector<std::string>& w) {
    std::string s;
    for (size_t i = 0; i < w.size(); ++i) {
        if (i) s += ' ';
        s += w[i];
    }
    return s;
}

std::string readInteger(const std::string& digits, bool le) {
    bool zero = true;
    for (char c : digits)
        if (c != '0') zero = false;
    if (zero) return "không";
    std::vector<int> chunks;  // 9-digit blocks, high first
    std::string rest = digits;
    while (!rest.empty()) {
        const size_t take = rest.size() < 9 ? rest.size() : 9;
        chunks.insert(chunks.begin(), std::atoi(rest.substr(rest.size() - take).c_str()));
        rest.resize(rest.size() - take);
    }
    while (!chunks.empty() && chunks.front() == 0) chunks.erase(chunks.begin());
    std::vector<std::string> words;
    readBelowBillion(chunks[0], true, le, words);
    for (size_t i = 1; i < chunks.size(); ++i) {
        words.push_back("tỷ");
        if (chunks[i] > 0) readBelowBillion(chunks[i], false, le, words);
    }
    return join(words);
}

std::string read(const Dec& d, bool le) {
    std::string s = readInteger(d.intPart, le);
    if (!d.frac.empty()) {
        std::string fw;
        if (d.frac.size() <= 2 && d.frac[0] != '0') {
            fw = readInteger(d.frac, le);
        } else {
            std::vector<std::string> w;
            for (char c : d.frac) w.push_back(kDigitWords[c - '0']);
            fw = join(w);
        }
        s += " phẩy " + fw;
    }
    return d.negative ? "âm " + s : s;
}

struct Amount {
    Dec value;
    bool multiplier = false;
    std::u32string currency;  // "" = none
    bool grouped = false;
};

int multiplierOf(const std::u32string& unit) {
    static const struct { const char* u; int e; } kMult[] = {
        {"k", 3}, {"nghìn", 3}, {"ngàn", 3}, {"nghin", 3}, {"ngan", 3},
        {"tr", 6}, {"triệu", 6}, {"trieu", 6}, {"tỷ", 9}, {"tỉ", 9}, {"ty", 9}};
    for (const auto& m : kMult)
        if (unit == U(m.u)) return m.e;
    return -1;
}
bool isCurrency(const std::u32string& unit) {
    static const char* const kCur[] = {"đ", "₫", "đồng", "vnd", "vnđ"};
    for (const char* c : kCur)
        if (unit == U(c)) return true;
    return false;
}

std::optional<Amount> parseAmount(const std::u32string& token) {
    std::vector<std::u32string> words;
    size_t a = 0;
    while (true) {
        const size_t b = token.find(U' ', a);
        words.push_back(token.substr(a, b == std::u32string::npos ? std::u32string::npos : b - a));
        if (b == std::u32string::npos) break;
        a = b + 1;
    }
    if (words.size() < 1 || words.size() > 2) return std::nullopt;
    std::u32string w = words[0];
    const bool neg = !w.empty() && (w[0] == U'-' || w[0] == 0x2212);
    if (neg) w.erase(0, 1);
    size_t np = 0;
    while (np < w.size() && (isDigit(w[np]) || w[np] == U'.' || w[np] == U',')) ++np;
    const auto lit = parseNumber(w.substr(0, np));
    if (!lit) return std::nullopt;
    std::u32string suffix = w.substr(np);
    if (words.size() == 2) {
        if (!suffix.empty() || words[1].empty()) return std::nullopt;
        suffix = words[1];
    }
    size_t up = 0;
    while (up < suffix.size() && !isDigit(suffix[up])) ++up;
    const std::u32string unit = lower(suffix.substr(0, up));
    const std::u32string tail = suffix.substr(up);
    if (!allOf(tail, isDigit)) return std::nullopt;
    if (words.size() == 2 && (unit.empty() || !tail.empty())) return std::nullopt;  // "12 5" is not one number
    const Dec value(neg, lit->value.intPart, lit->value.frac);
    const bool grouped = lit->groupSep != 0;
    Amount out;
    out.grouped = grouped;
    if (unit.empty()) {
        out.value = value;
        return out;
    }
    const int e = multiplierOf(unit);
    if (e >= 0) {
        Dec v = value;
        if (!tail.empty()) {  // "1tr2" = 1,2 triệu — only after a plain integer, ≤ 3 digits
            if (lit->groupSep || lit->decSep || tail.size() > 3) return std::nullopt;
            v = Dec(neg, lit->value.intPart, ascii(tail));
        }
        v = v.shifted(e);
        if (static_cast<int>(v.intPart.size()) > kMaxDigits) return std::nullopt;
        out.value = v;
        out.multiplier = true;
        return out;
    }
    if (isCurrency(unit) && tail.empty()) {
        out.value = value;
        out.currency = unit;
        return out;
    }
    return std::nullopt;
}

std::string group(const std::string& digits, char sep) {
    std::string out;
    for (size_t i = 0; i < digits.size(); ++i) {
        if (i > 0 && (digits.size() - i) % 3 == 0) out.push_back(sep);
        out.push_back(digits[i]);
    }
    return out;
}

std::string utf8(const std::u32string& s) {
    std::string o;
    for (char32_t c : s) {
        if (c < 0x80) {
            o.push_back(static_cast<char>(c));
        } else if (c < 0x800) {
            o.push_back(static_cast<char>(0xC0 | (c >> 6)));
            o.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        } else if (c < 0x10000) {
            o.push_back(static_cast<char>(0xE0 | (c >> 12)));
            o.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
            o.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        } else {
            o.push_back(static_cast<char>(0xF0 | (c >> 18)));
            o.push_back(static_cast<char>(0x80 | ((c >> 12) & 0x3F)));
            o.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
            o.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        }
    }
    return o;
}

// "1.250.000 ₫" (symbol ₫, spaced) / "1.250.000đ" (symbol đ, glued). Integers only.
std::optional<std::string> formatMoney(const Dec& d, const std::u32string& symbol) {
    if (!d.frac.empty()) return std::nullopt;
    const std::string body = (d.negative ? "-" : "") + group(d.intPart, '.');
    return symbol == U"\u0111" ? body + utf8(symbol) : body + " " + utf8(symbol);
}

bool atSentenceStart(const std::u32string& prefix) {
    if (!prefix.empty() && prefix.back() == U'\n') return true;
    size_t i = prefix.size();
    while (i > 0 && (prefix[i - 1] == U' ' || prefix[i - 1] == U'\t')) --i;
    if (i == 0) return true;
    const char32_t c = prefix[i - 1];
    return c == U'.' || c == U'!' || c == U'?' || c == U'\n';
}

std::u32string lastWord(const std::u32string& s) {
    size_t i = s.size();
    while (i > 0 && !isWhitespace(s[i - 1])) --i;
    return s.substr(i);
}

std::u32string upperFirst(const std::u32string& s) {
    if (s.empty()) return s;
    std::u32string o(s);
    o[0] = upperChar(o[0]);
    return o;
}

}  // namespace

std::optional<std::u32string> spellNumber(const std::u32string& canonical, bool le) {
    std::u32string s = canonical;
    const bool neg = !s.empty() && s[0] == U'-';
    if (neg) s.erase(0, 1);
    const size_t c = s.find(U',');
    std::u32string a = c == std::u32string::npos ? s : s.substr(0, c);
    std::u32string b = c == std::u32string::npos ? std::u32string() : s.substr(c + 1);
    if (a.empty() || !allOf(a, isDigit) || static_cast<int>(a.size()) > kMaxDigits) return std::nullopt;
    if (c != std::u32string::npos && (b.empty() || !allOf(b, isDigit))) return std::nullopt;
    return U(read(Dec(neg, ascii(a), ascii(b)), le).c_str());
}

std::optional<NumberChip> numberChip(const std::u32string& before, bool le) {
    if (hasSuffix(before, U"=")) return std::nullopt;
    std::u32string ctx = before;
    const bool hadSpace = hasSuffix(ctx, U" ");
    if (hadSpace) ctx.pop_back();
    if (ctx.empty() || isWhitespace(ctx.back())) return std::nullopt;
    const std::u32string w1 = lastWord(ctx);
    std::u32string token = w1;
    std::optional<Amount> amount = parseAmount(token);
    const std::u32string rest1 = ctx.substr(0, ctx.size() - w1.size());  // "2 tỷ", "1.250.000 ₫"
    if (hasSuffix(rest1, U" ")) {
        const std::u32string w0 = lastWord(rest1.substr(0, rest1.size() - 1));
        if (!w0.empty()) {
            auto a = parseAmount(w0 + U" " + w1);
            if (a && (a->multiplier || !a->currency.empty())) {
                token = w0 + U" " + w1;
                amount = a;
            }
        }
    }
    if (!amount) return std::nullopt;
    const Amount& a = *amount;
    const std::u32string prefix = ctx.substr(0, ctx.size() - token.size());
    std::optional<std::string> text;
    if (a.multiplier) {
        text = formatMoney(a.value, U"₫");
    } else if (!a.currency.empty()) {
        if ((a.currency == U"đ" || a.currency == U"₫") && !a.grouped && a.value.intPart.size() >= 4 && a.value.frac.empty())
            text = formatMoney(a.value, a.currency);
        else
            text = read(a.value, le) + " đồng";
    } else {
        const bool plain = !a.grouped && token.find(U',') == std::u32string::npos && token.find(U'.') == std::u32string::npos;
        std::u32string digits;
        for (char32_t c : token)
            if (isDigit(c)) digits.push_back(c);
        if (plain && ((digits.size() > 1 && digits[0] == U'0') || static_cast<int>(digits.size()) > kMaxPlainDigits))
            return std::nullopt;
        text = read(a.value, le);
    }
    if (!text) return std::nullopt;
    std::u32string t = U(text->c_str());
    if (atSentenceStart(prefix) && !t.empty() && isLetter(t[0])) t = upperFirst(t);
    const std::u32string sp = hadSpace ? U" " : U"";
    return NumberChip{t, token + sp, t + sp};
}

bool isMoneyFormat(const std::u32string& display) {
    size_t i = !display.empty() && display[0] == U'-' ? 1 : 0;
    return i < display.size() && isDigit(display[i]);
}

std::optional<Suggestion> moneyChip(const std::u32string& before) {
    if (!hasSuffix(before, U" ")) return std::nullopt;
    auto c = numberChip(before);
    if (!c || !isMoneyFormat(c->display)) return std::nullopt;
    return Suggestion{Kind::Number, toU16(c->display), toU16(c->replace), toU16(c->insert)};
}

// ================================================================ MathResults

namespace {

enum class T : uint8_t { Num, Op, LP, RP, Pct };
struct Tok {
    T t;
    double v;
    char op;
    bool operator==(const Tok& o) const { return t == o.t && (t != T::Op || op == o.op); }
};

struct Calc {
    double value;
    bool english, grouped;
};

// Locale-proof strtod: the TIP shares the host's C runtime locale.
double parseDouble(const std::string& digits, const std::string& frac) {
    std::string s = digits;
    if (!frac.empty()) {
        const lconv* lc = std::localeconv();
        s += (lc && lc->decimal_point && *lc->decimal_point) ? lc->decimal_point : ".";
        s += frac;
    }
    return std::strtod(s.c_str(), nullptr);
}

std::string fixed(double a, int decimals) {
    char buf[64];
    std::snprintf(buf, sizeof buf, "%.*f", decimals, a);
    std::string s(buf);
    for (char& c : s)
        if (!(c >= '0' && c <= '9') && c != '-') c = '.';  // locale decimal point -> '.'
    return s;
}

class Parser {
public:
    explicit Parser(const std::vector<Tok>& t) : toks_(t) {}
    bool run(double& out) {
        auto v = expression(0);
        if (!v || p_ != toks_.size()) return false;
        out = *v;
        return true;
    }

private:
    struct VP {
        double v;
        bool pct;
    };
    const Tok* peek() const { return p_ < toks_.size() ? &toks_[p_] : nullptr; }
    bool isOp(char c) const { const Tok* t = peek(); return t && t->t == T::Op && t->op == c; }
    bool is(T k) const { const Tok* t = peek(); return t && t->t == k; }

    std::optional<double> primary(int depth) {
        const Tok* t = peek();
        if (depth >= 32 || !t) return std::nullopt;
        if (t->t == T::Num) {
            ++p_;
            return t->v;
        }
        if (t->t == T::LP) {
            ++p_;
            auto v = expression(depth + 1);
            if (!v || !is(T::RP)) return std::nullopt;
            ++p_;
            return v;
        }
        return std::nullopt;
    }
    std::optional<VP> power(int depth) {
        auto v = primary(depth);
        if (!v) return std::nullopt;
        if (is(T::Pct)) {
            ++p_;
            return VP{*v / 100, true};
        }
        if (isOp('^')) {
            ++p_;
            auto e = unary(depth + 1);
            if (!e) return std::nullopt;
            return VP{std::pow(*v, e->v), false};
        }
        return VP{*v, false};
    }
    std::optional<VP> unary(int depth) {
        if (depth >= 32) return std::nullopt;
        if (isOp('-')) {
            ++p_;
            auto r = unary(depth + 1);
            if (!r) return std::nullopt;
            return VP{-r->v, false};
        }
        if (isOp('+')) {
            ++p_;
            auto r = unary(depth + 1);
            if (!r) return std::nullopt;
            return VP{r->v, false};
        }
        return power(depth);
    }
    std::optional<VP> term(int depth) {
        auto first = unary(depth);
        if (!first) return std::nullopt;
        VP v = *first;
        while (isOp('*') || isOp('/')) {
            const bool div = isOp('/');
            ++p_;
            auto r = unary(depth);
            if (!r) return std::nullopt;
            if (div) {
                if (r->v == 0) return std::nullopt;
                v.v /= r->v;
            } else {
                v.v *= r->v;
            }
            v.pct = false;
        }
        return v;
    }
    std::optional<double> expression(int depth) {
        auto first = term(depth);
        if (!first) return std::nullopt;
        double v = first->v;
        while (isOp('+') || isOp('-')) {
            const bool plus = isOp('+');
            ++p_;
            auto r = term(depth);
            if (!r) return std::nullopt;
            double rv = r->v;
            if (r->pct) rv *= v;
            v = plus ? v + rv : v - rv;
        }
        return v;
    }

    const std::vector<Tok>& toks_;
    size_t p_ = 0;
};

// Conflict = a well-formed calculation whose separators contradict ("1,5 * 2 + 2.5"):
// mathChip stops instead of trying a shorter tail ("2 + 2.5").
enum class Outcome : uint8_t { Ok, Invalid, Conflict };

// Numbers of the expression -> values, with "," / "." inferred from the WHOLE expression
// (rule at the top of MathResults.swift). dec = inferred decimal separator (0: none).
Outcome numbers(const std::vector<std::u32string>& lits, std::vector<double>& values, char32_t& dec,
                bool& grouped) {
    auto other = [](char32_t c) { return c == U'.' ? U',' : U'.'; };
    std::u32string certDec, certGroup, ambiguous;  // sets of at most '.' and ','
    auto add = [](std::u32string& set, char32_t c) {
        if (set.find(c) == std::u32string::npos) set.push_back(c);
    };
    for (const auto& lit : lits) {
        if (!isDigit(lit.back())) return Outcome::Invalid;
        const auto dots = std::count(lit.begin(), lit.end(), U'.');
        const auto commas = std::count(lit.begin(), lit.end(), U',');
        if (dots > 0 && commas > 0) {
            const char32_t d = lit.rfind(U'.') > lit.rfind(U',') ? U'.' : U',';
            if ((d == U'.' ? dots : commas) != 1) return Outcome::Invalid;
            add(certDec, d);
            add(certGroup, other(d));
        } else if (dots + commas > 1) {
            add(certGroup, dots > 0 ? U'.' : U',');
        } else if (dots + commas == 1) {
            const char32_t s = dots > 0 ? U'.' : U',';
            const size_t k = lit.find(s);
            if (lit.size() - k - 1 == 3 && k >= 1 && k <= 3 && lit[0] != U'0') add(ambiguous, s);
            else add(certDec, s);
        }
    }
    if (certDec.size() > 1 || certGroup.size() > 1) return Outcome::Conflict;
    if (!certDec.empty() && !certGroup.empty() && certDec[0] == certGroup[0]) return Outcome::Conflict;
    dec = 0;
    if (!certDec.empty()) dec = certDec[0];
    else if (!certGroup.empty()) dec = other(certGroup[0]);
    else if (ambiguous.size() > 1) return Outcome::Conflict;
    else if (!ambiguous.empty()) dec = other(ambiguous[0]);
    grouped = false;
    values.clear();
    for (const auto& lit : lits) {
        std::u32string intPart = lit, frac;
        const size_t k = dec ? lit.find(dec) : std::u32string::npos;
        if (k != std::u32string::npos) {
            intPart = lit.substr(0, k);
            frac = lit.substr(k + 1);
            if (frac.find(dec) != std::u32string::npos) return Outcome::Invalid;
        }
        std::u32string digits = intPart;
        if (dec && intPart.find(other(dec)) != std::u32string::npos) {
            std::vector<std::u32string> groups;
            for (size_t a = 0;;) {
                const size_t b = intPart.find(other(dec), a);
                groups.push_back(intPart.substr(a, b == std::u32string::npos ? std::u32string::npos : b - a));
                if (b == std::u32string::npos) break;
                a = b + 1;
            }
            if (groups[0].empty() || groups[0].size() > 3) return Outcome::Invalid;
            for (size_t g = 1; g < groups.size(); ++g)
                if (groups[g].size() != 3) return Outcome::Invalid;
            digits.clear();
            for (const auto& g : groups) digits += g;
            grouped = true;
        }
        if (digits.empty() || static_cast<int>(digits.size()) > kMaxDigits ||
            static_cast<int>(frac.size()) > kMaxDigits || !allOf(frac, isDigit))
            return Outcome::Invalid;
        values.push_back(parseDouble(ascii(digits), ascii(frac)));
    }
    return Outcome::Ok;
}

Outcome analyze(const std::u32string& cs, Calc& out) {
    if (static_cast<int>(cs.size()) > kMathMaxLength) return Outcome::Invalid;
    std::vector<Tok> toks;
    std::vector<std::u32string> lits;
    size_t i = 0;
    while (i < cs.size()) {
        const char32_t c = cs[i];
        if (c == U' ') {
            ++i;
            continue;
        }
        if (isDigit(c)) {
            size_t j = i;
            while (j < cs.size() && (isDigit(cs[j]) || cs[j] == U'.' || cs[j] == U',')) ++j;
            lits.push_back(cs.substr(i, j - i));
            toks.push_back({T::Num, 0, 0});
            i = j;
            continue;
        }
        switch (c) {
            case U'+': toks.push_back({T::Op, 0, '+'}); break;
            case U'-': case 0x2212: toks.push_back({T::Op, 0, '-'}); break;
            case U'*': case 0xD7: toks.push_back({T::Op, 0, '*'}); break;
            case U'x': case U'X': {
                // only between two numbers: "12x3", "(1+2)x3", "2 x (3)"
                size_t k = i + 1;
                while (k < cs.size() && cs[k] == U' ') ++k;
                const bool prevOk = !toks.empty() && (toks.back().t == T::Num || toks.back().t == T::RP ||
                                                      toks.back().t == T::Pct);
                if (!prevOk || k >= cs.size() || !(isDigit(cs[k]) || cs[k] == U'(')) return Outcome::Invalid;
                toks.push_back({T::Op, 0, '*'});
                break;
            }
            case U'/': case 0xF7: case U':': toks.push_back({T::Op, 0, '/'}); break;
            case U'^': toks.push_back({T::Op, 0, '^'}); break;
            case U'(': toks.push_back({T::LP, 0, 0}); break;
            case U')': toks.push_back({T::RP, 0, 0}); break;
            case U'%': toks.push_back({T::Pct, 0, 0}); break;
            default: return Outcome::Invalid;
        }
        ++i;
    }
    // A real calculation (not "5" or "-5" alone).
    bool hasOp = false;
    for (size_t k = 0; k < toks.size(); ++k)
        if (toks[k].t == T::Pct || (toks[k].t == T::Op && k > 0)) hasOp = true;
    if (!hasOp) return Outcome::Invalid;
    std::vector<double> values;
    char32_t dec = 0;
    bool grouped = false;
    const Outcome o = numbers(lits, values, dec, grouped);
    if (o == Outcome::Conflict) values.assign(lits.size(), 1.0);  // 1s: parses <=> well-formed
    else if (o != Outcome::Ok) return o;
    size_t n = 0;
    for (auto& t : toks)
        if (t.t == T::Num) t.v = values[n++];
    double v = 0;
    Parser p(toks);
    if (!p.run(v)) return Outcome::Invalid;
    if (o == Outcome::Conflict) return o;
    if (!std::isfinite(v) || std::fabs(v) >= 1e15) return Outcome::Invalid;
    out = Calc{v, dec == U'.', grouped};
    return Outcome::Ok;
}

std::optional<std::string> format(const Calc& c) {
    const double a = std::fabs(c.value);
    const int intDigits = a < 1 ? 1 : static_cast<int>(fixed(std::floor(a), 0).size());
    const int decimals = std::max(0, std::min(6, 12 - intDigits));
    std::string s = fixed(a, decimals);
    if (s.find('.') != std::string::npos) {
        while (!s.empty() && s.back() == '0') s.pop_back();
        if (!s.empty() && s.back() == '.') s.pop_back();
    }
    if (s == "0" && c.value != 0) return std::nullopt;
    const size_t dot = s.find('.');
    std::string intPart = s.substr(0, dot);
    if (c.grouped) intPart = group(intPart, c.english ? ',' : '.');
    std::string out = intPart;
    if (dot != std::string::npos) out += std::string(1, c.english ? '.' : ',') + s.substr(dot + 1);
    if (c.value < 0 && out != "0") out = "-" + out;
    return out;
}

bool isCalcChar(char32_t c) {
    static const std::u32string kCalc = U"0123456789.,+-−*xX×/÷:^()% ";
    return kCalc.find(c) != std::u32string::npos;
}

std::u32string trimSpaces(const std::u32string& s) {  // .whitespaces (no newlines here)
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == U' ' || s[a] == U'\t')) ++a;
    while (b > a && (s[b - 1] == U' ' || s[b - 1] == U'\t')) --b;
    return s.substr(a, b - a);
}

}  // namespace

std::optional<std::u32string> mathResult(const std::u32string& expr) {
    Calc c{};
    if (analyze(expr, c) != Outcome::Ok) return std::nullopt;
    auto f = format(c);
    if (!f) return std::nullopt;
    return fromAscii(*f);
}

std::optional<std::u32string> mathChip(const std::u32string& before) {
    if (!hasSuffix(before, U"=")) return std::nullopt;
    const std::u32string body = before.substr(0, before.size() - 1);
    size_t start = body.size();
    while (start > 0 && isCalcChar(body[start - 1])) --start;
    const std::u32string scanned = body.substr(start);
    // Glued to a letter ("abc12*3=", "v2+3=") -> a code or a name, not a calculation.
    const bool glued = start > 0 && isLetter(body[start - 1]);
    std::vector<std::u32string> candidates;
    if (!glued) candidates.push_back(scanned);
    for (size_t k = 0; k < scanned.size(); ++k)
        if (scanned[k] == U' ') candidates.push_back(scanned.substr(k + 1));
    for (const auto& cand : candidates) {
        const std::u32string e = trimSpaces(cand);
        if (e.empty() || static_cast<int>(e.size()) > kMathMaxLength) continue;
        const char32_t f = e[0];
        if (!(isDigit(f) || f == U'(' || f == U'-' || f == 0x2212)) continue;
        Calc c{};
        const Outcome o = analyze(e, c);
        if (o == Outcome::Conflict) return std::nullopt;
        if (o != Outcome::Ok) continue;
        if (auto f = format(c)) return fromAscii(*f);
    }
    return std::nullopt;
}

std::u32string mathLabel(const std::u32string& result) { return U"= " + result; }

// ================================================================ shared screen rule

bool standsAlone(const std::u32string& before, const std::u32string& token) {
    if (token.empty() || !hasSuffix(before, token)) return false;
    const size_t start = before.size() - token.size();
    if (start == 0) return true;
    return isWhitespace(before[start - 1]);
}

// ================================================================ typo gate

bool typoTriggers(char32_t c) {
    return c == U' ' || c == 0xA0 || c == U',' || c == U';' || c == U'!' || c == U'?' || c == U')';
}

bool isSentenceStart(const std::u32string& before) {
    size_t i = before.size();
    while (i > 0 && (before[i - 1] == U' ' || before[i - 1] == 0xA0 || before[i - 1] == U'\t')) --i;
    if (i == 0) return true;
    const char32_t l = before[i - 1];
    return l == U'.' || l == U'!' || l == U'?' || l == U'\n' || l == 0x2026;
}

bool caseAllows(const std::u32string& raw, bool sentenceStart) {
    int upper = 0;
    for (char32_t c : raw)
        if (isUpperAscii(c) || (c > 0x7F && lowerChar(c) != c)) ++upper;
    if (upper == 0) return true;
    return upper == 1 && !raw.empty() && isUpperAscii(raw[0]) && sentenceStart;
}

bool typoWorthChecking(char32_t boundary, const std::u32string& raw, const std::u32string& word, int minLen) {
    if (!typoTriggers(boundary)) return false;
    if (static_cast<int>(raw.size()) < minLen || raw.size() > 10 || !allOf(raw, isAsciiLetter)) return false;
    if (word.empty() || !allOf(word, isLetter)) return false;
    return !SyllableValidator::isValidSyllable(word.data(), static_cast<int>(word.size()));
}

std::optional<Suggestion> typoSuggestion(const std::u32string& before, const std::u32string& word, char32_t boundary,
                                         const std::u32string& raw, const std::u32string& fix) {
    const std::u32string replace = word + boundary;
    if (fix == word || !standsAlone(before, replace)) return std::nullopt;
    const std::u32string head = before.substr(0, before.size() - replace.size());
    if (!caseAllows(raw, isSentenceStart(head))) return std::nullopt;
    return Suggestion{Kind::Typo, toU16(fix), toU16(replace), toU16(fix + boundary)};
}

bool Rejected::contains(const std::u32string& w) const {
    const std::u32string k = lower(w);
    for (const auto& o : order_)
        if (o == k) return true;
    return false;
}

bool Rejected::add(const std::u32string& w) {
    const std::u32string k = lower(w);
    if (k.empty() || contains(k)) return false;
    order_.push_back(k);
    if (order_.size() > cap_) order_.erase(order_.begin(), order_.begin() + static_cast<std::ptrdiff_t>(order_.size() - cap_));
    return true;
}

// ================================================================ tones

namespace {
bool isEdgePunct(char32_t c) {
    static const std::u32string kEdge = U",;:\"'()[]…“”‘’.!?";
    return kEdge.find(c) != std::u32string::npos;
}
bool isSentenceEnd(char32_t c) { return c == U'.' || c == U'!' || c == U'?'; }
char32_t acuteOf(char32_t v) {
    switch (v) {
        case U'a': return 0xE1;
        case U'e': return 0xE9;
        case U'i': return 0xED;
        case U'o': return 0xF3;
        case U'u': return 0xFA;
        case U'y': return 0xFD;
        default: return 0;
    }
}
}  // namespace

bool opensEnglishRun(const std::u32string& w) {
    if (w.empty() || w.size() > 16 || !allOf(w, isAsciiLetter)) return false;
    const std::string a = ascii(w);
    return EnglishContextLookup::opensEnglishRun(a.data(), static_cast<int>(a.size()));
}

bool isUnaccentedSyllable(const std::u32string& chunk) {
    size_t a = 0, b = chunk.size();
    while (a < b && isEdgePunct(chunk[a])) ++a;
    while (b > a && isEdgePunct(chunk[b - 1])) --b;
    const std::u32string c = chunk.substr(a, b - a);
    if (c.empty() || c.size() > 7 || !allOf(c, isAsciiLetter)) return false;
    bool laterUpper = false, allUpper = true;
    for (size_t i = 0; i < c.size(); ++i) {
        if (!isUpperAscii(c[i])) allUpper = false;
        else if (i > 0) laterUpper = true;
    }
    if (laterUpper && !allUpper) return false;
    const std::u32string w = lower(c);
    if (opensEnglishRun(w)) return false;
    if (SyllableValidator::isValidSyllable(w.data(), static_cast<int>(w.size()), false)) return true;
    // Stop rimes (-c -ch -p -t) only take sắc/nặng: "hoc" is the unaccented học/hóc.
    size_t i = 0;
    while (i < w.size() && !acuteOf(w[i])) ++i;
    if (i == w.size()) return false;
    std::u32string acute = w;
    acute[i] = acuteOf(w[i]);
    return SyllableValidator::isValidSyllable(acute.data(), static_cast<int>(acute.size()), false);
}

ToneTrigger ToneTracker::feed(const std::u32string& chunk, char32_t b) {
    if (isNewline(b)) {
        count_ = 0;
        return ToneTrigger::None;
    }
    if (isWhitespace(b)) {
        if (chunk.empty()) return ToneTrigger::None;                   // two spaces
        if (isSentenceEnd(chunk.back())) {                              // the sentence already ended
            count_ = 0;
            return ToneTrigger::None;
        }
        count_ = isUnaccentedSyllable(chunk) ? std::min(count_ + 1, kToneMaxSyllables) : 0;
        return count_ >= kToneMinSyllables ? ToneTrigger::Pause : ToneTrigger::None;
    }
    if (isSentenceEnd(b)) {
        const bool ok = !chunk.empty() && isUnaccentedSyllable(chunk);
        const int n = ok ? count_ + 1 : 0;
        count_ = 0;
        return n >= kToneMinSyllables ? ToneTrigger::SentenceEnd : ToneTrigger::None;
    }
    return ToneTrigger::None;  // , ; : … — the chunk is checked again at the next space
}

std::optional<std::u32string> toneRun(const std::u32string& s) {
    auto ws = [](char32_t c) { return c == U' ' || c == U'\t' || c == 0xA0; };
    auto nl = [](char32_t c) { return c == U'\n' || c == U'\r'; };
    size_t end = s.size(), start = end;
    int n = 0;
    while (end > 0) {
        size_t w = end;
        while (w > 0 && ws(s[w - 1])) --w;
        if (w > 0 && nl(s[w - 1])) break;
        if (w == 0) break;
        size_t cs = w;
        while (cs > 0 && !ws(s[cs - 1]) && !nl(s[cs - 1])) --cs;
        const std::u32string chunk = s.substr(cs, w - cs);
        if (n > 0 && !chunk.empty() && isSentenceEnd(chunk.back())) break;  // previous sentence
        if (!isUnaccentedSyllable(chunk)) break;
        ++n;
        start = cs;
        end = cs;
        if (n >= kToneMaxSyllables) break;
    }
    if (n < kToneMinSyllables) return std::nullopt;
    return s.substr(start);
}

std::optional<Suggestion> toneSuggestion(const std::u32string& run, const std::u32string& restored) {
    if (run.empty() || restored == run || restored.size() != run.size()) return std::nullopt;
    std::u32string display = trimSpaces(restored);
    if (display.size() > 60) display = U"…" + display.substr(display.size() - 59);
    return Suggestion{Kind::Tones, toU16(display), toU16(run), toU16(restored)};
}

// ================================================================ date / time

namespace {
std::optional<Phrase> vietnamesePhrase(const std::u32string& p, const std::u32string& w) {
    if (p == U"hôm" && w == U"nay") return Phrase::Today;
    if (p == U"hôm" && w == U"qua") return Phrase::Yesterday;
    if (p == U"ngày" && w == U"mai") return Phrase::Tomorrow;
    if (p == U"bây" && w == U"giờ") return Phrase::Now;
    return std::nullopt;
}
bool isVietnameseHead(const std::u32string& p) { return p == U"hôm" || p == U"ngày" || p == U"bây"; }
std::optional<Phrase> englishPhrase(const std::u32string& w) {
    if (w == U"today") return Phrase::Today;
    if (w == U"tomorrow") return Phrase::Tomorrow;
    if (w == U"yesterday") return Phrase::Yesterday;
    if (w == U"now") return Phrase::Now;
    return std::nullopt;
}

// Howard Hinnant's days_from_civil / civil_from_days (proleptic Gregorian).
long daysFromCivil(int y, int m, int d) {
    y -= m <= 2;
    const long era = (y >= 0 ? y : y - 399) / 400;
    const long yoe = y - era * 400;
    const long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}
void civilFromDays(long z, int& y, int& m, int& d) {
    z += 719468;
    const long era = (z >= 0 ? z : z - 146096) / 146097;
    const long doe = z - era * 146097;
    const long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const long mp = (5 * doy + 2) / 153;
    d = static_cast<int>(doy - (153 * mp + 2) / 5 + 1);
    m = static_cast<int>(mp < 10 ? mp + 3 : mp - 9);
    y = static_cast<int>(yoe + era * 400 + (m <= 2));
}
}  // namespace

std::optional<Phrase> detectDate(char32_t boundary, const std::u32string& prevRun, const std::u32string& run,
                                 bool (*isEnglish)(const std::u32string&)) {
    if (boundary != U' ' || run.empty() || run.size() > 9) return std::nullopt;
    const std::u32string w = lower(run), p = lower(prevRun);
    if (auto m = vietnamesePhrase(p, w)) return m;
    if (auto m = englishPhrase(w)) {
        if (!p.empty() && allOf(p, isAsciiLetter) && isEnglish && isEnglish(p)) return m;
    }
    return std::nullopt;
}

std::u32string formatDate(Phrase p, const LocalTime& now) {
    char buf[32];
    if (p == Phrase::Now) {
        std::snprintf(buf, sizeof buf, "%02d:%02d", now.hour, now.minute);
        return fromAscii(buf);
    }
    int y = now.year, m = now.month, d = now.day;
    if (p != Phrase::Today) civilFromDays(daysFromCivil(y, m, d) + (p == Phrase::Tomorrow ? 1 : -1), y, m, d);
    std::snprintf(buf, sizeof buf, "%02d/%02d/%04d", d, m, y);
    return fromAscii(buf);
}

std::optional<Suggestion> dateSuggestion(const std::u32string& before, const std::u32string& prevRun,
                                         const std::u32string& run, Phrase phrase, const LocalTime& now) {
    const bool vi = isVietnameseHead(lower(prevRun));
    const std::u32string replace = (vi ? prevRun + U" " : std::u32string()) + run + U" ";
    if (!standsAlone(before, replace)) return std::nullopt;
    const std::u32string value = formatDate(phrase, now);
    return Suggestion{Kind::Date, toU16(value), toU16(replace), toU16(value + U" ")};
}

bool lastRuns(const std::u32string& before, std::u32string& prevRun, std::u32string& run) {
    prevRun.clear();
    run.clear();
    if (before.size() < 2 || before.back() != U' ') return false;
    size_t e = before.size() - 1, s = e;
    while (s > 0 && !isWhitespace(before[s - 1])) --s;
    if (s == e) return false;
    run = before.substr(s, e - s);
    if (s >= 2 && before[s - 1] == U' ') {
        size_t pe = s - 1, ps = pe;
        while (ps > 0 && !isWhitespace(before[ps - 1])) --ps;
        prevRun = before.substr(ps, pe - ps);
    }
    return true;
}

// ================================================================ key stream -> trigger

bool numberWorthChecking(const std::u32string& run, const std::u32string& prevRun) {
    if (run.empty()) return false;
    for (char32_t c : run)
        if (isDigit(c)) return true;
    if (run.size() > 8) return false;  // raw keys: "trieeuj" (triệu) is 7
    for (char32_t c : prevRun)
        if (isDigit(c)) return true;
    return false;
}

bool dateWorthReading(const std::u32string& prevRaw, const std::u32string& raw) {
    const std::u32string w = lower(raw), p = lower(prevRaw);
    if (!p.empty() && englishPhrase(w)) return true;
    if (p.empty() || w.empty() || w.size() > 7 || p.size() > 8) return false;
    const char32_t a = p[0], b = w[0];
    return (a == U'h' || a == U'n' || a == U'b') && (b == U'n' || b == U'q' || b == U'm' || b == U'g');
}

void HintTracker::reset() {
    chunk_.clear();
    prev_.clear();
    tones_.reset();
}

void HintTracker::onBackspace() {
    if (!chunk_.empty()) {
        chunk_.pop_back();
    } else {
        prev_.clear();
        tones_.reset();
    }
}

Trigger HintTracker::onChar(char32_t ch, const Commit& commit, const Enabled& en) {
    if (isLetter(ch) || isDigit(ch)) {  // hot path: a letter inside a word never triggers
        if (chunk_.size() < 48) chunk_.push_back(ch);
        return Trigger{};
    }
    ToneTrigger tt = ToneTrigger::None;
    if (en.tones) tt = tones_.feed(chunk_, ch);
    const std::u32string run = chunk_, prev = prev_;
    if (isWhitespace(ch)) {
        if (!chunk_.empty()) prev_ = chunk_;
        chunk_.clear();
    } else {
        chunk_.push_back(ch);
        if (chunk_.size() > 48) chunk_.erase(0, chunk_.size() - 48);
    }
    Trigger t;
    t.boundary = ch;
    if (ch == U'=' && en.math) {
        t.kind = TriggerKind::Math;
    } else if (ch == U' ' && en.number && numberWorthChecking(run, prev)) {
        t.kind = TriggerKind::Number;
    } else if (ch == U' ' && en.date && dateWorthReading(prev, run)) {
        t.kind = TriggerKind::Date;
    } else if (en.typo && !commit.raw.empty() && typoWorthChecking(ch, commit.raw, commit.word)) {
        t.kind = TriggerKind::Typo;
        t.raw = commit.raw;
        t.word = commit.word;
    } else if (tt != ToneTrigger::None) {
        t.kind = TriggerKind::Tones;
        t.delayMs = tt == ToneTrigger::Pause ? kTonePauseMs : 40;
    }
    return t;
}

// ================================================================ where to show

bool plausibleCaret(const Rect& r, const Rect& screen, int dpi) {
    const long scale100 = dpi > 0 ? dpi * 100 / 96 : 100;
    const long h = r.height(), w = r.width();
    if (h <= 0 || w < 0 || h > 160 * scale100 / 100 || w > 120 * scale100 / 100) return false;
    const long px = r.left, py = r.top + h / 2;
    return px >= screen.left && px < screen.right && py >= screen.top && py < screen.bottom;
}

void popupOrigin(const Rect& caret, long w, long h, const Rect& work, long& x, long& y, int dpi) {
    const long s = dpi > 0 ? dpi : 96;
    const long gap = 4 * s / 96, margin = 6 * s / 96;
    x = caret.left;
    y = caret.bottom + gap;  // below
    if (y + h > work.bottom - margin) {
        const long above = caret.top - gap - h;  // flip above
        if (above >= work.top + margin) y = above;
    }
    x = std::min(std::max(x, work.left + margin), work.right - margin - w);
    y = std::min(std::max(y, work.top + margin), work.bottom - margin - h);
    if (w + 2 * margin > work.width()) x = work.left;
    if (h + 2 * margin > work.height()) y = work.top;
}

// ================================================================ word prediction

// ---------------------------------------------------------------- Học từ bạn gõ

bool learnable(const std::u32string& w) {
    if (w.empty() || w.size() > 12) return false;  // NFC: one code point per Vietnamese letter
    int run = 0;
    char32_t prev = 0;
    for (char32_t c : w) {
        if (!isLetter(c)) return false;
        run = c == prev ? run + 1 : 1;
        if (run >= 3) return false;
        prev = c;
    }
    return true;
}

bool LearnTracker::commit(const std::u32string& word, char32_t boundary, bool standsAlone, int weight, Event& out) {
    const bool had = pending_;
    if (had) out = held_;
    pending_ = false;
    const std::u32string w = lower(word);
    if (!standsAlone || !learnable(w)) {
        prev1_.clear();
        prev2_.clear();
        return had;
    }
    held_ = Event{w, prev1_, prev2_, weight, word};
    pending_ = true;
    if (boundary == U' ') {
        prev2_ = prev1_;
        prev1_ = w;
    } else {
        prev1_.clear();
        prev2_.clear();
    }
    return had;
}

void LearnTracker::replacePending(const std::u32string& fixed) {
    if (!pending_) return;
    const std::u32string f = lower(fixed);
    if (!learnable(f)) return discard();
    if (prev1_ == held_.word) prev1_ = f;
    held_.word = f;
    held_.form = fixed;
}

void LearnTracker::discard() {
    pending_ = false;
    prev1_.clear();
    prev2_.clear();
}

bool LearnTracker::breakContext(Event& out) {
    const bool had = pending_;
    if (had) out = held_;
    discard();
    return had;
}

bool predictionAllowedForApp(const std::string& exe) {
    // Code editors / IDEs: Tab indents, and the editor completes code itself.
    static const char* const kEditors[] = {
        "code.exe",      "code - insiders.exe", "cursor.exe",     "windsurf.exe",  "devenv.exe",
        "sublime_text.exe", "notepad++.exe",    "zed.exe",        "idea64.exe",    "idea.exe",
        "pycharm64.exe", "webstorm64.exe",      "clion64.exe",    "rider64.exe",   "goland64.exe",
        "phpstorm64.exe", "rubymine64.exe",     "datagrip64.exe", "studio64.exe",  "eclipse.exe",
        "gvim.exe",      "vim.exe",             "emacs.exe",      "positron.exe",  "fleet.exe",
    };
    for (const char* e : kEditors)
        if (exe == e) return false;
    // Terminals, VM / remote viewers, games: their built-in rule types through the hook or
    // not at all — no caret hints there anyway.
    AppMode m;
    if (builtInAppMode(exe, m) && m != AppMode::InPlace && m != AppMode::Composition) return false;
    return true;
}

std::optional<Suggestion> predictSuggestion(const std::u32string& before, const std::u32string& typed,
                                            const std::u16string& candidate) {
    if (candidate.empty()) return std::nullopt;
    if (!typed.empty()) {
        if (!standsAlone(before, typed)) return std::nullopt;
    } else {
        if (before.size() < 2 || before.back() != U' ' || !isLetter(before[before.size() - 2])) return std::nullopt;
    }
    Suggestion s;
    s.kind = Kind::Predict;
    s.display = candidate;
    s.replace = toU16(typed);
    s.insert = candidate + u" ";
    return s;
}

// ---------------------------------------------------------------- email domains

const char32_t* const kEmailProviders[4] = {U"gmail.com", U"icloud.com", U"yahoo.com", U"outlook.com"};

namespace {
bool emailLocalChar(char32_t c) {
    return (c >= U'a' && c <= U'z') || (c >= U'A' && c <= U'Z') || (c >= U'0' && c <= U'9') || c == U'.' ||
           c == U'_' || c == U'%' || c == U'+' || c == U'-';
}
bool emailDelimiter(char32_t c) {
    return isWhitespace(c) || c == 0xA0 || c == U',' || c == U';' || c == U'<' || c == U'(' || c == U':' ||
           c == U'"' || c == U'\'';
}
bool endsWithU32(const std::u32string& s, const std::u32string& t) {
    return s.size() >= t.size() && s.compare(s.size() - t.size(), t.size(), t) == 0;
}
}  // namespace

std::optional<Suggestion> emailDomainSuggestion(const std::u32string& before, const std::u32string& typed,
                                                const std::u32string& raw) {
    const size_t at = before.rfind(U'@');
    if (at == std::u32string::npos) return std::nullopt;
    const std::u32string partial = before.substr(at + 1);
    std::u32string match = partial;
    bool mangled = false;
    if (!typed.empty()) {
        if (!endsWithU32(partial, typed)) return std::nullopt;
        match = partial.substr(0, partial.size() - typed.size()) + raw;
        mangled = lower(typed) != lower(raw);
    }
    if (match.size() > 11) return std::nullopt;
    for (char32_t c : match)
        if (!emailTokenChar(c)) return std::nullopt;
    size_t i = at;
    while (i > 0 && !emailDelimiter(before[i - 1])) --i;
    if (i == at) return std::nullopt;  // empty local part
    for (size_t j = i; j < at; ++j)
        if (!emailLocalChar(before[j])) return std::nullopt;  // "phúc@", "x@y@"
    const std::u32string p = lower(match);
    for (const char32_t* d : kEmailProviders) {
        const std::u32string domain(d);
        if (domain.size() <= p.size() || domain.compare(0, p.size(), p) != 0) continue;
        Suggestion s;
        s.kind = Kind::Email;
        s.display = toU16(domain);
        if (mangled) {  // Telex changed the composing word: replace it, from its raw keys on
            s.replace = toU16(typed);
            s.insert = toU16(domain.substr(p.size() - raw.size()));
        } else {
            s.insert = toU16(domain.substr(p.size()));
        }
        return s;
    }
    return std::nullopt;
}

Suggestion retroHint(const std::u16string& display, const std::u16string& replace, const std::u16string& insert) {
    return Suggestion{Kind::Retro, display, replace, insert};
}

Trigger withRetro(const Trigger& fromTracker, bool retroOffered) {
    if (!retroOffered) return fromTracker;
    Trigger t;
    t.kind = TriggerKind::Retro;
    t.delayMs = 40;  // the app has typed the boundary key by then
    return t;
}

std::optional<Suggestion> retroSuggestion(const std::u32string& before, const Suggestion& offer) {
    if (offer.kind != Kind::Retro || offer.replace.empty() || !hintStillValid(offer, before)) return std::nullopt;
    return offer;
}

bool hintStillValid(const Suggestion& s, const std::u32string& before) {
    // Retro: the rewritten words start mid-word ("í" of "Hí"): the exact tail is the check.
    if (s.kind == Kind::Retro) return !s.replace.empty() && endsWithU32(before, toU32(s.replace));
    if (s.kind == Kind::Email) {
        const size_t at = before.rfind(U'@');
        if (at == std::u32string::npos) return false;
        const std::u32string tail = before.substr(at + 1), rep = toU32(s.replace);
        if (!endsWithU32(tail, rep)) return false;
        return lower(tail.substr(0, tail.size() - rep.size())) + toU32(s.insert) == lower(toU32(s.display));
    }
    if (s.kind == Kind::Math) return !before.empty() && before.back() == U'=';
    if (s.kind == Kind::Predict && s.replace.empty())
        return before.size() >= 2 && before.back() == U' ' && isLetter(before[before.size() - 2]);
    return standsAlone(before, toU32(s.replace));
}

bool predictMuted(const std::u32string& typed, const std::u32string& declined) {
    if (declined.empty() || typed.empty()) return false;
    const std::u32string t = lower(typed), d = lower(declined);
    return t.size() >= d.size() && t.compare(0, d.size(), d) == 0;
}

std::u32string acceptSpaceReplacement(char32_t key) {
    switch (key) {
    case U'.': case U',': case U'?': case U'!': case U';': case U':':  // AutoSpace.triggers
    case U')': case U']': case U'}': case 0x201D: case 0x2019: case 0xBB: case 0x203A:
        return std::u32string(1, key) + U" ";
    case U'/':
        return std::u32string(1, key);
    default:
        return {};
    }
}

AcceptSpaceAct acceptSpaceKey(AcceptedSpace& st, char32_t ch, std::u32string& expect, std::u32string& replacement) {
    const AcceptedSpace was = st;
    st = AcceptedSpace();
    if (!was.carried.empty()) {
        if (ch != U' ') return AcceptSpaceAct::Pass;
        expect = was.carried;
        return AcceptSpaceAct::Swallow;
    }
    replacement = was.inserted.empty() || ch == 0 ? std::u32string() : acceptSpaceReplacement(ch);
    if (replacement.empty()) return AcceptSpaceAct::Pass;
    expect = was.inserted;
    return AcceptSpaceAct::Replace;
}

}  // namespace vtx::hints
