// tip_control.h — per-user setup the per-machine MSI cannot do: add the VietTelex
// keyboard to the current user's language list, autostart, and clean removal.
#pragma once
#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

#include "input_switch.h"

namespace vtx::app {

bool addKeyboardForUser();     // InstallLayoutOrTip("042A:{CLSID}{PROFILE}")
bool removeKeyboardForUser();  // same with ILOT_UNINSTALL
// Make VietTelex Windows' default input method for this user (SetDefaultLayoutOrTip, then
// the "Override for default input method" registry value if it does not already name
// VietTelex): new app windows then start in VietTelex (input_switch.h,
// 2026-10 Ctrl+Shift report; 1.3.14 field report). True = the override names VietTelex
// (or, where it cannot be read, SetDefaultLayoutOrTip succeeded). Starts no other process.
bool setDefaultKeyboardForUser();
// HKCU\Control Panel\International\User Profile\InputMethodOverride vs VietTelex.
OverrideState inputMethodOverride();
// LOWORD of SPI_GETDEFAULTINPUTLANG (the default input language), 0 = unreadable.
unsigned defaultInputLangId();
// Remove another layout/TIP from this user's list ("042A:{CLSID}{PROFILE}" / "042A:0000042A").
bool removeLayoutOrTipForUser(const std::wstring& spec);
// This process runs as LocalSystem (an MSI custom action of a Store / Intune / msiexec /qn
// install): its HKCU belongs to no person.
bool runningAsSystem();
void setAutostart(bool on);    // HKCU\...\Run "VietTelex" = "<exe>" --background
bool autostartEnabled();
std::wstring autostartValue();  // the Run value ("" = none)
std::wstring selfExePath();

// ---- app feel (core/app_feel.h; not yet run on real Windows, see tip_control.cpp) -------
// VietTelex enabled in this user's list; `registered` = the TIP's profile exists at all.
bool vietTelexInUserList(bool& registered);
// Language ids of the enabled text services (TIPs) other than VietTelex in the languages
// of the user's list, one entry per profile (debug-log header: counts, no names).
std::vector<unsigned> otherEnabledTextServiceLangs();
// ITfInputProcessorProfileMgr::ActivateProfile(TF_IPPMF_FORSESSION): VietTelex / a layout
// becomes the session's current input method.
bool selectVietTelexForSession();
bool activateLayoutForSession(uintptr_t hkl);
uintptr_t defaultInputHkl();               // SPI_GETDEFAULTINPUTLANG (0 = unknown)
std::vector<uintptr_t> keyboardLayouts();  // GetKeyboardLayoutList
// WM_INPUTLANGCHANGEREQUEST to the window's focused control (what the taskbar language
// button does); per thread, so it also works with "different input method per app window".
bool requestInputLanguage(HWND window, uintptr_t hkl);

}  // namespace vtx::app
