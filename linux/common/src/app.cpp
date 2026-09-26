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
    size_t slash = s.rfind('/');
    if (slash != std::string::npos) s = s.substr(slash + 1);
    const std::string desktop = ".desktop";
    if (s.size() > desktop.size() && s.compare(s.size() - desktop.size(), desktop.size(), desktop) == 0)
        s.resize(s.size() - desktop.size());
    for (auto &c : s)
        if (c >= 'A' && c <= 'Z') c = char(c - 'A' + 'a');
    while (!s.empty() && (s.back() == ' ' || s.back() == '\n')) s.pop_back();
    return s;
}

namespace {
// Last reverse-DNS component: "org.kde.konsole" → "konsole".
std::string shortName(const std::string &id) {
    size_t dot = id.rfind('.');
    return dot == std::string::npos ? id : id.substr(dot + 1);
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
        // GNOME Wayland: one shared text-input-v3 context for every app
        "gnome-shell",
    };
    std::string id = normalizeAppId(appId);
    if (id.empty()) return false;
    if (names.count(id) || names.count(shortName(id))) return true;
    if (id.rfind("libreoffice", 0) == 0) return true;
    if (id.rfind("vte-", 0) == 0) return true;
    return false;
}

bool isUnknownAppId(const std::string &appId) {
    std::string id = normalizeAppId(appId);
    return id.empty() || id == "default" || id == "gnome-shell" || id == "qibusinputcontext" || id == "xim";
}

AppPolicy resolveAppPolicy(const std::string &appId, const Settings &s, bool surroundingProven) {
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
    }
    // A generic id covers many apps: a "surrounding" pin on it proves nothing.
    if (unknown) pinned = false;
    bool forced = !pinned && isForcedPreeditApp(id);
    if (mode == DisplayMode::Surrounding) {
        if (!surroundingProven) mode = DisplayMode::Preedit;          // cannot edit before the caret
        else if (forced) mode = DisplayMode::Preedit;
    }
    p.mode = mode;
    p.allowSurroundingEdits = surroundingProven && !forced;
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
