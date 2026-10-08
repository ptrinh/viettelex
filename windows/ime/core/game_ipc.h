// game_ipc.h — "pass every key through" (game / fullscreen) between VietTelex.exe and the
// TIP. Portable part; the Win32 sides are app/src/game_mode.cpp and ime/src/text_service.cpp.
//
// Two reasons can make a TIP stand aside, both decided by VietTelex.exe:
//   kSuspendFullscreen  the window this TIP types in is an exclusive (D3D) fullscreen app
//                       or game (app/core/game_logic.h fullscreenSuspends) — Tự tắt tiếng
//                       Việt khi chơi game / toàn màn hình;
//   kSuspendGameMode    the user's "Chế độ game" hotkey is on (Settings::gameMode).
//
// Delivery, all event-driven (no polling, nothing on the key path but one bool read):
//   * app -> TIP window of the target thread (textToolWindowTitle(tid), the window Công cụ
//     văn bản already uses): PostMessage(kTipSuspendMsg, reasons, 0). The TIP keeps the
//     bits and re-reads the settings snapshot (gameMode) at once.
//   * kSuspendProp on the game's top-level window: a TIP that activates or gets focus there
//     LATER (Win+Space into VietTelex inside the game) reads it in OnSetFocus — not per key.
//   * Settings::gameMode in the snapshot: every other process picks it up on its next
//     focus change like any other setting.
// While suspended the TIP eats nothing (also not Ctrl+Shift / Alt+Z: games bind them), and
// a word in progress is committed as typed. Leaving restores nothing because nothing was
// changed: the Việt/Anh state of the app is never touched.
#pragma once
#include <cstdint>

namespace vtx {

constexpr unsigned kTipSuspendMsg = 0x8000u + 0x5Eu;  // WM_APP + 0x5E: wParam = reason bits
constexpr const wchar_t* kSuspendProp = L"VietTelex.Suspend";  // value = reason bits (non-zero)

enum : uint32_t {
    kSuspendFullscreen = 1u,
    kSuspendGameMode = 2u,
    kSuspendMask = kSuspendFullscreen | kSuspendGameMode,
};

// The TIP's view: `posted` = bits from kTipSuspendMsg / kSuspendProp (fullscreen only —
// game mode comes from the snapshot so it reaches every process), `gameModeSetting` =
// Settings::gameMode. True = eat nothing.
inline bool tipSuspended(uint32_t posted, bool gameModeSetting) {
    return ((posted & kSuspendMask) != 0) || gameModeSetting;
}

}  // namespace vtx
