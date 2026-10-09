// app.h — per-app policy (display mode resolution) and per-app Vi/En memory.
#pragma once

#include "viettelex/settings.h"

#include <map>
#include <string>

namespace viettelex {

// Normalises a frontend-provided identity ("/usr/bin/Konsole", "org.gnome.TextEditor.desktop",
// "gtk3-im:gedit") to the lowercase key used by [app_modes] and app-state.
std::string normalizeAppId(const std::string &raw);

// Built-in terminal emulators (VTE apps, konsole, kitty, alacritty, wezterm, foot, xterm,
// ptyxis, tilix…). VS Code's integrated terminal is not detectable (it is "code").
bool isTerminalApp(const std::string &appId);

// How the focused client talks to the IM. It decides whether Direct mode is safe: Direct
// sends BackSpace AND the replacement text as forwarded key events, so they must all
// reach the app through ONE ordered queue.
//   IBusGtk     "gtk3-im:" / "gtk-im:" IBus module: ForwardKeyEvent → gdk_event_put, and a
//               forwarded printable key is committed by the module itself (IBUS_IGNORED_MASK
//               → ibus_im_context_commit_event) → same queue, ordered.        Direct: yes
//   IBusGtk4    "gtk4-im:": ForwardKeyEvent → gtk_im_context_filter_key only reaches the IM,
//               never the widget: a forwarded BackSpace is lost.              Direct: no
//   IBusQt      "QIBusInputContext": ordered, but no app id / terminal purpose → unused.
//   IBusXim     "xim" (ibus-x11): no app id.                                  Direct: no
//   IBusWayland "gnome-shell" (GNOME text-input-v3) / ibus-wayland: forwarded keys become
//               wl_keyboard events, commits text-input events — two channels. Direct: no
//   FcitxOrdered   Fcitx5 D-Bus frontend with KeyEventOrderFix (fcitx5-gtk2/3, fcitx5-qt):
//               forwarded keys → gdk_event_put / QWindowSystemInterface queue, printable
//               ones committed by the module's fallback context → ordered.  Direct: yes
//   FcitxUnordered D-Bus without KeyEventOrderFix (fcitx5-gtk4: forwardKey is a no-op).
//   FcitxXim / FcitxWayland ("wayland": zwp_input_method_v1 — KWin, Weston) /
//   FcitxWaylandV2 ("wayland_v2": input-method-v2 — wlroots) / FcitxIBus (fcitx5's IBus
//   emulation, any other client — X11/XWayland apps with GTK_IM_MODULE=ibus…): no.
//   FcitxGnomeWayland  Fcitx5's "ibus" frontend serving gnome-shell itself on GNOME Wayland
//               (fcitxIBusIsGnomeShell): the same gnome-shell → mutter path as IBusWayland.
enum class ClientHost {
    Unknown, IBusGtk, IBusGtk4, IBusQt, IBusXim, IBusWayland,
    FcitxOrdered, FcitxUnordered, FcitxXim, FcitxWayland, FcitxIBus, FcitxWaylandV2,
    FcitxGnomeWayland,
};
// IBus client name as sent by the client ("gtk3-im:gnome-terminal-server", "xim", …).
ClientHost ibusClientHost(const std::string &rawClientName);
// Fcitx5 "ibus" frontend: is this input context gnome-shell's own (the one context every
// app types through on GNOME Wayland)? `rawProgram` is InputContext::program() as is.
//   * gnome-shell creates its context as CreateInputContext("gnome-shell") (js/misc/
//     inputMethod.js, 42 → main) and Fcitx5 keeps a non-generic name as the program;
//   * Fcitx5 versions with their own GNOME app monitor hand engines a VirtualInputContext
//     per app under that context, named by the shell's app id ("google-chrome.desktop",
//     "window:12"; the overview one is "gnome-shell") — names no IBus client sends
//     (GTK: "gtk3-im:…"/"gtk-im" → process name, Qt: process name, ibus-x11: "xim").
// Only in a GNOME Wayland session (the Fcitx5 process's XDG_CURRENT_DESKTOP /
// XDG_SESSION_TYPE): on GNOME X11 gnome-shell's context only serves the shell's own entries.
// InputContext::display() is no help: an "ibus" context gets the default focus group
// (Instance::defaultFocusGroup prefers any "wayland:" group), the same for X11 clients.
bool fcitxIBusIsGnomeShell(const std::string &rawProgram, bool gnomeWaylandSession);
// Fcitx5 InputContext::frontendName() + CapabilityFlag::KeyEventOrderFix; for "ibus" also
// the raw program + session (fcitxIBusIsGnomeShell → FcitxGnomeWayland, else FcitxIBus).
ClientHost fcitxClientHost(const std::string &frontendName, bool keyEventOrderFix,
                           const std::string &rawProgram = std::string(), bool gnomeWaylandSession = false);
bool hostSupportsDirect(ClientHost h);
// [experimental] no_underline = "forward-keys" (docs/NO-UNDERLINE-SPIKE.md): does the
// compositor deliver the IM's forwarded keys and its commits to the app in the order the IM
// sent them? IBusWayland: mutter >= 3.38 queues ForwardKeyEvent and CommitText as Clutter
// events in one queue (MR !1286) and flushes text_input.done before a passed-through key.
// FcitxWayland (zwp_input_method_v1, KWin): keysym / key / commit_string requests are handled
// synchronously in request order. FcitxGnomeWayland: Fcitx5's ibus frontend emits
// ForwardKeyEvent and CommitText as signals on the one D-Bus connection to gnome-shell, whose
// inputMethod.js turns them into forward_key / commit — the IBusWayland queue from there on. Only Chromium-based clients (ozone/wayland dispatches
// wl_keyboard and text-input on the same thread, synchronously) keep that order up to the
// page — see isChromiumApp. wlroots (input-method-v2 + virtual keyboard) is unverified.
bool hostOrdersForwardedKeys(ClientHost h);

// Built-in list of apps where Surrounding mode is unsafe (terminals, LibreOffice,
// Chromium/Electron, Firefox/Gecko, gnome-shell) → always Preedit unless the user pins
// "surrounding".
bool isForcedPreeditApp(const std::string &appId);
// The Chromium / Electron part of that list (browsers, Electron apps, PWAs "crx_*" /
// "chrome-*-default"): unreliable delete-surrounding, but BackSpace key events work.
bool isChromiumApp(const std::string &appId);

// Built-in list of apps that start in English (keys pass through): remote desktop / VM
// viewers and Wine programs. Any [app_modes] entry for the app overrides it.
bool isDefaultOffApp(const std::string &appId);
// Wine program (wine*-preloader / *.exe): forced preedit, NOT default-off.
bool isWineApp(const std::string &appId);

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
    ClientHost host = ClientHost::Unknown;  // may Direct mode be used here?
};

struct AppPolicy {
    bool off = false;                         // [app_modes] "off" / default-off app: no Vietnamese
    bool passthrough = false;                 // this field only (numeric / sensitive)
    bool rememberState = true;                // may a Vi/En toggle here be saved per app?
    DisplayMode mode = DisplayMode::Preedit;  // effective display mode (Direct: terminals)
    // May the Session read back / delete text before the caret (re-edit, ⌫ reopen)?
    // False for forced-preedit apps, and for unknown apps / any app until real
    // surrounding text has been proven for this focus.
    bool allowSurroundingEdits = false;
    // [experimental] no_underline = "forward-keys": mode is Surrounding, but every delete is
    // sent as forwarded BackSpace keys (Session::setDeleteWithKeys). Never re-edit / reopen.
    bool deleteWithKeys = false;
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
