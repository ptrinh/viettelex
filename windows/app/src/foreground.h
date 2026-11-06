// foreground.h — who the foreground app is and whether it is in Vietnamese, for the hook
// and the tray (1.1.5), plus the per-app Việt/Anh store on the app side and the app's
// debug log. See direct_policy.h (hostIdentity, foregroundLanguage) and app_language.h.
#pragma once
#include <windows.h>

#include <string>

#include "hotkey.h"

namespace vtx::app {

struct FgApp {
    std::wstring identity;  // lower-case exe; consoles -> conhost.exe
    std::string windowClass;
    DWORD tid = 0;          // GetWindowThreadProcessId (a console's CLIENT thread)
    DWORD pid = 0;
    bool console = false;
};
FgApp describeWindow(HWND hwnd);

// Vietnamese for the hook / tray (TIP prop first; see foregroundLanguage()). Portable:
// the app's own memory unless it yields there (core/portable.h).
bool fgVietnamese(HWND fg, const FgApp& app);
// kTipLangProp on the window's root (1 VI, 2 EN, 0 none) and its thread's input language
// (LOWORD of GetKeyboardLayout, 0 unknown).
int fgTipProp(HWND fg);
unsigned fgLangId(const FgApp& app);
// Portable: the state of an app with no memory yet (!Settings::startEnglish).
void setPortableDefaultVietnamese(bool on);
// The thread's focused control is a classic Win32 password box (core/portable.h).
bool focusedPasswordField(DWORD tid);

// HKCU\Software\VietTelex\AppLanguage\<identity>, default true (portable: settings.ini).
bool storedVietnamese(const std::wstring& identity);
void storeVietnamese(const std::wstring& identity, bool on);
// Rewrites %LOCALAPPDATA%\VietTelex\applang.txt from HKCU (AppContainers read it).
void mirrorAppLanguage();

// The Ctrl+Shift chord completed (hook_fallback.cpp watcher). When the foreground window
// is on ANOTHER keyboard (input_switch.h foreignChordAction): store Việt for that app and
// ask the window for the Vietnamese input language. True = requested (show "V").
bool activateVietTelexForChord(SwitchHotkey hotkey, bool suspended);

// debug.log (component = "app", "hook", "direct", "verify"); gated on settings.debugLogging.
void appSetLogging(bool on);
bool appLogging();
void appLog(const char* component, const std::string& msg);

std::string narrowAscii(const std::wstring& w);

}  // namespace vtx::app
