// gnome.h — which app is focused on GNOME Wayland (pure logic, no D-Bus I/O).
//
// On GNOME Wayland every app types through ONE input context owned by gnome-shell, so IBus
// reports "gnome-shell" (1.5.28+) or "default" (1.5.26, Ubuntu 22.04) and Fcitx5 < 5.1.22
// reports "gnome-shell". The real app is only known to gnome-shell, which publishes it on
// the session bus as org.gnome.Shell.Introspect.GetRunningApplications (a{sa{sv}}: desktop
// id → {"active-on-seats": as, "sandboxed-app-id": s}). That method is allow-listed to the
// desktop portal backends (GNOME 41+, incl. 42 and 46), so GnomeAppMonitor (gnome_monitor.h)
// reads the portal's own call and its reply, like fcitx5 5.1.22 (gnomeappmonitor.cpp).
//
// This header is the part that does not need a bus: payload parsing, the freshness state
// machine and the id substitution, so it is unit-tested with GNOME 42/46 fixtures.
#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <utility>
#include <vector>

struct _GVariant;

namespace viettelex {
namespace gnome {

// The id used while the Activities overview is shown (forced preedit, see app.cpp).
extern const char *const kOverviewAppId;

struct RunningApp {
    std::string id;               // ShellApp id: "org.gnome.TextEditor.desktop", "window:12"
    bool active = false;          // has "active-on-seats" (non-empty) = the focused app
    std::string sandboxedAppId;   // Flatpak / Snap id, when the shell reports one
};

// Parses the GetRunningApplications reply body "(a{sa{sv}})" (or the bare "a{sa{sv}}").
// False when the value has another type.
bool parseRunningApplications(_GVariant *value, std::vector<RunningApp> &out);

// The focused app's normalised id ("org.gnome.texteditor"), or "" when no app is focused,
// the focused one is window-backed (no .desktop file: "window:N") or it is ambiguous.
std::string focusedAppId(const std::vector<RunningApp> &apps);

// XDG_CURRENT_DESKTOP contains GNOME (":"-separated, any case) and the session is Wayland
// (XDG_SESSION_TYPE=wayland, or WAYLAND_DISPLAY set when the type is unset).
bool isGnomeWayland(const char *currentDesktop, const char *sessionType, const char *waylandDisplay);
bool isGnomeWaylandSession();  // from the environment

// The ids a frontend gets for gnome-shell's shared context: "gnome-shell", "default",
// "wayland" and "" (normalised). Only these are replaced by the focused app.
bool isSharedShellClientId(const std::string &clientId);

// Freshness bookkeeping over the messages seen on the bus, in bus order:
//   RunningApplicationsChanged signal → every call made before it is stale;
//   GetRunningApplications call (sender, serial) → reply (destination, reply serial).
// Until a reply to a call made after the latest signal arrives, the focus is "pending"
// and resolve() keeps the generic id (preedit) rather than guess from the previous app.
class FocusTracker {
public:
    bool onAppsChanged();  // the signal; true if resolve() may have changed
    void onCall(const std::string &sender, uint32_t serial);        // a GetRunningApplications call
    // A reply from gnome-shell; ignored unless it answers a call we saw. True if the
    // resolved state may have changed.
    bool onReply(const std::string &destination, uint32_t replySerial, const std::vector<RunningApp> &apps);
    bool onOverview(bool active);                                   // OverviewActive
    // What the frontend should use for `clientId`: unchanged unless it is a shared shell
    // id; then "gnome-shell-overview", the focused app, or unchanged (unknown / pending).
    std::string resolve(const std::string &clientId) const;

    bool valid() const { return valid_; }
    bool pending() const { return pending_; }
    const std::string &focus() const { return focus_; }
    bool overview() const { return overview_; }

private:
    uint64_t signalSeq_ = 0;
    std::map<std::pair<std::string, uint32_t>, uint64_t> calls_;  // → signalSeq_ at call time
    bool valid_ = false, pending_ = false, overview_ = false;
    std::string focus_;
};

}  // namespace gnome
}  // namespace viettelex
