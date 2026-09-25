// watcher.h — live settings: inotify on the config dir + mtime fallback.
// The frontend polls `fd()` in its own event loop and calls `drain()` when readable.
#pragma once

#include "viettelex/settings.h"

#include <ctime>
#include <string>

namespace viettelex {

class SettingsWatcher {
public:
    explicit SettingsWatcher(std::string dir = configDir());
    ~SettingsWatcher();
    SettingsWatcher(const SettingsWatcher &) = delete;
    SettingsWatcher &operator=(const SettingsWatcher &) = delete;

    int fd() const { return fd_; }        // -1 when inotify is unavailable
    // Reads pending inotify events; true if config.toml/shortcuts.yml changed.
    bool drain();
    // mtime check (focus-in fallback); true if either file changed since last load.
    bool changedOnDisk();
    // Reloads from disk and records mtimes.
    const Settings &reload();
    const Settings &settings() const { return settings_; }
    const std::string &dir() const { return dir_; }

private:
    std::string dir_;
    int fd_ = -1;
    int wd_ = -1;
    Settings settings_;
    struct timespec cfgMtime_ = {0, 0}, scMtime_ = {0, 0};
};

}  // namespace viettelex
