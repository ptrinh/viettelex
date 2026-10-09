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

bool isTerminalApp(const std::string &appId) {
    static const std::set<std::string> names = {
        "gnome-terminal", "gnome-terminal-server", "terminal", "kgx", "console", "ptyxis",
        "konsole", "kitty", "alacritty", "wezterm", "wezterm-gui", "foot", "footclient", "xterm",
        "uxterm", "tilix", "terminator", "xfce4-terminal", "lxterminal", "mate-terminal",
        "qterminal", "terminology", "st", "urxvt", "rxvt", "yakuake", "guake", "blackbox",
        "gnome-console", "tilda", "sakura", "roxterm", "deepin-terminal", "cool-retro-term",
        "ghostty", "contour", "rio", "vte", "vte-2.91",
    };
    std::string id = normalizeAppId(appId);
    if (id.empty()) return false;
    if (names.count(id) || names.count(shortName(id))) return true;
    return startsWith(id, "vte-");
}

ClientHost ibusClientHost(const std::string &raw) {
    std::string c = raw;
    for (auto &ch : c)
        if (ch >= 'A' && ch <= 'Z') ch = char(ch - 'A' + 'a');
    if (startsWith(c, "gtk3-im:") || startsWith(c, "gtk-im:")) return ClientHost::IBusGtk;
    if (startsWith(c, "gtk4-im:")) return ClientHost::IBusGtk4;
    if (c == "qibusinputcontext") return ClientHost::IBusQt;
    if (c == "xim" || startsWith(c, "xim:")) return ClientHost::IBusXim;
    if (c == "gnome-shell" || startsWith(c, "ibus-wayland") || c == "wayland") return ClientHost::IBusWayland;
    return ClientHost::Unknown;
}

ClientHost fcitxClientHost(const std::string &frontend, bool keyEventOrderFix) {
    if (frontend == "dbus") return keyEventOrderFix ? ClientHost::FcitxOrdered : ClientHost::FcitxUnordered;
    if (frontend == "xim") return ClientHost::FcitxXim;
    if (frontend == "wayland") return ClientHost::FcitxWayland;
    if (frontend == "wayland_v2") return ClientHost::FcitxWaylandV2;
    if (frontend == "ibus") return ClientHost::FcitxIBus;
    return ClientHost::Unknown;
}

bool hostSupportsDirect(ClientHost h) { return h == ClientHost::IBusGtk || h == ClientHost::FcitxOrdered; }

bool hostOrdersForwardedKeys(ClientHost h) { return h == ClientHost::IBusWayland || h == ClientHost::FcitxWayland; }

bool isChromiumApp(const std::string &appId) {
    static const std::set<std::string> names = {
        // Chromium / Electron (unreliable surrounding text, esp. on Wayland)
        "chrome", "google-chrome", "google-chrome-stable", "google-chrome-beta", "chromium",
        "chromium-browser", "chromium-freeworld", "brave", "brave-browser", "brave-browser-stable",
        "microsoft-edge", "microsoft-edge-stable", "vivaldi", "vivaldi-stable", "opera", "code",
        "code-oss", "code-insiders", "vscodium", "codium", "cursor",
        "electron", "slack", "discord", "signal-desktop", "obsidian", "zalo", "teams-for-linux",
        // more Chromium-based browsers (Cốc Cốc: Messenger trên web lặp chữ / ⌫ xoá 2 lần khi
        // dùng surrounding — user Zorin OS Wayland, 08/10/2026)
        "coccoc", "coccoc-browser", "coccoc-browser-stable", "yandex-browser", "yandex-browser-stable",
        "thorium", "thorium-browser", "ungoogled-chromium", "google-chrome-unstable",
        "microsoft-edge-beta", "microsoft-edge-dev", "opera-beta", "opera-developer",
        "vivaldi-snapshot", "brave-browser-beta", "brave-browser-nightly", "chromium-freeworld",
        "cromite", "cromite-browser", "helium", "helium-browser", "slimjet", "slimjet-browser",
        "flashpeak-slimjet",
        // Flatpak ids whose last component is not the app's own name (shortName alone misses
        // them): Brave/Edge/Yandex/ungoogled-chromium, Vivaldi flatpak WM_CLASS
        "com.brave.browser", "com.microsoft.edge", "ru.yandex.browser", "vivaldi-flatpak",
        "io.github.ungoogled_software.ungoogled_chromium", "com.github.eloston.ungoogledchromium",
        "wavebox", "min-browser",
        // AI code editors / VS Code forks (Electron). Antigravity: user báo gạch chân 10/2026
        "antigravity", "windsurf", "kiro", "trae", "void", "pearai", "positron",
        // chat (Electron / Chromium): .desktop, WM_CLASS, binary, Flatpak / snap ids
        "signal", "org.signal.signal", "element", "element-desktop", "im.riot.riot",
        "mattermost", "mattermost-desktop", "com.mattermost.desktop", "rocketchat-desktop",
        "rocket.chat", "rocketchat", "caprine", "ferdium", "rambox", "franz", "beeper",
        "beepertexts", "vesktop", "teams_for_linux", "whatsapp-desktop-linux", "whatsappdesktop",
        "zalo-linux", "feishu", "bytedance-feishu", "bytedance-feishu-stable",
        // notes / productivity / dev tools (Electron), Spotify (CEF)
        "notion", "notion-app", "logseq", "joplin", "joplin-desktop", "joplin_desktop", "typora",
        "marktext", "notesnook", "anytype", "bitwarden", "bitwarden-desktop",
        "com.bitwarden.desktop", "1password", "com.onepassword.onepassword", "postman",
        "insomnia", "figma-linux", "figma_linux", "github-desktop", "io.github.shiftey.desktop",
        "io.github.shiftey",  // normalizeAppId strips a ".Desktop" tail: "io.github.shiftey.Desktop"
        "gitkraken", "spotify", "com.spotify.client", "claude", "claude-desktop",
    };
    std::string id = normalizeAppId(appId);
    if (id.empty()) return false;
    if (names.count(id) || names.count(shortName(id))) return true;
    // AppImage desktop files: "appimagekit-joplin", AppImageLauncher "appimagekit_<md5>-Logseq"
    if (startsWith(id, "appimagekit")) {
        size_t dash = id.find('-');
        if (dash != std::string::npos && names.count(id.substr(dash + 1))) return true;
    }
    // Arch system Electron ("electron37" + app.asar) runs unnamed apps under this binary
    if (startsWith(id, "electron") && id.size() > 8 &&
        id.find_first_not_of("0123456789", 8) == std::string::npos)
        return true;
    // Chromium web apps / PWA (Messenger cài từ trình duyệt): WM_CLASS "crx_<id>",
    // "chrome-<id>-default", "brave-<id>-default", "msedge-<id>-default"; mọi bản Cốc Cốc.
    if (startsWith(id, "crx_") || startsWith(id, "coccoc")) return true;
    for (const char *p : {"chrome-", "brave-", "msedge-", "vivaldi-", "opera-"})
        if (startsWith(id, p) && endsWith(id, "-default")) return true;
    return false;
}

bool isForcedPreeditApp(const std::string &appId) {
    static const std::set<std::string> names = {
        // KDE launchers/shell, JetBrains/Java (AWT/Swing IM bridge), WPS / OnlyOffice, Steam
        "krunner", "plasmashell", "idea", "java", "wps", "wpp", "et", "wpsoffice",
        "desktopeditors", "steam",
        // LibreOffice
        "soffice", "soffice.bin", "libreoffice", "libreoffice-writer", "libreoffice-calc",
        "libreoffice-impress",
        // Firefox / Gecko (URL bar selects + autocompletes; surrounding text lags)
        "firefox", "firefox-esr", "librewolf", "zen", "zen-browser", "thunderbird",
        // GNOME Wayland: one shared text-input-v3 context for every app; the overview search
        "gnome-shell", "gnome-shell-overview",
    };
    if (isTerminalApp(appId)) return true;
    std::string id = normalizeAppId(appId);
    if (id.empty()) return false;
    if (names.count(id) || names.count(shortName(id))) return true;
    if (id.rfind("libreoffice", 0) == 0) return true;
    if (startsWith(id, "jetbrains-")) return true;
    if (isChromiumApp(id)) return true;
    // Wine: app Windows chạy NGAY trên máy (không có bộ gõ nào khác như remote desktop/VM) —
    // nhận chữ qua XIM, sửa chữ quanh con trỏ không tin được ⇒ gạch chân. Trước 1.0.5 nằm
    // trong danh sách mặc định tắt ⇒ Word qua Wine gõ ra "he1 lo6" (user Zorin OS 08/10/2026).
    if (isWineApp(id)) return true;
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
    return false;
}

bool isWineApp(const std::string &appId) {
    std::string id = normalizeAppId(appId);
    // "wine64-preloader", "notepad.exe", "C:\...\WINWORD.EXE"
    if (startsWith(id, "wine") && endsWith(id, "-preloader")) return true;
    return id.size() > 4 && endsWith(id, ".exe");
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
    DisplayMode mode = s.displayMode == DisplayMode::Direct ? DisplayMode::Preedit : s.displayMode;
    bool pinned = false, pinPreedit = false, pinDirect = false;
    auto it = s.appModes.find(id);
    if (it == s.appModes.end() && !id.empty()) it = s.appModes.find(shortName(id));
    if (it != s.appModes.end()) {
        if (it->second == "off") p.off = true;
        else if (it->second == "surrounding") { mode = DisplayMode::Surrounding; pinned = true; }
        else if (it->second == "preedit") { mode = DisplayMode::Preedit; pinned = true; pinPreedit = true; }
        else if (it->second == "direct") { mode = DisplayMode::Preedit; pinned = true; pinDirect = true; }
    } else if (isDefaultOffApp(id)) {
        p.off = true;  // built-in English-only list; any [app_modes] entry overrides it
    }
    // A generic id covers many apps: a "surrounding"/"direct" pin on it proves nothing.
    if (unknown) pinned = pinDirect = false;
    bool forced = !pinned && isForcedPreeditApp(id);
    if (mode == DisplayMode::Surrounding) {
        if (!surroundingProven) mode = DisplayMode::Preedit;          // cannot edit before the caret
        else if (forced) mode = DisplayMode::Preedit;
    }
    p.allowSurroundingEdits = surroundingProven && !forced;
    bool terminal = field.terminal || isTerminalApp(id);
    // Field type beats every app rule.
    if (field.terminal) {
        mode = DisplayMode::Preedit;
        p.allowSurroundingEdits = false;
    }
    // Direct: a terminal (or an app pinned "direct") on a host that delivers forwarded keys
    // in order. A "preedit" pin keeps the preedit. Direct never reads text back.
    bool wantDirect = pinDirect || (terminal && s.terminalDirect && !pinPreedit &&
                                    (field.terminal || mode == DisplayMode::Preedit));
    if (wantDirect && hostSupportsDirect(field.host) && !field.urlOrEmail) {
        mode = DisplayMode::Direct;
        p.allowSurroundingEdits = false;
    } else if (pinDirect && terminal) {
        p.allowSurroundingEdits = false;  // fell back to Preedit: still no read-back
    }
    if (field.urlOrEmail) mode = DisplayMode::Preedit;
    if (field.numeric || field.sensitive) p.passthrough = true;
    if (field.sensitive) p.rememberState = false;
    // [experimental] no_underline = "forward-keys" (docs/NO-UNDERLINE-SPIKE.md): a Chromium /
    // Electron app that would otherwise get the preedit types in place, deletes going out as
    // forwarded BackSpace keys — only on a host that keeps them in order with the commits, and
    // only where its text before the caret was proven (the Session verifies every delete and
    // the result of each one, and drops back to preedit on any doubt). A pin always wins.
    if (s.noUnderline == NoUnderline::ForwardKeys && mode == DisplayMode::Preedit && !pinned && !unknown &&
        !p.off && !p.passthrough && !field.terminal && !field.urlOrEmail && surroundingProven &&
        isChromiumApp(id) && hostOrdersForwardedKeys(field.host)) {
        mode = DisplayMode::Surrounding;
        p.deleteWithKeys = true;
        p.allowSurroundingEdits = false;  // no re-edit / ⌫ reopen: in-word edits only
    }
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
