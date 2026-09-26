// icons.h — the app's tray icon (Việt/Anh state glyphs; the TIP no longer adds a
// language-bar item since 1.0.8).
// Glyphs come from the macOS artwork (resources, see res/icon_ids.h); the "VI"/"EN" text
// choice is drawn at runtime like the system's own ENG/VIE labels.
#pragma once
#include <string>

#include "globals.h"

namespace vtx::tip {

// True when the TASKBAR uses the light theme (HKCU ...\Personalize SystemUsesLightTheme).
// Unreadable (AppContainer, secure desktop) -> false: dark taskbar, the Windows default.
bool TaskbarIsLight();

// The icon for choice `menuIcon` ("vt", "star", "flag", "logo", "vi"; anything else = vt)
// in state `vietnamese`, for the current taskbar theme. `module` holds the icon resources.
// size <= 0: SM_CXSMICON. Caller destroys.
HICON CreateStateIcon(HINSTANCE module, const std::string& menuIcon, bool vietnamese, int size = 0);

// Short text ("VI", "EN") as an icon, in `color`, on a transparent background.
HICON CreateTextIcon(const wchar_t* text, int size, COLORREF color);

// Copy of `icon` with its alpha multiplied by `opacity` (0..1). Caller destroys both.
HICON CreateDimmedIcon(HICON icon, int size, float opacity);

}  // namespace vtx::tip
