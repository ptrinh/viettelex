// settings_store.h — VietTelex.exe owns the settings (spec §9):
//   HKCU\Software\VietTelex  one value per key (DWORD / REG_SZ), shortcuts and
//                            appModes as REG_BINARY UTF-8 JSON, plus "snapshot".
//   %LOCALAPPDATA%\VietTelex\settings.bin  the same snapshot, readable from
//                            AppContainers (ALL APPLICATION PACKAGES: read).
// save() writes both; the TIP picks the change up on its next focus change.
//
// Portable build (core/portable.h): the same values live in settings.ini next to the exe
// (fallback %APPDATA%\VietTelex\settings.ini) — never in HKCU\Software\VietTelex, and no
// snapshot is published (there is no TIP; writing settings.bin would overwrite the
// INSTALLED build's snapshot on a PC that has both).
#pragma once
#include <string>

#include "settings.h"

namespace vtx::app {

// Pick the backend: call once, before any other function here. `portableIni` = the
// settings.ini path (portable::settingsPath), ignored when `portable` is false.
void initStorage(bool portable, const std::wstring& portableIni);
bool portableMode();
// Some value is stored for this user already (any VietTelex version wrote settings).
bool settingsStored();
// Portable per-app Việt/Anh memory ("AppLanguage\<identity>" in settings.ini). Thread-safe
// (the hook thread reads it at each word start). False = nothing stored for that app.
bool portableAppLanguage(const std::wstring& identity, bool& vietnamese);
void setPortableAppLanguage(const std::wstring& identity, bool vietnamese);

// loadSettings() also fills Settings::systemTextPrediction from Windows' own setting
// (readSystemTextPrediction); saveSettings() never stores that mirror under VietTelex.
Settings loadSettings();
bool readSystemTextPrediction();
bool saveSettings(const Settings& s);

// Plain values the app keeps for itself (not part of the TIP snapshot).
unsigned long long readQword(const wchar_t* name, unsigned long long def = 0);
void writeQword(const wchar_t* name, unsigned long long v);
std::wstring readString(const wchar_t* name);
void writeString(const wchar_t* name, const std::wstring& v);
bool readFlag(const wchar_t* name);
// -1 = value absent, else 0 / 1 (onboardingDone: absent and 0 mean different things).
int readFlagState(const wchar_t* name);
void writeFlag(const wchar_t* name, bool v);

// Remove everything under HKCU\Software\VietTelex and %LOCALAPPDATA%\VietTelex
// (uninstall: "gỡ sạch").
void eraseUserData();

std::wstring widen(const std::string& utf8);
std::string narrow(const std::wstring& w);

}  // namespace vtx::app
