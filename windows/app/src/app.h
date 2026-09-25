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

}  // namespace vtx::app
