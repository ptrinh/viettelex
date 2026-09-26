// hook_fallback.h — per-app keyboard-hook fallback (spec §5.3, mode "hookFallback").
//
// For the rare app without usable TSF (old Java/Qt, some games, RDP-like canvases):
// while such an app is in the FOREGROUND, and the VietTelex keyboard (vi-VN) is its
// active input method, and the app is in Vietnamese mode, a WH_KEYBOARD_LL hook runs
// the same TypingSession (in-place) and types with SendInput(KEYEVENTF_UNICODE).
// Everything else: no hook installed at all. Self-injected events carry a marker in
// dwExtraInfo and are ignored; a RateBreaker stops any synthetic-event cascade.
#pragma once
#include <string>

#include "settings.h"

namespace vtx::app {

void hookConfigure(const Settings& s);  // (re)apply settings; starts/stops watching
void hookShutdown();
// The TIP found a field it cannot type into without an underline (CUAS/IMM app,
// xterm.js, unflagged console): the hook types there until the foreground changes.
void hookSetDirectFromTip(bool on);
// Called (UI thread) when a hook-mode app is elevated above VietTelex.exe: SendInput
// cannot reach it (UIPI). The app shows a non-modal notice.
void hookSetElevationNotifier(void (*notify)(const std::wstring& exe));

}  // namespace vtx::app
