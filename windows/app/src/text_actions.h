// text_actions.h — Công cụ văn bản for the SELECTION in any app (macOS TextActions.swift):
// Thêm dấu, HOA, thường, Hoa Đầu Từ, Hoa đầu câu, Xoá dấu. Entry points: the tray menu's
// "Công cụ văn bản" submenu and the optional global Thêm dấu hotkey (default off).
//
// Read/replace: first through the TIP inside the target app (TSF selection + edit
// session, ime/core/text_tool_ipc.h); where TSF has no usable selection (IMM32/CUAS apps,
// VietTelex not the active keyboard), Ctrl+C / Ctrl+V with the whole clipboard saved and
// restored. Never in password fields, terminals, remote/VM viewers or elevated apps.
// Nothing here runs per keystroke: no hook, no timer outside one request.
#pragma once
#include <windows.h>

namespace vtx::app {

// (Re)register the Thêm dấu hotkey from g_settings (settingsChanged, startup).
void textActionsConfigure();
void textActionsShutdown();

// Gợi ý từ: watch Windows' "Show text suggestions when typing on the physical keyboard"
// (word_prediction.h kHwkbPredictionKey) — RegNotifyChangeKeyValue + a thread-pool wait, no
// thread of our own, nothing polled. A change updates g_settings.systemTextPrediction and
// republishes the snapshot (TIPs pick it up at their next focus change).
void predictionWatchStart();
void predictionWatchStop();

// "Học từ bạn gõ" (app/core/learned_words.h): the model + %LOCALAPPDATA%\VietTelex\
// learned-words.bin live here (UI thread). The TIPs send committed words (HintJob::Learn);
// recorded only while g_settings.learnWords && systemTextPrediction. Saved 5 s after the last
// word (atomic: temp file + MoveFileEx) and at exit; corrupt file => start empty.
void learnedClear();          // "Xoá từ đã học" (settings window): RAM + file
void learnedSettingsChanged();  // switch / Windows setting off: save, drop from RAM

// A text tool is running (between the hotkey / menu and its result).
bool textActionsBusy();

// Main-window messages owned by this module (WM_HOTKEY, WM_COPYDATA from the TIP, timers).
bool textActionsMessage(UINT msg, WPARAM wp, LPARAM lp, LRESULT& result);
// AppCommand::TextToolReply from the TIP.
void textActionsTipReply(LPARAM lp);
// Foreground changes (tray path): remember the last app window the user was in.
void textActionsNoteForeground(HWND hwnd);

// Tray menu: append the "Công cụ văn bản" submenu (ids firstId … firstId+5) when enabled;
// run the picked tool on the app the user came from.
void appendTextToolsMenu(HMENU menu, UINT firstId);
bool runTextToolMenuCommand(UINT cmd, UINT firstId);

}  // namespace vtx::app
