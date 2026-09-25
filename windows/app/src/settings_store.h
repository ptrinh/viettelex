// settings_store.h — VietTelex.exe owns the settings (spec §9):
//   HKCU\Software\VietTelex  one value per key (DWORD / REG_SZ), shortcuts and
//                            appModes as REG_BINARY UTF-8 JSON, plus "snapshot".
//   %LOCALAPPDATA%\VietTelex\settings.bin  the same snapshot, readable from
//                            AppContainers (ALL APPLICATION PACKAGES: read).
// save() writes both; the TIP picks the change up on its next focus change.
#pragma once
#include <string>

#include "settings.h"

namespace vtx::app {

Settings loadSettings();
bool saveSettings(const Settings& s);

// Plain values the app keeps for itself (not part of the TIP snapshot).
unsigned long long readQword(const wchar_t* name, unsigned long long def = 0);
void writeQword(const wchar_t* name, unsigned long long v);
std::wstring readString(const wchar_t* name);
void writeString(const wchar_t* name, const std::wstring& v);
bool readFlag(const wchar_t* name);
void writeFlag(const wchar_t* name, bool v);

// Remove everything under HKCU\Software\VietTelex and %LOCALAPPDATA%\VietTelex
// (uninstall: "gỡ sạch").
void eraseUserData();

std::wstring widen(const std::string& utf8);
std::string narrow(const std::wstring& w);

}  // namespace vtx::app
