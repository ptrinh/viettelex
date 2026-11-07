// input_switch.h — what Settings says about remembering Việt/Anh per app (1.1.5).
//
// Two different mechanisms, depending on how the user switches:
//   * in-TIP switch (Ctrl+Shift, Alt+Z, tray): VietTelex remembers Việt/Anh per app
//     itself (app_language.h);
//   * Windows input source (Win+Space, the taskbar VIE/ENG button, VietTelex <-> ENG):
//     Windows decides. Per-app memory is its "Let me use a different input method for
//     each app window" option = SystemParametersInfo(SPI_GET/SETTHREADLOCALINPUTSETTINGS)
//     (documented since Windows 8; stored per user, default off = one input method for
//     the whole session).
// Pure; unit-tested. The Win32 side is in settings_window.cpp.
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

#include "hotkey.h"

namespace vtx {

enum class PerAppInput { On, Off, Unknown };

// SPI_GETTHREADLOCALINPUTSETTINGS result -> state (call failed = Unknown).
inline PerAppInput perAppInputFromSpi(bool callSucceeded, int value) {
    if (!callSucceeded) return PerAppInput::Unknown;
    return value ? PerAppInput::On : PerAppInput::Off;
}

// Which sentence describes the switch-hotkey choice.
enum class HotkeyNote {
    TipRemembers,     // Ctrl+Shift / Alt+Z: VietTelex remembers per app
    WindowsPerApp,    // Win+Space or Off, Windows option on: each app window keeps its own
    WindowsGlobal,    // Win+Space or Off, Windows option off: one input method everywhere
    WindowsUnknown,   // …option unreadable
};
HotkeyNote hotkeyNote(SwitchHotkey h, PerAppInput windows);

// What the "per-app input method (Windows)" card's button does.
enum class PerAppAction { None, Enable, OpenSettings };
inline PerAppAction perAppAction(PerAppInput s) {
    return s == PerAppInput::On ? PerAppAction::None
                                : s == PerAppInput::Off ? PerAppAction::Enable : PerAppAction::OpenSettings;
}
// After an Enable attempt, re-read: still not On -> open Windows Settings instead.
inline bool enableNeedsSettingsPage(PerAppInput afterSet) { return afterSet != PerAppInput::On; }

// Windows Settings page holding "Advanced keyboard settings" (Windows 10 1803+ and 11:
// Typing; the option itself is under Advanced keyboard settings there).
constexpr const wchar_t* kTypingSettingsUri = L"ms-settings:typing";

// ---- Ctrl+Shift while ANOTHER keyboard is active (2026-10 field report) ---------------
// "Mở ứng dụng lên thì phải Win+Space về VietTelex rồi mới Ctrl+Shift được": the Ctrl+Shift
// chord is recognised inside the TIP's key sink, which only runs while VietTelex is the
// window's active input profile. With "different input method for each app window" on
// and another keyboard (ENG) as Windows' default input method, every new window starts on
// ENG and the chord does nothing. Two fixes:
//   1. (root cause, one click, with consent) make VietTelex Windows' default input method
//      — SetDefaultLayoutOrTip (input.dll) — so new windows start in VietTelex;
//   2. (always) VietTelex.exe watches the Ctrl+Shift chord with its low-level hook (observe
//      only, never eats a key) and, when the foreground window is NOT in VietTelex, asks
//      that window to switch to the Vietnamese input language (WM_INPUTLANGCHANGEREQUEST,
//      what the taskbar language indicator does) and stores Việt for the app.
constexpr unsigned kLangViVN = 0x042A;

// Held modifier set (hotkey.h kMod* bits) after a low-level key event: `before` = state
// read with GetAsyncKeyState (not yet updated for this event), `vk` = the event's key.
uint8_t chordHeldAfter(uint8_t before, unsigned vk, bool down);
bool isChordModifierVk(unsigned vk);

// Install the observe-only chord watcher? Only for the Ctrl+Shift choice (Alt+Z is a
// PreserveKey of the TIP — eating it in other keyboards would break apps' Alt+Z).
inline bool chordWatcherWanted(SwitchHotkey h) { return h == SwitchHotkey::CtrlShift; }

// Which low-level hooks VietTelex.exe's hook thread keeps installed (2026-10 perf audit H1).
//   keyboard: typing (hook / Direct mode) or the observe-only chord watcher;
//   mouse:    typing (a click resets the word), or — for the watcher alone — ONLY while
//             Ctrl+Shift are held together (chord armed: a click then cancels the toggle).
//             A permanent WH_MOUSE_LL woke the high-priority hook thread on every mouse
//             move for every default install.
//   suspended (game / fullscreen / Chế độ game): nothing — every key passes anyway and the
//             chord is ignored there (foreignChordAction).
// Raw input (the hook watchdog's second key signal) is registered exactly while the
// keyboard hook is.
struct HookNeeds {
    bool keyboard = false;
    bool mouse = false;
};
inline HookNeeds hookNeeds(bool typing, bool watchChord, bool chordArmed, bool suspended) {
    HookNeeds n;
    if (suspended) return n;
    n.keyboard = typing || watchChord;
    n.mouse = typing || (watchChord && chordArmed);
    return n;
}

// The watcher saw the chord complete (ModifierChord::note returned true). Toggle only on
// the release, outside games, and with no mouse button held (Ctrl+Shift+drag / click
// selection — a click that arrived before the mouse hook was in).
inline bool chordToggleAllowed(bool completed, bool keyDown, bool suspended, bool mouseButtonHeld) {
    return completed && !keyDown && !suspended && !mouseButtonHeld;
}

enum class ForeignChord { Ignore, ActivateVietTelex };
// The chord completed. `tipProp` = kTipLangProp on the foreground root (1/2 = the TIP is
// active there: it toggles by itself), `fgLangId` = LOWORD(GetKeyboardLayout(thread)) of
// the foreground thread (0 = unknown), `suspended` = game / fullscreen / Chế độ game.
// Both TIP signals must say "not VietTelex" — a UWP CoreWindow carries the prop on a
// different root than the frame, and its thread layout is still vi-VN.
ForeignChord foreignChordAction(SwitchHotkey h, int tipProp, unsigned fgLangId, bool suspended);

// The input-locale handle to request for Vietnamese: the first HKL of the user's list whose
// language is vi-VN (GetKeyboardLayoutList), 0 = VietTelex/Vietnamese is not in the list.
uintptr_t pickVietnameseHkl(const uintptr_t* hkls, size_t count);

// "Make VietTelex the default input method" card (Kiểu gõ page). `defaultLangId` =
// LOWORD of SPI_GETDEFAULTINPUTLANG (0 = unknown). Only for the in-TIP hotkeys: with
// Win+Space the user switches through Windows anyway.
enum class DefaultInputAdvice { None, MakeVietTelexDefault };
DefaultInputAdvice defaultInputAdvice(SwitchHotkey h, unsigned defaultLangId);
// SetDefaultLayoutOrTip profile-list string "0x042A:{CLSID}{PROFILE}" (documented format).
std::string defaultLayoutOrTipSpec(unsigned langId, const std::string& clsid, const std::string& profile);

// ---- "Override for default input method" (Windows 8+; field report 1.3.14) -------------
// Windows Settings → Typing → Advanced keyboard settings → "Override for default input
// method": the keyboard every new window starts with, whatever the language order. The
// reporter (Windows 10, fresh 1.3.14) still had to pick "Vietnamese - VietTelex" there by
// hand after SetDefaultLayoutOrTip. The documented per-user setter is PowerShell's
// Set-WinDefaultInputMethodOverride -InputTip "<LANGID>:{CLSID}{PROFILE}" (International
// module, no admin); Windows keeps it in HKCU\Control Panel\International\User Profile,
// value InputMethodOverride (read back to check).
std::string inputMethodOverrideSpec(unsigned langId, const std::string& clsid, const std::string& profile);
enum class OverrideState {
    None,       // no override: the first language's default keyboard
    VietTelex,  // the override is VietTelex
    Other,      // another keyboard (e.g. Windows' own Vietnamese one) is forced as default
};
// `present` = the registry value exists. Case-insensitive; "0x" and a trailing ';' tolerated.
OverrideState overrideState(bool present, const std::string& value, unsigned langId, const std::string& clsid,
                            const std::string& profile);
// powershell.exe arguments that set it (spec from inputMethodOverrideSpec: hex + GUIDs only).
std::string setOverrideArgs(const std::string& spec);
// The Kiểu gõ card with the override known: VietTelex there -> nothing to offer; another
// keyboard forced -> offer (even when that keyboard is a Vietnamese one: the default
// language is then vi-VN although VietTelex is not what new windows get); none -> by
// language as before.
DefaultInputAdvice defaultInputAdvice(SwitchHotkey h, unsigned defaultLangId, OverrideState o);

// Welcome window: pre-tick "make VietTelex the default input method"? Same rule as the
// Kiểu gõ card — a fresh install leaves Windows on the old keyboard (ENG), and a UniKey
// user has never needed Win+Space, so nothing types Vietnamese until it is switched.
inline bool welcomeOffersDefaultInput(SwitchHotkey h, unsigned defaultLangId) {
    return defaultInputAdvice(h, defaultLangId) == DefaultInputAdvice::MakeVietTelexDefault;
}

// ---- Windows' own Ctrl+Shift (2026-10 field report, UniKey user) -----------------------
// "Không gõ được tiếng Việt, không chuyển được Việt/Anh dù đã đặt Ctrl+Shift." Windows has
// two input hotkeys of its own, in HKCU\Keyboard Layout\Toggle (REG_SZ "1".."4"):
//   "Language Hotkey" (older builds: "Hotkey")  between input languages   (VIE <-> ENG)
//   "Layout Hotkey"                              between keyboards of one language
// 1 = Left Alt+Shift, 2 = Ctrl+Shift, 3 = not assigned, 4 = grave accent (`).
// Defaults when a value is absent: language = Left Alt+Shift, layout = Ctrl+Shift.
// With VietTelex's Ctrl+Shift:
//   * language = Ctrl+Shift: one press flips VietTelex Việt->Anh AND Windows VIE->ENG; the
//     next press brings VIE back with VietTelex still in Anh (remembered per app). The
//     taskbar says VIE and nothing types Vietnamese.
//   * layout = Ctrl+Shift (the default) and another Vietnamese keyboard in the list
//     (Microsoft Vietnamese Telex, the legacy layout): the press also jumps from VietTelex
//     to that keyboard.
// Fix (only on the user's click): move Windows' hotkeys off Ctrl+Shift, then
// SystemParametersInfo(SPI_SETLANGTOGGLE) so Windows re-reads them (documented).
enum class WinToggle : uint8_t { AltShift = 1, CtrlShift = 2, None = 3, Grave = 4 };
// One registry value; `present` false (missing) or anything but "1".."4" -> `dflt`.
WinToggle parseWinToggle(bool present, const std::string& value, WinToggle dflt);
const char* winToggleValue(WinToggle t);  // "1".."4"

struct WinToggles {
    WinToggle language = WinToggle::AltShift;
    WinToggle layout = WinToggle::CtrlShift;
};
// From the raw values: "Language Hotkey" wins over the legacy "Hotkey".
WinToggles readWinToggles(bool hasLanguage, const std::string& language, bool hasLegacy, const std::string& legacy,
                          bool hasLayout, const std::string& layout);

enum class WinHotkeyClash { None, LanguageSwitch, LayoutSwitch };
WinHotkeyClash winHotkeyClash(SwitchHotkey ours, const WinToggles& w, bool otherVietnameseKeyboard);

// The values to write: Ctrl+Shift between languages -> Left Alt+Shift (Windows' default);
// a Ctrl+Shift layout hotkey, or one now equal to the language hotkey -> not assigned.
struct WinToggleFix {
    bool changeLanguage = false;
    WinToggle language = WinToggle::AltShift;
    bool changeLayout = false;
    WinToggle layout = WinToggle::None;
};
WinToggleFix winToggleFix(const WinToggles& w);

}  // namespace vtx
