// debug_log.h — VIETTELEX_DEBUG=1 diagnostics for both frontends (journal / stderr).
//
// Off by default: enabled() is one cached getenv, so call sites cost a branch when off.
// On: the first line is a context header (version, frontend + version, distro, arch, desktop,
// session type, locale, layouts, settings snapshot — never user/host names), identical
// consecutive lines collapse into one "×N" line, and the settings line is re-emitted only when
// a reload changed it. Storage: journald (or the terminal) owns size/rotation — nothing here
// writes a file.
//
// PRIVACY: lines carry structure only (modes, flags, lengths, counts) — NEVER typed or
// surrounding text, shortcut triggers/expansions or window titles.
#pragma once

#include "viettelex/settings.h"

#include <cstddef>
#include <functional>
#include <string>
#include <vector>

namespace viettelex::debuglog {

bool enabled();  // VIETTELEX_DEBUG set in the IM daemon's environment (read once)

// Process environment that explains most "works here, not there" reports.
struct Env {
    std::string os;           // /etc/os-release PRETTY_NAME
    std::string arch;         // uname -m
    std::string kernel;       // uname -r
    std::string desktop;      // XDG_CURRENT_DESKTOP
    std::string sessionType;  // XDG_SESSION_TYPE (x11 / wayland / tty)
    bool waylandDisplay = false;
    bool x11Display = false;
    std::string locale;       // LC_ALL > LC_CTYPE > LANG
    std::string install;      // "deb" / "rpm" / "pacman" / "source"
};
Env readEnv();

// Frontend facts the common code cannot see.
struct Frontend {
    std::string name;     // "fcitx5" / "ibus"
    std::string version;  // frontend (daemon / headers) version
    std::string layouts;  // keyboard layout(s) / enabled input methods, comma-separated
    int gnomeShell = 0;   // GNOME Shell major (0 = not GNOME / unknown)
};

// One compact line per settings group: method, typing toggles, display, auto text, hints.
std::string settingsLine(const Settings &s);
// Header lines (no timestamps — journald stamps every line).
std::vector<std::string> headerLines(const std::string &version, const Frontend &fe, const Env &env,
                                     const Settings &s);

// Collapses runs of identical lines: push() returns what to print now (the first line of a
// run prints at once; repeats print nothing; the run's end prints "  ×N" before the new line).
class Collapser {
public:
    std::vector<std::string> push(const std::string &line);
    std::vector<std::string> flush();  // pending "×N" (if any)

private:
    std::string last_;
    size_t repeats_ = 0;
};

// Header-once + collapse + settings-on-change, printing through `sink` (FCITX_INFO / g_message).
// Single-threaded (each frontend logs from its main loop).
class Logger {
public:
    using Sink = std::function<void(const std::string &)>;
    explicit Logger(Sink sink) : sink_(std::move(sink)) {}
    // Emits the header on the first call, later calls only a changed settings line.
    void context(const std::string &version, const Frontend &fe, const Settings &s);
    void line(const std::string &l);

private:
    void out(const std::vector<std::string> &ls);
    Sink sink_;
    Collapser collapse_;
    bool headerDone_ = false;
    std::string lastSettings_;
};

}  // namespace viettelex::debuglog
