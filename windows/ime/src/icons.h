// icons.h — mode icons drawn at runtime (no bitmap assets, crisp at any DPI).
// Glyph is black with alpha; the language bar recolours it to the taskbar text colour
// (TF_LBI_STYLE_TEXTCOLORICON), so one icon serves light and dark taskbars.
#pragma once
#include <string>

#include "globals.h"

namespace vtx::tip {

// vietnamese: "V" (menuIcon "vt": V with a small T) vs "E". size <= 0: SM_CXSMICON.
HICON CreateModeIcon(bool vietnamese, bool vtStyle, int size, COLORREF color = RGB(0, 0, 0));

// True when the TASKBAR uses the light theme (HKCU ...\Personalize SystemUsesLightTheme).
// Unreadable (AppContainer, secure desktop) -> false: dark taskbar, the Windows default.
bool TaskbarIsLight();

// The macOS-derived glyph for the current state, sized for the taskbar (SM_CXSMICON
// unless `size` > 0). `menuIcon` "letter" -> runtime-drawn V/E. Caller destroys.
HICON CreateStateIcon(HINSTANCE module, const std::string& menuIcon, bool vietnamese, int size = 0);

}  // namespace vtx::tip
