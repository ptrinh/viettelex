#include "update_check.h"

#include "shortcuts.h"  // parseFlatJson

namespace vtx {

namespace {
// Extract the text of the object value of top-level key `key` ("{...}"), honouring
// strings and nesting. Empty when absent.
std::string objectValue(const std::string& s, const std::string& key) {
    const std::string needle = "\"" + key + "\"";
    size_t pos = 0;
    while ((pos = s.find(needle, pos)) != std::string::npos) {
        size_t i = pos + needle.size();
        while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) ++i;
        if (i < s.size() && s[i] == ':') {
            ++i;
            while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) ++i;
            if (i >= s.size() || s[i] != '{') return {};
            size_t start = i;
            int depth = 0;
            bool inStr = false;
            for (; i < s.size(); ++i) {
                char c = s[i];
                if (inStr) {
                    if (c == '\\') ++i;
                    else if (c == '"') inStr = false;
                    continue;
                }
                if (c == '"') inStr = true;
                else if (c == '{') ++depth;
                else if (c == '}' && --depth == 0) return s.substr(start, i - start + 1);
            }
            return {};
        }
        pos = i;
    }
    return {};
}
}  // namespace

bool parseStableJson(const std::string& json, WindowsRelease& out) {
    out = WindowsRelease{};
    std::string obj = objectValue(json, "windows");
    if (obj.empty()) return false;
    StringMap m;
    if (!parseFlatJson(obj, m)) return false;
    auto get = [&](const char* k) {
        auto it = m.find(k);
        return it == m.end() ? std::string() : it->second;
    };
    out.version = get("version");
    out.x64 = get("x64");
    out.arm64 = get("arm64");
    out.notes = get("notes");
    if (out.version.empty() || compareVersions(out.version, "0") <= 0) return false;
    return true;
}

int compareVersions(const std::string& a, const std::string& b) {
    size_t i = 0, j = 0;
    while (i < a.size() || j < b.size()) {
        unsigned long x = 0, y = 0;
        while (i < a.size() && a[i] != '.') {
            if (a[i] >= '0' && a[i] <= '9') x = x * 10 + static_cast<unsigned long>(a[i] - '0');
            ++i;
        }
        while (j < b.size() && b[j] != '.') {
            if (b[j] >= '0' && b[j] <= '9') y = y * 10 + static_cast<unsigned long>(b[j] - '0');
            ++j;
        }
        if (x != y) return x < y ? -1 : 1;
        if (i < a.size()) ++i;
        if (j < b.size()) ++j;
    }
    return 0;
}

bool isTrustedDownloadUrl(const std::string& url) {
    static const char* const kPrefixes[] = {
        "https://github.com/ptrinh/viettelex/releases/download/",
        "https://viettelex.com/",
    };
    for (const char* p : kPrefixes) {
        std::string pre(p);
        if (url.compare(0, pre.size(), pre) == 0 && url.find("..") == std::string::npos) return true;
    }
    return false;
}

}  // namespace vtx
