#include "portable.h"

#include <cstdlib>

namespace vtx::portable {

namespace {
bool isSep(wchar_t c) { return c == L'\\' || c == L'/'; }

wchar_t lowerW(wchar_t c) { return (c >= L'A' && c <= L'Z') ? static_cast<wchar_t>(c - L'A' + L'a') : c; }

std::string lowerA(std::string s) {
    for (char& c : s)
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return s;
}

bool parseUnsigned(const std::string& s, uint64_t& out) {
    if (s.empty() || s.size() > 20) return false;
    uint64_t v = 0;
    for (char c : s) {
        if (c < '0' || c > '9') return false;
        const uint64_t d = static_cast<uint64_t>(c - '0');
        if (v > (UINT64_MAX - d) / 10) return false;
        v = v * 10 + d;
    }
    out = v;
    return true;
}

std::string escape(const std::string& s) {
    std::string o;
    for (char c : s) {
        switch (c) {
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default: o.push_back(c);
        }
    }
    return o;
}

bool unescape(const std::string& s, std::string& out) {
    out.clear();
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] != '\\') {
            out.push_back(s[i]);
            continue;
        }
        if (++i >= s.size()) return false;
        switch (s[i]) {
            case '\\': out.push_back('\\'); break;
            case 'n': out.push_back('\n'); break;
            case 'r': out.push_back('\r'); break;
            case 't': out.push_back('\t'); break;
            default: return false;
        }
    }
    return true;
}

int hexVal(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
}  // namespace

std::wstring exeDirOf(const std::wstring& exePath) {
    const size_t p = exePath.find_last_of(L"\\/");
    if (p == std::wstring::npos) return L"";
    return exePath.substr(0, p);
}

std::wstring joinPath(const std::wstring& dir, const std::wstring& name) {
    if (dir.empty()) return name;
    return isSep(dir.back()) ? dir + name : dir + L"\\" + name;
}

bool detectPortable(const std::wstring& exeDir, const std::function<bool(const std::wstring&)>& fileExists) {
    if (exeDir.empty() || !fileExists) return false;
    for (const wchar_t* m : kMarkerNames)
        if (fileExists(joinPath(exeDir, m))) return true;
    return false;
}

std::wstring settingsPath(const std::wstring& exeDir, bool exeDirWritable, const std::wstring& appData) {
    if (!exeDir.empty() && exeDirWritable) return joinPath(exeDir, kSettingsFileName);
    if (!appData.empty()) return joinPath(joinPath(appData, L"VietTelex"), kSettingsFileName);
    return L"";
}

bool launchedFromArchive(const std::wstring& exePath) {
    // Folder names only (never the exe's own name), lower-cased, either separator.
    auto archiveFolder = [](const std::wstring& f) {
        const std::wstring zip = L".zip";
        return (f.size() > zip.size() && f.compare(f.size() - zip.size(), zip.size(), zip) == 0) ||
               f.rfind(L"7zo", 0) == 0 || f.rfind(L"rar$ex", 0) == 0;
    };
    std::wstring seg;
    for (wchar_t c : exePath) {
        if (!isSep(c)) {
            seg.push_back(lowerW(c));
            continue;
        }
        if (archiveFolder(seg)) return true;
        seg.clear();
    }
    return false;
}

bool yields(int tipProp, unsigned fgLangId) { return tipProp != 0 || fgLangId == 0x042A; }

HookPlan hookPlan(AppMode mode, bool passwordField, bool yieldsHere) {
    HookPlan p;
    if (mode == AppMode::Off || passwordField || yieldsHere) return p;
    p.install = true;
    return p;
}

bool isPasswordField(const std::string& windowClass, uint32_t style) {
    constexpr uint32_t kEsPassword = 0x0020;
    if (!(style & kEsPassword)) return false;
    const std::string c = lowerA(windowClass);
    return c == "edit" || c.rfind("richedit", 0) == 0;
}

std::wstring autostartCommand(const std::wstring& exePath) { return L"\"" + exePath + L"\" --background"; }

bool autostartPointsHere(const std::wstring& runValue, const std::wstring& exePath) {
    const std::wstring want = autostartCommand(exePath);
    if (runValue.size() != want.size() || exePath.empty()) return false;
    for (size_t i = 0; i < want.size(); ++i)
        if (lowerW(runValue[i]) != lowerW(want[i])) return false;
    return true;
}

// ---------------------------------------------------------------- KeyValueFile

bool KeyValueFile::validName(const std::string& name) {
    if (name.empty()) return false;
    for (char c : name)
        if (c == '=' || c == '\r' || c == '\n') return false;
    return name[0] != ';' && name[0] != '#' && name[0] != '[';
}

bool KeyValueFile::getDword(const std::string& name, uint32_t& out) const {
    auto it = map_.find(name);
    if (it == map_.end() || it->second.type != Type::Dword) return false;
    out = static_cast<uint32_t>(it->second.number);
    return true;
}

bool KeyValueFile::getQword(const std::string& name, uint64_t& out) const {
    auto it = map_.find(name);
    if (it == map_.end() || it->second.type != Type::Qword) return false;
    out = it->second.number;
    return true;
}

bool KeyValueFile::getString(const std::string& name, std::string& out) const {
    auto it = map_.find(name);
    if (it == map_.end() || it->second.type != Type::String) return false;
    out = it->second.bytes;
    return true;
}

bool KeyValueFile::getBinary(const std::string& name, std::string& out) const {
    auto it = map_.find(name);
    if (it == map_.end() || it->second.type != Type::Binary) return false;
    out = it->second.bytes;
    return true;
}

void KeyValueFile::setDword(const std::string& name, uint32_t v) {
    if (!validName(name)) return;
    map_[name] = Value{Type::Dword, v, {}};
}
void KeyValueFile::setQword(const std::string& name, uint64_t v) {
    if (!validName(name)) return;
    map_[name] = Value{Type::Qword, v, {}};
}
void KeyValueFile::setString(const std::string& name, const std::string& v) {
    if (!validName(name)) return;
    map_[name] = Value{Type::String, 0, v};
}
void KeyValueFile::setBinary(const std::string& name, const std::string& v) {
    if (!validName(name)) return;
    map_[name] = Value{Type::Binary, 0, v};
}

std::map<std::string, uint32_t> KeyValueFile::dwordsWithPrefix(const std::string& prefix) const {
    std::map<std::string, uint32_t> out;
    for (auto it = map_.lower_bound(prefix); it != map_.end() && it->first.compare(0, prefix.size(), prefix) == 0;
         ++it)
        if (it->second.type == Type::Dword && it->first.size() > prefix.size())
            out[it->first.substr(prefix.size())] = static_cast<uint32_t>(it->second.number);
    return out;
}

std::string KeyValueFile::serialize() const {
    static const char kHex[] = "0123456789abcdef";
    std::string o = "; VietTelex portable settings (UTF-8). Delete this file to start over.\r\n[VietTelex]\r\n";
    for (const auto& kv : map_) {
        o += kv.first;
        o += '=';
        const Value& v = kv.second;
        switch (v.type) {
            case Type::Dword: o += "dword:" + std::to_string(static_cast<uint32_t>(v.number)); break;
            case Type::Qword: o += "qword:" + std::to_string(v.number); break;
            case Type::String: o += "sz:" + escape(v.bytes); break;
            case Type::Binary:
                o += "hex:";
                for (unsigned char c : v.bytes) {
                    o.push_back(kHex[c >> 4]);
                    o.push_back(kHex[c & 15]);
                }
                break;
        }
        o += "\r\n";
    }
    return o;
}

void KeyValueFile::parse(const std::string& text) {
    map_.clear();
    size_t pos = 0;
    // A UTF-8 BOM (Notepad) is fine.
    if (text.compare(0, 3, "\xEF\xBB\xBF") == 0) pos = 3;
    while (pos < text.size()) {
        size_t end = text.find('\n', pos);
        if (end == std::string::npos) end = text.size();
        std::string line = text.substr(pos, end - pos);
        pos = end + 1;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty() || line[0] == ';' || line[0] == '#' || line[0] == '[') continue;
        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string name = line.substr(0, eq), rest = line.substr(eq + 1);
        if (!validName(name)) continue;
        const size_t colon = rest.find(':');
        if (colon == std::string::npos) continue;
        const std::string type = rest.substr(0, colon), data = rest.substr(colon + 1);
        uint64_t n = 0;
        if (type == "dword") {
            if (parseUnsigned(data, n) && n <= 0xFFFFFFFFull) setDword(name, static_cast<uint32_t>(n));
        } else if (type == "qword") {
            if (parseUnsigned(data, n)) setQword(name, n);
        } else if (type == "sz") {
            std::string s;
            if (unescape(data, s)) setString(name, s);
        } else if (type == "hex") {
            if (data.size() % 2) continue;
            std::string b;
            bool ok = true;
            for (size_t i = 0; i < data.size() && ok; i += 2) {
                const int hi = hexVal(data[i]), lo = hexVal(data[i + 1]);
                ok = hi >= 0 && lo >= 0;
                b.push_back(static_cast<char>((hi << 4) | (lo & 15)));
            }
            if (ok) setBinary(name, b);
        }
    }
}

}  // namespace vtx::portable
