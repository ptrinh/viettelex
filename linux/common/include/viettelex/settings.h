// settings.h — VietTelex Linux settings (contract: linux/common/SETTINGS.md).
// Pure parsing/serialisation, no I/O except the explicit load*/save* helpers.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <string>

namespace viettelex {

// Preedit: composition shown by the client. Surrounding: edit committed text through
// delete-surrounding + commit. Direct (terminals, only on hosts whose forwarded keys reach
// the app in order — see app.h): type committed text and fix it with forwarded BackSpace
// keys, never reading anything back. Direct is chosen per app/field, never globally.
enum class DisplayMode { Preedit, Surrounding, Direct };

using ShortcutTable = std::map<std::string, std::string>;

struct Settings {
    // [typing] — defaults mirror the macOS app (AppState.swift)
    bool vni = false;
    bool simpleTelex = false;
    bool freeMarking = true;
    bool modernTone = false;
    bool quickTelex = false;
    bool spellCheck = true;
    bool autoRestore = true;
    bool teencode = false;
    bool contextualEnglish = true;
    bool collisionPrefersVietnamese = true;
    bool bracketVowels = false;
    bool shortcutsEnabled = true;
    bool reEditWord = true;
    // [general]
    DisplayMode displayMode = DisplayMode::Preedit;  // Preedit | Surrounding only
    bool preeditUnderline = false;  // "Gạch chân chữ đang gõ" (clients that honour attributes)
    bool terminalDirect = true;     // terminals on ordered hosts: Direct instead of Preedit
    std::string toggleHotkey = "Ctrl+space";
    bool perAppState = true;
    bool defaultVietnamese = true;
    // [app_modes] app id (lowercase) -> "preedit" | "surrounding" | "direct" | "off"
    std::map<std::string, std::string> appModes;
    // shortcuts.yml (never null after load)
    std::shared_ptr<const ShortcutTable> shortcuts = std::make_shared<ShortcutTable>();
};

// config.toml subset → Settings. Unknown keys / bad values fall back to defaults.
Settings parseConfig(const std::string &toml);
// Sets `key = literal` inside [section] of an existing config.toml text, preserving every
// other line (comments, unknown keys); appends the key/section when missing.
// `literal` is already TOML (`true`, `"vni"`).
std::string setConfigValue(const std::string &toml, const std::string &section, const std::string &key,
                           const std::string &literal);
// Settings → config.toml (canonical form, used by tests and as a reference writer).
std::string serializeConfig(const Settings &s);

// shortcuts.yml (flat YAML, same rules as macOS ShortcutImporter line parser).
ShortcutTable parseShortcuts(const std::string &yaml);
std::string exportShortcuts(const ShortcutTable &t);

// Hotkey "Ctrl+Shift+space". Returns false for an empty/invalid string.
struct Hotkey {
    uint32_t keysym = 0;  // lowercase keysym
    uint32_t mods = 0;    // VT_MOD_* bits (keys.h)
};
bool parseHotkey(const std::string &s, Hotkey &out);

// Paths ($XDG_CONFIG_HOME / $XDG_STATE_HOME aware).
std::string configDir();                // …/viettelex
std::string configPath();               // …/viettelex/config.toml
std::string shortcutsPath();            // …/viettelex/shortcuts.yml
std::string stateDir();                 // …/viettelex (state)
std::string appStatePath();             // …/viettelex/app-state

bool readFile(const std::string &path, std::string &out);
bool writeFileAtomic(const std::string &path, const std::string &data);  // tmp + rename
bool mkdirs(const std::string &dir);

// Loads config.toml + shortcuts.yml from the config dir (missing files = defaults).
Settings loadSettings(const std::string &dir);

}  // namespace viettelex
