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
#include <fcitx/action.h>
#include <fcitx/userinterfacemanager.h>

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
void phase3(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid);
void phase4(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid);
void phase5(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid);
void finish(EventDispatcher *dispatcher, Instance *instance);

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

        // 2b. dead keys (#161, U.S. International): no keyboard engine composes them while
        //     VietTelex is active — VietTelex does, exactly one output per sequence.
        auto press = [tf, uuid](const char *k) {
            tf->call<ITestFrontend::keyEvent>(uuid, Key(k), false);
            tf->call<ITestFrontend::keyEvent>(uuid, Key(k), true);
        };
        press("dead_acute");
        EXPECT(preeditOf(ic).empty());
        tf->call<ITestFrontend::pushCommitExpectation>("é");
        press("e");
        tf->call<ITestFrontend::pushCommitExpectation>("'");
        press("dead_acute");
        press("space");
        tf->call<ITestFrontend::pushCommitExpectation>("ü");
        press("dead_diaeresis");
        press("u");
        tf->call<ITestFrontend::pushCommitExpectation>("'");  // not composable: accent, then x
        press("dead_acute");
        tf->call<ITestFrontend::pushCommitExpectation>("x");
        type(tf, uuid, "x ");
        press("dead_acute");
        press("Escape");                                     // cancelled: nothing typed
        tf->call<ITestFrontend::pushCommitExpectation>("a");  // a plain a, not á
        type(tf, uuid, "a ");

        // 3. … and once active, Ctrl+Space is VietTelex's Việt/Anh toggle: keys pass through.
        //    The tray icon follows it (Vᴛ ↔ E, like the macOS menu bar).
        EXPECT(instance->inputMethodIcon(ic) == "viettelex");
        tf->call<ITestFrontend::keyEvent>(uuid, Key("Control+space"), false);
        EXPECT(instance->inputMethod(ic) == "viettelex");
        EXPECT(instance->inputMethodIcon(ic) == "viettelex-off");
        type(tf, uuid, "vieejt ");
        EXPECT(preeditOf(ic).empty());
        tf->call<ITestFrontend::keyEvent>(uuid, Key("Control+space"), false);
        EXPECT(instance->inputMethodIcon(ic) == "viettelex");
        // "Công cụ…" and its six tools are registered actions.
        EXPECT(instance->userInterfaceManager().lookupAction("viettelex-tools"));
        EXPECT(instance->userInterfaceManager().lookupAction("viettelex-tool-addTones"));
        EXPECT(instance->userInterfaceManager().lookupAction("viettelex-tool-stripDiacritics"));

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

        // 5b. … also when the client cannot draw preedit (no CapabilityFlag::Preedit): the
        //     word lives in the PANEL preedit, which Fcitx5's own focus-out commit
        //     (instance.cpp: clientPreedit().toStringForCommit()) never sees — VietTelex must
        //     commit it, exactly once. A leftover expectation would make the "google" commit
        //     below mismatch; a second commit would hit an empty expectation queue.
        ic->setCapabilityFlags(CapabilityFlags{});
        type(tf, uuid, "dduwowcj");
        EXPECT(preeditOf(ic).empty());
        EXPECT(ic->inputPanel().preedit().toString() == "được");
        tf->call<ITestFrontend::pushCommitExpectation>("được");
        ic->focusOut();
        ic->focusIn();
        ic->setCapabilityFlags(CapabilityFlags{CapabilityFlag::Preedit});
        tf->call<ITestFrontend::pushCommitExpectation>("google");
        type(tf, uuid, "google ");

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
            ic2->focusOut();
            phase3(dispatcher, instance, uuid);
            return true;
        });
}

void finish(EventDispatcher *dispatcher, Instance *instance) {
    std::printf("fcitx5 smoke: %d checks passed\n", g_checks);
    instance->deactivate();
    dispatcher->schedule([dispatcher, instance]() {
        dispatcher->detach();
        instance->exit();
    });
}

// Text tools end to end (needs the helper: ctest sets VIETTELEX_TEXT_TOOL): the selection
// comes from surrounding text, the result is committed over it.
std::unique_ptr<EventSourceTime> g_toolTimer;
std::unique_ptr<HandlerTableEntry<EventHandler>> g_commitWatch;
std::string g_committed;
int g_polls = 0;

void phase3(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid) {
    const char *helper = std::getenv("VIETTELEX_TEXT_TOOL");
    if (!helper || !*helper) {
        std::printf("fcitx5 smoke: text tools skipped (VIETTELEX_TEXT_TOOL unset)\n");
        return finish(dispatcher, instance);
    }
    auto *ic = instance->inputContextManager().findByUUID(uuid);
    ic->focusIn();
    ic->setCapabilityFlags(CapabilityFlags{CapabilityFlag::Preedit, CapabilityFlag::SurroundingText});
    ic->surroundingText().setText("xin: toi di hoc", 15, 5);  // "toi di hoc" selected
    ic->updateSurroundingText();
    g_commitWatch = instance->watchEvent(EventType::InputContextCommitString, EventWatcherPhase::PreInputMethod,
                                         [](Event &e) {
                                             g_committed = static_cast<CommitStringEvent &>(e).text();
                                         });
    auto *tf = instance->addonManager().addon("testfrontend");
    tf->call<ITestFrontend::pushCommitExpectation>("tôi đi học");
    auto *a = instance->userInterfaceManager().lookupAction("viettelex-tool-addTones");
    EXPECT(a);
    a->activate(ic);

    g_toolTimer = instance->eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, now(CLOCK_MONOTONIC) + 100000, 0,
        [dispatcher, instance, uuid](EventSourceTime *src, uint64_t) {
            if (g_committed.empty() && ++g_polls < 100) {  // ≤ 10 s
                src->setNextInterval(100000);
                src->setOneShot();
                return true;
            }
            EXPECT(g_committed == "tôi đi học");
            phase4(dispatcher, instance, uuid);
            return true;
        });
}

// Caret suggestion end to end (helper --serve): "12*3=" → aux text "= 36 …" in the input
// panel (drawn at the caret), Tab commits "36"; any other key hides it.
std::unique_ptr<EventSourceTime> g_hintTimer;

void phase4(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid) {
    auto *ic = instance->inputContextManager().findByUUID(uuid);
    auto *tf = instance->addonManager().addon("testfrontend");
    ic->setCapabilityFlags(CapabilityFlags{CapabilityFlag::Preedit});
    ic->reset();
    // Still VNI (phase 2): digits are composing keys, committed at the next boundary.
    tf->call<ITestFrontend::pushCommitExpectation>("12");
    tf->call<ITestFrontend::pushCommitExpectation>("3");
    for (const char *k : {"1", "2", "asterisk", "3", "equal"}) {
        tf->call<ITestFrontend::keyEvent>(uuid, Key(k), false);
        tf->call<ITestFrontend::keyEvent>(uuid, Key(k), true);
    }
    g_polls = 0;
    g_hintTimer = instance->eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, now(CLOCK_MONOTONIC) + 50000, 0,
        [dispatcher, instance, uuid](EventSourceTime *src, uint64_t) {
            auto *ic = instance->inputContextManager().findByUUID(uuid);
            auto *tf = instance->addonManager().addon("testfrontend");
            if (ic->inputPanel().auxDown().empty() && ++g_polls < 100) {  // ≤ 5 s
                src->setNextInterval(50000);
                src->setOneShot();
                return true;
            }
            EXPECT(ic->inputPanel().auxDown().toString() == "= 36   Tab / Enter");
            EXPECT(preeditOf(ic).empty());  // never in the app's text
            tf->call<ITestFrontend::pushCommitExpectation>("36");
            tf->call<ITestFrontend::keyEvent>(uuid, Key("Tab"), false);
            EXPECT(ic->inputPanel().auxDown().empty());
            phase5(dispatcher, instance, uuid);
            return true;
        });
}

// Word prediction end to end (word_prediction = true, live reload): "thành phố hồ␣" (two
// context words with a trigram row) → after the 300 ms pause the native candidate list shows
// ONE entry "Chí" (no number label, aux "Tab"); a click (CandidateWord::select) commits it + a
// space. Smart quotes: '"' → “.
std::unique_ptr<EventSourceTime> g_predTimer;

void phase5(EventDispatcher *dispatcher, Instance *instance, ICUUID uuid) {
    {
        std::ofstream(g_cfgDir + "/viettelex/config.toml.tmp")
            << "[general]\nword_prediction = true\nsmart_punctuation = true\n";
        std::rename((g_cfgDir + "/viettelex/config.toml.tmp").c_str(), (g_cfgDir + "/viettelex/config.toml").c_str());
    }
    g_polls = 0;
    g_predTimer = instance->eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, now(CLOCK_MONOTONIC) + 300000, 0,
        [dispatcher, instance, uuid](EventSourceTime *src, uint64_t) {
            auto *ic = instance->inputContextManager().findByUUID(uuid);
            auto *tf = instance->addonManager().addon("testfrontend");
            if (g_polls == 0) {  // settings reloaded (inotify): type, then poll for the list
                ++g_polls;
                for (const char *w : {"thành", "phố", "hồ"}) tf->call<ITestFrontend::pushCommitExpectation>(w);
                type(tf, uuid, " thanhf phoos hoof ");  // after the "36" of phase 4: words of their own
                EXPECT(!ic->inputPanel().candidateList());  // not before the pause
                src->setNextInterval(50000);
                src->setOneShot();
                return true;
            }
            auto list = ic->inputPanel().candidateList();
            if (!list && ++g_polls < 100) {  // ≤ 5 s
                src->setNextInterval(50000);
                src->setOneShot();
                return true;
            }
            EXPECT(list && list->size() == 1);  // one suggestion, no list
            EXPECT(list->candidate(0).text().toString() == "Chí");
            EXPECT(list->label(0).toString().empty());  // digits are never selection keys
            EXPECT(ic->inputPanel().auxDown().toString() == "Tab");
            tf->call<ITestFrontend::pushCommitExpectation>("Chí ");
            list->candidate(0).select(ic);
            EXPECT(!ic->inputPanel().candidateList());
            tf->call<ITestFrontend::pushCommitExpectation>("“");
            tf->call<ITestFrontend::keyEvent>(uuid, Key("quotedbl"), false);
            tf->call<ITestFrontend::keyEvent>(uuid, Key("quotedbl"), true);
            finish(dispatcher, instance);
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
    setenv("LC_CTYPE", "en_US.UTF-8", 1);  // dead keys: en_US Compose rules (or the built-in table)
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
