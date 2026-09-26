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
// Chromium/Electron, Firefox/Gecko, gnome-shell) → always Preedit unless the user pins
// "surrounding".
bool isForcedPreeditApp(const std::string &appId);

// Identities that do not name a real app: empty, "default" (IBus < 1.5.28 has no
// focus_in_id), "gnome-shell" (GNOME Wayland shares one text-input-v3 context for every
// app), "qibusinputcontext" (Qt IBus plugin), "xim" (XIM clients). Case-insensitive.
bool isUnknownAppId(const std::string &appId);

struct AppPolicy {
    bool off = false;                         // [app_modes] "off": no Vietnamese here
    DisplayMode mode = DisplayMode::Preedit;  // effective display mode
    // May the Session read back / delete text before the caret (re-edit, ⌫ reopen)?
    // False for forced-preedit apps, and for unknown apps / any app until real
    // surrounding text has been proven for this focus.
    bool allowSurroundingEdits = false;
};

// surroundingProven: the client actually delivered surrounding text for this focus (not
// just the capability bit — IBus keeps an empty text for clients that never send one).
AppPolicy resolveAppPolicy(const std::string &appId, const Settings &s, bool surroundingProven);

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
