// settings.cpp — see settings.h / SETTINGS.md.
#include "viettelex/settings.h"

#include "viettelex/keys.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace viettelex {

namespace {

std::string trim(const std::string &s) {
    size_t b = 0, e = s.size();
    while (b < e && (s[b] == ' ' || s[b] == '\t' || s[b] == '\r')) ++b;
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r')) --e;
    return s.substr(b, e - b);
}

std::string lower(std::string s) {
    for (auto &c : s)
        if (c >= 'A' && c <= 'Z') c = char(c - 'A' + 'a');
    return s;
}

// Parse a TOML basic string starting at s[i] == '"'. Sets `end` past the closing quote.
bool parseQuoted(const std::string &s, size_t i, std::string &out, size_t &end) {
    if (i >= s.size() || s[i] != '"') return false;
    out.clear();
    for (size_t k = i + 1; k < s.size(); ++k) {
        char c = s[k];
        if (c == '\\' && k + 1 < s.size()) {
            char n = s[++k];
            switch (n) {
            case 'n': out += '\n'; break;
            case 't': out += '\t'; break;
            case '"': out += '"'; break;
            case '\\': out += '\\'; break;
            default: out += n; break;
            }
        } else if (c == '"') {
            end = k + 1;
            return true;
        } else {
            out += c;
        }
    }
    return false;
}

std::string quote(const std::string &v) {
    std::string o = "\"";
    for (char c : v) {
        switch (c) {
        case '"': o += "\\\""; break;
        case '\\': o += "\\\\"; break;
        case '\n': o += "\\n"; break;
        case '\t': o += "\\t"; break;
        default: o += c;
        }
    }
    return o + "\"";
}

struct Value {
    enum { None, Bool, Str, Int } kind = None;
    bool b = false;
    std::string s;
};

Value parseValue(const std::string &raw) {
    Value v;
    std::string t = trim(raw);
    if (t.empty()) return v;
    if (t[0] == '"') {
        size_t end = 0;
        if (parseQuoted(t, 0, v.s, end)) v.kind = Value::Str;
        return v;
    }
    // strip trailing comment for bare values
    size_t hash = t.find('#');
    if (hash != std::string::npos) t = trim(t.substr(0, hash));
    if (t == "true") { v.kind = Value::Bool; v.b = true; }
    else if (t == "false") { v.kind = Value::Bool; v.b = false; }
    else if (!t.empty() && (isdigit((unsigned char)t[0]) || t[0] == '-')) { v.kind = Value::Int; v.s = t; }
    return v;
}

void setBool(bool &dst, const Value &v) {
    if (v.kind == Value::Bool) dst = v.b;
}

bool isWhitespace(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }

size_t utf8Count(const std::string &s) {
    size_t n = 0;
    for (unsigned char c : s)
        if ((c & 0xc0) != 0x80) ++n;
    return n;
}

bool startsWith(const std::string &s, const char *p) { return s.rfind(p, 0) == 0; }
bool endsWith(const std::string &s, char c) { return !s.empty() && s.back() == c; }

std::string envOr(const char *var, const std::string &fallbackUnderHome) {
    const char *v = std::getenv(var);
    if (v && *v) return v;
    const char *home = std::getenv("HOME");
    return std::string(home ? home : "") + "/" + fallbackUnderHome;
}

}  // namespace

// MARK: - config.toml

Settings parseConfig(const std::string &toml) {
    Settings s;
    std::istringstream in(toml);
    std::string line, section;
    while (std::getline(in, line)) {
        std::string t = trim(line);
        if (t.empty() || t[0] == '#') continue;
        if (t[0] == '[') {
            size_t close = t.find(']');
            if (close != std::string::npos) section = trim(t.substr(1, close - 1));
            continue;
        }
        // key
        std::string key;
        size_t pos;
        if (t[0] == '"') {
            size_t end = 0;
            if (!parseQuoted(t, 0, key, end)) continue;
            pos = t.find('=', end);
        } else {
            pos = t.find('=');
            if (pos == std::string::npos) continue;
            key = trim(t.substr(0, pos));
        }
        if (pos == std::string::npos) continue;
        Value v = parseValue(t.substr(pos + 1));
        if (section == "typing") {
            if (key == "input_method") {
                if (v.kind == Value::Str) s.vni = lower(v.s) == "vni";
            }
            else if (key == "simple_telex") setBool(s.simpleTelex, v);
            else if (key == "free_marking") setBool(s.freeMarking, v);
            else if (key == "modern_tone") setBool(s.modernTone, v);
            else if (key == "quick_telex") setBool(s.quickTelex, v);
            else if (key == "spell_check") setBool(s.spellCheck, v);
            else if (key == "auto_restore") setBool(s.autoRestore, v);
            else if (key == "teencode") setBool(s.teencode, v);
            else if (key == "contextual_english") setBool(s.contextualEnglish, v);
            else if (key == "collision_prefers_vietnamese") setBool(s.collisionPrefersVietnamese, v);
            else if (key == "bracket_vowels") setBool(s.bracketVowels, v);
            else if (key == "shortcuts_enabled") setBool(s.shortcutsEnabled, v);
            else if (key == "re_edit_word") setBool(s.reEditWord, v);
        } else if (section == "general") {
            if (key == "display_mode") {
                if (v.kind == Value::Str) {
                    std::string m = lower(v.s);
                    if (m == "surrounding") s.displayMode = DisplayMode::Surrounding;
                    else if (m == "preedit") s.displayMode = DisplayMode::Preedit;
                }
            } else if (key == "toggle_hotkey") {
                if (v.kind == Value::Str) s.toggleHotkey = v.s;
            }
            else if (key == "per_app_state") setBool(s.perAppState, v);
            else if (key == "default_vietnamese") setBool(s.defaultVietnamese, v);
        } else if (section == "app_modes") {
            if (v.kind == Value::Str && !key.empty()) {
                std::string m = lower(v.s);
                if (m == "preedit" || m == "surrounding" || m == "off") s.appModes[lower(key)] = m;
            }
        }
    }
    return s;
}

std::string serializeConfig(const Settings &s) {
    auto b = [](bool v) { return v ? "true" : "false"; };
    std::ostringstream o;
    o << "[typing]\n"
      << "input_method = " << (s.vni ? "\"vni\"" : "\"telex\"") << "\n"
      << "simple_telex = " << b(s.simpleTelex) << "\n"
      << "free_marking = " << b(s.freeMarking) << "\n"
      << "modern_tone = " << b(s.modernTone) << "\n"
      << "quick_telex = " << b(s.quickTelex) << "\n"
      << "spell_check = " << b(s.spellCheck) << "\n"
      << "auto_restore = " << b(s.autoRestore) << "\n"
      << "teencode = " << b(s.teencode) << "\n"
      << "contextual_english = " << b(s.contextualEnglish) << "\n"
      << "collision_prefers_vietnamese = " << b(s.collisionPrefersVietnamese) << "\n"
      << "bracket_vowels = " << b(s.bracketVowels) << "\n"
      << "shortcuts_enabled = " << b(s.shortcutsEnabled) << "\n"
      << "re_edit_word = " << b(s.reEditWord) << "\n"
      << "\n[general]\n"
      << "display_mode = " << (s.displayMode == DisplayMode::Surrounding ? "\"surrounding\"" : "\"preedit\"") << "\n"
      << "toggle_hotkey = " << quote(s.toggleHotkey) << "\n"
      << "per_app_state = " << b(s.perAppState) << "\n"
      << "default_vietnamese = " << b(s.defaultVietnamese) << "\n"
      << "\n[app_modes]\n";
    for (auto &kv : s.appModes) o << quote(kv.first) << " = " << quote(kv.second) << "\n";
    return o.str();
}

std::string setConfigValue(const std::string &toml, const std::string &section, const std::string &key,
                           const std::string &literal) {
    std::vector<std::string> lines;
    {
        std::istringstream in(toml);
        std::string l;
        while (std::getline(in, l)) lines.push_back(l);
    }
    std::string cur;
    int sectionStart = -1, sectionEnd = -1;  // [start, end) line indexes of the section body
    for (size_t i = 0; i < lines.size(); ++i) {
        std::string t = trim(lines[i]);
        if (!t.empty() && t[0] == '[') {
            if (cur == section && sectionEnd < 0) sectionEnd = int(i);
            size_t close = t.find(']');
            cur = close == std::string::npos ? "" : trim(t.substr(1, close - 1));
            if (cur == section && sectionStart < 0) sectionStart = int(i) + 1;
            continue;
        }
        if (cur != section || t.empty() || t[0] == '#') continue;
        std::string k;
        size_t eq;
        if (t[0] == '"') {
            size_t end = 0;
            if (!parseQuoted(t, 0, k, end)) continue;
            eq = t.find('=', end);
        } else {
            eq = t.find('=');
            if (eq == std::string::npos) continue;
            k = trim(t.substr(0, eq));
        }
        if (eq != std::string::npos && k == key) {
            std::string keyText = (key.find_first_of(" .\"") != std::string::npos) ? quote(key) : key;
            lines[i] = keyText + " = " + literal;
            std::string out;
            for (auto &x : lines) out += x + "\n";
            return out;
        }
    }
    if (cur == section && sectionEnd < 0) sectionEnd = int(lines.size());
    std::string keyText = (key.find_first_of(" .\"") != std::string::npos) ? quote(key) : key;
    std::string newLine = keyText + " = " + literal;
    if (sectionStart < 0) {
        if (!lines.empty() && !trim(lines.back()).empty()) lines.push_back("");
        lines.push_back("[" + section + "]");
        lines.push_back(newLine);
    } else {
        // insert after the last non-blank line of the section
        int at = sectionEnd;
        while (at > sectionStart && trim(lines[size_t(at - 1)]).empty()) --at;
        lines.insert(lines.begin() + at, newLine);
    }
    std::string out;
    for (auto &x : lines) out += x + "\n";
    return out;
}

// MARK: - shortcuts.yml

ShortcutTable parseShortcuts(const std::string &yaml) {
    ShortcutTable out;
    std::istringstream in(yaml);
    std::string raw;
    while (std::getline(in, raw)) {
        std::string line = trim(raw);
        if (line.empty() || line[0] == ';' || line[0] == '#' || startsWith(line, "//")) continue;
        size_t colon = line.find(':');
        if (colon == std::string::npos) continue;
        std::string key = trim(line.substr(0, colon));
        std::string value = trim(line.substr(colon + 1));
        if (utf8Count(value) >= 2 &&
            ((value.front() == '"' && endsWith(value, '"')) || (value.front() == '\'' && endsWith(value, '\''))))
            value = value.substr(1, value.size() - 2);
        if (key.empty() || value.empty() || utf8Count(key) > 64) continue;
        bool ws = false;
        for (char c : key) ws |= isWhitespace(c);
        if (ws) continue;
        out[key] = value;
    }
    return out;
}

std::string exportShortcuts(const ShortcutTable &t) {
    std::string out = "# VietTelex — bảng gõ tắt\n";
    for (auto &kv : t) {  // std::map: sorted by key (byte order, like Swift's sorted())
        const std::string &v = kv.second;
        bool q = !v.empty() && (v.front() == ' ' || v.back() == ' ' || v.front() == '\'' ||
                                v.front() == '"' || v.front() == '#');
        out += kv.first + ": " + (q ? "\"" + v + "\"" : v) + "\n";
    }
    return out;
}

// MARK: - hotkey

bool parseHotkey(const std::string &spec, Hotkey &out) {
    std::string s = trim(spec);
    if (s.empty()) return false;
    std::vector<std::string> parts;
    size_t start = 0;
    // split on '+', but a trailing "+" key ("Ctrl++") is the plus key
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '+' && i > start) { parts.push_back(s.substr(start, i - start)); start = i + 1; }
    }
    parts.push_back(s.substr(start));
    Hotkey hk;
    for (size_t i = 0; i + 1 < parts.size(); ++i) {
        std::string m = lower(trim(parts[i]));
        if (m == "ctrl" || m == "control") hk.mods |= VT_MOD_CTRL;
        else if (m == "alt") hk.mods |= VT_MOD_ALT;
        else if (m == "shift") hk.mods |= VT_MOD_SHIFT;
        else if (m == "super" || m == "meta") hk.mods |= VT_MOD_SUPER;
        else return false;
    }
    std::string key = trim(parts.back());
    std::string lk = lower(key);
    static const std::map<std::string, uint32_t> names = {
        {"space", 0x20}, {"grave", 0x60}, {"tab", ks::Tab}, {"return", ks::Return},
        {"escape", ks::Escape}, {"backspace", ks::BackSpace}, {"comma", ','}, {"period", '.'},
        {"slash", '/'}, {"semicolon", ';'}, {"apostrophe", '\''}, {"minus", '-'}, {"equal", '='},
        {"bracketleft", '['}, {"bracketright", ']'}, {"backslash", '\\'}, {"plus", '+'},
    };
    auto it = names.find(lk);
    if (it != names.end()) hk.keysym = it->second;
    else if (key.size() == 1 && (unsigned char)key[0] > 0x20 && (unsigned char)key[0] < 0x7f)
        hk.keysym = (uint32_t)(unsigned char)lower(key)[0];
    else if (lk.size() >= 2 && lk[0] == 'f' && isdigit((unsigned char)lk[1])) {
        int n = std::atoi(lk.c_str() + 1);
        if (n < 1 || n > 24) return false;
        hk.keysym = 0xffbe + uint32_t(n - 1);  // XK_F1
    } else return false;
    // Super+space belongs to GNOME's input-source switcher (spec §4/§6).
    if (hk.keysym == 0x20 && hk.mods == VT_MOD_SUPER) return false;
    if (hk.mods == 0 && hk.keysym < 0x7f) return false;  // a bare printable key would eat typing
    out = hk;
    return true;
}

// MARK: - files

std::string configDir() { return envOr("XDG_CONFIG_HOME", ".config") + "/viettelex"; }
std::string configPath() { return configDir() + "/config.toml"; }
std::string shortcutsPath() { return configDir() + "/shortcuts.yml"; }
std::string stateDir() { return envOr("XDG_STATE_HOME", ".local/state") + "/viettelex"; }
std::string appStatePath() { return stateDir() + "/app-state"; }

bool readFile(const std::string &path, std::string &out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    std::ostringstream ss;
    ss << f.rdbuf();
    out = ss.str();
    return true;
}

bool mkdirs(const std::string &dir) {
    if (dir.empty()) return false;
    std::string cur;
    for (size_t i = 0; i <= dir.size(); ++i) {
        if (i == dir.size() || dir[i] == '/') {
            if (!cur.empty() && ::mkdir(cur.c_str(), 0700) != 0 && errno != EEXIST) return false;
        }
        if (i < dir.size()) cur += dir[i];
    }
    return true;
}

bool writeFileAtomic(const std::string &path, const std::string &data) {
    size_t slash = path.rfind('/');
    if (slash != std::string::npos) mkdirs(path.substr(0, slash));
    std::string tmp = path + ".tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f) return false;
        f << data;
        if (!f) return false;
    }
    return std::rename(tmp.c_str(), path.c_str()) == 0;
}

Settings loadSettings(const std::string &dir) {
    std::string text;
    Settings s = readFile(dir + "/config.toml", text) ? parseConfig(text) : Settings();
    std::string sc;
    if (readFile(dir + "/shortcuts.yml", sc)) s.shortcuts = std::make_shared<ShortcutTable>(parseShortcuts(sc));
    return s;
}

}  // namespace viettelex
