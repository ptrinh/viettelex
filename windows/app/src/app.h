// app.h — state shared by the tray app's modules (single UI thread).
#pragma once
#include <windows.h>

#include "settings.h"

namespace vtx::app {

extern HINSTANCE g_inst;
extern HWND g_mainWnd;  // hidden message window (class kAppWindowClass)
extern Settings g_settings;

// Persist g_settings, publish the snapshot to the TIP, re-apply locally.
void settingsChanged();

// Settings window (settings_window.cpp).
enum class Tab : int { Typing = 0, Spelling, Shortcuts, Apps, About };
void showSettings(Tab tab = Tab::Typing);
void refreshSettingsWindow();  // settings changed elsewhere (e.g. TIP menu)
bool settingsDialogMessage(MSG* msg);
bool settingsWindowOpen();

// Dark mode helpers (settings_window.cpp).
bool systemUsesDarkApps();

// Shortcut import with a file picker: VietTelex/macOS files and other input methods' macro
// files, UTF-8 or UTF-16 (settings_window.cpp; also the welcome window's import button).
void importShortcutsDialog(HWND owner);

// First-run welcome window (welcome.cpp, WINDOWS-APP-FEEL-SPEC §4): one page — "Đã sẵn
// sàng — gõ thử ở đây", how to switch, and a "Xử lý" row only when another Vietnamese
// input method / Windows' own Vietnamese keyboard is found (app_feel.h welcomeResolveRow).
void showWelcome();
bool welcomeDialogMessage(MSG* msg);
bool welcomeWindowOpen();

// Hand the idle working set back to Windows a few seconds from now, once no window is open
// and the user is not typing (core/idle_trim.h; main.cpp). Called after start and whenever
// Settings / the welcome window closes.
void requestIdleTrim();

}  // namespace vtx::app
