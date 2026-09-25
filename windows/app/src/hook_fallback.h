// hook_fallback.h — per-app keyboard-hook fallback (spec §5.3, mode "hookFallback").
//
// For the rare app without usable TSF (old Java/Qt, some games, RDP-like canvases):
// while such an app is in the FOREGROUND, and the VietTelex keyboard (vi-VN) is its
// active input method, and the app is in Vietnamese mode, a WH_KEYBOARD_LL hook runs
// the same TypingSession (in-place) and types with SendInput(KEYEVENTF_UNICODE).
// Everything else: no hook installed at all. Self-injected events carry a marker in
// dwExtraInfo and are ignored; a RateBreaker stops any synthetic-event cascade.
#pragma once
#include "settings.h"

namespace vtx::app {

void hookConfigure(const Settings& s);  // (re)apply settings; starts/stops watching
void hookShutdown();

}  // namespace vtx::app
