#include "macro_import.h"

#include "utf.h"

namespace vtx {

namespace {

bool validUtf8(const std::string& s) {
    size_t i = 0;
    while (i < s.size()) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        if (c == 0) return false;  // NUL: not a text file (or UTF-16 we failed to spot)
        size_t n;
        char32_t cp;
        if (c < 0x80) {
            ++i;
            continue;
        }
        if ((c >> 5) == 0x6) { n = 2; cp = c & 0x1F; }
        else if ((c >> 4) == 0xE) { n = 3; cp = c & 0x0F; }
        else if ((c >> 3) == 0x1E) { n = 4; cp = c & 0x07; }
        else return false;
        if (i + n > s.size()) return false;
        for (size_t k = 1; k < n; ++k) {
            const unsigned char cc = static_cast<unsigned char>(s[i + k]);
            if ((cc >> 6) != 0x2) return false;
            cp = (cp << 6) | (cc & 0x3F);
        }
        if ((n == 2 && cp < 0x80) || (n == 3 && cp < 0x800) || (n == 4 && (cp < 0x10000 || cp > 0x10FFFF)) ||
            (cp >= 0xD800 && cp <= 0xDFFF))
            return false;  // overlong / surrogate / out of range
        i += n;
    }
    return true;
}

std::string fromUtf16(const std::string& b, size_t start, bool bigEndian) {
    std::u16string u;
    u.reserve((b.size() - start) / 2);
    for (size_t i = start; i + 1 < b.size(); i += 2) {
        const unsigned char lo = static_cast<unsigned char>(b[i + (bigEndian ? 1 : 0)]);
        const unsigned char hi = static_cast<unsigned char>(b[i + (bigEndian ? 0 : 1)]);
        u.push_back(static_cast<char16_t>(lo | (hi << 8)));
    }
    return utf16ToUtf8(u);
}

bool hasWhitespace(const std::string& s) {
    for (char c : s)
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f') return true;
    return false;
}

bool usableKey(const std::string& key) {
    return !key.empty() && !hasWhitespace(key) && utf8ToUtf16(key).size() <= 64;
}

// Lines without their terminator (\n, \r\n).
template <class F>
void forEachLine(const std::string& text, F&& f) {
    size_t start = 0;
    while (start < text.size()) {
        size_t nl = text.find('\n', start);
        std::string line = text.substr(start, nl == std::string::npos ? std::string::npos : nl - start);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        f(line);
        if (nl == std::string::npos) break;
        start = nl + 1;
    }
}

std::string firstLine(const std::string& text) {
    std::string l = text.substr(0, text.find('\n'));
    if (!l.empty() && l.back() == '\r') l.pop_back();
    return l;
}

// mactab.cpp readHeader: "***", optional spaces, "version=<n>". -1 = no header.
int uniKeyHeaderVersion(const std::string& line) {
    size_t p = line.find("***");
    if (p == std::string::npos) return -1;
    p += 3;
    while (p < line.size() && line[p] == ' ') ++p;
    if (line.compare(p, 8, "version=") != 0) return -1;
    p += 8;
    if (p >= line.size() || line[p] < '0' || line[p] > '9') return -1;
    int v = 0;
    while (p < line.size() && line[p] >= '0' && line[p] <= '9' && v < 1000) v = v * 10 + (line[p++] - '0');
    return v;
}

void addEntry(MacroImport& out, const std::string& key, const std::string& value) {
    if (!usableKey(key) || value.empty()) {
        ++out.skipped;
        return;
    }
    out.entries[key] = value;
}

}  // namespace

bool decodeTextFile(const std::string& b, std::string& utf8, TextEncoding* enc) {
    auto set = [&](TextEncoding e) {
        if (enc) *enc = e;
    };
    utf8.clear();
    set(TextEncoding::Unknown);
    const auto at = [&](size_t i) { return static_cast<unsigned char>(b[i]); };
    if (b.size() >= 3 && at(0) == 0xEF && at(1) == 0xBB && at(2) == 0xBF) {
        utf8 = b.substr(3);
        if (!validUtf8(utf8)) return false;
        set(TextEncoding::Utf8Bom);
        return true;
    }
    if (b.size() >= 2 && at(0) == 0xFF && at(1) == 0xFE) {
        utf8 = fromUtf16(b, 2, false);
        set(TextEncoding::Utf16Le);
        return true;
    }
    if (b.size() >= 2 && at(0) == 0xFE && at(1) == 0xFF) {
        utf8 = fromUtf16(b, 2, true);
        set(TextEncoding::Utf16Be);
        return true;
    }
    // No BOM. UTF-16LE text of mostly-ASCII keys has NUL high bytes (odd offsets).
    if (b.size() >= 4 && b.size() % 2 == 0) {
        size_t oddNul = 0, evenNul = 0;
        for (size_t i = 0; i < b.size(); ++i)
            if (at(i) == 0) (i % 2 ? oddNul : evenNul)++;
        const size_t pairs = b.size() / 2;
        if (oddNul * 2 >= pairs && evenNul == 0) {
            utf8 = fromUtf16(b, 0, false);
            set(TextEncoding::Utf16Le);
            return true;
        }
    }
    if (!validUtf8(b)) return false;
    utf8 = b;
    set(TextEncoding::Utf8);
    return true;
}

bool parseMacroFile(const std::string& bytes, MacroImport& out) {
    out = MacroImport{};
    std::string text;
    if (!decodeTextFile(bytes, text, &out.encoding)) return false;
    const std::string head = firstLine(text);
    const bool openKey = head.find("Compatible OpenKey Macro Data file") != std::string::npos;
    const int version = uniKeyHeaderVersion(head);
    if (openKey || version >= 0) {
        out.format = openKey ? MacroFormat::OpenKey : MacroFormat::UniKey;
        out.viqr = !openKey && version != 1;
        bool first = true;
        forEachLine(text, [&](const std::string& line) {
            if (first) {  // the header (both programs skip it)
                first = false;
                return;
            }
            const size_t colon = line.find(':');
            if (colon == std::string::npos) return;  // not a macro line (UniKey: addItem fails)
            std::string key = line.substr(0, colon), value = line.substr(colon + 1);
            // OpenKey readFromFile: an empty name takes the next ':'-field ("::" macros).
            while (key.empty() && !value.empty()) {
                const size_t c2 = value.find(':');
                if (c2 == std::string::npos) break;
                key += ":" + value.substr(0, c2);
                value = value.substr(c2 + 1);
            }
            addEntry(out, key, value);
        });
        return !out.entries.empty();
    }
    // Generic: VietTelex/macOS formats, then "key<TAB>value" lines the colon parser skips.
    StringMap m;
    if (parseShortcutFile(text, m)) out.entries = m;
    forEachLine(text, [&](const std::string& line) {
        if (line.find(':') != std::string::npos || line.empty() || line[0] == '#' || line[0] == ';') return;
        const size_t tab = line.find('\t');
        if (tab == std::string::npos) return;
        std::string value = line.substr(tab + 1);
        while (!value.empty() && value.front() == '\t') value.erase(0, 1);
        addEntry(out, line.substr(0, tab), value);
    });
    if (!out.entries.empty()) out.format = MacroFormat::Generic;
    return !out.entries.empty();
}

}  // namespace vtx
