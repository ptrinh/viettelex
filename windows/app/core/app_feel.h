// app_feel.h — "cài xong là gõ được, dùng như một app" (docs/WINDOWS-APP-FEEL-SPEC.md):
// the portable decisions behind the installed build's app-like shell. Unit-tested on any
// OS; the Win32/TSF calls that carry them out are app/src/main.cpp, tip_control.cpp and
// welcome.cpp (kept thin, see the spec's "Kiểm thử").
//
//   §1 keyboard on at start   planKeyboardAtStart
//   §2 tray on for new users  isNewUser / applyNewUserDefaults
//   §2/§3 tray V / E / off    trayStateFor / trayClickAction
//   §4 minimal welcome        welcomeResolveRow
//   §5 Thoát from the tray    pickExitLayout
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "onboarding.h"
#include "settings.h"

namespace vtx {

// ---- §1 VietTelex added, made the default and selected ---------------------------------
// When VietTelex.exe starts (any start: interactive, autostart, after the MSI):
//   portable / SYSTEM / TIP not registered  -> nothing (no TSF keyboard to manage)
//   VietTelex missing from the user's list  -> add + default + select (it was removed, or
//                                              a Store install never reached this user)
//   first run (the welcome shows now)       -> add (idempotent) + default + select
//   left with tray "Thoát" last time        -> select again ("mở lại app = bật lại")
//   otherwise                               -> nothing: an existing user's choice of
//                                              default keyboard is never touched
// Nothing is ever removed from the user's list.
struct KeyboardStatus {
    bool portable = false;
    bool systemAccount = false;
    bool tipRegistered = true;     // HKLM/HKCR registration of the TIP exists
    bool inUserList = false;       // VietTelex enabled in this user's vi-VN list
    bool firstRun = false;         // decideWelcome == Show for this start
    bool reselectPending = false;  // HKCU reselectOnStart (written by tray Thoát)
};
struct KeyboardPlan {
    bool add = false;              // InstallLayoutOrTip
    bool makeDefault = false;      // SetDefaultLayoutOrTip
    bool select = false;           // activate for the session + the foreground window
    bool rememberPrevious = false; // store the keyboard in use now (Thoát returns to it)
};
KeyboardPlan planKeyboardAtStart(const KeyboardStatus& s);

// ---- §2 tray icon on for NEW users only ---------------------------------------------------
// New = nothing stored for this user yet (no settings, never set up, welcome never shown).
// Existing users keep their saved showTrayIcon, whatever it is.
bool isNewUser(bool settingsStored, bool setupDone, bool welcomeShown);
// The values a new user starts with on top of Settings' defaults (shared with the TIP, so
// they cannot simply change there): the tray icon is on.
void applyNewUserDefaults(Settings& s);

// ---- start without the Settings window (#159) ---------------------------------------------
// A start with no command: does the Settings window open? `background` = --background
// (autostart), `explicitSettings` = --settings (installer, tray), `startHidden` = the user's
// "Mở app không hiện cửa sổ Cài đặt". A second start while the app runs is not decided here:
// it always opens Settings, so a user with the tray icon hidden is never locked out.
bool opensSettingsAtStart(bool background, bool explicitSettings, bool startHidden);

// ---- §2/§3 tray icon state + left click ---------------------------------------------------
enum class TrayState { Vietnamese, English, Off };
// `tipProp` = kTipLangProp on the foreground root (1 VI, 2 EN, 0 none), `fgLangId` =
// LOWORD(GetKeyboardLayout(foreground thread)) (0 = unknown), `storedVietnamese` = the
// per-app Việt/Anh memory, `alwaysEnglish` = the app's mode is "Luôn tiếng Anh".
// Installed: the TIP says it, else another keyboard selected -> Off, else the memory.
//   A console window without the prop stays English (its thread's layout is cmd's, not
//   conhost's — never claim "off" from it).
// Portable: Off while it yields (portableYields: the installed TIP or another Vietnamese
//   keyboard is active there), English for "Luôn tiếng Anh", else the memory.
TrayState trayStateFor(bool portable, int tipProp, bool console, unsigned fgLangId, bool storedVietnamese,
                       bool alwaysEnglish);

enum class TrayClick {
    ToggleLanguage,      // V <-> E for the app the user came from
    SelectVietTelex,     // installed, Off: switch that window (and the session) to VietTelex
    SwitchToEnglishKeys, // portable, Off: give that window an English layout, then type
};
TrayClick trayClickAction(TrayState state, bool portable);

// ---- §4 the minimal welcome's "Xử lý" row ---------------------------------------------------
// Only a running Vietnamese input method or Windows' own Vietnamese keyboard in the list
// show it (Windows' Ctrl+Shift clash alone does not: the Kiểu gõ page card covers it).
enum class ResolveRow { None, OtherInputMethod, WindowsKeyboard, Both };
ResolveRow welcomeResolveRow(const std::vector<ConflictKind>& found);

// The one-button "remove Windows' built-in Vietnamese keyboard" (welcome row, conflict
// dialog; field report 1.3.14: removing it by hand was confusing). The InstallLayoutOrTip
// ILOT_UNINSTALL specs for every OTHER enabled Vietnamese profile of the user's list, each
// once — never VietTelex, never a profile that cannot be expressed (those stay for
// Windows Settings). Only the user's own list; Windows keeps the keyboard installed.
// Third-party input methods are never in here (they are processes, not profiles).
std::vector<std::string> builtInKeyboardRemovals(const std::vector<ViProfile>& found, const std::string& ourClsid);

// ---- §5 Thoát: back to the keyboard used before VietTelex, else English -------------------
// `hkls` = GetKeyboardLayoutList, `saved` = HKL stored when VietTelex was selected (0 =
// none). The saved one if still in the list and not Vietnamese; else US English (0x0409);
// else the first non-Vietnamese layout; else 0 (nothing to switch to).
uintptr_t pickExitLayout(const uintptr_t* hkls, size_t count, uintptr_t saved);
// Worth storing as "the keyboard before VietTelex": a real, non-Vietnamese layout.
inline bool rememberableLayout(uintptr_t hkl) { return hkl != 0 && (hkl & 0xFFFF) != 0x042A; }

}  // namespace vtx
