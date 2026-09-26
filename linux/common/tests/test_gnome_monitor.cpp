// test_gnome_monitor — GnomeAppMonitor against a real dbus-daemon (run under dbus-run-session).
//
// A fake gnome-shell owns org.gnome.Shell + org.gnome.Shell.Introspect with GNOME 42/46
// semantics: GetRunningApplications answers only the portal backend (DBusSenderChecker
// allow-list; everyone else gets AccessDenied unless "unsafe mode"), RunningApplications-
// Changed on every focus change, OverviewActive + PropertiesChanged. A fake
// xdg-desktop-portal-gnome calls GetRunningApplications on each signal, like background.c.
// The monitor must learn the focus only from that traffic (BecomeMonitor).

#include "viettelex/gnome_monitor.h"

#include <gio/gio.h>

#include <atomic>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>

using viettelex::GnomeAppMonitor;

static int g_fail = 0, g_pass = 0;
#define CHECK(x)                                                                  \
    do {                                                                          \
        if (x) ++g_pass;                                                          \
        else {                                                                    \
            ++g_fail;                                                             \
            std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__, __LINE__, #x); \
        }                                                                         \
    } while (0)

namespace {

const char *kIntrospectXml =
    "<node><interface name='org.gnome.Shell.Introspect'>"
    "<method name='GetRunningApplications'><arg type='a{sa{sv}}' direction='out'/></method>"
    "<signal name='RunningApplicationsChanged'/>"
    "</interface></node>";
const char *kShellXml =
    "<node><interface name='org.gnome.Shell'>"
    "<property name='OverviewActive' type='b' access='readwrite'/>"
    "</interface></node>";

struct FakeShell {
    GDBusConnection *conn = nullptr;
    std::string focus;          // desktop id of the focused app ("" = none)
    bool overview = false;
    bool unsafeMode = false;
    std::string portalUnique;   // the only allowed caller
    int denied = 0, answered = 0;
};
FakeShell g_shell;

struct FakePortal {
    GDBusConnection *conn = nullptr;
    int delayMs = 0;
    bool useUniqueDest = false;
    int calls = 0;
};
FakePortal g_portal;

GVariant *runningApps() {
    GVariantBuilder b;
    g_variant_builder_init(&b, G_VARIANT_TYPE("a{sa{sv}}"));
    const char *ids[] = {"org.gnome.Nautilus.desktop", "org.gnome.gedit.desktop", "org.gnome.Terminal.desktop"};
    for (const char *id : ids) {
        GVariantBuilder p;
        g_variant_builder_init(&p, G_VARIANT_TYPE("a{sv}"));
        if (g_shell.focus == id) {
            const gchar *seats[] = {"seat0", nullptr};
            g_variant_builder_add(&p, "{sv}", "active-on-seats", g_variant_new_strv(seats, -1));
        }
        g_variant_builder_add(&b, "{s@a{sv}}", id, g_variant_builder_end(&p));
    }
    return g_variant_new("(@a{sa{sv}})", g_variant_builder_end(&b));
}

void introspectCall(GDBusConnection *, const gchar *sender, const gchar *, const gchar *, const gchar *method,
                    GVariant *, GDBusMethodInvocation *inv, gpointer) {
    if (std::strcmp(method, "GetRunningApplications") != 0) {
        g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.UnknownMethod", "no");
        return;
    }
    if (!g_shell.unsafeMode && g_shell.portalUnique != (sender ? sender : "")) {
        ++g_shell.denied;
        g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.AccessDenied",
                                                   "GetRunningApplications is not allowed");
        return;
    }
    ++g_shell.answered;
    g_dbus_method_invocation_return_value(inv, runningApps());
}

GVariant *shellGetProperty(GDBusConnection *, const gchar *, const gchar *, const gchar *, const gchar *prop,
                           GError **, gpointer) {
    if (std::strcmp(prop, "OverviewActive") == 0) return g_variant_new_boolean(g_shell.overview);
    return nullptr;
}

void emitFocusChanged() {
    g_dbus_connection_emit_signal(g_shell.conn, nullptr, "/org/gnome/Shell/Introspect", "org.gnome.Shell.Introspect",
                                  "RunningApplicationsChanged", nullptr, nullptr);
}

void setOverview(bool on) {
    g_shell.overview = on;
    GVariantBuilder ch;
    g_variant_builder_init(&ch, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&ch, "{sv}", "OverviewActive", g_variant_new_boolean(on));
    g_dbus_connection_emit_signal(g_shell.conn, nullptr, "/org/gnome/Shell", "org.freedesktop.DBus.Properties",
                                  "PropertiesChanged",
                                  g_variant_new("(sa{sv}as)", "org.gnome.Shell", &ch, nullptr), nullptr);
}

// The portal: on each RunningApplicationsChanged, call GetRunningApplications.
gboolean portalCallNow(gpointer) {
    ++g_portal.calls;
    const char *dest = g_portal.useUniqueDest ? g_dbus_connection_get_unique_name(g_shell.conn) : "org.gnome.Shell";
    g_dbus_connection_call(g_portal.conn, dest, "/org/gnome/Shell/Introspect", "org.gnome.Shell.Introspect",
                           "GetRunningApplications", nullptr, G_VARIANT_TYPE("(a{sa{sv}})"),
                           G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000, nullptr,
                           [](GObject *src, GAsyncResult *res, gpointer) {
                               GVariant *v = g_dbus_connection_call_finish(G_DBUS_CONNECTION(src), res, nullptr);
                               if (v) g_variant_unref(v);
                           },
                           nullptr);
    return G_SOURCE_REMOVE;
}

void portalOnSignal(GDBusConnection *, const gchar *, const gchar *, const gchar *, const gchar *, GVariant *,
                    gpointer) {
    if (g_portal.delayMs > 0) g_timeout_add(guint(g_portal.delayMs), portalCallNow, nullptr);
    else portalCallNow(nullptr);
}

GDBusConnection *connect(const std::string &address) {
    GError *err = nullptr;
    auto flags = GDBusConnectionFlags(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                      G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION);
    GDBusConnection *c = g_dbus_connection_new_for_address_sync(address.c_str(), flags, nullptr, nullptr, &err);
    if (!c) {
        std::fprintf(stderr, "connect: %s\n", err->message);
        std::exit(2);
    }
    return c;
}

void requestName(GDBusConnection *c, const char *name) {
    GVariant *r = g_dbus_connection_call_sync(c, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                                              "org.freedesktop.DBus", "RequestName", g_variant_new("(su)", name, 4u),
                                              G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr);
    if (!r) {
        std::fprintf(stderr, "RequestName %s failed\n", name);
        std::exit(2);
    }
    g_variant_unref(r);
}

// Iterates the default main context (the fakes live there) until `cond` or the timeout.
bool waitFor(const std::function<bool()> &cond, int timeoutMs) {
    gint64 end = g_get_monotonic_time() + gint64(timeoutMs) * 1000;
    while (!cond()) {
        if (g_get_monotonic_time() > end) return false;
        g_main_context_iteration(nullptr, FALSE);
        g_usleep(2000);
    }
    return true;
}

void spin(int ms) { waitFor([] { return false; }, ms); }

}  // namespace

int main() {
    const char *addrEnv = std::getenv("DBUS_SESSION_BUS_ADDRESS");
    if (!addrEnv || !*addrEnv) {
        std::printf("gnome monitor test: no session bus (run under dbus-run-session) — skipped\n");
        return 77;
    }
    std::string address = addrEnv;

    // fake gnome-shell
    g_shell.conn = connect(address);
    GDBusNodeInfo *iNode = g_dbus_node_info_new_for_xml(kIntrospectXml, nullptr);
    GDBusNodeInfo *sNode = g_dbus_node_info_new_for_xml(kShellXml, nullptr);
    GDBusInterfaceVTable iv = {introspectCall, nullptr, nullptr, {nullptr}};
    GDBusInterfaceVTable sv = {nullptr, shellGetProperty, nullptr, {nullptr}};
    g_dbus_connection_register_object(g_shell.conn, "/org/gnome/Shell/Introspect", iNode->interfaces[0], &iv,
                                      nullptr, nullptr, nullptr);
    g_dbus_connection_register_object(g_shell.conn, "/org/gnome/Shell", sNode->interfaces[0], &sv, nullptr,
                                      nullptr, nullptr);
    requestName(g_shell.conn, "org.gnome.Shell");
    requestName(g_shell.conn, "org.gnome.Shell.Introspect");

    // fake xdg-desktop-portal-gnome
    g_portal.conn = connect(address);
    requestName(g_portal.conn, "org.freedesktop.impl.portal.desktop.gnome");
    g_shell.portalUnique = g_dbus_connection_get_unique_name(g_portal.conn);
    g_dbus_connection_signal_subscribe(g_portal.conn, "org.gnome.Shell", "org.gnome.Shell.Introspect",
                                       "RunningApplicationsChanged", "/org/gnome/Shell/Introspect", nullptr,
                                       G_DBUS_SIGNAL_FLAGS_NONE, portalOnSignal, nullptr, nullptr);

    g_shell.focus = "org.gnome.Nautilus.desktop";
    std::atomic<int> changes{0};
    {
        GnomeAppMonitor mon;
        mon.setOnChange([&changes] { ++changes; });
        CHECK(mon.start());  // session bus from the environment
        CHECK(waitFor([&] { return mon.monitoring(); }, 5000));
        spin(200);  // initial Properties.Get + the direct call (denied)
        CHECK(g_shell.denied == 1);
        CHECK(mon.resolve("gnome-shell") == "gnome-shell");  // nothing learnt yet

        // focus → gedit; portal answers 300 ms later: pending meanwhile
        g_portal.delayMs = 300;
        g_shell.focus = "org.gnome.gedit.desktop";
        emitFocusChanged();
        spin(100);
        CHECK(mon.resolve("gnome-shell") == "gnome-shell");
        CHECK(waitFor([&] { return mon.resolve("gnome-shell") == "org.gnome.gedit"; }, 3000));
        CHECK(mon.resolve("default") == "org.gnome.gedit");
        CHECK(mon.resolve("gtk3-im:kitty") == "gtk3-im:kitty");
        CHECK(changes > 0);

        // focus → terminal, portal addressing the shell by unique name (GDBusProxy does)
        g_portal.delayMs = 0;
        g_portal.useUniqueDest = true;
        g_shell.focus = "org.gnome.Terminal.desktop";
        emitFocusChanged();
        CHECK(waitFor([&] { return mon.resolve("gnome-shell") == "org.gnome.terminal"; }, 3000));

        // overview
        setOverview(true);
        CHECK(waitFor([&] { return mon.resolve("gnome-shell") == "gnome-shell-overview"; }, 3000));
        setOverview(false);
        CHECK(waitFor([&] { return mon.resolve("gnome-shell") == "org.gnome.terminal"; }, 3000));

        // someone else calling (denied) changes nothing; nothing focused → generic
        GDBusConnection *rogue = connect(address);
        GVariant *r = g_dbus_connection_call_sync(rogue, "org.gnome.Shell", "/org/gnome/Shell/Introspect",
                                                  "org.gnome.Shell.Introspect", "GetRunningApplications", nullptr,
                                                  nullptr, G_DBUS_CALL_FLAGS_NONE, 500, nullptr, nullptr);
        (void)r;  // AccessDenied: the main loop is not running, so it times out or fails
        spin(200);
        CHECK(mon.resolve("gnome-shell") == "org.gnome.terminal");
        g_object_unref(rogue);
        g_shell.focus = "";
        emitFocusChanged();
        CHECK(waitFor([&] { return g_shell.answered >= 3; }, 3000));
        spin(200);
        CHECK(mon.resolve("gnome-shell") == "gnome-shell");
        CHECK(mon.monitoring());
        mon.stop();
        CHECK(!mon.running());
        CHECK(mon.resolve("gnome-shell") == "gnome-shell");
    }

    // unsafe mode: the direct call at start works, no focus change needed
    g_shell.unsafeMode = true;
    g_shell.focus = "org.gnome.gedit.desktop";
    {
        GnomeAppMonitor mon;
        CHECK(mon.start(address));
        CHECK(waitFor([&] { return mon.resolve("gnome-shell") == "org.gnome.gedit"; }, 5000));
    }

    std::printf("gnome monitor tests: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
