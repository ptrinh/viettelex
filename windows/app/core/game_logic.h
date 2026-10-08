// game_logic.h — games and fullscreen apps, the floating Việt/Anh indicator: the portable
// decisions (unit-tested on any OS). Win32 side: app/src/game_mode.cpp (foreground watch,
// hotkey, telling the TIP) and app/src/switch_toast.cpp (the indicator window). The TIP
// side of "stand aside" is ime/core/game_ipc.h.
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

namespace vtx {

// ---- Tự tắt tiếng Việt khi chơi game / toàn màn hình (Settings::autoOffFullscreen) ----
// SHQueryUserNotificationState values (shellapi.h QUERY_USER_NOTIFICATION_STATE).
enum class Quns : int {
    Unknown = 0,
    NotPresent = 1,        // screen saver / locked / fast user switching
    Busy = 2,              // a fullscreen app — ALSO Chrome F11, YouTube fullscreen, video players
    D3DFullScreen = 3,     // an exclusive-mode Direct3D app (games)
    PresentationMode = 4,  // the user turned on Windows presentation settings
    AcceptsNotifications = 5,
    QuietTime = 6,
    App = 7,               // a Windows Store app is running
};

// What VietTelex.exe sees of the foreground window when it changes (and in the few
// one-shot re-checks after that, fullscreenRecheckDelaysMs).
struct ForegroundProbe {
    int quns = 0;               // SHQueryUserNotificationState, 0 if the call failed
    bool coversMonitor = false; // window rect contains its monitor's full rect
    bool hasCaption = true;     // WS_CAPTION
    bool shellOrDesktop = false;// Progman / WorkerW / Shell_TrayWnd …: never a game
    bool ownProcess = false;    // our own Settings / welcome window
};

// Stand aside (the TIP and the hook eat nothing) for this foreground window? Default ON,
// but only for what is certainly a game or a slideshow:
//   * QUNS_RUNNING_D3D_FULL_SCREEN — exclusive fullscreen Direct3D;
//   * QUNS_PRESENTATION_MODE, and only while the foreground itself is a captionless window
//     covering its monitor (the system-wide setting alone must not turn off typing in a
//     normal window during a talk).
// QUNS_BUSY is NEVER enough: it is also what borderless fullscreen browsers (Chrome F11,
// YouTube fullscreen) and video players report, and people type there. Borderless games
// therefore are not detected; the per-app "Tắt" mode (Ứng dụng) and Chế độ game cover them.
bool fullscreenSuspends(bool settingOn, const ForegroundProbe& p);

// Window rect (screen coordinates) covers the whole monitor rect.
struct Rect {
    long left = 0, top = 0, right = 0, bottom = 0;
};
bool coversMonitor(const Rect& window, const Rect& monitor);

// A game usually becomes exclusive-fullscreen a moment AFTER its window comes to the
// foreground. So when the new foreground covers its monitor but is not (yet) suspended,
// re-check a few times — bounded one-shot timers, never a poll, nothing on the key path.
constexpr unsigned kFullscreenRecheckDelaysMs[] = {300, 1500, 4000};
constexpr size_t kFullscreenRecheckCount = sizeof(kFullscreenRecheckDelaysMs) / sizeof(kFullscreenRecheckDelaysMs[0]);
inline bool fullscreenRecheckWanted(bool settingOn, const ForegroundProbe& p, bool suspendedNow) {
    return settingOn && !suspendedNow && p.coversMonitor && !p.shellOrDesktop && !p.ownProcess;
}

// Which window is currently told to stand aside, and what to tell whom when the foreground
// (or its fullscreen state) changes. Windows are opaque ids (HWND values).
class FullscreenTracker {
public:
    struct Step {
        uintptr_t resume = 0;   // remove the suspension from this window (0 = none)
        uintptr_t suspend = 0;  // suspend this window (0 = none)
    };
    Step update(uintptr_t foreground, bool suspendHere);
    Step clear();  // setting turned off / app quitting: resume whatever is suspended
    uintptr_t suspended() const { return suspended_; }

private:
    uintptr_t suspended_ = 0;
};

// ---- Chế độ game hotkey (settings gameModeHotkey) ------------------------------------
// A global toggle (RegisterHotKey on VietTelex.exe) for "pass every key through", for
// borderless games the automatic check cannot see. Default OFF: a RegisterHotKey steals
// its chord from every app, and Ctrl+Alt+<letter> is AltGr+<letter> on keyboard layouts
// with AltGr. Never offered: Win+G / Win+Alt+G (Xbox Game Bar), Ctrl+Shift (the Việt/Anh
// chord), Ctrl+Alt+T/Ctrl+Shift+T (Thêm dấu choices).
struct GameHotkeyChoice {
    const char* id;
    unsigned mods;  // MOD_ALT 1, MOD_CONTROL 2, MOD_SHIFT 4, MOD_WIN 8
    unsigned vk;
    const wchar_t* label;  // nullptr = "off" (localised by the caller)
};
constexpr GameHotkeyChoice kGameModeHotkeys[] = {
    {"off", 0, 0, nullptr},
    {"ctrl-alt-g", 0x2 | 0x1, 'G', L"Ctrl+Alt+G"},
    {"ctrl-shift-alt-g", 0x2 | 0x4 | 0x1, 'G', L"Ctrl+Shift+Alt+G"},
};
constexpr size_t kGameModeHotkeyCount = sizeof(kGameModeHotkeys) / sizeof(kGameModeHotkeys[0]);
size_t gameModeHotkeyIndex(const std::string& id);  // unknown -> 0 ("off")
bool gameModeHotkeyKeys(const std::string& id, unsigned& mods, unsigned& vk);  // false = nothing to register

// ---- Floating V/E indicator (settings switchIndicator) -------------------------------
// "auto" (default): shown while the tray icon is hidden (the default since 1.0.5), since
// then nothing else on screen says which language you just switched to; with the tray
// icon the icon already does. "on" / "off" force it.
enum class SwitchIndicator : uint8_t { Auto, On, Off };
SwitchIndicator parseSwitchIndicator(const std::string& s);
const char* switchIndicatorName(SwitchIndicator v);

// Show it for this switch? Only on a user switch (Ctrl+Shift / Alt+Z / Chế độ game),
// never during a fullscreen game or slideshow, never while keys pass through.
bool showSwitchToast(SwitchIndicator setting, bool trayIconShown, bool suspended, int quns);

// Where: just below the caret when the app reports one, else the bottom-right corner of
// the work area; always kept inside the work area. Returns the top-left corner.
struct Point {
    long x = 0, y = 0;
};
Point toastPosition(bool caretKnown, const Rect& caret, const Rect& workArea, long width, long height, long margin);

constexpr unsigned kSwitchToastMs = 1000;  // auto-hide

}  // namespace vtx
