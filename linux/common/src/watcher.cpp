// watcher.cpp — see watcher.h.
#include "viettelex/watcher.h"

#include <cstring>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

namespace viettelex {

namespace {
struct timespec mtimeOf(const std::string &path) {
    struct stat st;
    if (::stat(path.c_str(), &st) != 0) return {0, 0};
    return st.st_mtim;
}
bool same(const struct timespec &a, const struct timespec &b) {
    return a.tv_sec == b.tv_sec && a.tv_nsec == b.tv_nsec;
}
}  // namespace

SettingsWatcher::SettingsWatcher(std::string dir) : dir_(std::move(dir)) {
    mkdirs(dir_);
    fd_ = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (fd_ >= 0) {
        wd_ = inotify_add_watch(fd_, dir_.c_str(),
                                IN_CLOSE_WRITE | IN_MOVED_TO | IN_DELETE | IN_CREATE | IN_MOVED_FROM);
        if (wd_ < 0) { ::close(fd_); fd_ = -1; }
    }
    reload();
}

SettingsWatcher::~SettingsWatcher() {
    if (fd_ >= 0) ::close(fd_);
}

bool SettingsWatcher::drain() {
    if (fd_ < 0) return false;
    bool relevant = false;
    alignas(struct inotify_event) char buf[4096];
    for (;;) {
        ssize_t n = ::read(fd_, buf, sizeof buf);
        if (n <= 0) break;
        for (char *p = buf; p < buf + n;) {
            auto *ev = reinterpret_cast<struct inotify_event *>(p);
            if (ev->len > 0) {
                const char *name = ev->name;
                // IN_CREATE of config.toml.tmp is noise; the rename (IN_MOVED_TO) is the signal.
                if ((std::strcmp(name, "config.toml") == 0 || std::strcmp(name, "shortcuts.yml") == 0) &&
                    !(ev->mask & IN_CREATE))
                    relevant = true;
            }
            p += sizeof(struct inotify_event) + ev->len;
        }
    }
    return relevant;
}

bool SettingsWatcher::changedOnDisk() {
    return !same(mtimeOf(dir_ + "/config.toml"), cfgMtime_) ||
           !same(mtimeOf(dir_ + "/shortcuts.yml"), scMtime_);
}

const Settings &SettingsWatcher::reload() {
    cfgMtime_ = mtimeOf(dir_ + "/config.toml");
    scMtime_ = mtimeOf(dir_ + "/shortcuts.yml");
    settings_ = loadSettings(dir_);
    return settings_;
}

}  // namespace viettelex
