// config.h — process-wide TIP configuration: settings snapshot, this process's exe
// name / app mode, and the per-app Vietnamese/English memory.
//
// The TIP never parses the registry settings the app owns; it reads the binary
// snapshot %LOCALAPPDATA%\VietTelex\settings.bin (written by VietTelex.exe, readable
// from AppContainers). Reload is event-driven: activation, focus changes, and right
// after a menu command — a cheap file-time check, no timer, no polling thread.
#pragma once
#include <string>

#include "app_policy.h"
#include "globals.h"
#include "settings.h"

namespace vtx::tip::config {

// Call from ActivateEx. `secure` = TF_TMAE_SECUREMODE (UAC / lock screen): defaults
// only, never touches user data.
void init(bool secure);

// Re-read settings.bin if its timestamp changed. Returns the settings generation
// (incremented on every successful change); callers copy settings when it moves.
unsigned long refresh();
unsigned long generation();
Settings copySettings();

bool secureMode();
bool inAppContainer();
const std::string& exeName();  // lowercase, e.g. "notepad.exe"
AppMode appMode();             // resolved for exeName() with current overrides

// Per-app Vietnamese/English memory (default Vietnamese). Stored under
// HKCU\Software\VietTelex\AppLanguage\<exe> (DWORD) outside AppContainer/secure mode.
bool vietnamese();
void setVietnamese(bool on);
void reloadVietnamese();  // pick up a toggle made in another process of the same app
// The app a focused context belongs to, when the process is only a host (WebView2):
// per-app mode and Việt/Anh memory then follow that app. See appIdentity().
void setActiveApp(const std::wstring& exeBaseName);

// Debug log (settings.debugLogging): OutputDebugString only, never typed characters.
void log(const char* msg);

}  // namespace vtx::tip::config
