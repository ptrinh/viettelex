// app.cpp — see app.h.
#include "viettelex/app.h"

#include <set>
#include <sstream>

namespace viettelex {

std::string normalizeAppId(const std::string &raw) {
    std::string s = raw;
    // "gtk3-im:gedit" / "ibus-x11:foo": the IM-module prefix is not the app
    size_t colon = s.rfind(':');
    if (colon != std::string::npos) s = s.substr(colon + 1);
    size_t slash = s.find_last_of("/\\");  // also Wine's "C:\\…\\app.exe"
    if (slash != std::string::npos) s = s.substr(slash + 1);
    const std::string desktop = ".desktop";
    if (s.size() > desktop.size() && s.compare(s.size() - desktop.size(), desktop.size(), desktop) == 0)
        s.resize(s.size() - desktop.size());
    for (auto &c : s)
        if (c >= 'A' && c <= 'Z') c = char(c - 'A' + 'a');
    while (!s.empty() && (s.back() == ' ' || s.back() == '\n')) s.pop_back();
    // Snap: "firefox_firefox" → "firefox"
    size_t us = s.find('_');
    if (us != std::string::npos && us > 0 && s.compare(us + 1, std::string::npos, s, 0, us) == 0)
        s.resize(us);
    return s;
}

namespace {
// Last reverse-DNS component: "org.kde.konsole" → "konsole".
std::string shortName(const std::string &id) {
    size_t dot = id.rfind('.');
    return dot == std::string::npos ? id : id.substr(dot + 1);
}

bool startsWith(const std::string &s, const char *p) { return s.rfind(p, 0) == 0; }
bool endsWith(const std::string &s, const std::string &p) {
    return s.size() >= p.size() && s.compare(s.size() - p.size(), p.size(), p) == 0;
}
}  // namespace

bool isForcedPreeditApp(const std::string &appId) {
    static const std::set<std::string> names = {
        // terminals
        "gnome-terminal", "gnome-terminal-server", "terminal", "kgx", "console", "ptyxis",
        "konsole", "kitty", "alacritty", "wezterm", "wezterm-gui", "foot", "footclient", "xterm",
        "uxterm", "tilix", "terminator", "xfce4-terminal", "lxterminal", "mate-terminal",
        "qterminal", "terminology", "st", "urxvt", "rxvt", "yakuake", "guake", "blackbox",
        "gnome-console", "tilda", "sakura", "roxterm", "deepin-terminal", "cool-retro-term",
        "ghostty", "contour", "rio", "vte", "vte-2.91",
        // KDE launchers/shell, JetBrains/Java (AWT/Swing IM bridge), WPS / OnlyOffice, Steam
        "krunner", "plasmashell", "idea", "java", "wps", "wpp", "et", "wpsoffice",
        "desktopeditors", "steam",
        // LibreOffice
        "soffice", "soffice.bin", "libreoffice", "libreoffice-writer", "libreoffice-calc",
        "libreoffice-impress",
        // Chromium / Electron (unreliable surrounding text, esp. on Wayland)
        "chrome", "google-chrome", "google-chrome-stable", "google-chrome-beta", "chromium",
        "chromium-browser", "chromium-freeworld", "brave", "brave-browser", "brave-browser-stable",
        "microsoft-edge", "microsoft-edge-stable", "vivaldi", "vivaldi-stable", "opera", "code",
        "code-oss", "code-insiders", "vscodium", "codium", "cursor",
        "electron", "slack", "discord", "signal-desktop", "obsidian", "zalo", "teams-for-linux",
        // Firefox / Gecko (URL bar selects + autocompletes; surrounding text lags)
        "firefox", "firefox-esr", "librewolf", "zen", "zen-browser", "thunderbird",
        // GNOME Wayland: one shared text-input-v3 context for every app; the overview search
        "gnome-shell", "gnome-shell-overview",
    };
    std::string id = normalizeAppId(appId);
    if (id.empty()) return false;
    if (names.count(id) || names.count(shortName(id))) return true;
    if (id.rfind("libreoffice", 0) == 0) return true;
    if (startsWith(id, "vte-") || startsWith(id, "jetbrains-")) return true;
    return false;
}

bool isDefaultOffApp(const std::string &appId) {
    static const std::set<std::string> names = {
        // remote desktop / virtual machines: the remote side has its own input method
        "remmina", "anydesk", "rustdesk", "virtualboxvm", "vmware", "vmplayer", "remote-viewer",
        "gnome-connections", "org.gnome.connections", "krdc", "xfreerdp", "xfreerdp3", "wlfreerdp",
        "sdl-freerdp", "moonlight", "parsec",
    };
    std::string id = normalizeAppId(appId);
    if (id.empty()) return false;
    if (names.count(id) || names.count(shortName(id))) return true;
    // Wine: "wine64-preloader", "notepad.exe"
    if (startsWith(id, "wine") && endsWith(id, "-preloader")) return true;
    if (id.size() > 4 && endsWith(id, ".exe")) return true;
    return false;
}

bool isUnknownAppId(const std::string &appId) {
    std::string id = normalizeAppId(appId);
    if (id.empty() || id[0] == '(') return true;  // "(12345)": only a pid
    bool digits = true;
    for (char c : id) digits = digits && c >= '0' && c <= '9';
    if (digits) return true;
    static const std::set<std::string> generic = {
        "default", "gnome-shell", "qibusinputcontext", "xim", "wayland", "sdl2_application",
        "sdl3_application", "gtk-im",
    };
    return generic.count(id) > 0;
}

AppPolicy resolveAppPolicy(const std::string &appId, const Settings &s, bool surroundingProven,
                           const FieldHints &field) {
    AppPolicy p;
    std::string id = normalizeAppId(appId);
    bool unknown = isUnknownAppId(id);
    DisplayMode mode = s.displayMode;
    bool pinned = false;
    auto it = s.appModes.find(id);
    if (it == s.appModes.end() && !id.empty()) it = s.appModes.find(shortName(id));
    if (it != s.appModes.end()) {
        if (it->second == "off") p.off = true;
        else if (it->second == "surrounding") { mode = DisplayMode::Surrounding; pinned = true; }
        else if (it->second == "preedit") { mode = DisplayMode::Preedit; pinned = true; }
    } else if (isDefaultOffApp(id)) {
        p.off = true;  // built-in English-only list; any [app_modes] entry overrides it
    }
    // A generic id covers many apps: a "surrounding" pin on it proves nothing.
    if (unknown) pinned = false;
    bool forced = !pinned && isForcedPreeditApp(id);
    if (mode == DisplayMode::Surrounding) {
        if (!surroundingProven) mode = DisplayMode::Preedit;          // cannot edit before the caret
        else if (forced) mode = DisplayMode::Preedit;
    }
    p.allowSurroundingEdits = surroundingProven && !forced;
    // Field type beats every app rule.
    if (field.terminal) {
        mode = DisplayMode::Preedit;
        p.allowSurroundingEdits = false;
    }
    if (field.urlOrEmail) mode = DisplayMode::Preedit;
    if (field.numeric || field.sensitive) p.passthrough = true;
    if (field.sensitive) p.rememberState = false;
    p.mode = mode;
    return p;
}

// MARK: - AppStateStore

AppStateStore::AppStateStore(std::string path) : path_(std::move(path)) {}

void AppStateStore::load() {
    map_.clear();
    std::string text;
    if (!readFile(path_, text)) return;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
        size_t tab = line.find('\t');
        if (tab == std::string::npos || tab == 0) continue;
        std::string v = line.substr(tab + 1);
        if (v == "vi") map_[line.substr(0, tab)] = true;
        else if (v == "en") map_[line.substr(0, tab)] = false;
    }
}

bool AppStateStore::vietnamese(const std::string &appId, bool fallback) const {
    auto it = map_.find(appId);
    return it == map_.end() ? fallback : it->second;
}

void AppStateStore::set(const std::string &appId, bool vietnamese) {
    if (appId.empty()) return;
    auto it = map_.find(appId);
    if (it != map_.end() && it->second == vietnamese) return;
    map_[appId] = vietnamese;
    save();
}

void AppStateStore::save() const {
    std::string out;
    for (auto &kv : map_) out += kv.first + "\t" + (kv.second ? "vi" : "en") + "\n";
    writeFileAtomic(path_, out);
}

}  // namespace viettelex
