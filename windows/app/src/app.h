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

// Dark mode helpers (settings_window.cpp).
bool systemUsesDarkApps();

// Shortcut import with a file picker: VietTelex/macOS files and UniKey / OpenKey macro
// files, UTF-8 or UTF-16 (settings_window.cpp; also the welcome window's "Chuyển từ UniKey").
void importShortcutsDialog(HWND owner);

// First-run welcome window (welcome.cpp).
void showWelcome();
bool welcomeDialogMessage(MSG* msg);

}  // namespace vtx::app
