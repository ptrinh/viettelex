#include <cstdio>
#include <vector>

#include "app_messages.h"
#include "breaker.h"
#include "test.h"
#include "text_action_logic.h"
#include "text_tool_ipc.h"
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

// Store policy 10.2.7 (1.3.x failed it): an in-use TIP DLL parked as "*.old" NEXT TO the
// original kept C:\Program Files\VietTelex after uninstall. It is parked in TEMP now.
TEST(helper_uninstall_leaves_no_folder) {
    // x64 and x86 folders both hold VietTelexTIP_1_3_5.dll: parked names must differ
    const std::wstring a = parkedName(L"VietTelexTIP_1_3_5.dll", 0, 42);
    const std::wstring b = parkedName(L"VietTelexTIP_1_3_5.dll", 1, 42);
    CHECK(a == std::wstring(L"VietTelexTIP_1_3_5.dll.0.42.old"));
    CHECK(a != b);
    CHECK(isReleasedLeftover(a));
    CHECK(!isTipDllName(a));  // never mistaken for a live TIP DLL
    // rename only within a volume
    CHECK(sameVolumeRoot(L"C:\\", L"c:"));
    CHECK(sameVolumeRoot(L"C:\\", L"C:\\"));
    CHECK(!sameVolumeRoot(L"C:\\", L"D:\\"));
    CHECK(!sameVolumeRoot(L"", L""));  // unknown volume: never "same"
    // --remove=[REMOVE]: "ALL" on uninstall, empty on install / upgrade / repair
    HelperArgs h = parseHelperArgs({L"--max-version", L"1.3.6", L"--remove=ALL", L"--release-tip",
                                    L"C:\\Program Files\\VietTelex\\.", L"C:\\Program Files (x86)\\VietTelex\\."});
    CHECK(h.uninstall && h.releaseTip);
    CHECK_EQ(h.dirs.size(), size_t(2));
    CHECK(!parseHelperArgs({L"--remove=", L"--release-tip", L"C:\\x\\."}).uninstall);
    CHECK(!parseHelperArgs({L"--release-tip", L"C:\\x\\."}).uninstall);
    CHECK(parseHelperArgs({L"--remove=all"}).uninstall);
    CHECK_EQ(parseHelperArgs({L"--remove=ALL", L"--release-tip", L"C:\\x\\."}).dirs.size(), size_t(1));
    // terminate on uninstall: only the installed VietTelex.exe
    const std::vector<std::wstring> dirs = {L"C:\\Program Files\\VietTelex", L"C:\\Program Files (x86)\\VietTelex"};
    CHECK(isInstalledAppImage(L"C:\\Program Files\\VietTelex\\VietTelex.exe", dirs));
    CHECK(isInstalledAppImage(L"c:\\program files\\viettelex\\VIETTELEX.EXE", dirs));
    CHECK(!isInstalledAppImage(L"C:\\Users\\a\\Downloads\\VietTelex.exe", dirs));  // portable copy
    CHECK(!isInstalledAppImage(L"C:\\Program Files\\VietTelex\\other.exe", dirs));
    CHECK(!isInstalledAppImage(L"C:\\Program Files\\VietTelex\\sub\\VietTelex.exe", dirs));
    CHECK(!isInstalledAppImage(L"VietTelex.exe", dirs));
    CHECK(!isInstalledAppImage(L"C:\\Program Files\\VietTelex\\VietTelex.exe", {}));
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
    bool setComposition(const std::u16string& t, int, bool) override {
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
    bool setComposition(const std::u16string&, int, bool) override { return false; }
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

// 2026-10 field report: Ctrl+Shift (UniKey habit) did nothing in a newly opened app until
// Win+Space brought VietTelex back — the chord lives in the TIP, inactive on ENG.
TEST(ctrl_shift_from_another_keyboard_activates_viettelex) {
    // Chord bookkeeping from low-level events (L/R variants, as WH_KEYBOARD_LL reports them).
    uint8_t held = chordHeldAfter(0, 0xA2, true);  // LCtrl down
    CHECK(held == kModCtrl);
    held = chordHeldAfter(held, 0xA1, true);       // RShift down
    CHECK(held == (kModCtrl | kModShift));
    ModifierChord chord;
    CHECK(!chord.note(kModCtrl));
    CHECK(!chord.note(held));                      // armed
    CHECK(chord.note(chordHeldAfter(held, 0xA1, false)));  // release -> fires once
    CHECK(isChordModifierVk(0x5B) && !isChordModifierVk('A'));

    // Decision at fire time.
    const unsigned enUS = 0x0409;
    CHECK(foreignChordAction(SwitchHotkey::CtrlShift, 0, enUS, false) == ForeignChord::ActivateVietTelex);
    CHECK(foreignChordAction(SwitchHotkey::CtrlShift, 0, 0, false) == ForeignChord::ActivateVietTelex);  // unknown layout
    CHECK(foreignChordAction(SwitchHotkey::CtrlShift, 1, enUS, false) == ForeignChord::Ignore);  // TIP active (V)
    CHECK(foreignChordAction(SwitchHotkey::CtrlShift, 2, enUS, false) == ForeignChord::Ignore);  // TIP active (E)
    CHECK(foreignChordAction(SwitchHotkey::CtrlShift, 0, 0x042A, false) == ForeignChord::Ignore);  // vi-VN already
    CHECK(foreignChordAction(SwitchHotkey::CtrlShift, 0, enUS, true) == ForeignChord::Ignore);   // game / fullscreen
    CHECK(foreignChordAction(SwitchHotkey::WinSpace, 0, enUS, false) == ForeignChord::Ignore);
    CHECK(foreignChordAction(SwitchHotkey::AltZ, 0, enUS, false) == ForeignChord::Ignore);
    CHECK(foreignChordAction(SwitchHotkey::Off, 0, enUS, false) == ForeignChord::Ignore);
    CHECK(chordWatcherWanted(SwitchHotkey::CtrlShift));
    CHECK(!chordWatcherWanted(SwitchHotkey::AltZ) && !chordWatcherWanted(SwitchHotkey::WinSpace));
    CHECK(chordToggleAllowed(true, false, false, false));
    CHECK(!chordToggleAllowed(true, true, false, false));   // fires on release only
    CHECK(!chordToggleAllowed(true, false, true, false));   // game / fullscreen
    CHECK(!chordToggleAllowed(true, false, false, true));   // Ctrl+Shift+click / drag
    CHECK(!chordToggleAllowed(false, false, false, false));

    // Which input locale to request.
    const uintptr_t list[] = {0x04090409, 0x042A042A, 0xF0C1042A};
    CHECK(pickVietnameseHkl(list, 3) == 0x042A042A);
    const uintptr_t noVi[] = {0x04090409, 0x04110411};
    CHECK(pickVietnameseHkl(noVi, 2) == 0);
    CHECK(pickVietnameseHkl(nullptr, 0) == 0);

    // Root cause: another keyboard is Windows' default input method.
    CHECK(defaultInputAdvice(SwitchHotkey::CtrlShift, enUS) == DefaultInputAdvice::MakeVietTelexDefault);
    CHECK(defaultInputAdvice(SwitchHotkey::AltZ, enUS) == DefaultInputAdvice::MakeVietTelexDefault);
    CHECK(defaultInputAdvice(SwitchHotkey::CtrlShift, 0x042A) == DefaultInputAdvice::None);
    CHECK(defaultInputAdvice(SwitchHotkey::CtrlShift, 0) == DefaultInputAdvice::None);  // unreadable
    CHECK(defaultInputAdvice(SwitchHotkey::WinSpace, enUS) == DefaultInputAdvice::None);
    CHECK_EQ(defaultLayoutOrTipSpec(0x042A, "{A}", "{B}"), std::string("0x042A:{A}{B}"));
    // The welcome window pre-ticks the same fix.
    CHECK(welcomeOffersDefaultInput(SwitchHotkey::CtrlShift, enUS));
    CHECK(!welcomeOffersDefaultInput(SwitchHotkey::CtrlShift, 0x042A));
    CHECK(!welcomeOffersDefaultInput(SwitchHotkey::WinSpace, enUS));
}

// 2026-10 field report (UniKey user): "không chuyển được Việt/Anh dù đã đặt Ctrl+Shift".
// Windows' own input hotkeys (HKCU\Keyboard Layout\Toggle) on Ctrl+Shift switch the
// keyboard on the same press as VietTelex's toggle.
TEST(windows_ctrl_shift_hotkey_clash) {
    // Parsing: missing / garbage -> the default; "1".."4" as documented.
    CHECK(parseWinToggle(false, "2", WinToggle::AltShift) == WinToggle::AltShift);
    CHECK(parseWinToggle(true, "2", WinToggle::AltShift) == WinToggle::CtrlShift);
    CHECK(parseWinToggle(true, "3", WinToggle::AltShift) == WinToggle::None);
    CHECK(parseWinToggle(true, "4", WinToggle::AltShift) == WinToggle::Grave);
    CHECK(parseWinToggle(true, "", WinToggle::CtrlShift) == WinToggle::CtrlShift);
    CHECK(parseWinToggle(true, "9", WinToggle::CtrlShift) == WinToggle::CtrlShift);
    CHECK(parseWinToggle(true, "12", WinToggle::CtrlShift) == WinToggle::CtrlShift);
    for (int i = 1; i <= 4; ++i) {
        const WinToggle t = static_cast<WinToggle>(i);
        CHECK(parseWinToggle(true, winToggleValue(t), WinToggle::None) == t);
    }
    // Nothing stored: Windows' defaults (languages Left Alt+Shift, layouts Ctrl+Shift).
    WinToggles w = readWinToggles(false, "", false, "", false, "");
    CHECK(w.language == WinToggle::AltShift && w.layout == WinToggle::CtrlShift);
    // "Language Hotkey" wins over the legacy "Hotkey"; the legacy one is used alone.
    w = readWinToggles(true, "1", true, "2", true, "3");
    CHECK(w.language == WinToggle::AltShift && w.layout == WinToggle::None);
    w = readWinToggles(false, "", true, "2", true, "3");
    CHECK(w.language == WinToggle::CtrlShift);

    // Clash: Ctrl+Shift between languages (the field report).
    WinToggles lang;
    lang.language = WinToggle::CtrlShift;
    lang.layout = WinToggle::None;
    CHECK(winHotkeyClash(SwitchHotkey::CtrlShift, lang, false) == WinHotkeyClash::LanguageSwitch);
    CHECK(winHotkeyClash(SwitchHotkey::AltZ, lang, false) == WinHotkeyClash::None);       // not our key
    CHECK(winHotkeyClash(SwitchHotkey::WinSpace, lang, false) == WinHotkeyClash::None);
    // Default layout hotkey (Ctrl+Shift): harmless with VietTelex alone in vi-VN...
    const WinToggles dflt;
    CHECK(winHotkeyClash(SwitchHotkey::CtrlShift, dflt, false) == WinHotkeyClash::None);
    // ...but jumps to Microsoft's Vietnamese keyboard when it is in the list too.
    CHECK(winHotkeyClash(SwitchHotkey::CtrlShift, dflt, true) == WinHotkeyClash::LayoutSwitch);

    // Fix: languages back to Left Alt+Shift, no Ctrl+Shift left anywhere.
    WinToggleFix f = winToggleFix(lang);
    CHECK(f.changeLanguage && f.language == WinToggle::AltShift);
    CHECK(!f.changeLayout);
    f = winToggleFix(dflt);
    CHECK(!f.changeLanguage);
    CHECK(f.changeLayout && f.layout == WinToggle::None);
    WinToggles grave;  // languages on `, layouts on Ctrl+Shift
    grave.language = WinToggle::Grave;
    f = winToggleFix(grave);
    CHECK(!f.changeLanguage && f.language == WinToggle::Grave);
    CHECK(f.changeLayout && f.layout == WinToggle::None);
    WinToggles swapped;  // languages Ctrl+Shift, layouts Alt+Shift: layouts must not collide
    swapped.language = WinToggle::CtrlShift;
    swapped.layout = WinToggle::AltShift;
    f = winToggleFix(swapped);
    CHECK(f.changeLanguage && f.language == WinToggle::AltShift);
    CHECK(f.changeLayout && f.layout == WinToggle::None);
    // After any fix there is no clash left.
    for (const WinToggles& before : {lang, dflt, grave, swapped}) {
        const WinToggleFix x = winToggleFix(before);
        WinToggles after;
        after.language = x.language;
        after.layout = x.layout;
        CHECK(winHotkeyClash(SwitchHotkey::CtrlShift, after, true) == WinHotkeyClash::None);
    }
}

// 2026-10 perf audit H1/H2: the default Ctrl+Shift watcher kept WH_MOUSE_LL (and raw
// input) installed for good — every mouse move woke the high-priority hook thread.
TEST(hook_needs_mouse_only_while_typing_or_chord_armed) {
    // Default install: watcher only. Keyboard hook yes, mouse hook no...
    HookNeeds n = hookNeeds(false, true, false, false);
    CHECK(n.keyboard && !n.mouse);
    // ...until Ctrl+Shift are held together (a click must cancel the toggle).
    n = hookNeeds(false, true, true, false);
    CHECK(n.keyboard && n.mouse);
    // Typing (hook / Direct): both, a click resets the word.
    n = hookNeeds(true, false, false, false);
    CHECK(n.keyboard && n.mouse);
    // Nothing wanted: nothing installed (armed state of a dead watcher is irrelevant).
    n = hookNeeds(false, false, true, false);
    CHECK(!n.keyboard && !n.mouse);
    // Game / fullscreen / Chế độ game: unhooked, not just flagged.
    n = hookNeeds(true, true, true, true);
    CHECK(!n.keyboard && !n.mouse);
}

// ---- Công cụ văn bản (text_action_logic.h) ----------------------------------------------

namespace {
std::vector<uint8_t> readAll(const char* path) {
    std::vector<uint8_t> b;
    if (FILE* f = std::fopen(path, "rb")) {
        uint8_t buf[65536];
        size_t n;
        while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) b.insert(b.end(), buf, buf + n);
        std::fclose(f);
    }
    return b;
}
}  // namespace

TEST(text_action_hotkey_choices) {
    unsigned mods = 0, vk = 0;
    CHECK(!addTonesHotkeyKeys("off", mods, vk));  // default: nothing registered
    CHECK(!addTonesHotkeyKeys("bogus", mods, vk));
    CHECK_EQ(addTonesHotkeyIndex("bogus"), size_t{0});
    CHECK(addTonesHotkeyKeys("ctrl-alt-t", mods, vk));
    CHECK_EQ(mods, 3u);  // MOD_CONTROL | MOD_ALT
    CHECK_EQ(vk, static_cast<unsigned>('T'));
    CHECK(addTonesHotkeyKeys("win-alt-t", mods, vk) && mods == 9u);
    CHECK_EQ(addTonesHotkeyIndex("ctrl-shift-t"), size_t{2});
    CHECK(kTextToolMenuOrder[0] == text::Tool::AddTones);
}

TEST(text_action_transform) {
    std::u16string out;
    CHECK(transformText(text::Tool::Upper, u"tiếng việt", nullptr, out) && out == u"TIẾNG VIỆT");
    CHECK(transformText(text::Tool::StripDiacritics, u"Đường đi", nullptr, out) && out == u"Duong di");
    CHECK(!transformText(text::Tool::Upper, u"ABC 123", nullptr, out));        // unchanged -> nothing
    CHECK(!transformText(text::Tool::Lower, u"", nullptr, out));               // empty
    CHECK(!transformText(text::Tool::AddTones, u"toi di hoc", nullptr, out));  // no data
    std::u16string big(kTextToolMaxLength + 1, u'a');
    CHECK(!transformText(text::Tool::Upper, big, nullptr, out));  // over the cap
    // NFD input (some apps store decomposed text) comes back NFC
    CHECK(transformText(text::Tool::Lower, u"TIẾNG", nullptr, out) && out == u"tiếng");

    const std::vector<uint8_t> vl = readAll(VTX_KB_RESOURCES "/vnlexicon.bin");
    const std::vector<uint8_t> el = readAll(VTX_KB_RESOURCES "/enlexicon.bin");
    const std::vector<uint8_t> lm = readAll(VTX_KB_RESOURCES "/vnlm.bin");
    addtones::LanguageData d;
    CHECK(d.load(vl.data(), vl.size(), el.data(), el.size(), lm.data(), lm.size()));
    CHECK(d.lm.ok());
    CHECK(transformText(text::Tool::AddTones, u"toi di hoc hom nay", &d, out) && out == u"tôi đi học hôm nay");
    CHECK(!transformText(text::Tool::AddTones, u"hello world", &d, out));  // English: unchanged
}

TEST(text_action_clipboard_policy) {
    CHECK(clipboardFallbackAllowed("notepad.exe", false, "Notepad"));
    CHECK(clipboardFallbackAllowed("chrome.exe", false, "Chrome_WidgetWin_1"));
    CHECK(!clipboardFallbackAllowed("conhost.exe", true, "ConsoleWindowClass"));  // Ctrl+C = interrupt
    CHECK(!clipboardFallbackAllowed("windowsterminal.exe", false, "CASCADIA_HOSTING_WINDOW_CLASS"));
    CHECK(!clipboardFallbackAllowed("mintty.exe", false, "mintty"));
    CHECK(!clipboardFallbackAllowed("mstsc.exe", false, "TscShellContainerClass"));  // keys go remote
    CHECK(clipboardFormatKind(13) == ClipFormatKind::Global);      // CF_UNICODETEXT
    CHECK(clipboardFormatKind(8) == ClipFormatKind::Global);       // CF_DIB
    CHECK(clipboardFormatKind(0xC0A1) == ClipFormatKind::Global);  // registered (HTML Format…)
    CHECK(clipboardFormatKind(2) == ClipFormatKind::Skip);         // CF_BITMAP: re-synthesised
    CHECK(clipboardFormatKind(14) == ClipFormatKind::EnhMetafile);
    CHECK(clipboardFormatKind(0x250) == ClipFormatKind::Skip);     // CF_PRIVATEFIRST range
    CHECK(isShellSurfaceClass("Shell_TrayWnd") && isShellSurfaceClass("NotifyIconOverflowWindow"));
    CHECK(!isShellSurfaceClass("Notepad") && !isShellSurfaceClass("Chrome_WidgetWin_1"));
}

// Regression (text tools, not yet released): Công cụ văn bản's WM_APP + 0x61/0x62 were the updater's "check finished"
// / "download finished" too, and text_actions sees every main-window message first — the
// in-app update never got its result. One list, no duplicates.
TEST(main_window_messages_are_distinct) {
    using namespace vtx::app;
    const size_t n = sizeof kMainWindowMessages / sizeof kMainWindowMessages[0];
    for (size_t i = 0; i < n; ++i) {
        CHECK(kMainWindowMessages[i] >= kWmApp && kMainWindowMessages[i] < 0xC000u);
        for (size_t j = i + 1; j < n; ++j) CHECK(kMainWindowMessages[i] != kMainWindowMessages[j]);
    }
}

// ---- UI strings (app/src/strings.cpp is portable) ---------------------------------------
#include <cwchar>
#include <string>

#include <viettelex/vtx_engine.h>

#include "strings.h"

// 2026-10 UX audit: Windows keyboards have no ⌫ glyph ("Backspace"), the auto-restore
// example read "retore → retore" (looked like nothing happens), and the tray item that
// only hides the icon was enumerated as "Quit".
TEST(ui_strings_windows_wording) {
    using namespace vtx::app;
    for (int en = 0; en < 2; ++en) {
        setEnglish(en != 0);
        for (int i = 0; i < static_cast<int>(S::Count); ++i) {
            const wchar_t* s = tr(static_cast<S>(i));
            CHECK(s != nullptr);
            if (s) CHECK(std::wcschr(s, L'⌫') == nullptr);  // ⌫
        }
        const wchar_t* restore = tr(S::AutoRestoreDesc);
        CHECK(std::wcsstr(restore, L"retore → retore") == nullptr);
        CHECK(std::wcsstr(restore, L"“tet” → “text”") != nullptr);  // engine output, checked below
    }
    // The example is what the engine does with the default settings: "text" shows "tet"
    // while typing and is restored to "text" at the word end.
    vtx_engine* e = vtx_create();
    vtx_set_flags(e, vtx::Settings().engineFlags());
    vtx_action a;
    for (char c : std::string("text")) vtx_feed(e, static_cast<uint32_t>(c), &a);
    uint16_t buf[VTX_MAX_TEXT + 1];
    int32_t n = vtx_composed(e, buf, VTX_MAX_TEXT + 1);
    CHECK(std::u16string(reinterpret_cast<const char16_t*>(buf), static_cast<size_t>(n)) == u"tet");
    n = vtx_commit_text(e, 1, buf, VTX_MAX_TEXT + 1);
    CHECK(std::u16string(reinterpret_cast<const char16_t*>(buf), static_cast<size_t>(n)) == u"text");
    vtx_destroy(e);
    setEnglish(false);
    CHECK(std::wcscmp(tr(S::MenuHideTray), L"Ẩn biểu tượng khay") == 0);
    CHECK(std::wcscmp(tr(S::SecHints), L"Gợi ý cạnh con trỏ") == 0);
}

// Word prediction follows a Windows setting users could not find from VietTelex: the
// Chính tả page shows its state ("Gợi ý chữ khi gõ") with a button to ms-settings:typing.
TEST(ui_strings_text_prediction_card) {
    using namespace vtx::app;
    CHECK(textPredictionState(true) == S::TextPredictionOn);
    CHECK(textPredictionState(false) == S::TextPredictionOff);
    setEnglish(false);
    CHECK(std::wcscmp(tr(S::TextPrediction), L"Gợi ý chữ khi gõ") == 0);
    CHECK(std::wcscmp(tr(S::TextPredictionButton), L"Mở cài đặt Gõ phím của Windows…") == 0);
    const std::wstring on = textPredictionDesc(true), off = textPredictionDesc(false);
    CHECK(on.rfind(L"Đang bật", 0) == 0);
    CHECK(off.rfind(L"Đang tắt — bật trong Cài đặt Windows để dùng gợi ý chữ", 0) == 0);
    CHECK(on.find(tr(S::TextPredictionCaption)) != std::wstring::npos);  // caption follows the state
    CHECK(off.find(tr(S::TextPredictionCaption)) != std::wstring::npos);
    setEnglish(true);
    CHECK(textPredictionDesc(true).rfind(L"On.", 0) == 0);
    CHECK(textPredictionDesc(false).rfind(L"Off", 0) == 0);
    CHECK(std::wcsstr(tr(S::TextPredictionCaption), L"physical keyboard") != nullptr);
    setEnglish(false);
    CHECK(std::wstring(vtx::kTypingSettingsUri) == L"ms-settings:typing");  // what the button opens
}

