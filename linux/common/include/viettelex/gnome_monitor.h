// gnome_monitor.h — the focused app on GNOME Wayland, read from the session bus.
//
// Mechanism (same as fcitx5 5.1.22 gnomeappmonitor.cpp; no GNOME extension needed):
//   * gnome-shell emits org.gnome.Shell.Introspect.RunningApplicationsChanged (a broadcast
//     signal) synchronously whenever the focused app changes;
//   * xdg-desktop-portal-gnome answers it at once with GetRunningApplications — a method
//     only the portal backends may call (GNOME 41+ DBusSenderChecker, 42 and 46 included;
//     anyone else gets AccessDenied unless the shell runs in unsafe mode);
//   * a second, private session-bus connection becomes a D-Bus monitor
//     (org.freedesktop.DBus.Monitoring.BecomeMonitor — allowed for the bus owner's uid)
//     with match rules for exactly that signal, that call, gnome-shell's replies and its
//     OverviewActive PropertiesChanged, and reads the reply meant for the portal.
// Everything is signal-driven (no polling). Messages are handled on GDBus's worker thread
// and on a private thread (connection setup, initial OverviewActive); `onChange` is called
// from those threads, so frontends marshal it onto their own loop.
//
// If the portal is not running, the id simply stays generic (preedit). A direct call is
// tried once at start (works in unsafe mode, harmless otherwise).
#pragma once

#include <functional>
#include <memory>
#include <string>

namespace viettelex {

class GnomeAppMonitor {
public:
    GnomeAppMonitor();
    ~GnomeAppMonitor();
    GnomeAppMonitor(const GnomeAppMonitor &) = delete;
    GnomeAppMonitor &operator=(const GnomeAppMonitor &) = delete;

    // Starts once (idempotent). `busAddress` empty = the user session bus. Returns false if
    // already stopped / could not spawn; connection errors are only logged.
    bool start(const std::string &busAddress = std::string());
    void stop();
    bool running() const;

    // See gnome::FocusTracker::resolve. Thread-safe.
    std::string resolve(const std::string &clientId) const;
    // Monitor is active (BecomeMonitor succeeded) — for tests/diagnostics.
    bool monitoring() const;

    // Called (from a background thread) when resolve() may give a different answer.
    void setOnChange(std::function<void()> cb);

    struct Impl;

private:
    std::shared_ptr<Impl> d_;
};

}  // namespace viettelex
