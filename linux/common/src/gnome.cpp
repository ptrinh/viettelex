// gnome.cpp — see gnome.h.
#include "viettelex/gnome.h"

#include "viettelex/app.h"

#include <glib.h>

#include <cstdlib>

namespace viettelex {
namespace gnome {

const char *const kOverviewAppId = "gnome-shell-overview";

bool parseRunningApplications(GVariant *value, std::vector<RunningApp> &out) {
    out.clear();
    if (!value) return false;
    GVariant *dict = nullptr;
    if (g_variant_is_of_type(value, G_VARIANT_TYPE("(a{sa{sv}})"))) {
        dict = g_variant_get_child_value(value, 0);
    } else if (g_variant_is_of_type(value, G_VARIANT_TYPE("a{sa{sv}}"))) {
        dict = g_variant_ref(value);
    } else {
        return false;
    }
    GVariantIter iter;
    g_variant_iter_init(&iter, dict);
    const gchar *id = nullptr;
    GVariant *props = nullptr;
    while (g_variant_iter_loop(&iter, "{&s@a{sv}}", &id, &props)) {
        RunningApp app;
        app.id = id ? id : "";
        GVariant *seats = g_variant_lookup_value(props, "active-on-seats", G_VARIANT_TYPE("as"));
        if (seats) {
            app.active = g_variant_n_children(seats) > 0;
            g_variant_unref(seats);
        }
        const gchar *sandboxed = nullptr;
        if (g_variant_lookup(props, "sandboxed-app-id", "&s", &sandboxed) && sandboxed)
            app.sandboxedAppId = sandboxed;
        out.push_back(std::move(app));
    }
    g_variant_unref(dict);
    return true;
}

std::string focusedAppId(const std::vector<RunningApp> &apps) {
    std::string found;
    int n = 0;
    for (const auto &a : apps) {
        if (!a.active) continue;
        ++n;
        std::string raw = a.id;
        // Window-backed ShellApp ("window:12"): no desktop id; the sandbox id is still one.
        if (raw.empty() || raw.rfind("window:", 0) == 0) raw = a.sandboxedAppId;
        found = normalizeAppId(raw);
    }
    if (n != 1 || isUnknownAppId(found)) return "";
    return found;
}

namespace {
std::string lower(const char *s) {
    std::string r = s ? s : "";
    for (auto &c : r)
        if (c >= 'A' && c <= 'Z') c = char(c - 'A' + 'a');
    return r;
}
}  // namespace

bool isGnomeWayland(const char *currentDesktop, const char *sessionType, const char *waylandDisplay) {
    std::string desk = lower(currentDesktop);
    bool gnome = false;
    size_t start = 0;
    while (start <= desk.size()) {
        size_t end = desk.find(':', start);
        if (end == std::string::npos) end = desk.size();
        if (desk.compare(start, end - start, "gnome") == 0) gnome = true;
        start = end + 1;
    }
    if (!gnome) return false;
    std::string type = lower(sessionType);
    if (!type.empty()) return type == "wayland";
    return waylandDisplay && *waylandDisplay;
}

bool isGnomeWaylandSession() {
    return isGnomeWayland(std::getenv("XDG_CURRENT_DESKTOP"), std::getenv("XDG_SESSION_TYPE"),
                          std::getenv("WAYLAND_DISPLAY"));
}

bool isSharedShellClientId(const std::string &clientId) {
    std::string id = normalizeAppId(clientId);
    return id.empty() || id == "gnome-shell" || id == "default" || id == "wayland";
}

// MARK: - FocusTracker

bool FocusTracker::onAppsChanged() {
    ++signalSeq_;
    bool changed = valid_ && !pending_;
    pending_ = true;
    return changed;
}

void FocusTracker::onCall(const std::string &sender, uint32_t serial) {
    if (calls_.size() >= 16) calls_.erase(calls_.begin());  // replies that never came
    calls_[{sender, serial}] = signalSeq_;
}

bool FocusTracker::onReply(const std::string &destination, uint32_t replySerial,
                           const std::vector<RunningApp> &apps) {
    auto it = calls_.find({destination, replySerial});
    if (it == calls_.end()) return false;
    uint64_t seq = it->second;
    calls_.erase(it);
    std::string before = resolve("gnome-shell");
    focus_ = focusedAppId(apps);
    valid_ = true;
    // A call made before the latest signal answers with the state of that time.
    if (seq == signalSeq_) pending_ = false;
    return resolve("gnome-shell") != before;
}

bool FocusTracker::onOverview(bool active) {
    if (overview_ == active) return false;
    overview_ = active;
    return true;
}

std::string FocusTracker::resolve(const std::string &clientId) const {
    if (!isSharedShellClientId(clientId)) return clientId;
    if (overview_) return kOverviewAppId;
    if (!valid_ || pending_ || focus_.empty()) return clientId;
    return focus_;
}

}  // namespace gnome
}  // namespace viettelex
