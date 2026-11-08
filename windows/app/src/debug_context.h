// debug_context.h — VietTelex.exe's side of the debug-log header (ime/core/debug_header.h,
// ime/src/debug_file.h): gathers the facts once, hands them to the shared writer.
#pragma once
#include "settings.h"

namespace vtx::app {

// Settings loaded / changed: turns the app's logging on or off (appSetLogging) and, when
// logging just turned on (app start included), writes the full header. While on, a
// changed settings summary is logged as one "settings changed:" line. Nothing at all
// (no registry / COM work) while logging is off. UI thread.
void debugContextApply(const Settings& s);
// App exit: writes a pending "^ repeated Nx" line.
void debugContextShutdown();

}  // namespace vtx::app
