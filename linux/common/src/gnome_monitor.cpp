// gnome_monitor.cpp — see gnome_monitor.h.
#include "viettelex/gnome_monitor.h"

#include "viettelex/gnome.h"

#include <gio/gio.h>

#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

namespace viettelex {

namespace {
constexpr const char *kShell = "org.gnome.Shell";
constexpr const char *kShellPath = "/org/gnome/Shell";
constexpr const char *kIntrospect = "org.gnome.Shell.Introspect";
constexpr const char *kIntrospectPath = "/org/gnome/Shell/Introspect";

// Only what the tracker needs: gnome-shell's focus signal, anyone's GetRunningApplications
// call (the portal's, ours), gnome-shell's replies, and its OverviewActive changes.
const char *const kRules[] = {
    "type='signal',sender='org.gnome.Shell',path='/org/gnome/Shell/Introspect',"
    "interface='org.gnome.Shell.Introspect',member='RunningApplicationsChanged'",
    "type='method_call',path='/org/gnome/Shell/Introspect',interface='org.gnome.Shell.Introspect',"
    "member='GetRunningApplications'",
    "type='method_return',sender='org.gnome.Shell'",
    "type='signal',sender='org.gnome.Shell',path='/org/gnome/Shell',"
    "interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.gnome.Shell'",
};

void logErr(const char *what, GError *err) {
    std::fprintf(stderr, "viettelex: gnome app monitor: %s: %s\n", what, err ? err->message : "failed");
}
}  // namespace

struct GnomeAppMonitor::Impl {
    mutable std::mutex mu;  // tracker + flags + connections
    gnome::FocusTracker tracker;
    bool started = false, stopped = false, monitoring = false;
    std::string monUnique;
    GDBusConnection *mon = nullptr, *conn = nullptr;
    guint filterId = 0;
    std::thread thread;

    std::mutex cbMu;  // held while calling back, so stop() waits for a running one
    std::function<void()> cb;

    void notify() {
        std::lock_guard<std::mutex> l(cbMu);
        if (cb) cb();
    }

    // GDBus worker thread. Returns true when resolve() may have changed.
    bool handle(GDBusMessage *msg) {
        GDBusMessageType type = g_dbus_message_get_message_type(msg);
        const gchar *iface = g_dbus_message_get_interface(msg);
        const gchar *member = g_dbus_message_get_member(msg);
        auto is = [](const gchar *a, const char *b) { return a && std::strcmp(a, b) == 0; };
        std::lock_guard<std::mutex> l(mu);
        if (type == G_DBUS_MESSAGE_TYPE_SIGNAL) {
            if (is(iface, kIntrospect) && is(member, "RunningApplicationsChanged")) return tracker.onAppsChanged();
            if (is(iface, "org.freedesktop.DBus.Properties") && is(member, "PropertiesChanged")) {
                GVariant *body = g_dbus_message_get_body(msg);
                if (!body || !g_variant_is_of_type(body, G_VARIANT_TYPE("(sa{sv}as)"))) return false;
                const gchar *name = nullptr;
                GVariant *changed = nullptr;
                g_variant_get(body, "(&s@a{sv}@as)", &name, &changed, nullptr);
                bool result = false;
                gboolean active = FALSE;
                if (is(name, kShell) && g_variant_lookup(changed, "OverviewActive", "b", &active))
                    result = tracker.onOverview(active);
                g_variant_unref(changed);
                return result;
            }
            return false;
        }
        if (type == G_DBUS_MESSAGE_TYPE_METHOD_CALL) {
            const gchar *sender = g_dbus_message_get_sender(msg);
            if (sender && is(iface, kIntrospect) && is(member, "GetRunningApplications"))
                tracker.onCall(sender, g_dbus_message_get_serial(msg));
            return false;
        }
        if (type == G_DBUS_MESSAGE_TYPE_METHOD_RETURN) {
            const gchar *dest = g_dbus_message_get_destination(msg);
            GVariant *body = g_dbus_message_get_body(msg);
            std::vector<gnome::RunningApp> apps;
            if (!dest || !gnome::parseRunningApplications(body, apps)) return false;
            return tracker.onReply(dest, g_dbus_message_get_reply_serial(msg), apps);
        }
        return false;
    }

    static GDBusMessage *filter(GDBusConnection *, GDBusMessage *msg, gboolean incoming, gpointer ud) {
        if (!incoming) return msg;
        auto self = *static_cast<std::shared_ptr<Impl> *>(ud);
        GDBusMessageType type = g_dbus_message_get_message_type(msg);
        const gchar *dest = g_dbus_message_get_destination(msg);
        {
            std::lock_guard<std::mutex> l(self->mu);
            if (self->stopped) {
                g_object_unref(msg);
                return nullptr;
            }
            // Replies to our own calls (BecomeMonitor) go on to GDBus.
            if ((type == G_DBUS_MESSAGE_TYPE_METHOD_RETURN || type == G_DBUS_MESSAGE_TYPE_ERROR) && dest &&
                self->monUnique == dest)
                return msg;
        }
        // Everything else is observed only: a monitor must never answer (GDBus would reply
        // "unknown method" to monitored calls), so it is dropped here.
        bool changed = false;
        try {
            changed = self->handle(msg);
        } catch (...) {
        }
        g_object_unref(msg);
        if (changed) self->notify();
        return nullptr;
    }

    // Private thread: blocking setup, then done (messages arrive on GDBus's worker thread).
    void run(std::shared_ptr<Impl> self, std::string address) {
        GError *err = nullptr;
        if (address.empty()) {
            gchar *a = g_dbus_address_get_for_bus_sync(G_BUS_TYPE_SESSION, nullptr, &err);
            if (!a) {
                logErr("session bus address", err);
                g_clear_error(&err);
                return;
            }
            address = a;
            g_free(a);
        }
        auto flags = GDBusConnectionFlags(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION);
        GDBusConnection *m = g_dbus_connection_new_for_address_sync(address.c_str(), flags, nullptr, nullptr, &err);
        if (!m) {
            logErr("connect", err);
            g_clear_error(&err);
            return;
        }
        g_dbus_connection_set_exit_on_close(m, FALSE);
        {
            std::lock_guard<std::mutex> l(mu);
            mon = m;
            monUnique = g_dbus_connection_get_unique_name(m);
            if (stopped) return;
            filterId = g_dbus_connection_add_filter(m, filter, new std::shared_ptr<Impl>(self), [](gpointer p) {
                delete static_cast<std::shared_ptr<Impl> *>(p);
            });
        }
        GVariantBuilder rules;
        g_variant_builder_init(&rules, G_VARIANT_TYPE("as"));
        for (const char *r : kRules) g_variant_builder_add(&rules, "s", r);
        GVariant *res = g_dbus_connection_call_sync(m, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                                                    "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
                                                    g_variant_new("(asu)", &rules, 0u), nullptr,
                                                    G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &err);
        if (!res) {
            logErr("BecomeMonitor", err);
            g_clear_error(&err);
            return;
        }
        g_variant_unref(res);

        GDBusConnection *c = g_dbus_connection_new_for_address_sync(address.c_str(), flags, nullptr, nullptr, &err);
        if (!c) {
            logErr("connect", err);
            g_clear_error(&err);
        } else {
            g_dbus_connection_set_exit_on_close(c, FALSE);
        }
        {
            std::lock_guard<std::mutex> l(mu);
            monitoring = true;
            conn = c;
            if (stopped || !c) return;
        }
        // Initial overview state (later changes come as PropertiesChanged).
        res = g_dbus_connection_call_sync(c, kShell, kShellPath, "org.freedesktop.DBus.Properties", "Get",
                                          g_variant_new("(ss)", kShell, "OverviewActive"), G_VARIANT_TYPE("(v)"),
                                          G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000, nullptr, nullptr);
        if (res) {
            GVariant *v = nullptr;
            g_variant_get(res, "(v)", &v);
            bool changed = false;
            if (v && g_variant_is_of_type(v, G_VARIANT_TYPE_BOOLEAN)) {
                std::lock_guard<std::mutex> l(mu);
                changed = tracker.onOverview(g_variant_get_boolean(v));
            }
            if (v) g_variant_unref(v);
            g_variant_unref(res);
            if (changed) notify();
        }
        // Initial focus: AccessDenied unless the shell runs in unsafe mode; when it works,
        // the monitor sees this call and its reply like the portal's.
        res = g_dbus_connection_call_sync(c, kShell, kIntrospectPath, kIntrospect, "GetRunningApplications",
                                          nullptr, nullptr, G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000, nullptr, nullptr);
        if (res) g_variant_unref(res);
    }
};

GnomeAppMonitor::GnomeAppMonitor() : d_(std::make_shared<Impl>()) {}

GnomeAppMonitor::~GnomeAppMonitor() { stop(); }

bool GnomeAppMonitor::start(const std::string &busAddress) {
    std::lock_guard<std::mutex> l(d_->mu);
    if (d_->started) return !d_->stopped;
    d_->started = true;
    try {
        std::shared_ptr<Impl> self = d_;
        d_->thread = std::thread([self, busAddress] { self->run(self, busAddress); });
    } catch (...) {
        d_->stopped = true;
        return false;
    }
    return true;
}

void GnomeAppMonitor::stop() {
    {
        std::lock_guard<std::mutex> l(d_->mu);
        if (d_->stopped) return;
        d_->stopped = true;
    }
    if (d_->thread.joinable()) d_->thread.join();
    {
        std::lock_guard<std::mutex> cb(d_->cbMu);  // no callback in flight after this
        d_->cb = nullptr;
    }
    GDBusConnection *m, *c;
    guint fid;
    {
        std::lock_guard<std::mutex> l(d_->mu);
        m = d_->mon;
        c = d_->conn;
        fid = d_->filterId;
        d_->mon = d_->conn = nullptr;
        d_->filterId = 0;
        d_->monitoring = false;
    }
    if (m) {
        if (fid) g_dbus_connection_remove_filter(m, fid);  // drops the filter's Impl reference
        g_dbus_connection_close(m, nullptr, nullptr, nullptr);
        g_object_unref(m);
    }
    if (c) {
        g_dbus_connection_close(c, nullptr, nullptr, nullptr);
        g_object_unref(c);
    }
}

bool GnomeAppMonitor::running() const {
    std::lock_guard<std::mutex> l(d_->mu);
    return d_->started && !d_->stopped;
}

std::string GnomeAppMonitor::resolve(const std::string &clientId) const {
    std::lock_guard<std::mutex> l(d_->mu);
    if (!d_->monitoring) return clientId;
    return d_->tracker.resolve(clientId);
}

bool GnomeAppMonitor::monitoring() const {
    std::lock_guard<std::mutex> l(d_->mu);
    return d_->monitoring;
}

void GnomeAppMonitor::setOnChange(std::function<void()> cb) {
    std::lock_guard<std::mutex> l(d_->cbMu);
    d_->cb = std::move(cb);
}

}  // namespace viettelex
