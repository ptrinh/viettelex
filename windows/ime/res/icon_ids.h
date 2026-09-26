// icon_ids.h — resource IDs of the macOS-derived icons (windows/installer/icons/make_icons.py)
// and the keyboard-icon choice (settings `menuIcon`). Plain #defines first: this file is
// included by the .rc files (resource compiler) and by C++.
//
//   1            app icon (viettelex.ico)
//   100 + style*4 + state*2 + theme    taskbar input-indicator glyphs
//       style  0 vt (MenuIcon1)   1 star (MenuIcon2)   2 flag (MenuIcon3)
//       state  0 Vietnamese        1 English (dimmed)
//       theme  0 dark taskbar (white glyph)   1 light taskbar (dark glyph)
//   200 + choice                        static keyboard-profile icons (Win+Space list):
//       white glyph + dark outline, readable on light and dark flyouts
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
#define IDI_PROFILE_VT 200
#define IDI_PROFILE_STAR 201
#define IDI_PROFILE_FLAG 202
#define IDI_PROFILE_LOGO 203
#define IDI_PROFILE_VI 204

#ifdef __cplusplus
#include <string>
namespace vtx {

// The five keyboard/indicator icon choices, in picker order.
enum class IconChoice : int { Vt = 0, Star = 1, Flag = 2, Logo = 3, Vi = 4 };
constexpr int kIconChoiceCount = 5;

// Settings value -> choice. Unknown values and the retired "letter" (V / E) -> Vᴛ.
inline IconChoice parseIconChoice(const std::string& s) {
    if (s == "star") return IconChoice::Star;
    if (s == "flag") return IconChoice::Flag;
    if (s == "logo") return IconChoice::Logo;
    if (s == "vi") return IconChoice::Vi;
    return IconChoice::Vt;
}
inline const char* iconChoiceName(IconChoice c) {
    switch (c) {
        case IconChoice::Star: return "star";
        case IconChoice::Flag: return "flag";
        case IconChoice::Logo: return "logo";
        case IconChoice::Vi: return "vi";
        case IconChoice::Vt: break;
    }
    return "vt";
}

// How the DYNAMIC input-mode icon (taskbar indicator, follows Việt/Anh state) is made.
struct IndicatorIcon {
    int resourceId;  // icon resource to load; 0 = draw text at runtime
    bool dim;        // English state of a colour/runtime icon: draw at reduced opacity
    const char* text;  // runtime text ("VI" / "EN") when resourceId == 0
};
inline IndicatorIcon indicatorIcon(IconChoice c, bool vietnamese, bool lightTaskbar) {
    switch (c) {
        case IconChoice::Logo: return {IDI_APP, !vietnamese, nullptr};
        case IconChoice::Vi: return {0, false, vietnamese ? "VI" : "EN"};
        default: {
            const int style = c == IconChoice::Star ? 1 : c == IconChoice::Flag ? 2 : 0;
            return {100 + style * 4 + (vietnamese ? 0 : 2) + (lightTaskbar ? 1 : 0), false, nullptr};
        }
    }
}

// Legacy helper (tray glyph): resource id for a glyph choice, 0 for runtime-drawn ones.
inline int glyphIconId(const std::string& menuIcon, bool vietnamese, bool lightTaskbar) {
    return indicatorIcon(parseIconChoice(menuIcon), vietnamese, lightTaskbar).resourceId;
}

// STATIC profile icon: resource id, and its 0-based INDEX in the TIP DLL — the value of
// LanguageProfile\IconIndex. Windows counts icon groups in resource order: numeric IDs
// ascending, so the index is the position of the id in kAllIconIds.
constexpr int kAllIconIds[] = {IDI_APP, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
                               IDI_PROFILE_VT, IDI_PROFILE_STAR, IDI_PROFILE_FLAG, IDI_PROFILE_LOGO, IDI_PROFILE_VI};
inline int profileIconId(IconChoice c) { return IDI_PROFILE_VT + static_cast<int>(c); }
inline int iconIndexOf(int resourceId) {
    for (int i = 0; i < static_cast<int>(sizeof(kAllIconIds) / sizeof(kAllIconIds[0])); ++i)
        if (kAllIconIds[i] == resourceId) return i;
    return 0;
}
inline int profileIconIndex(IconChoice c) { return iconIndexOf(profileIconId(c)); }

}  // namespace vtx
#endif
#endif  // VTX_ICON_IDS_H
