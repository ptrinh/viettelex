// main.cpp — VietTelex.exe: tray icon, settings window, updater, hook fallback, and
// the per-user setup/cleanup the MSI delegates to it. Typing itself lives in the TIP:
// quitting this app never stops Vietnamese input (spec §8).
//
// Command line:
//   (none)          open Settings (starting the tray app if needed)
//   --background    no window (autostart; tray icon only if enabled)
//   --settings      open Settings (after an interactive install)
//   --command <n>   run an AppCommand (open Settings / About, check for updates, Telex/VNI)
//   --setup-user    add the keyboard for this user + autostart, then exit (installer)
//   --cleanup-user  remove keyboard, autostart and all user data, then exit (uninstall)
//   --set-profile-icon <choice>  (elevated) set the keyboard profile icon, then exit
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>

#include <string>
#include <vector>

#include "app.h"
#include "app_quit.h"
#include "setup_helper_logic.h"
#include "icons.h"
#include "registration.h"
#include "res/icon_ids.h"
#include "foreground.h"
#include "hook_fallback.h"
#include "ipc.h"
#include "settings_store.h"
#include "strings.h"
#include "tip_control.h"
#include "updater.h"
#include "uninstall.h"
#include "version.h"

namespace vtx::app {

HINSTANCE g_inst = nullptr;
HWND g_mainWnd = nullptr;
Settings g_settings;

namespace {

// Keep in sync with ime/src/globals.h (kAppWindowClass, kAppCommandMsg).
constexpr wchar_t kAppWindowClass[] = L"VietTelexAppWindow";
constexpr UINT kAppCommandMsg = WM_APP + 0x56;
constexpr UINT kTrayMsg = WM_APP + 0x57;
constexpr UINT kTrayId = 1;
UINT g_taskbarCreated = 0;

enum TrayCmd : UINT { kTraySettings = 1, kTrayUpdate, kTrayAbout, kTrayQuit };


// Tray glyph = the keyboard icon chosen in settings, for the current taskbar theme.
// Việt/Anh state of the app in the foreground — the tray icon is the only state indicator
// (1.0.8: the taskbar shows just the keyboard-profile icon). Fed by the TIP
// (AppCommand::StateChanged) and by foreground changes (fgWinEvent).
bool g_stateVietnamese = true;
HWINEVENTHOOK g_fgHook = nullptr;
void CALLBACK fgWinEvent(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD);

HICON trayIcon() { return tip::CreateStateIcon(g_inst, g_settings.menuIcon, g_stateVietnamese); }

bool g_trayShown = false;

void addTrayIcon() {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof nid;
    nid.hWnd = g_mainWnd;
    nid.uID = kTrayId;
    nid.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE | NIF_SHOWTIP;
    nid.uCallbackMessage = kTrayMsg;
    nid.hIcon = trayIcon();
    lstrcpynW(nid.szTip, tr(S::TrayTip), ARRAYSIZE(nid.szTip));
    g_trayShown = Shell_NotifyIconW(NIM_ADD, &nid) != FALSE;
    nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &nid);
    if (nid.hIcon) DestroyIcon(nid.hIcon);
}

void removeTrayIcon() {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof nid;
    nid.hWnd = g_mainWnd;
    nid.uID = kTrayId;
    Shell_NotifyIconW(NIM_DELETE, &nid);
    g_trayShown = false;
}

// The tray icon is OPTIONAL (settings showTrayIcon, default off since 1.0.5): the taskbar
// input indicator already shows Việt/Anh, and Start menu -> VietTelex opens Settings.
void syncTrayIcon() {
    if (!g_mainWnd) return;
    if (!g_settings.showTrayIcon) {
        if (g_trayShown) removeTrayIcon();
        if (g_fgHook) {
            UnhookWinEvent(g_fgHook);
            g_fgHook = nullptr;
        }
        return;
    }
    if (!g_fgHook)
        g_fgHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, fgWinEvent, 0, 0,
                                   WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    if (!g_trayShown) {
        addTrayIcon();
        return;
    }
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof nid;
    nid.hWnd = g_mainWnd;
    nid.uID = kTrayId;
    nid.uFlags = NIF_ICON;
    nid.hIcon = trayIcon();
    Shell_NotifyIconW(NIM_MODIFY, &nid);
    if (nid.hIcon) DestroyIcon(nid.hIcon);
}

void showTrayMenu() {
    HMENU m = CreatePopupMenu();
    AppendMenuW(m, MF_STRING, kTraySettings, tr(S::MenuSettings));
    AppendMenuW(m, MF_STRING, kTrayUpdate, tr(S::MenuCheckUpdate));
    AppendMenuW(m, MF_STRING, kTrayAbout, tr(S::MenuAbout));
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING, kTrayQuit, tr(S::MenuQuit));
    POINT pt;
    GetCursorPos(&pt);
    SetForegroundWindow(g_mainWnd);
    UINT cmd = TrackPopupMenu(m, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, pt.x, pt.y, 0, g_mainWnd, nullptr);
    DestroyMenu(m);
    switch (cmd) {
        case kTraySettings: showSettings(Tab::Typing); break;
        case kTrayUpdate: startUpdateCheck(g_mainWnd, true); break;
        case kTrayAbout: showSettings(Tab::About); break;
        case kTrayQuit:  // "Ẩn biểu tượng khay": the app keeps running, just without the icon
            g_settings.showTrayIcon = false;
            settingsChanged();
            refreshSettingsWindow();
            break;
        default: break;
    }
}

// Non-modal notice (notification-area balloon) that hook mode cannot type into an
// elevated app — shown once per app; uses a temporary icon when the tray icon is off.
void showElevationNotice(const std::wstring& exe) {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof nid;
    nid.hWnd = g_mainWnd;
    nid.uID = g_trayShown ? kTrayId : kTrayId + 1;
    nid.uFlags = NIF_INFO | NIF_ICON | NIF_TIP;
    nid.hIcon = trayIcon();
    lstrcpynW(nid.szTip, tr(S::TrayTip), ARRAYSIZE(nid.szTip));
    lstrcpynW(nid.szInfoTitle, tr(S::AppName), ARRAYSIZE(nid.szInfoTitle));
    std::wstring msg = std::wstring(tr(S::ElevatedHookNotice)) + L" (" + exe + L")";
    lstrcpynW(nid.szInfo, msg.c_str(), ARRAYSIZE(nid.szInfo));
    nid.dwInfoFlags = NIIF_WARNING;
    Shell_NotifyIconW(g_trayShown ? NIM_MODIFY : NIM_ADD, &nid);
    if (nid.hIcon) DestroyIcon(nid.hIcon);
    if (!g_trayShown) SetTimer(g_mainWnd, 77, 15000, nullptr);  // drop the temporary icon
}

void setTrayState(bool vietnamese) {
    if (vietnamese == g_stateVietnamese) return;
    g_stateVietnamese = vietnamese;
    syncTrayIcon();
}

// Foreground app changed: its Việt/Anh state. The TIP's kTipLangProp on the window when
// present (the only truth for consoles, whose reported thread is cmd's), else the
// VietTelex keyboard on that thread plus the remembered per-app state (foreground.h).
void CALLBACK fgWinEvent(HWINEVENTHOOK, DWORD, HWND hwnd, LONG idObject, LONG, DWORD, DWORD) {
    if (idObject != OBJID_WINDOW || !hwnd) return;
    const FgApp app = describeWindow(hwnd);
    const bool on = fgVietnamese(hwnd, app);
    if (appLogging())
        appLog("app", "tray state for " + narrowAscii(app.identity) + " (class " + app.windowClass + "): " +
                          (on ? "vi" : "en"));
    setTrayState(on);
}

// In-TIP Việt/Anh switch (Ctrl+Shift, Alt+Z): store it for hosts that cannot (bit 1:
// AppContainer / low IL — keyed by the foreground app, where the switch happened) and
// refresh the mirror those hosts read.
void onAppLanguage(LPARAM lp) {
    const bool on = (lp & 1) != 0;
    if (lp & 2) {
        const FgApp app = describeWindow(GetForegroundWindow());
        storeVietnamese(app.identity, on);
        appLog("app", "applang stored for " + narrowAscii(app.identity) + " (TIP could not): " + (on ? "vi" : "en"));
    }
    mirrorAppLanguage();
    setTrayState(on);
}

void runCommand(unsigned cmd, LPARAM lp = 0) {
    if (!isValidAppCommand(cmd)) return;
    switch (static_cast<AppCommand>(cmd)) {
        case AppCommand::StateChanged: setTrayState(lp != 0); break;
        case AppCommand::DirectMode: hookSetDirectFromTip(lp != 0); break;
        case AppCommand::SetAppLanguage: onAppLanguage(lp); break;
        case AppCommand::OpenSettings: showSettings(Tab::Typing); break;
        case AppCommand::CheckUpdate: startUpdateCheck(g_mainWnd, true); break;
        case AppCommand::OpenAbout: showSettings(Tab::About); break;
        case AppCommand::SetTelex:
        case AppCommand::SetVni:
            g_settings.vniMode = static_cast<AppCommand>(cmd) == AppCommand::SetVni;
            settingsChanged();
            refreshSettingsWindow();
            break;
    }
}

wchar_t g_pendingVersion[32] = {};  // version being installed (names the msiexec log)

void onUpdateChecked(UpdateInfo* info) {
    if (!info->interactive) markAutoChecked();
    if (info->available) {
        wchar_t msg[256];
        wsprintfW(msg, tr(S::UpdateAvailable), info->version);
        // Auto-check notifies once per version (lastNotifiedUpdateVersion, as macOS).
        bool show = info->interactive || readString(L"lastNotifiedUpdateVersion") != info->version;
        if (show) {
            writeString(L"lastNotifiedUpdateVersion", info->version);
            if (MessageBoxW(nullptr, msg, tr(S::AppName), MB_YESNO | MB_ICONINFORMATION | MB_SETFOREGROUND) == IDYES) {
                lstrcpynW(g_pendingVersion, info->version, 32);
                startDownload(g_mainWnd, info->url);
            }
        }
    } else if (info->interactive) {
        MessageBoxW(nullptr, info->ok ? tr(S::UpToDate) : tr(S::UpdateFailed), tr(S::AppName),
                    MB_OK | (info->ok ? MB_ICONINFORMATION : MB_ICONWARNING) | MB_SETFOREGROUND);
    }
    delete info;
}

void onDownloaded(WPARAM status, wchar_t* path) {
    if (status == kDownloadOk && path) {
        // Hand off and leave NOW: saves nothing pending (settings are saved on change),
        // WM_DESTROY removes the tray icon, WinMain releases the single-instance mutex.
        if (runInstaller(path, g_pendingVersion)) PostMessageW(g_mainWnd, WM_CLOSE, 0, 0);
    } else {
        MessageBoxW(nullptr, status == kDownloadBadSignature ? tr(S::UpdateBadSignature) : tr(S::UpdateFailed),
                    tr(S::AppName), MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
    }
    delete[] path;
}

LRESULT CALLBACK mainProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == g_taskbarCreated && g_taskbarCreated) {
        g_trayShown = false;  // Explorer restarted: the old icon is gone
        syncTrayIcon();
        return 0;
    }
    switch (msg) {
        case kAppCommandMsg: runCommand(static_cast<unsigned>(wp), lp); return 0;
        // Restart Manager / logoff / an upgrade closing us: agree, then exit cleanly
        // (settings are saved on every change, so there is nothing left to flush).
        case WM_TIMER:
            if (wp == 77) {
                KillTimer(h, 77);
                NOTIFYICONDATAW nid = {};
                nid.cbSize = sizeof nid;
                nid.hWnd = h;
                nid.uID = kTrayId + 1;
                Shell_NotifyIconW(NIM_DELETE, &nid);
            }
            return 0;
        case WM_QUERYENDSESSION: return TRUE;
        case WM_ENDSESSION:
            if (wp) DestroyWindow(h);
            return 0;
        case WM_CLOSE: DestroyWindow(h); return 0;
        case kTrayMsg:
            switch (LOWORD(lp)) {
                case WM_LBUTTONUP:
                case NIN_SELECT:
                case NIN_KEYSELECT: showSettings(Tab::Typing); break;
                case WM_CONTEXTMENU:
                case WM_RBUTTONUP: showTrayMenu(); break;
                default: break;
            }
            return 0;
        case WM_SETTINGCHANGE:  // taskbar switched light/dark
            if (lp && lstrcmpW(reinterpret_cast<LPCWSTR>(lp), L"ImmersiveColorSet") == 0) syncTrayIcon();
            return 0;
        case kMsgUpdateChecked: onUpdateChecked(reinterpret_cast<UpdateInfo*>(lp)); return 0;
        case kMsgUpdateDownloaded: onDownloaded(wp, reinterpret_cast<wchar_t*>(lp)); return 0;
        case WM_DESTROY:
            removeTrayIcon();
            hookShutdown();
            PostQuitMessage(0);
            return 0;
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

bool snapshotMissing() {
    wchar_t buf[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return false;
    std::wstring p = std::wstring(buf) + L"\\VietTelex\\settings.bin";
    return GetFileAttributesW(p.c_str()) == INVALID_FILE_ATTRIBUTES;
}

// Undocumented but stable since 1903: uxtheme ordinal 135 SetPreferredAppMode —
// makes the tray/context menus follow the dark theme. Skipped when unavailable.
void allowDarkMenus() {
    HMODULE ux = LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!ux) return;
    using Fn = int(WINAPI*)(int);
    if (auto fn = reinterpret_cast<Fn>(reinterpret_cast<void*>(GetProcAddress(ux, MAKEINTRESOURCEA(135)))))
        fn(1 /* AllowDark */);
    using Refresh = void(WINAPI*)();  // #104 RefreshImmersiveColorPolicyState
    if (auto r = reinterpret_cast<Refresh>(reinterpret_cast<void*>(GetProcAddress(ux, MAKEINTRESOURCEA(104))))) r();
}

std::string g_profileIconArg;

// Elevated helper (run with the "runas" verb by Settings when the icon choice changes):
// point the keyboard profile's IconIndex (HKLM, 64- and 32-bit views) at the choice's
// icon in VietTelexTIP.dll. Chosen over a user-writable icon FILE because the profile
// icon is loaded into every process incl. elevated ones and the secure desktop — no
// user-writable file should ever be parsed there. Cost: one UAC prompt per change.
int setProfileIcon(const std::string& name) {
    const DWORD index = static_cast<DWORD>(profileIconIndex(parseIconChoice(name)));
    const std::wstring key = widen(reg::languageProfileKey());
    int written = 0;
    for (REGSAM view : {KEY_WOW64_64KEY, KEY_WOW64_32KEY}) {
        HKEY k;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, key.c_str(), 0, KEY_SET_VALUE | view, &k) == ERROR_SUCCESS) {
            if (RegSetValueExW(k, L"IconIndex", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&index), sizeof index) ==
                ERROR_SUCCESS)
                ++written;
            RegCloseKey(k);
        }
    }
    // Explorer / the input switcher cache icons: nudge them (new processes re-read anyway).
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
    DWORD_PTR r;
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, reinterpret_cast<LPARAM>(L"intl"), SMTO_ABORTIFHUNG, 2000,
                        &r);
    return written > 0 ? 0 : 1;
}

// `--wait-install <pid>` (a copy of this exe in %TEMP%): wait for msiexec, then start the
// installed VietTelex if the MSI's LaunchApp did not (UAC cancelled, install failed).
// Appends one line to %LOCALAPPDATA%\VietTelex\update-watcher.log (evidence for reports).
void watcherLog(const std::wstring& line) {
    wchar_t dir[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", dir, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return;
    std::wstring folder = std::wstring(dir) + L"\\VietTelex";
    CreateDirectoryW(folder.c_str(), nullptr);
    HANDLE f = CreateFileW((folder + L"\\" + vtx::kWatcherLogName).c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME t;
    GetLocalTime(&t);
    wchar_t stamp[40];
    wsprintfW(stamp, L"%04u-%02u-%02u %02u:%02u:%02u ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
    std::string u = narrow(stamp + line + L"\r\n");
    DWORD w = 0;
    WriteFile(f, u.data(), static_cast<DWORD>(u.size()), &w, nullptr);
    CloseHandle(f);
}

// `--wait-install <pid>` (a copy of this exe in %TEMP%): wait for msiexec, then — only if
// it FAILED or was cancelled — start the installed VietTelex (success: the MSI's
// LaunchApp already started the new version; starting another would race it).
int waitInstall(unsigned long pid) {
    bool known = false;
    DWORD code = 0;
    if (HANDLE p = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
        WaitForSingleObject(p, 2 * 60 * 60 * 1000);
        known = GetExitCodeProcess(p, &code) && code != STILL_ACTIVE;
        CloseHandle(p);
    }
    Sleep(3000);  // LaunchApp runs at the very end of the install
    wchar_t exe[MAX_PATH] = {};
    DWORD sz = sizeof exe;
    const bool have = RegGetValueW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\VietTelex", L"AppPath",
                                   RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, exe, &sz) == ERROR_SUCCESS &&
                      GetFileAttributesW(exe) != INVALID_FILE_ATTRIBUTES;
    HWND runningWnd = FindWindowW(kAppWindowClass, nullptr);
    wchar_t title[64] = {};
    if (runningWnd) GetWindowTextW(runningWnd, title, 64);
    const vtx::AfterInstall act = vtx::afterInstallAction(known, code, runningWnd != nullptr, have);
    wchar_t line[512];
    wsprintfW(line, L"watcher %s: msiexec pid %lu exit %s%lu, running=\"%s\", installed=%s -> %s",
              VTX_VER_STRING_W, pid, known ? L"" : L"unknown/", static_cast<unsigned long>(code), title,
              have ? exe : L"(none)", act == vtx::AfterInstall::LaunchInstalled ? L"relaunch installed app" : L"nothing");
    watcherLog(line);
    if (act == vtx::AfterInstall::LaunchInstalled)
        ShellExecuteW(nullptr, L"open", exe, L"--settings", nullptr, SW_SHOWNORMAL);
    return 0;
}

unsigned long g_waitPid = 0;

unsigned parseCommandArg(const wchar_t* cmdLine, bool& background, int& oneShot) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(cmdLine, &argc);
    unsigned cmd = 0;
    {
        std::vector<std::wstring> all;
        for (int i = 1; argv && i < argc; ++i) all.push_back(argv[i]);
        if (vtx::parseWaitInstallArg(all, g_waitPid)) oneShot = 4;
    }
    for (int i = 1; argv && i < argc; ++i) {
        std::wstring a = argv[i];
        if (a == L"--background") background = true;
        else if (a == L"--settings") background = false;  // installer: open Settings
        else if (a == L"--setup-user") oneShot = 1;
        else if (a == L"--cleanup-user") oneShot = 2;
        else if (a == L"--set-profile-icon" && i + 1 < argc) {
            oneShot = 3;
            g_profileIconArg = narrow(argv[++i]);
        }
        else if (a == L"--command" && i + 1 < argc) {
            cmd = static_cast<unsigned>(_wtoi(argv[++i]));
            if (!vtx::isUserCommand(cmd)) cmd = 0;
        }
    }
    if (argv) LocalFree(argv);
    return cmd;
}

}  // namespace

void settingsChanged() {
    saveSettings(g_settings);
    syncTrayIcon();
    setEnglish(g_settings.uiLanguage == "en");
    hookConfigure(g_settings);
}

}  // namespace vtx::app

using namespace vtx::app;

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    g_inst = inst;
    bool background = false;
    int oneShot = 0;
    unsigned cmd = parseCommandArg(GetCommandLineW(), background, oneShot);

    if (oneShot == 1) {  // installer, as the installing user
        g_settings = loadSettings();
        saveSettings(g_settings);  // publish the snapshot for the TIP
        addKeyboardForUser();
        setAutostart(true);
        writeFlag(L"userSetupDone", true);
        return 0;
    }
    if (oneShot == 3) return setProfileIcon(g_profileIconArg);  // elevated helper
    if (oneShot == 4) return waitInstall(g_waitPid);             // detached update watcher
    if (oneShot == 2) {  // uninstaller: "gỡ sạch"
        if (HWND h = FindWindowW(kAppWindowClass, nullptr)) PostMessageW(h, WM_CLOSE, 0, 0);
        removeKeyboardForUser();
        setAutostart(false);
        eraseUserData();
        return 0;
    }

    // Single instance: a second launch hands its request to the first and leaves
    // ("yield, not kill" — macOS SingleInstance) — unless the running one is OLDER (an
    // upgrade just replaced the files): then it is asked to quit and this one takes over.
    HANDLE mutex = CreateMutexW(nullptr, TRUE, L"Local\\VietTelex.App");
    if (mutex && GetLastError() == ERROR_ALREADY_EXISTS) {
        HWND h = FindWindowW(kAppWindowClass, nullptr);
        wchar_t title[64] = {};
        if (h) GetWindowTextW(h, title, 64);
        if (h && vtx::decideHandoff(title, vtx::versionForDisplay(VTX_VER_STRING)) == vtx::Handoff::PassToRunning) {
            AllowSetForegroundWindow(ASFW_ANY);
            PostMessageW(h, kAppCommandMsg,
                         cmd ? cmd : (background ? 0 : static_cast<unsigned>(vtx::AppCommand::OpenSettings)), 0);
            CloseHandle(mutex);
            return 0;
        }
        closeRunningApps(GetCurrentProcessId(), vtx::kQuitGraceMs);  // older instance: replace it
    }

    INITCOMMONCONTROLSEX icc = {sizeof icc, ICC_TAB_CLASSES | ICC_LISTVIEW_CLASSES | ICC_LINK_CLASS |
                                                ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&icc);
    allowDarkMenus();

    g_settings = loadSettings();
    setEnglish(g_settings.uiLanguage == "en");
    if (snapshotMissing()) saveSettings(g_settings);
    if (!readFlag(L"userSetupDone")) {  // another user on a per-machine install
        addKeyboardForUser();
        setAutostart(true);
        writeFlag(L"userSetupDone", true);
    }

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof wc;
    wc.lpfnWndProc = mainProc;
    wc.hInstance = inst;
    wc.lpszClassName = kAppWindowClass;
    RegisterClassExW(&wc);
    // Hidden top-level window (not HWND_MESSAGE: those are invisible to FindWindow,
    // which is how the TIP and a second instance reach us).
    const std::wstring mainTitle = vtx::mainWindowTitle(vtx::versionForDisplay(VTX_VER_STRING));  // version for handoff
    g_mainWnd = CreateWindowExW(WS_EX_TOOLWINDOW, kAppWindowClass, mainTitle.c_str(), WS_POPUP, 0, 0, 0, 0, nullptr,
                                nullptr, inst, nullptr);
    if (!g_mainWnd) return 1;
    // The TIP posts from inside other apps, some at lower integrity (UIPI).
    ChangeWindowMessageFilterEx(g_mainWnd, kAppCommandMsg, MSGFLT_ALLOW, nullptr);
    g_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    syncTrayIcon();
    hookSetElevationNotifier(showElevationNotice);
    hookConfigure(g_settings);
    mirrorAppLanguage();  // AppContainer hosts read the per-app Việt/Anh memory from here
    appLog("app", std::string("started ") + VTX_VER_STRING);

    if (cmd) runCommand(cmd);
    else if (!background) showSettings(Tab::Typing);
    if (g_settings.autoUpdateCheck && autoCheckDue()) startUpdateCheck(g_mainWnd, false);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (settingsDialogMessage(&msg)) continue;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    if (mutex) CloseHandle(mutex);
    return 0;
}
