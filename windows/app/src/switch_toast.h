// switch_toast.h — the floating V/E indicator: a tiny top-most window near the caret (or
// the screen corner) for ~1 s after a Việt/Anh switch. Click-through, never activated,
// never takes focus. Created on first use; costs nothing on the typing path (it only runs
// when the TIP posts AppCommand::UserSwitched). Decisions: app/core/game_logic.h.
#pragma once

namespace vtx::app {

void toastShow(const wchar_t* text);  // "V", "E", "Game: bật"…
void toastShutdown();

}  // namespace vtx::app
