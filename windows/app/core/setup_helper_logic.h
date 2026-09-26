// setup_helper_logic.h — pure decisions of VietTelexSetupHelper.exe (the MSI's own helper,
// run from the Binary table so it exists before any file is installed). Unit-tested.
//
//   --quit-app          (immediate, as the user, before InstallValidate) ask every
//                       VietTelex.exe to close (WM_CLOSE to its hidden window), wait, then
//                       terminate only processes whose image name is VietTelex.exe.
//   --release-tip <dir>… (deferred, SYSTEM, after InstallInitialize and BEFORE the old
//                       product is removed) rename every in-use VietTelexTIP*.dll out of
//                       the way and schedule its deletion at the next reboot. The TIP is
//                       loaded into other apps and cannot be closed; renaming a loaded DLL
//                       is allowed, so MSI never meets a file in use and never asks for a
//                       reboot. Apps keep the old copy mapped until they exit; new
//                       processes load the new, version-named DLL.
#pragma once
#include <string>
#include <vector>

namespace vtx {

constexpr const wchar_t* kAppExeName = L"VietTelex.exe";
constexpr unsigned kQuitGraceMs = 3000;  // WM_CLOSE -> wait this long -> terminate

// Case-insensitive file-name match; only the exact app image may ever be terminated.
bool isAppImage(const std::wstring& imagePathOrName);

// TIP DLLs VietTelex has shipped: VietTelexTIP.dll, VietTelexTIP_arm64.dll,
// VietTelexTIP_x64.dll and the version-named VietTelexTIP_1_0_6.dll /
// VietTelexTIP_arm64_1_0_6.dll ... (case-insensitive, ".dll" only).
bool isTipDllName(const std::wstring& fileName);

// Leftover renamed copies: "<anything>.old" created by releaseName().
bool isReleasedLeftover(const std::wstring& fileName);

// "VietTelexTIP_1_0_6.dll" + stamp -> "VietTelexTIP_1_0_6.dll.<stamp>.old"
std::wstring releaseName(const std::wstring& fileName, unsigned long long stamp);

// Version-stamped DLL base names for a release ("1.0.6" -> "_1_0_6"). Dots would break
// the ARM64X forwarder's module references, so they become underscores.
std::string versionSuffix(const std::string& version);

// Parses the helper's command line (already split into arguments).
struct HelperArgs {
    bool quitApp = false;
    bool releaseTip = false;
    std::vector<std::wstring> dirs;  // --release-tip targets
};
HelperArgs parseHelperArgs(const std::vector<std::wstring>& argv);

}  // namespace vtx

namespace vtx {

// Single-instance handoff (VietTelex.exe starting while another instance runs). The main
// window's title carries the version ("VietTelex 1.0.6"); instances from before 1.0.6
// titled it just "VietTelex". A NEWER exe must replace an older running one — otherwise
// the fresh LaunchApp after an upgrade only re-activates the old process (seen on real
// Windows: Settings still said 1.0.4 after installing 1.0.5).
enum class Handoff { PassToRunning, ReplaceRunning };
Handoff decideHandoff(const std::wstring& runningTitle, const std::string& ourVersion);
std::wstring mainWindowTitle(const std::string& version);  // "VietTelex <version>"

}  // namespace vtx

namespace vtx {

// In-app update handoff ("Kiểm tra cập nhật" -> signed MSI):
//   1. app starts `msiexec /i <msi>` and a DETACHED watcher (a copy of VietTelex.exe in
//      %TEMP%, so no installed file is held) with `--wait-install <msiexec pid>`;
//   2. app exits at once (tray icon removed, mutex released) — it is one of the files
//      the MSI replaces, so it must not wait;
//   3. the MSI's LaunchApp starts the NEW app, which opens Settings;
//   4. when msiexec exits the watcher starts the installed app if none is running (UAC
//      cancelled / install failed: the old version comes back instead of nothing).
constexpr const wchar_t* kWatcherFileName = L"VietTelex-update-watcher.exe";
std::wstring watcherArgs(unsigned long msiexecPid);
bool parseWaitInstallArg(const std::vector<std::wstring>& argv, unsigned long& pid);
enum class AfterInstall { Nothing, LaunchInstalled };
AfterInstall afterInstallAction(bool appAlreadyRunning, bool installedExeExists);

}  // namespace vtx
