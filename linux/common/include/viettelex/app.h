// app.h — per-app policy (display mode resolution) and per-app Vi/En memory.
#pragma once

#include "viettelex/settings.h"

#include <map>
#include <string>

namespace viettelex {

// Normalises a frontend-provided identity ("/usr/bin/Konsole", "org.gnome.TextEditor.desktop",
// "gtk3-im:gedit") to the lowercase key used by [app_modes] and app-state.
std::string normalizeAppId(const std::string &raw);

// Built-in list of apps where Surrounding mode is unsafe (terminals, LibreOffice,
// Chromium/Electron) → always Preedit unless the user pins "surrounding".
bool isForcedPreeditApp(const std::string &appId);

struct AppPolicy {
    bool off = false;                         // [app_modes] "off": no Vietnamese here
    DisplayMode mode = DisplayMode::Preedit;  // effective display mode
};

// clientSurrounding: the client advertises surrounding-text support.
AppPolicy resolveAppPolicy(const std::string &appId, const Settings &s, bool clientSurrounding);

// Vi/En memory per app ("app\tvi|en" lines). Saves atomically on change.
class AppStateStore {
public:
    explicit AppStateStore(std::string path);
    void load();
    // Returns the remembered state, or `fallback` for an unknown app.
    bool vietnamese(const std::string &appId, bool fallback) const;
    void set(const std::string &appId, bool vietnamese);
    const std::map<std::string, bool> &entries() const { return map_; }

private:
    void save() const;
    std::string path_;
    std::map<std::string, bool> map_;
};

}  // namespace viettelex
