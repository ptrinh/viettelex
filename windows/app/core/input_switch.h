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

}  // namespace vtx
