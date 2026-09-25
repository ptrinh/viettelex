#include "shortcuts.h"

#include <cstdint>
#include <vector>

#include "utf.h"

namespace vtx {

namespace {

void skipWs(const std::string& s, size_t& i) {
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
}

void appendUtf8(std::string& out, char32_t cp) {
    std::u16string tmp;
    if (cp >= 0x10000) {
        cp -= 0x10000;
        tmp.push_back(static_cast<char16_t>(0xD800 + (cp >> 10)));
        tmp.push_back(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
    } else {
        tmp.push_back(static_cast<char16_t>(cp));
    }
    out += utf16ToUtf8(tmp);
}

bool hex4(const std::string& s, size_t i, uint32_t& v) {
    if (i + 4 > s.size()) return false;
    v = 0;
    for (size_t k = 0; k < 4; ++k) {
        char c = s[i + k];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= static_cast<uint32_t>(c - '0');
        else if (c >= 'a' && c <= 'f') v |= static_cast<uint32_t>(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') v |= static_cast<uint32_t>(c - 'A' + 10);
        else return false;
    }
    return true;
}

bool parseString(const std::string& s, size_t& i, std::string& out) {
    if (i >= s.size() || s[i] != '"') return false;
    ++i;
    out.clear();
    while (i < s.size()) {
        char c = s[i++];
        if (c == '"') return true;
        if (c != '\\') { out.push_back(c); continue; }
        if (i >= s.size()) return false;
        char e = s[i++];
        switch (e) {
            case '"': out.push_back('"'); break;
            case '\\': out.push_back('\\'); break;
            case '/': out.push_back('/'); break;
            case 'b': out.push_back('\b'); break;
            case 'f': out.push_back('\f'); break;
            case 'n': out.push_back('\n'); break;
            case 'r': out.push_back('\r'); break;
            case 't': out.push_back('\t'); break;
            case 'u': {
                uint32_t v;
                if (!hex4(s, i, v)) return false;
                i += 4;
                if (v >= 0xD800 && v <= 0xDBFF && i + 6 <= s.size() && s[i] == '\\' && s[i + 1] == 'u') {
                    uint32_t lo;
                    if (hex4(s, i + 2, lo) && lo >= 0xDC00 && lo <= 0xDFFF) {
                        i += 6;
                        v = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00);
                    }
                }
                appendUtf8(out, v);
                break;
            }
            default: return false;
        }
    }
    return false;
}

std::string jsonEscape(const std::string& s) {
    std::string o = "\"";
    for (unsigned char c : s) {
        switch (c) {
            case '"': o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if (c < 0x20) {
                    static const char* hx = "0123456789abcdef";
                    o += "\\u00";
                    o.push_back(hx[c >> 4]);
                    o.push_back(hx[c & 15]);
                } else {
                    o.push_back(static_cast<char>(c));
                }
        }
    }
    o += '"';
    return o;
}

std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r')) ++a;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r')) --b;
    return s.substr(a, b - a);
}

bool hasWhitespace(const std::string& s) {
    for (char c : s)
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f') return true;
    return false;
}

size_t charCount(const std::string& utf8) { return utf8ToUtf16(utf8).size(); }

}  // namespace

bool parseFlatJson(const std::string& text, StringMap& out) {
    out.clear();
    size_t i = 0;
    // Skip UTF-8 BOM.
    if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF &&
        static_cast<unsigned char>(text[1]) == 0xBB && static_cast<unsigned char>(text[2]) == 0xBF)
        i = 3;
    skipWs(text, i);
    if (i >= text.size() || text[i] != '{') return false;
    ++i;
    skipWs(text, i);
    if (i < text.size() && text[i] == '}') { ++i; skipWs(text, i); return i == text.size(); }
    while (true) {
        std::string k, v;
        skipWs(text, i);
        if (!parseString(text, i, k)) return false;
        skipWs(text, i);
        if (i >= text.size() || text[i] != ':') return false;
        ++i;
        skipWs(text, i);
        if (!parseString(text, i, v)) return false;
        out[k] = v;
        skipWs(text, i);
        if (i < text.size() && text[i] == ',') { ++i; continue; }
        if (i < text.size() && text[i] == '}') { ++i; break; }
        return false;
    }
    skipWs(text, i);
    return i == text.size();
}

std::string toFlatJson(const StringMap& m) {
    std::string o = "{";
    bool first = true;
    for (const auto& kv : m) {
        if (!first) o += ",";
        first = false;
        o += jsonEscape(kv.first);
        o += ":";
        o += jsonEscape(kv.second);
    }
    o += "}";
    return o;
}

bool parseShortcutFile(const std::string& text, StringMap& out) {
    out.clear();
    StringMap json;
    if (parseFlatJson(text, json) && !json.empty()) { out = json; return true; }
    size_t start = 0;
    while (start <= text.size()) {
        size_t nl = text.find('\n', start);
        std::string raw = text.substr(start, nl == std::string::npos ? std::string::npos : nl - start);
        start = nl == std::string::npos ? text.size() + 1 : nl + 1;
        std::string line = trim(raw);
        if (line.empty() || line[0] == ';' || line[0] == '#' || line.compare(0, 2, "//") == 0) continue;
        size_t colon = line.find(':');
        if (colon == std::string::npos) continue;
        std::string key = trim(line.substr(0, colon));
        std::string value = trim(line.substr(colon + 1));
        if (value.size() >= 2 && ((value.front() == '"' && value.back() == '"') ||
                                  (value.front() == '\'' && value.back() == '\'')))
            value = value.substr(1, value.size() - 2);
        if (key.empty() || value.empty() || charCount(key) > 64 || hasWhitespace(key)) continue;
        out[key] = value;
    }
    return !out.empty();
}

std::string exportShortcutsYaml(const StringMap& m) {
    std::string o = "# VietTelex — bảng gõ tắt\n";
    for (const auto& kv : m) {
        const std::string& v = kv.second;
        bool quote = !v.empty() && (v.front() == ' ' || v.back() == ' ' || v.front() == '\'' ||
                                    v.front() == '"' || v.front() == '#');
        o += kv.first + ": " + (quote ? "\"" + v + "\"" : v) + "\n";
    }
    return o;
}

const std::u16string* findShortcut(const std::map<std::u16string, std::u16string>& table,
                                   const std::u16string& composed, const std::u16string& raw,
                                   char16_t charBeforeWord) {
    if (table.empty() || composed.empty()) return nullptr;
    if (gluesShortcutToken(charBeforeWord)) return nullptr;
    auto it = table.find(composed);
    if (it != table.end()) return &it->second;
    if (!raw.empty()) {
        it = table.find(raw);
        if (it != table.end()) return &it->second;
    }
    return nullptr;
}

}  // namespace vtx
