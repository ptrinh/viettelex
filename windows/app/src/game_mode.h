// game_mode.h — games and fullscreen in VietTelex.exe (decisions: app/core/game_logic.h;
// the TIP side: ime/core/game_ipc.h).
//   * Tự tắt khi chơi game toàn màn hình (settings autoOffFullscreen): a foreground WinEvent
//     hook, installed only while the setting is on, plus at most three one-shot re-checks
//     when a new foreground window covers its monitor. Nothing runs per key.
//   * Chế độ game (settings gameMode) and its optional global hotkey (gameModeHotkey).
#pragma once
#include <windows.h>

namespace vtx::app {

void gameConfigure();  // after every settings change (hotkey, foreground watch, game mode)
void gameShutdown();   // un-suspend whatever is suspended, unregister everything
// Main-window messages: the hotkey and the re-check timers. True = handled.
bool gameMessage(UINT msg, WPARAM wp, LPARAM lp, LRESULT& result);

void toggleGameMode();       // hotkey / Settings: flips g_settings.gameMode and applies it
bool gameSuspendedNow();     // keys currently pass through for the foreground (or everywhere)
int currentNotificationState();  // SHQueryUserNotificationState, 0 if unavailable

}  // namespace vtx::app
