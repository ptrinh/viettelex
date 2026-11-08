// test_debug_log — VIETTELEX_DEBUG log formatting (debug_log.h): header lines, settings
// snapshot (counts only for user content), ×N collapse, settings line only on change.
// Pure: no frontend, no file. Builds on macOS too:
//   c++ -std=c++17 -Ilinux/common/include -Ilinux/engine-capi/include linux/common/tests/test_debug_log.cpp \
//       linux/common/src/debug_log.cpp linux/common/src/settings.cpp -o /tmp/t && /tmp/t

#include "viettelex/debug_log.h"
#include "viettelex/settings.h"

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

using namespace viettelex;
using namespace viettelex::debuglog;

static int g_fail = 0, g_pass = 0;
#define CHECK(x)                                                                    \
    do {                                                                            \
        if (x) ++g_pass;                                                            \
        else {                                                                      \
            ++g_fail;                                                               \
            std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__, __LINE__, #x); \
        }                                                                           \
    } while (0)

static bool contains(const std::string &s, const std::string &needle) { return s.find(needle) != std::string::npos; }

static void testSettingsLine() {
    Settings s;
    auto table = std::make_shared<ShortcutTable>();
    (*table)["vn"] = "Việt Nam bí mật";
    s.shortcuts = table;
    s.appModes["org.gnome.terminal"] = "direct";
    std::string l = settingsLine(s);
    CHECK(contains(l, "method=telex"));
    CHECK(contains(l, "spell=1"));
    CHECK(contains(l, "shortcuts=on:1"));
    CHECK(contains(l, "appModes=1"));
    // Shortcut content never leaks.
    CHECK(!contains(l, "vn="));
    CHECK(!contains(l, "Việt Nam"));
    CHECK(!contains(l, "terminal"));
    s.vni = true;
    CHECK(contains(settingsLine(s), "method=vni"));
    s.vni = false;
    s.simpleTelex = true;
    CHECK(contains(settingsLine(s), "method=telex-simple"));
}

static void testHeader() {
    Env env;
    env.os = "Ubuntu 26.04 LTS";
    env.arch = "x86_64";
    env.kernel = "6.14.0";
    env.desktop = "GNOME";
    env.sessionType = "wayland";
    env.waylandDisplay = true;
    env.locale = "vi_VN.UTF-8";
    env.install = "deb";
    Frontend fe{"fcitx5", "5.1.19", "us [keyboard-us,viettelex]", 49};
    auto h = headerLines("1.0.23", fe, env, Settings{});
    CHECK(h.size() == 5);
    CHECK(h[0] == "=== VietTelex Linux 1.0.23 debug log — fcitx5 5.1.19");
    CHECK(h[1] == "os: Ubuntu 26.04 LTS | x86_64 | kernel 6.14.0 | install deb");
    CHECK(h[2] == "desktop: GNOME | session wayland (wayland=1 x11=0) | gnome-shell 49");
    CHECK(h[3] == "locale: vi_VN.UTF-8 | layouts: us [keyboard-us,viettelex]");
    CHECK(h[4].rfind("settings: method=telex", 0) == 0);
    // Unknown values print "?", never an empty field.
    auto h2 = headerLines("1.0.23", Frontend{"ibus", "", "", 0}, Env{}, Settings{});
    CHECK(h2[0] == "=== VietTelex Linux 1.0.23 debug log — ibus ?");
    CHECK(h2[2] == "desktop: ? | session ? (wayland=0 x11=0)");
}

static void testCollapser() {
    Collapser c;
    CHECK(c.push("a") == std::vector<std::string>{"a"});
    CHECK(c.push("a").empty());
    CHECK(c.push("a").empty());
    CHECK((c.push("b") == std::vector<std::string>{"  ×3", "b"}));
    CHECK(c.push("c") == std::vector<std::string>{"c"});
    CHECK(c.flush().empty());
    CHECK(c.push("c").empty());
    CHECK(c.flush() == std::vector<std::string>{"  ×2"});
    // After a flush the same line prints again (a new run).
    CHECK(c.push("c") == std::vector<std::string>{"c"});
}

static void testLogger() {
    std::vector<std::string> out;
    Logger log([&](const std::string &l) { out.push_back(l); });
    Settings s;
    Frontend fe{"ibus", "1.5.30", "", 0};
    log.line("field a");
    log.context("1.0.23", fe, s);
    size_t afterHeader = out.size();
    CHECK(afterHeader == 6);
    CHECK(out[1].rfind("vt === VietTelex Linux 1.0.23", 0) == 0);
    log.context("1.0.23", fe, s);  // unchanged settings: nothing
    CHECK(out.size() == afterHeader);
    s.vni = true;
    log.context("1.0.23", fe, s);  // changed: one settings line
    CHECK(out.size() == afterHeader + 1);
    CHECK(contains(out.back(), "method=vni"));
    log.line("key sym=97 mode=0 dist=0 before=3");
    log.line("key sym=97 mode=0 dist=0 before=3");
    log.line("key sym=98 mode=0 dist=0 before=4");
    CHECK(out[out.size() - 2] == "vt   ×2");
    CHECK(out.back() == "vt key sym=98 mode=0 dist=0 before=4");
}

int main() {
    testSettingsLine();
    testHeader();
    testCollapser();
    testLogger();
    std::printf("test_debug_log: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
