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

// Built-in list of apps that start in English (keys pass through): remote desktop / VM
// viewers and Wine programs. Any [app_modes] entry for the app overrides it.
bool isDefaultOffApp(const std::string &appId);

// Identities that do not name a real app: empty, "default" (IBus < 1.5.28 has no
// focus_in_id), "gnome-shell" (GNOME Wayland shares one text-input-v3 context for every
// app), "qibusinputcontext" (Qt IBus plugin), "xim" (XIM clients), "wayland",
// "sdl2_application"/"sdl3_application", "gtk-im", "(1234)"/bare pids. Case-insensitive.
bool isUnknownAppId(const std::string &appId);

// What the focused field says about itself (IBus content type, Fcitx5 capability flags).
struct FieldHints {
    bool terminal = false;    // IBus PURPOSE_TERMINAL / Fcitx5 Terminal → Preedit, no edits
    bool urlOrEmail = false;  // URL / EMAIL → Preedit
    bool numeric = false;     // DIGITS / NUMBER / PHONE (Fcitx5 Digit/Number/Dialable) → passthrough
    bool sensitive = false;   // Fcitx5 Sensitive / IBus HINT_PRIVATE → passthrough, not remembered
};

struct AppPolicy {
    bool off = false;                         // [app_modes] "off" / default-off app: no Vietnamese
    bool passthrough = false;                 // this field only (numeric / sensitive)
    bool rememberState = true;                // may a Vi/En toggle here be saved per app?
    DisplayMode mode = DisplayMode::Preedit;  // effective display mode
    // May the Session read back / delete text before the caret (re-edit, ⌫ reopen)?
    // False for forced-preedit apps, and for unknown apps / any app until real
    // surrounding text has been proven for this focus.
    bool allowSurroundingEdits = false;
};

// surroundingProven: the client actually delivered surrounding text for this focus (not
// just the capability bit — IBus keeps an empty text for clients that never send one).
AppPolicy resolveAppPolicy(const std::string &appId, const Settings &s, bool surroundingProven,
                           const FieldHints &field = FieldHints());

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
