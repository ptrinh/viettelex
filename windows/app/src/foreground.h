// foreground.h — who the foreground app is and whether it is in Vietnamese, for the hook
// and the tray (1.1.5), plus the per-app Việt/Anh store on the app side and the app's
// debug log. See direct_policy.h (hostIdentity, foregroundLanguage) and app_language.h.
#pragma once
#include <windows.h>

#include <string>

namespace vtx::app {

struct FgApp {
    std::wstring identity;  // lower-case exe; consoles -> conhost.exe
    std::string windowClass;
    DWORD tid = 0;          // GetWindowThreadProcessId (a console's CLIENT thread)
    DWORD pid = 0;
    bool console = false;
};
FgApp describeWindow(HWND hwnd);

// Vietnamese for the hook / tray (TIP prop first; see foregroundLanguage()).
bool fgVietnamese(HWND fg, const FgApp& app);

// HKCU\Software\VietTelex\AppLanguage\<identity>, default true.
bool storedVietnamese(const std::wstring& identity);
void storeVietnamese(const std::wstring& identity, bool on);
// Rewrites %LOCALAPPDATA%\VietTelex\applang.txt from HKCU (AppContainers read it).
void mirrorAppLanguage();

// debug.log (component = "app", "hook", "direct", "verify"); gated on settings.debugLogging.
void appSetLogging(bool on);
bool appLogging();
void appLog(const char* component, const std::string& msg);

std::string narrowAscii(const std::wstring& w);

}  // namespace vtx::app
