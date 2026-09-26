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
    // after msiexec exits:
    CHECK(afterInstallAction(true, true) == AfterInstall::Nothing);            // LaunchApp ran the new one
    CHECK(afterInstallAction(false, true) == AfterInstall::LaunchInstalled);   // UAC cancelled / failed
    CHECK(afterInstallAction(false, false) == AfterInstall::Nothing);          // nothing installed any more
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
