// test_fcitx5 — headless smoke test of the real addon inside a real fcitx5 Instance
// (fcitx5's testfrontend: no X/Wayland needed). Loads viettelex.so from the build tree,
// types through the Fcitx5 key path and asserts the committed strings.

#include "testfrontend_public.h"

#include <fcitx-utils/eventdispatcher.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/log.h>
#include <fcitx-utils/testing.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputmethodgroup.h>
#include <fcitx/inputmethodmanager.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>

using namespace fcitx;

namespace {

std::string g_cfgDir;
int g_checks = 0;

#define EXPECT(cond)                                                                    \
    do {                                                                                \
        ++g_checks;                                                                     \
        if (!(cond)) {                                                                  \
            std::fprintf(stderr, "%s:%d: EXPECT(%s) failed\n", __FILE__, __LINE__, #cond); \
            std::exit(1);                                                               \
        }                                                                               \
    } while (0)

void type(AddonInstance *tf, ICUUID uuid, const std::string &keys) {
    for (char c : keys) {
        std::string name = c == ' ' ? "space" : std::string(1, c);
        tf->call<ITestFrontend::keyEvent>(uuid, Key(name), false);
        tf->call<ITestFrontend::keyEvent>(uuid, Key(name), true);
    }
}

std::string preeditOf(InputContext *ic) { return ic->inputPanel().clientPreedit().toString(); }

void phase2(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid);

void scheduleEvent(EventDispatcher *dispatcher, Instance *instance) {
    dispatcher->schedule([dispatcher, instance]() {
        auto *addon = instance->addonManager().addon("viettelex", true);
        EXPECT(addon);
        EXPECT(instance->inputMethodManager().entry("viettelex"));
        auto group = instance->inputMethodManager().currentGroup();
        group.inputMethodList().clear();
        group.inputMethodList().push_back(InputMethodGroupItem("keyboard-us"));
        group.inputMethodList().push_back(InputMethodGroupItem("viettelex"));
        group.setDefaultInputMethod("viettelex");
        instance->inputMethodManager().setGroup(group);

        auto *tf = instance->addonManager().addon("testfrontend");
        auto uuid = tf->call<ITestFrontend::createInputContext>("gedit");
        auto *ic = instance->inputContextManager().findByUUID(uuid);
        EXPECT(ic);
        ic->setCapabilityFlags(CapabilityFlags{CapabilityFlag::Preedit});
        ic->focusIn();
        // Fcitx5's trigger key activates the IM (keyboard-us → viettelex) …
        tf->call<ITestFrontend::keyEvent>(uuid, Key("Control+space"), false);
        EXPECT(instance->inputMethod(ic) == "viettelex");

        // 1. preedit composition — no underline by default (preedit_underline = false) —
        //    committed at the boundary
        type(tf, uuid, "vieej");
        EXPECT(preeditOf(ic) == "việ");
        EXPECT(ic->inputPanel().clientPreedit().size() == 1);
        EXPECT(!ic->inputPanel().clientPreedit().formatAt(0).test(TextFormatFlag::Underline));
        tf->call<ITestFrontend::pushCommitExpectation>("việt");
        type(tf, uuid, "t ");
        EXPECT(preeditOf(ic).empty());

        // 2. auto-restore of a non-Vietnamese word
        tf->call<ITestFrontend::pushCommitExpectation>("google");
        type(tf, uuid, "google ");

        // 3. … and once active, Ctrl+Space is VietTelex's Việt/Anh toggle: keys pass through
        tf->call<ITestFrontend::keyEvent>(uuid, Key("Control+space"), false);
        EXPECT(instance->inputMethod(ic) == "viettelex");
        type(tf, uuid, "vieejt ");
        EXPECT(preeditOf(ic).empty());
        tf->call<ITestFrontend::keyEvent>(uuid, Key("Control+space"), false);

        // 4. password field: literal
        ic->setCapabilityFlags(CapabilityFlags{CapabilityFlag::Preedit, CapabilityFlag::Password});
        type(tf, uuid, "vieejt");
        EXPECT(preeditOf(ic).empty());
        ic->setCapabilityFlags(CapabilityFlags{CapabilityFlag::Preedit});

        // 5. focus out commits the pending word (not swallowed)
        type(tf, uuid, "dduwowcj");
        EXPECT(preeditOf(ic) == "được");
        tf->call<ITestFrontend::pushCommitExpectation>("được");
        ic->focusOut();
        ic->focusIn();

        // 6. live settings: write shortcuts.yml + VNI; inotify must apply it without restart
        {
            std::ofstream(g_cfgDir + "/viettelex/shortcuts.yml.tmp") << "ko: không\n";
            std::rename((g_cfgDir + "/viettelex/shortcuts.yml.tmp").c_str(),
                        (g_cfgDir + "/viettelex/shortcuts.yml").c_str());
            std::ofstream(g_cfgDir + "/viettelex/config.toml.tmp") << "[typing]\ninput_method = \"vni\"\n";
            std::rename((g_cfgDir + "/viettelex/config.toml.tmp").c_str(),
                        (g_cfgDir + "/viettelex/config.toml").c_str());
        }
        phase2(dispatcher, instance, uuid);
    });
}

std::unique_ptr<EventSourceTime> g_timer;

void phase2(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid) {
    g_timer = instance->eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, now(CLOCK_MONOTONIC) + 300000, 0,
        [dispatcher, instance, uuid](EventSourceTime *, uint64_t) {
            auto *tf = instance->addonManager().addon("testfrontend");
            auto *ic = instance->inputContextManager().findByUUID(uuid);
            tf->call<ITestFrontend::pushCommitExpectation>("không");
            type(tf, uuid, "ko ");
            type(tf, uuid, "vie65t");
            EXPECT(preeditOf(ic) == "việt");      // VNI now active
            tf->call<ITestFrontend::pushCommitExpectation>("việt");
            type(tf, uuid, " ");

            // Vi/En is remembered per program: a second app starts Vietnamese, and after
            // switching "kitty" to English it stays English on the next focus.
            auto uuid2 = tf->call<ITestFrontend::createInputContext>("kitty");
            auto *ic2 = instance->inputContextManager().findByUUID(uuid2);
            ic2->setCapabilityFlags(CapabilityFlags{CapabilityFlag::Preedit});
            ic2->focusIn();
            tf->call<ITestFrontend::keyEvent>(uuid2, Key("Control+space"), false);  // activate IM
            EXPECT(instance->inputMethod(ic2) == "viettelex");
            tf->call<ITestFrontend::keyEvent>(uuid2, Key("Control+space"), false);  // → English
            EXPECT(instance->inputMethod(ic2) == "viettelex");  // … stayed in VietTelex
            ic2->focusOut();
            ic->focusIn();
            type(tf, uuid, "a1");
            EXPECT(preeditOf(ic) == "á");          // gedit still Vietnamese
            tf->call<ITestFrontend::pushCommitExpectation>("á");
            ic->focusOut();
            ic2->focusIn();
            type(tf, uuid2, "a1");
            EXPECT(preeditOf(ic2).empty());       // kitty remembered English
            std::ifstream st(g_cfgDir + "/../state/viettelex/app-state");
            std::string all((std::istreambuf_iterator<char>(st)), std::istreambuf_iterator<char>());
            EXPECT(all.find("kitty\ten") != std::string::npos);

            std::printf("fcitx5 smoke: %d checks passed\n", g_checks);
            instance->deactivate();
            dispatcher->schedule([dispatcher, instance]() {
                dispatcher->detach();
                instance->exit();
            });
            return true;
        });
}

}  // namespace

int main() {
    char tmpl[] = "/tmp/vt-fcitx5-XXXXXX";
    std::string root = mkdtemp(tmpl);
    g_cfgDir = root + "/config";
    setenv("XDG_CONFIG_HOME", g_cfgDir.c_str(), 1);
    setenv("XDG_STATE_HOME", (root + "/state").c_str(), 1);
    setupTestingEnvironment(VT_FCITX5_BUILD_DIR, {"."}, {VT_FCITX5_TEST_DATA});
    char arg0[] = "test_fcitx5";
    char arg1[] = "--disable=all";
    char arg2[] = "--enable=testim,testfrontend,viettelex,testui";
    char *argv[] = {arg0, arg1, arg2};
    Instance instance(FCITX_ARRAY_SIZE(argv), argv);
    instance.addonManager().registerDefaultLoader(nullptr);
    EventDispatcher dispatcher;
    dispatcher.attach(&instance.eventLoop());
    scheduleEvent(&dispatcher, &instance);
    instance.exec();
    if (std::system(("rm -rf '" + root + "'").c_str()) != 0) return 1;
    return 0;
}
