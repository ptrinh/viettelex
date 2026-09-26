#include "breaker.h"
#include "test.h"
#include "update_check.h"

using namespace vtx;

TEST(version_compare) {
    CHECK(compareVersions("0.10.0", "0.9.3") > 0);
    CHECK(compareVersions("1.0", "1.0.0") == 0);
    CHECK(compareVersions("1.0.1", "1.0") > 0);
    CHECK(compareVersions("0.1.0", "0.1.0.1") < 0);
    CHECK(isNewer("0.2.0", "0.1.9"));
    CHECK(!isNewer("0.1.0", "0.1.0"));
}

TEST(stable_json_windows_object) {
    const char* j = R"({
      "version": "1.7.12",
      "url": "https://github.com/ptrinh/viettelex/releases/tag/v1.7.12",
      "build": 108,
      "windows": { "version": "0.2.0",
                   "x64": "https://github.com/ptrinh/viettelex/releases/download/win-v0.2.0/VietTelex-0.2.0-x64.msi",
                   "arm64": "https://github.com/ptrinh/viettelex/releases/download/win-v0.2.0/VietTelex-0.2.0-arm64.msi",
                   "notes": "https://github.com/ptrinh/viettelex/releases/tag/win-v0.2.0" }
    })";
    WindowsRelease r;
    CHECK(parseStableJson(j, r));
    CHECK_EQ(r.version, std::string("0.2.0"));
    CHECK(isTrustedDownloadUrl(r.x64));
    CHECK(isTrustedDownloadUrl(r.arm64));
}

TEST(stable_json_without_windows_is_no_update) {
    WindowsRelease r;
    CHECK(!parseStableJson(R"({"version":"1.7.12","url":"x","build":108})", r));
    CHECK(!parseStableJson(R"({"windows": {"x64":"a"}})", r));
    CHECK(!parseStableJson("garbage", r));
    // "windows" appearing inside a string value is not the key.
    CHECK(!parseStableJson(R"({"url":"\"windows\" soon"})", r));
}

TEST(download_url_allowlist) {
    CHECK(!isTrustedDownloadUrl("http://github.com/ptrinh/viettelex/releases/download/a.msi"));
    CHECK(!isTrustedDownloadUrl("https://evil.example/VietTelex.msi"));
    CHECK(!isTrustedDownloadUrl("https://github.com/ptrinh/viettelex/releases/download/../../x"));
    CHECK(!isTrustedDownloadUrl("https://viettelex.com.evil.example/a.msi"));
}

TEST(rate_breaker_trips_and_recovers) {
    RateBreaker b(10, 100, 1000);
    CHECK(b.allow(0, 5));
    CHECK(b.allow(10, 5));
    CHECK(!b.allow(20, 1));    // 11 > 10 inside the window
    CHECK(b.tripped(500));
    CHECK(!b.allow(900, 1));
    CHECK(b.allow(1100, 1));   // cooldown over
    CHECK_EQ(b.trips(), 1u);
    CHECK(b.allow(1300, 10));  // new window
}

#include "uninstall.h"

TEST(uninstall_guid_validation) {
    CHECK(isGuidString("{4822CAE4-A773-47FC-A9E1-30E16D0A6F4C}"));
    CHECK(isGuidString("{4822cae4-a773-47fc-a9e1-30e16d0a6f4c}"));
    CHECK(!isGuidString("4822CAE4-A773-47FC-A9E1-30E16D0A6F4C"));
    CHECK(!isGuidString("{4822CAE4-A773-47FC-A9E1-30E16D0A6F4C} & calc"));
    CHECK(!isGuidString("{4822CAE4XA773-47FC-A9E1-30E16D0A6F4C}"));
    CHECK(!isGuidString(""));
}

TEST(uninstall_product_lookup) {
    const std::string x64 = "{68939A18-0B26-465E-BE51-F6F903FA4999}";
    const std::string arm = "{39889E85-E65B-46F3-B083-185FE3FDC31D}";
    std::vector<std::string> asked;
    RelatedProducts fake = [&](const std::string& up) {
        asked.push_back(up);
        if (up == kUpgradeCodeX64) return std::vector<std::string>{"garbage", x64};
        if (up == kUpgradeCodeArm64) return std::vector<std::string>{arm};
        return std::vector<std::string>{};
    };
    CHECK_EQ(findInstalledProductCode(fake, false), x64);  // invalid entries skipped
    CHECK_EQ(asked.front(), std::string(kUpgradeCodeX64));
    asked.clear();
    CHECK_EQ(findInstalledProductCode(fake, true), arm);
    CHECK_EQ(asked.front(), std::string(kUpgradeCodeArm64));
    RelatedProducts none = [](const std::string&) { return std::vector<std::string>{}; };
    CHECK(findInstalledProductCode(none, false).empty());  // dev build -> Settings fallback
}

TEST(uninstall_command_line) {
    CHECK_EQ(uninstallParameters("{68939A18-0B26-465E-BE51-F6F903FA4999}"),
             std::string("/x {68939A18-0B26-465E-BE51-F6F903FA4999}"));
    CHECK(uninstallParameters("{bad}").empty());
}

TEST(version_display_strips_build_field) {
    CHECK_EQ(versionForDisplay("1.0.4.0"), std::string("1.0.4"));
    CHECK_EQ(versionForDisplay("1.0.0.0"), std::string("1.0.0"));
    CHECK_EQ(versionForDisplay("1.2.3.4"), std::string("1.2.3.4"));
    CHECK_EQ(versionForDisplay("1.0.4"), std::string("1.0.4"));
    CHECK_EQ(versionForDisplay("2.0"), std::string("2.0"));
}

#include "setup_helper_logic.h"

TEST(helper_only_terminates_the_app_image) {
    CHECK(isAppImage(L"C:\\Program Files\\VietTelex\\VietTelex.exe"));
    CHECK(isAppImage(L"viettelex.EXE"));
    CHECK(!isAppImage(L"C:\\Windows\\explorer.exe"));
    CHECK(!isAppImage(L"VietTelexSetupHelper.exe"));
    CHECK(!isAppImage(L"VietTelex.exe.bak"));
}

TEST(helper_tip_dll_names) {
    for (const wchar_t* n : {L"VietTelexTIP.dll", L"VietTelexTIP_arm64.dll", L"VietTelexTIP_x64.dll",
                             L"VietTelexTIP_1_0_6.dll", L"viettelextip_arm64_1_0_6.DLL", L"VietTelexTIP_x64_2_10_0.dll",
                             L"C:\\Program Files\\VietTelex\\VietTelexTIP_1_0_6.dll"})
        CHECK(isTipDllName(n));
    for (const wchar_t* n : {L"VietTelex.exe", L"VietTelexTIP.dll.123.old", L"VietTelexTIPx.dll", L"VietTelexTIP_.dll",
                             L"VietTelexTIP_1.0.6.dll", L"VietTelexTIP_arm.dll", L"other.dll"})
        CHECK(!isTipDllName(n));
    CHECK(isReleasedLeftover(L"VietTelexTIP.dll.42.old"));
    CHECK(!isReleasedLeftover(L"notes.old"));
    CHECK(releaseName(L"VietTelexTIP_1_0_6.dll", 42) == std::wstring(L"VietTelexTIP_1_0_6.dll.42.old"));
    CHECK_EQ(versionSuffix("1.0.6"), std::string("_1_0_6"));
}

TEST(helper_args) {
    HelperArgs a = parseHelperArgs({L"--quit-app"});
    CHECK(a.quitApp && !a.releaseTip);
    a = parseHelperArgs({L"--release-tip", L"C:\\Program Files\\VietTelex\\", L"C:\\Program Files (x86)\\VietTelex\\\""});
    CHECK(a.releaseTip && !a.quitApp);
    CHECK_EQ(a.dirs.size(), size_t(2));
    CHECK(a.dirs[0] == std::wstring(L"C:\\Program Files\\VietTelex"));
    CHECK(a.dirs[1] == std::wstring(L"C:\\Program Files (x86)\\VietTelex"));
    CHECK(parseHelperArgs({L"--bogus"}).dirs.empty());
    // exactly what the MSI passes: "[INSTALLFOLDER]." "[INSTALLFOLDER86]."
    a = parseHelperArgs({L"--release-tip", L"C:\\Program Files\\VietTelex\\.", L"C:\\Program Files (x86)\\VietTelex\\."});
    CHECK_EQ(a.dirs.size(), size_t(2));
    CHECK(a.dirs[0] == std::wstring(L"C:\\Program Files\\VietTelex"));
    CHECK(a.dirs[1] == std::wstring(L"C:\\Program Files (x86)\\VietTelex"));
}

TEST(single_instance_handoff_by_version) {
    CHECK(mainWindowTitle("1.0.6") == std::wstring(L"VietTelex 1.0.6"));
    // pre-1.0.6 instances have the bare title -> always replaced by the new exe
    CHECK(decideHandoff(L"VietTelex", "1.0.6") == Handoff::ReplaceRunning);
    CHECK(decideHandoff(L"VietTelex 1.0.5.0", "1.0.6") == Handoff::ReplaceRunning);
    CHECK(decideHandoff(L"VietTelex 1.0.6", "1.0.6") == Handoff::PassToRunning);   // same: yield
    CHECK(decideHandoff(L"VietTelex 1.0.7", "1.0.6") == Handoff::PassToRunning);   // newer runs
    CHECK(decideHandoff(L"VietTelex 1.0.10", "1.0.9") == Handoff::PassToRunning);  // numeric compare
    CHECK(decideHandoff(L"VietTelex 1.0.9", "1.0.10") == Handoff::ReplaceRunning);
    CHECK(decideHandoff(L"VietTelex x", "1.0.6") == Handoff::ReplaceRunning);      // garbage
}

TEST(update_handoff_sequence) {
    CHECK(watcherArgs(4242) == std::wstring(L"--wait-install 4242"));
    unsigned long pid = 0;
    CHECK(parseWaitInstallArg({L"--wait-install", L"4242"}, pid) && pid == 4242);
    CHECK(!parseWaitInstallArg({L"--wait-install", L"0"}, pid));
    CHECK(!parseWaitInstallArg({L"--wait-install", L"12a"}, pid));
    CHECK(!parseWaitInstallArg({L"--wait-install"}, pid));
    CHECK(!parseWaitInstallArg({L"--wait-install", L"99999999999"}, pid));
    // after msiexec exits: success codes -> the MSI's LaunchApp already started the new app
    for (unsigned long ok : {0ul, 3010ul, 1641ul}) {
        CHECK(msiexecSucceeded(ok));
        CHECK(afterInstallAction(true, ok, false, true) == AfterInstall::Nothing);
    }
    // cancelled (1602) / failed (1603) / other: bring the installed version back
    for (unsigned long bad : {1602ul, 1603ul, 1618ul, 1ul}) {
        CHECK(!msiexecSucceeded(bad));
        CHECK(afterInstallAction(true, bad, false, true) == AfterInstall::LaunchInstalled);
        CHECK(afterInstallAction(true, bad, true, true) == AfterInstall::Nothing);   // already running
        CHECK(afterInstallAction(true, bad, false, false) == AfterInstall::Nothing); // nothing installed
    }
    CHECK(afterInstallAction(false, 0, false, true) == AfterInstall::LaunchInstalled);  // exit unknown
    CHECK(afterInstallAction(false, 0, true, true) == AfterInstall::Nothing);
    CHECK(updateLogName("1.1.0") == std::wstring(L"update-1.1.0.log"));
}

TEST(helper_release_never_touches_newer_dlls) {
    CHECK_EQ(tipDllVersion(L"VietTelexTIP.dll"), std::string("0"));
    CHECK_EQ(tipDllVersion(L"VietTelexTIP_arm64.dll"), std::string("0"));
    CHECK_EQ(tipDllVersion(L"VietTelexTIP_1_0_8.dll"), std::string("1.0.8"));
    CHECK_EQ(tipDllVersion(L"viettelextip_x64_1_0_10.DLL"), std::string("1.0.10"));
    CHECK(tipDllVersion(L"VietTelex.exe").empty());
    // new 1.0.8 install: moves its predecessors (and a same-version copy on repair)
    CHECK(shouldRelease(L"VietTelexTIP_1_0_7.dll", "1.0.8"));
    CHECK(shouldRelease(L"VietTelexTIP.dll", "1.0.8"));
    CHECK(shouldRelease(L"VietTelexTIP_1_0_8.dll", "1.0.8"));
    // old 1.0.7 package being removed by 1.0.8 (late RemoveExistingProducts)
    CHECK(!shouldRelease(L"VietTelexTIP_1_0_8.dll", "1.0.7"));
    CHECK(!shouldRelease(L"VietTelexTIP_arm64_1_0_10.dll", "1.0.9"));
    CHECK(!shouldRelease(L"VietTelex.exe", "1.0.8"));
    HelperArgs a = parseHelperArgs({L"--release-tip", L"C:\\x\\.", L"--max-version", L"1.0.7"});
    CHECK_EQ(a.maxVersion, std::string("1.0.7"));
    CHECK_EQ(a.dirs.size(), size_t(1));
}

TEST(hook_elevated_foreground_warning) {
    CHECK(hookNeedsElevationWarning(true, true, 0x3000, 0x2000, false));   // admin app
    CHECK(hookNeedsElevationWarning(true, false, 0, 0x2000, false));       // token unreadable
    CHECK(!hookNeedsElevationWarning(true, true, 0x2000, 0x2000, false));  // same level
    CHECK(!hookNeedsElevationWarning(false, true, 0x3000, 0x2000, false)); // not a hook app
    CHECK(!hookNeedsElevationWarning(true, true, 0x3000, 0x2000, true));   // warned already
}

#include "hook_watchdog.h"

TEST(hook_watchdog_reinstalls_silently_removed_hook) {
    HookWatchdog w(1000);
    CHECK(!w.rawKey(5000));            // not active: never
    w.setActive(true, 10000);
    w.lowLevelKey(10100);
    CHECK(!w.rawKey(10100));           // both saw the key
    CHECK(!w.rawKey(10900));           // within threshold
    // Windows removed the hook (LowLevelHooksTimeout): raw input keeps seeing keys,
    // the LL hook does not.
    CHECK(w.rawKey(11200));
    w.hookInstalled(11200);            // reinstalled
    CHECK(!w.rawKey(11300));
    w.lowLevelKey(11300);
    CHECK(!w.rawKey(12000));
    w.setActive(false, 12000);
    CHECK(!w.rawKey(99999));
}

#include "direct_policy.h"

TEST(direct_integrity_decision_table) {
    CHECK(directUsable(true, 0x2000, 0x2000));    // medium -> medium
    CHECK(directUsable(true, 0x1000, 0x2000));    // low (AppContainer-ish) target
    CHECK(!directUsable(true, 0x3000, 0x2000));   // admin app: UIPI blocks SendInput
    CHECK(!directUsable(true, 0x4000, 0x2000));   // system
    CHECK(!directUsable(false, 0, 0x2000));       // token unreadable = treat as higher
    CHECK(directUsable(true, 0x3000, 0x3000));    // VietTelex itself elevated
}

TEST(direct_sendinput_short_count) {
    CHECK(classifySend(8, 8) == SendOutcome::Ok);
    CHECK(classifySend(0, 8) == SendOutcome::NothingSent);
    CHECK(classifySend(3, 8) == SendOutcome::Partial);
    CHECK(injectionAllowed(42, 42, false));
    CHECK(!injectionAllowed(43, 42, false));      // focus moved between key and injection
    CHECK(!injectionAllowed(42, 42, true));       // secure desktop
    CHECK(!injectionAllowed(0, 42, false));
}

TEST(direct_echo_verification_console_and_uia) {
    // fake console buffer row up to the cursor
    const std::u16string row = u"C:\\Users\\me> echo thử gõ";
    CHECK(echoMatches(row, u"gõ"));
    CHECK(!echoMatches(row, u"go"));              // our backspaces/Unicode did not land
    CHECK(!echoMatches(u"gõ", u"xgõ"));
    // UIA text range before the caret (Windows Terminal TextPattern / Qt ValuePattern)
    CHECK(echoMatches(u"tiếng việt", u"việt"));
    CHECK(!echoMatches(u"tiếng vieetj", u"việt"));
    CHECK(echoInValue(u"xin chào các bạn", u"chào"));   // Qt/Java ValuePattern
    CHECK(!echoInValue(u"xin chaof", u"chào"));
    CHECK(checkStillRelevant(7, 7));
    CHECK(!checkStillRelevant(7, 9));             // user typed on: not evidence
}

TEST(direct_echo_mismatch_counter_policy) {
    EchoPolicy p;
    CHECK(!p.record(1, 0, Echo::Mismatch));
    CHECK(!p.fellBack(1, 0));
    CHECK(p.record(1, 0, Echo::Mismatch));        // 2nd mismatch: fall back
    CHECK(p.fellBack(1, 0));
    CHECK(!p.record(1, 0, Echo::Mismatch));       // already fallen: reported once
    // a match in between resets the count
    CHECK(!p.record(2, 0, Echo::Mismatch));
    CHECK(!p.record(2, 0, Echo::Match));
    CHECK(!p.record(2, 0, Echo::Mismatch));
    CHECK(!p.fellBack(2, 0));
    // unverifiable hosts keep Direct
    for (int i = 0; i < 5; ++i) CHECK(!p.record(3, 0, Echo::Unverifiable));
    CHECK(!p.fellBack(3, 0));
    // per control within one window
    CHECK(!p.record(4, 1, Echo::Mismatch));
    CHECK(!p.record(4, 2, Echo::Mismatch));
    CHECK(!p.fellBack(4, 1) && !p.fellBack(4, 2));
    p.focusChanged();
    CHECK(!p.fellBack(1, 0));
}

// ---------------------------------------------------------------- 1.1.5
#include "app_language.h"
#include "app_policy.h"
#include "debug_log.h"
#include "input_switch.h"
#include "keymap.h"
#include "session.h"
#include "settings.h"

TEST(console_window_identity_is_conhost) {
    // GetWindowThreadProcessId on a console window names its CLIENT; the TIP runs in
    // conhost.exe and the built-in Direct rule is keyed "conhost.exe".
    CHECK_EQ(hostIdentity("ConsoleWindowClass", "cmd.exe"), std::string("conhost.exe"));
    CHECK_EQ(hostIdentity("ConsoleWindowClass", "powershell.exe"), std::string("conhost.exe"));
    CHECK_EQ(hostIdentity("Notepad", "notepad.exe"), std::string("notepad.exe"));
    CHECK_EQ(hostIdentity("CASCADIA_HOSTING_WINDOW_CLASS", "windowsterminal.exe"), std::string("windowsterminal.exe"));
    CHECK(resolveAppMode("conhost.exe", {}) == AppMode::Direct);
    CHECK(resolveAppMode("cmd.exe", {}) != AppMode::Direct);  // the 1.1.4 lookup: no rule
}

TEST(foreground_language_decision) {
    CHECK(foregroundLanguage(1, true, false, false));   // TIP says Vietnamese: authoritative
    CHECK(!foregroundLanguage(2, false, true, true));   // TIP says English
    CHECK(!foregroundLanguage(0, true, true, true));    // console without the TIP's word: no
    CHECK(foregroundLanguage(0, false, true, true));    // normal window: HKL + memory
    CHECK(!foregroundLanguage(0, false, true, false));
    CHECK(!foregroundLanguage(0, false, false, true));
}

TEST(hook_arming_waits_for_boundary_when_engaged_mid_focus) {
    HookArming a;
    a.engaged(true);
    CHECK(a.key(false));  // fresh window: at once
    a.engaged(false);     // handed over mid-word
    CHECK(!a.key(false));
    CHECK(!a.key(false));
    CHECK(!a.key(true));  // the boundary itself still belongs to the TIP's word
    CHECK(a.key(false));
    a.disengaged();
    CHECK(!a.key(false));
    a.click();
    CHECK(a.key(false));
    CHECK(tipStaysOut(true, true, false, true));
    CHECK(!tipStaysOut(true, false, false, true));  // no ack: compose
    CHECK(!tipStaysOut(true, true, true, true));
    CHECK(!tipStaysOut(true, true, false, false));
    CHECK(!tipStaysOut(false, true, false, true));
}

// ---- fake conhost: the TIP (loaded in conhost via ConsoleTSF) AND the hook, one screen.
namespace {
struct FakeConsole {
    std::u16string screen;      // cmd's line buffer as displayed
    std::u16string composition; // the TIP's composition (conversion area)
};

// The TIP's view of a console: nothing readable, composition committed into the line.
class ConsoleTipSink final : public TextSink {
public:
    explicit ConsoleTipSink(FakeConsole& c) : c_(c) {}
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string&, const std::u16string&) override { return false; }
    bool compositionActive() override { return active_; }
    bool setComposition(const std::u16string& t, int) override {
        active_ = true;
        c_.composition = t;
        return true;
    }
    void endComposition(const std::u16string& f) override {
        if (!active_) return;
        c_.screen += f;
        c_.composition.clear();
        active_ = false;
    }
    void endCompositionAsIs() override { endComposition(c_.composition); }
    bool canReadContext() override { return false; }

private:
    FakeConsole& c_;
    bool active_ = false;
};

// The hook's SendInput batch, applied as conhost would: VK_BACK (with scan code) erases,
// KEYEVENTF_UNICODE inserts. Injected keys never reach the TIP (GetMessageExtraInfo).
class InjectSink final : public TextSink {
public:
    explicit InjectSink(FakeConsole& c) : c_(c) {}
    bool blind() override { return true; }
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) override {
        for (size_t i = 0; i < expect.size() && !c_.screen.empty(); ++i) c_.screen.pop_back();
        c_.screen += insert;
        sent = true;
        return true;
    }
    bool compositionActive() override { return false; }
    bool setComposition(const std::u16string&, int) override { return false; }
    void endComposition(const std::u16string&) override {}
    void endCompositionAsIs() override {}
    bool sent = false;

private:
    FakeConsole& c_;
};

uint32_t vkOf(char c) { return c == ' ' ? 0x20 : static_cast<uint32_t>(c - 'a' + 'A'); }

struct ConsoleRig {
    enum class Build { V114, V115 };
    Build build;
    bool handoverMidFocus = false;  // the hook engages after typing started
    bool arming = true;             // 1.1.5 HookArming on/off (to show the race)
    int engageAfterKeys = 0;

    FakeConsole con;
    TypingSession tip, hook;
    Settings st;
    ConsoleRig(Build b) : build(b) {
        SessionOptions o;
        o.engineFlags = st.engineFlags();
        o.autoRestore = st.autoRestore;
        tip.configure(o);
        tip.setOutputMode(OutputMode::Composition);
        tip.setCompositionOnlyContext(true);
        o.reEditWord = false;
        hook.configure(o);
        hook.setOutputMode(OutputMode::InPlace);
    }

    std::u16string type(const std::string& keys) {
        // Hook side (VietTelex.exe): which app is this window?
        const std::string ownerExe = "cmd.exe";  // what GetWindowThreadProcessId reports
        const std::string id = build == Build::V114 ? ownerExe : hostIdentity("ConsoleWindowClass", ownerExe);
        const bool rule = resolveAppMode(id, {}) == AppMode::Direct;
        // 1.1.4: the TIP stays out on its own rule whenever the app runs. 1.1.5: only on ack.
        HookArming arm;
        bool engaged = false, acked = false;
        auto engage = [&](bool fresh) {
            engaged = rule;
            acked = engaged;
            arm.engaged(fresh || !arming);
        };
        if (!handoverMidFocus) engage(true);
        ConsoleTipSink tipSink(con);
        int n = 0;
        for (char c : keys) {
            if (handoverMidFocus && n++ == engageAfterKeys) engage(false);
            KeyInput k = classifyKey(vkOf(c), Modifiers{});
            const bool boundary = k.kind == KeyKind::Char && k.ch == U' ';
            // 1) WH_KEYBOARD_LL in VietTelex.exe
            if (engaged && arm.key(boundary || !arming) && hook.wantsKey(k)) {
                InjectSink inj(con);
                const bool eaten = hook.handleKey(k, inj);
                if (inj.sent) {
                    if (!eaten) con.screen += static_cast<char16_t>(k.ch);  // replayed after the batch
                    continue;
                }
                if (eaten) continue;
            }
            // 2) the TIP in conhost
            const bool tipOut = build == Build::V114 ? true /* rule Direct + app running */
                                                     : (!tip.wordActive() && tipStaysOut(true, acked, false, true));
            if (!tipOut && tip.wantsKey(k) && tip.handleKey(k, tipSink)) continue;
            // 3) conhost / cmd
            con.screen += static_cast<char16_t>(k.ch);
        }
        tip.flush(tipSink);
        return con.screen;
    }
};
}  // namespace

TEST(fake_conhost_reproduces_1_1_4_raw_words) {
    // Win10 cmd.exe report: nobody typed — hook keyed the window as cmd.exe (no rule),
    // the TIP stayed out on its conhost.exe Direct rule.
    ConsoleRig r(ConsoleRig::Build::V114);
    CHECK(r.type("gox thuwr tieengs vieetj") == u"gox thuwr tieengs vieetj");
}

TEST(fake_conhost_1_1_5_hook_types_everything) {
    ConsoleRig r(ConsoleRig::Build::V115);
    CHECK(r.type("gox thuwr tieengs vieetj ") == u"gõ thử tiếng việt ");
}

TEST(fake_conhost_handover_mid_word_needs_arming) {
    // The hook engages after "gox thu" (TIP handover arrives late). Without arming the
    // hook starts a fresh word at "w" while the TIP composes "thu": two typists, garbage.
    ConsoleRig bad(ConsoleRig::Build::V115);
    bad.handoverMidFocus = true;
    bad.arming = false;
    bad.engageAfterKeys = 7;
    CHECK(bad.type("gox thuwr tieengs ") != u"gõ thử tiếng ");
    ConsoleRig good(ConsoleRig::Build::V115);
    good.handoverMidFocus = true;
    good.engageAfterKeys = 7;
    CHECK(good.type("gox thuwr tieengs ") == u"gõ thử tiếng ");
}

TEST(debug_log_line_format_and_rotation) {
    LogStamp t{2026, 9, 26, 14, 3, 7, 5};
    const std::string l = formatLogLine(t, 4312, "conhost.exe", "tip", "rule 4\nx");
    CHECK_EQ(l, std::string("2026-09-26 14:03:07.005 pid=4312 conhost.exe [tip] rule 4 x\r\n"));
    CHECK(!logNeedsRotation(0, 100));
    CHECK(!logNeedsRotation(1000, 100));
    CHECK(logNeedsRotation(kDebugLogMaxBytes - 10, 100));
}

TEST(app_language_switch_focus_sequence) {
    // Chrome -> E, Notepad stays V, back to Chrome: E; a new app defaults to V.
    AppLanguageStore s;
    CHECK(s.vietnamese("chrome.exe"));
    s.set("chrome.exe", false);
    CHECK(s.vietnamese("notepad.exe"));
    CHECK(!s.vietnamese("chrome.exe"));
    CHECK(!s.vietnamese("Chrome.EXE"));
    s.set("chrome.exe", true);
    CHECK(s.vietnamese("chrome.exe"));
}

TEST(app_language_persistence_round_trip) {
    AppLanguageStore a;
    a.set("chrome.exe", false);
    a.set("searchhost.exe", false);
    a.set("notepad.exe", true);
    AppLanguageStore b;
    b.parse(a.serialize());
    CHECK(!b.vietnamese("chrome.exe"));
    CHECK(!b.vietnamese("searchhost.exe"));
    CHECK(b.vietnamese("notepad.exe"));
    CHECK(b.known("notepad.exe"));
    b.parse("bad line\nx.exe\t2\n\tn\nok.exe\t0\r\n");
    CHECK(!b.vietnamese("ok.exe"));
    CHECK(!b.known("x.exe"));
    CHECK_EQ(b.entries().size(), static_cast<size_t>(1));
}

TEST(app_language_webview2_and_console_keys) {
    AppLanguageStore s;
    s.set(appIdentity("msedgewebview2.exe", "ms-teams.exe"), false);  // TIP inside WebView2
    CHECK(!s.vietnamese("ms-teams.exe"));                             // app side: fg exe
    CHECK(s.vietnamese("msedgewebview2.exe"));
    s.set("conhost.exe", false);                                      // TIP in conhost
    CHECK(!s.vietnamese(hostIdentity("ConsoleWindowClass", "cmd.exe")));  // hook / tray
}

TEST(windows_per_app_input_option) {
    CHECK(perAppInputFromSpi(true, 1) == PerAppInput::On);
    CHECK(perAppInputFromSpi(true, 0) == PerAppInput::Off);
    CHECK(perAppInputFromSpi(false, 1) == PerAppInput::Unknown);
    CHECK(hotkeyNote(SwitchHotkey::CtrlShift, PerAppInput::Off) == HotkeyNote::TipRemembers);
    CHECK(hotkeyNote(SwitchHotkey::AltZ, PerAppInput::Unknown) == HotkeyNote::TipRemembers);
    CHECK(hotkeyNote(SwitchHotkey::WinSpace, PerAppInput::On) == HotkeyNote::WindowsPerApp);
    CHECK(hotkeyNote(SwitchHotkey::WinSpace, PerAppInput::Off) == HotkeyNote::WindowsGlobal);
    CHECK(hotkeyNote(SwitchHotkey::Off, PerAppInput::Unknown) == HotkeyNote::WindowsUnknown);
    CHECK(perAppAction(PerAppInput::Off) == PerAppAction::Enable);
    CHECK(perAppAction(PerAppInput::On) == PerAppAction::None);
    CHECK(perAppAction(PerAppInput::Unknown) == PerAppAction::OpenSettings);
    CHECK(enableNeedsSettingsPage(PerAppInput::Off));
    CHECK(!enableNeedsSettingsPage(PerAppInput::On));
    CHECK(parseSwitchHotkey("win-space") == SwitchHotkey::WinSpace);
}
