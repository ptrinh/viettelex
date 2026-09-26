// icon_ids.h — resource IDs of the macOS-derived icons (windows/installer/icons/make_icons.py).
// Plain #defines: included by the .rc files (resource compiler) and by C++.
//   1            app icon (viettelex.ico)
//   100 + style*4 + state*2 + theme
//       style  0 vt (MenuIcon1)   1 star (MenuIcon2)   2 flag (MenuIcon3)
//       state  0 Vietnamese        1 English (dimmed)
//       theme  0 dark taskbar (white glyph)   1 light taskbar (dark glyph)
#ifndef VTX_ICON_IDS_H
#define VTX_ICON_IDS_H
#define IDI_APP 1
#define IDI_GLYPH_VT_V_DARK 100
#define IDI_GLYPH_VT_V_LIGHT 101
#define IDI_GLYPH_VT_E_DARK 102
#define IDI_GLYPH_VT_E_LIGHT 103
#define IDI_GLYPH_STAR_V_DARK 104
#define IDI_GLYPH_STAR_V_LIGHT 105
#define IDI_GLYPH_STAR_E_DARK 106
#define IDI_GLYPH_STAR_E_LIGHT 107
#define IDI_GLYPH_FLAG_V_DARK 108
#define IDI_GLYPH_FLAG_V_LIGHT 109
#define IDI_GLYPH_FLAG_E_DARK 110
#define IDI_GLYPH_FLAG_E_LIGHT 111

#ifdef __cplusplus
#include <string>
namespace vtx {
// Resource ID for the tray / input-indicator glyph. `menuIcon` = settings value
// ("vt" default, "star", "flag"; anything else -> vt). Returns 0 for "letter" (the
// runtime-drawn V/E letters).
inline int glyphIconId(const std::string& menuIcon, bool vietnamese, bool lightTaskbar) {
    int style = 0;
    if (menuIcon == "letter") return 0;
    if (menuIcon == "star") style = 1;
    else if (menuIcon == "flag") style = 2;
    return 100 + style * 4 + (vietnamese ? 0 : 2) + (lightTaskbar ? 1 : 0);
}
}  // namespace vtx
#endif
#endif  // VTX_ICON_IDS_H
