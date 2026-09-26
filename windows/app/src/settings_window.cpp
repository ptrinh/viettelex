// settings_window.cpp — Cài đặt, Windows 11 / Fluent look in plain Win32.
//
//   ┌──────────────┬───────────────────────────────────────────┐
//   │ [icon] Viet… │  Page title (28px)                        │
//   │              │  Section header                           │
//   │ ▌Kiểu gõ     │  ┌─────────────────────────────────────┐  │
//   │  Chính tả    │  │ Title                     Bật (●  ) │  │  setting card
//   │  Gõ tắt      │  │ one-line description                │  │
//   │  Ứng dụng    │  └─────────────────────────────────────┘  │
//   │  Giới thiệu  │  ...                          (scrolls)   │
//   └──────────────┴───────────────────────────────────────────┘
//
// Everything visual is painted here (GDI+ for anti-aliased shapes, GDI for ClearType
// text) on an 8-px grid, in DIPs scaled per monitor (per-monitor v2). Toggles are small
// custom child windows (focusable, Space toggles). Combos, edits, list views and buttons
// stay native, themed dark with the system's DarkMode_* visual styles. Title bar follows
// the theme (DWMWA_USE_IMMERSIVE_DARK_MODE); Win11 adds Mica (title bar) and round
// window/card corners, Win10 gets flat cards. Accent colour = the user's Windows accent.
// Every change applies immediately through settingsChanged() (like macOS).
#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <msi.h>
#include <uxtheme.h>

#include <algorithm>
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

#include <string>
#include <vector>

#include "app.h"
#include "icons.h"
#include "res/icon_ids.h"
#include "settings_store.h"
#include "shortcuts.h"
#include "strings.h"
#include "uninstall.h"
#include "updater.h"
#include "utf.h"
#include "version.h"

namespace vtx::app {

namespace {

constexpr wchar_t kWndClass[] = L"VietTelexSettings";
constexpr wchar_t kPageClass[] = L"VietTelexSettingsPage";
constexpr wchar_t kToggleClass[] = L"VietTelexToggle";
constexpr int kPageCount = 5;

// ---------------------------------------------------------------- metrics (DIP)
constexpr int kWinW = 920, kWinH = 660;   // client size
constexpr int kNavW = 272;
constexpr int kPad = 32;                  // page side padding
constexpr int kCardPadX = 16, kCardPadY = 14, kCardGap = 4, kSectionGap = 24;
constexpr int kControlW = 240;            // every combo is this wide
constexpr int kToggleW = 40, kToggleH = 20;
constexpr int kTileW = 96, kTileH = 84;  // icon picker tiles

// ---------------------------------------------------------------- ids
enum Id : int {
    IdToggleBase = 1000,
    IdComboMethod = 2000,
    IdComboHotkey,
    IdComboIcon,
    IdComboLang,
    IdScList = 3000,
    IdScKey,
    IdScValue,
    IdScAdd,
    IdScRemove,
    IdScImport,
    IdScExport,
    IdAppList = 4000,
    IdAppExe,
    IdAppMode,
    IdAppAdd,
    IdAppRemove,
    IdCheckNow = 5000,
    IdUninstall,
    IdIconTile = 6000,  // + IconChoice
};

struct ToggleDef {
    bool Settings::*field;
    S title, desc;
};
const ToggleDef kToggles[] = {
    {&Settings::simpleTelex, S::SimpleTelex, S::SimpleTelexDesc},                      // 0
    {&Settings::freeMarking, S::FreeMarking, S::FreeMarkingDesc},                      // 1
    {&Settings::quickTelex, S::QuickTelex, S::QuickTelexDesc},                         // 2
    {&Settings::modernOrthography, S::ModernOrthography, S::ModernOrthographyDesc},    // 3
    {&Settings::bracketVowels, S::BracketVowels, S::BracketVowelsDesc},                // 4
    {&Settings::autoRestore, S::AutoRestore, S::AutoRestoreDesc},                      // 5
    {&Settings::liveSpellCheck, S::LiveSpellCheck, S::LiveSpellCheckDesc},             // 6
    {&Settings::contextualEnglish, S::ContextualEnglish, S::ContextualEnglishDesc},    // 7
    {&Settings::collisionPrefersVietnamese, S::CollisionPrefersVi, S::CollisionPrefersViDesc},  // 8
    {&Settings::teencode, S::Teencode, S::TeencodeDesc},                               // 9
    {&Settings::reEditWord, S::ReEditWord, S::ReEditWordDesc},                         // 10
    {&Settings::autoUpdateCheck, S::AutoUpdateCheck, S::AutoUpdateCheckDesc},          // 11
    {&Settings::debugLogging, S::DebugLogging, S::DebugLoggingDesc},                   // 12
    {&Settings::showTrayIcon, S::ShowTray, S::ShowTrayDesc},                           // 13
};
constexpr int kToggleCount = static_cast<int>(sizeof(kToggles) / sizeof(kToggles[0]));

const char* const kHotkeys[] = {"ctrl-shift", "win-space", "alt-z", "off"};
const S kHotkeyLabels[] = {S::HotkeyCtrlShift, S::HotkeyWinSpace, S::HotkeyAltZ, S::HotkeyOff};
const S kIconLabels[kIconChoiceCount] = {S::IconVt, S::IconStar, S::IconFlag, S::IconLogo, S::IconVi};
const AppMode kModes[] = {AppMode::Composition, AppMode::InPlace, AppMode::HookFallback, AppMode::Off};
const S kModeLabels[] = {S::ModeComposition, S::ModeInPlace, S::ModeHook, S::ModeOff};

// ---------------------------------------------------------------- theme
struct Palette {
    COLORREF bg, card, cardBorder, text, subtext, navHover, navSelected, accent, accentText, ctrlBg,
        toggleOffBorder, divider, ctrlBorder, danger;
};

Palette g_pal;
bool g_dark = false;
bool g_win11 = false;
UINT g_dpi = 96;
HFONT g_fBody = nullptr, g_fCaption = nullptr, g_fTitle = nullptr, g_fSection = nullptr, g_fIcon = nullptr,
      g_fHeader = nullptr;
HBRUSH g_brBg = nullptr, g_brCard = nullptr, g_brCtrl = nullptr;
ULONG_PTR g_gdiplusToken = 0;

int px(int dip) { return MulDiv(dip, static_cast<int>(g_dpi), 96); }

COLORREF mix(COLORREF a, COLORREF b, int pctB) {
    auto ch = [&](int s) {
        int x = (a >> s) & 0xFF, y = (b >> s) & 0xFF;
        return static_cast<COLORREF>((x * (100 - pctB) + y * pctB) / 100) << s;
    };
    return ch(0) | ch(8) | ch(16);
}

bool readDark() {
    DWORD v = 1, sz = sizeof v;
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                     L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &v, &sz) != ERROR_SUCCESS)
        return false;
    return v == 0;
}

COLORREF readAccent() {
    DWORD v = 0, sz = sizeof v;  // ABGR
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\DWM", L"AccentColor", RRF_RT_REG_DWORD,
                     nullptr, &v, &sz) == ERROR_SUCCESS)
        return RGB(v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF);
    return RGB(0x00, 0x67, 0xC0);  // Windows default blue
}

bool isWin11() {
    using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
    OSVERSIONINFOW vi = {};
    vi.dwOSVersionInfoSize = sizeof vi;
    if (auto fn = reinterpret_cast<RtlGetVersionFn>(
            reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"))))
        fn(&vi);
    return vi.dwMajorVersion >= 10 && vi.dwBuildNumber >= 22000;
}

void makePalette() {
    g_dark = readDark();
    COLORREF accent = readAccent();
    if (g_dark) {
        g_pal = {RGB(0x20, 0x20, 0x20), RGB(0x2B, 0x2B, 0x2B), RGB(0x1D, 0x1D, 0x1D), RGB(0xFF, 0xFF, 0xFF),
                 RGB(0xC5, 0xC5, 0xC5), RGB(0x2D, 0x2D, 0x2D), RGB(0x2D, 0x2D, 0x2D),
                 mix(accent, RGB(255, 255, 255), 35),  // Win11 uses the light accent shade on dark
                 RGB(0, 0, 0), RGB(0x32, 0x32, 0x32), RGB(0xC5, 0xC5, 0xC5), RGB(0x3A, 0x3A, 0x3A),
                 RGB(0x48, 0x48, 0x48), RGB(0xFF, 0x99, 0xA4)};
    } else {
        g_pal = {RGB(0xF3, 0xF3, 0xF3), RGB(0xFB, 0xFB, 0xFB), RGB(0xE5, 0xE5, 0xE5), RGB(0x1B, 0x1B, 0x1B),
                 RGB(0x5F, 0x5F, 0x5F), RGB(0xEA, 0xEA, 0xEA), RGB(0xEA, 0xEA, 0xEA), accent,
                 RGB(255, 255, 255), RGB(0xFF, 0xFF, 0xFF), RGB(0x86, 0x86, 0x86), RGB(0xE5, 0xE5, 0xE5),
                 RGB(0xD1, 0xD1, 0xD1), RGB(0xC4, 0x2B, 0x1C)};
    }
}

int CALLBACK fontFound(const LOGFONTW*, const TEXTMETRICW*, DWORD, LPARAM p) {
    *reinterpret_cast<bool*>(p) = true;
    return 0;
}

bool fontExists(const wchar_t* face) {
    HDC dc = GetDC(nullptr);
    LOGFONTW lf = {};
    lf.lfCharSet = DEFAULT_CHARSET;
    lstrcpynW(lf.lfFaceName, face, LF_FACESIZE);
    bool found = false;
    EnumFontFamiliesExW(dc, &lf, fontFound, reinterpret_cast<LPARAM>(&found), 0);
    ReleaseDC(nullptr, dc);
    return found;
}

const wchar_t* g_iconFace = nullptr;  // Segoe Fluent Icons / Segoe MDL2 Assets, if present

void makeFonts() {
    for (HFONT* f : {&g_fBody, &g_fCaption, &g_fTitle, &g_fSection, &g_fIcon, &g_fHeader})
        if (*f) DeleteObject(*f), *f = nullptr;
    const wchar_t* face = fontExists(L"Segoe UI Variable Text") ? L"Segoe UI Variable Text" : L"Segoe UI";
    const wchar_t* display = fontExists(L"Segoe UI Variable Display") ? L"Segoe UI Variable Display" : face;
    auto mk = [&](int dip, int weight, const wchar_t* f) {
        return CreateFontW(-px(dip), 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, f);
    };
    g_fBody = mk(14, FW_NORMAL, face);
    g_fCaption = mk(12, FW_NORMAL, face);
    g_fSection = mk(14, FW_SEMIBOLD, face);
    g_fHeader = mk(15, FW_SEMIBOLD, face);
    g_fTitle = mk(28, FW_SEMIBOLD, display);
    g_iconFace = fontExists(L"Segoe Fluent Icons") ? L"Segoe Fluent Icons"
                 : fontExists(L"Segoe MDL2 Assets") ? L"Segoe MDL2 Assets"
                                                      : nullptr;
    if (g_iconFace) g_fIcon = mk(16, FW_NORMAL, g_iconFace);
}

void makeBrushes() {
    for (HBRUSH* b : {&g_brBg, &g_brCard, &g_brCtrl})
        if (*b) DeleteObject(*b), *b = nullptr;
    g_brBg = CreateSolidBrush(g_pal.bg);
    g_brCard = CreateSolidBrush(g_pal.card);
    g_brCtrl = CreateSolidBrush(g_pal.ctrlBg);
}

Gdiplus::Color gc(COLORREF c, BYTE a = 255) { return Gdiplus::Color(a, GetRValue(c), GetGValue(c), GetBValue(c)); }

void roundRectPath(Gdiplus::GraphicsPath& p, float x, float y, float w, float h, float r) {
    if (r <= 0.5f) {
        p.AddRectangle(Gdiplus::RectF(x, y, w, h));
        return;
    }
    float d = r * 2;
    p.AddArc(x, y, d, d, 180, 90);
    p.AddArc(x + w - d, y, d, d, 270, 90);
    p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
    p.AddArc(x, y + h - d, d, d, 90, 90);
    p.CloseFigure();
}

void fillRound(Gdiplus::Graphics& g, const RECT& r, float radius, COLORREF fill, COLORREF border, bool withBorder) {
    Gdiplus::GraphicsPath path;
    roundRectPath(path, r.left + 0.5f, r.top + 0.5f, static_cast<float>(r.right - r.left - 1),
                  static_cast<float>(r.bottom - r.top - 1), radius);
    Gdiplus::SolidBrush b(gc(fill));
    g.FillPath(&b, &path);
    if (withBorder) {
        Gdiplus::Pen pen(gc(border), 1.0f);
        g.DrawPath(&pen, &path);
    }
}

void text(HDC dc, const std::wstring& s, RECT r, HFONT f, COLORREF c, UINT flags) {
    HGDIOBJ old = SelectObject(dc, f);
    SetTextColor(dc, c);
    SetBkMode(dc, TRANSPARENT);
    DrawTextW(dc, s.c_str(), static_cast<int>(s.size()), &r, flags | DT_NOPREFIX);
    SelectObject(dc, old);
}

int textHeight(const std::wstring& s, int width, HFONT f) {
    HDC dc = GetDC(nullptr);
    HGDIOBJ old = SelectObject(dc, f);
    RECT r = {0, 0, width, 0};
    DrawTextW(dc, s.c_str(), static_cast<int>(s.size()), &r, DT_WORDBREAK | DT_CALCRECT | DT_NOPREFIX);
    SelectObject(dc, old);
    ReleaseDC(nullptr, dc);
    return r.bottom - r.top;
}

// Undocumented but stable since 1809: uxtheme #133 AllowDarkModeForWindow. The
// DarkMode_* visual styles only take effect on a window that was allowed dark mode first
// (without it Windows 10 draws the light classic look — the 1.0.3/1.0.4 screenshots).
void allowDark(HWND h) {
    using Fn = BOOL(WINAPI*)(HWND, BOOL);
    static Fn fn = [] {
        HMODULE ux = GetModuleHandleW(L"uxtheme.dll");
        if (!ux) ux = LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        return ux ? reinterpret_cast<Fn>(reinterpret_cast<void*>(GetProcAddress(ux, MAKEINTRESOURCEA(133)))) : nullptr;
    }();
    if (fn) fn(h, g_dark ? TRUE : FALSE);
}

void applyControlTheme(HWND h, const wchar_t* darkClass) {
    allowDark(h);
    SetWindowTheme(h, g_dark ? darkClass : L"Explorer", nullptr);
    SendMessageW(h, WM_THEMECHANGED, 0, 0);
}

// ---------------------------------------------------------------- page model
enum class ItemKind { Section, Setting, Block, About, Links, IconPicker };
enum class Ctl { None, Toggle, Combo, Button };

struct Item {
    ItemKind kind = ItemKind::Setting;
    S title = S::AppName;
    S desc = S::Count;         // S::Count = no description
    Ctl ctl = Ctl::None;
    int toggle = -1;           // index into kToggles
    int ctlId = 0;             // combo / button id
    int blockHeight = 0;       // Block: content height (DIP) below the title
    // layout results (px, page coordinates before scrolling)
    RECT rc = {0, 0, 0, 0};
    HWND hwnd = nullptr;       // the control, if any
};

struct LinkHit {
    RECT rc;
    const wchar_t* url;
};

HWND g_wnd = nullptr, g_page = nullptr;
int g_tab = 0, g_hoverNav = -1;
std::vector<Item> g_items;
std::vector<LinkHit> g_links;
int g_scroll = 0, g_contentH = 0;
bool g_syncing = false;
HICON g_appIcon = nullptr, g_bigIcon = nullptr;

// Block children (lists page)
HWND g_list = nullptr, g_edit1 = nullptr, g_edit2 = nullptr, g_combo = nullptr;
std::vector<HWND> g_blockButtons;

std::wstring u16w(const std::u16string& s) { return widen(utf16ToUtf8(s)); }
std::u16string wu16(const std::wstring& s) { return utf8ToUtf16(narrow(s)); }

std::wstring windowText(HWND h) {
    int n = GetWindowTextLengthW(h);
    std::wstring s(static_cast<size_t>(n) + 1, L'\0');
    GetWindowTextW(h, &s[0], n + 1);
    s.resize(static_cast<size_t>(n));
    return s;
}

std::wstring trim(const std::wstring& s) {
    size_t a = s.find_first_not_of(L" \t\r\n"), b = s.find_last_not_of(L" \t\r\n");
    return a == std::wstring::npos ? L"" : s.substr(a, b - a + 1);
}

Item section(S t) {
    Item i;
    i.kind = ItemKind::Section;
    i.title = t;
    return i;
}
Item toggleItem(int idx) {
    Item i;
    i.title = kToggles[idx].title;
    i.desc = kToggles[idx].desc;
    i.ctl = Ctl::Toggle;
    i.toggle = idx;
    return i;
}
Item comboItem(S t, S d, int id) {
    Item i;
    i.title = t;
    i.desc = d;
    i.ctl = Ctl::Combo;
    i.ctlId = id;
    return i;
}
Item buttonItem(S t, S d, int id) {
    Item i = comboItem(t, d, id);
    i.ctl = Ctl::Button;
    return i;
}
Item blockItem(S t, S d, int h) {
    Item i;
    i.kind = ItemKind::Block;
    i.title = t;
    i.desc = d;
    i.blockHeight = h;
    return i;
}

std::vector<Item> pageItems(int tab) {
    std::vector<Item> v;
    switch (tab) {
        case 0:
            v.push_back(section(S::SecInputStyle));
            v.push_back(comboItem(S::InputMethod, S::InputMethodDesc, IdComboMethod));
            for (int i = 0; i <= 4; ++i) v.push_back(toggleItem(i));
            v.push_back(section(S::SecSwitch));
            v.push_back(comboItem(S::SwitchHotkey, S::SwitchHotkeyDesc, IdComboHotkey));
            v.push_back(section(S::SecAppearance));
            {
                Item picker;
                picker.kind = ItemKind::IconPicker;
                picker.title = S::MenuIcon;
                picker.desc = S::MenuIconDesc;
                v.push_back(picker);
            }
            v.push_back(toggleItem(13));
            v.push_back(comboItem(S::UiLanguage, S::UiLanguageDesc, IdComboLang));
            break;
        case 1:
            v.push_back(section(S::SecSpelling));
            for (int i = 5; i <= 10; ++i) v.push_back(toggleItem(i));
            break;
        case 2: v.push_back(blockItem(S::SecShortcuts, S::ShortcutsDesc, 360)); break;
        case 3: v.push_back(blockItem(S::SecApps, S::AppsDesc, 360)); break;
        case 4: {
            Item hero;
            hero.kind = ItemKind::About;
            v.push_back(hero);
            v.push_back(section(S::SecUpdates));
            v.push_back(buttonItem(S::CheckNow, S::CheckNowDesc, IdCheckNow));
            v.push_back(toggleItem(11));
            v.push_back(section(S::SecDiagnostics));
            v.push_back(toggleItem(12));
            v.push_back(section(S::SecUninstall));
            v.push_back(buttonItem(S::Uninstall, S::UninstallDesc, IdUninstall));
            Item links;
            links.kind = ItemKind::Links;
            v.push_back(links);
            break;
        }
        default: break;
    }
    return v;
}

const S kPageTitles[kPageCount] = {S::TabTyping, S::TabSpelling, S::TabShortcuts, S::TabApps, S::TabAbout};
// Segoe Fluent Icons / MDL2 glyphs: Keyboard, Font, List, AllApps, Info.
const wchar_t kNavGlyphs[kPageCount] = {0xE765, 0xE8D2, 0xE8FD, 0xE71D, 0xE946};

// ---------------------------------------------------------------- toggle control
struct ToggleState {
    bool on = false;
    bool hover = false;
};

LRESULT CALLBACK toggleProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    auto* st = reinterpret_cast<ToggleState*>(GetWindowLongPtrW(h, GWLP_USERDATA));
    switch (msg) {
        case WM_NCCREATE:
            SetWindowLongPtrW(h, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(new ToggleState()));
            break;
        case WM_NCDESTROY:
            delete st;
            SetWindowLongPtrW(h, GWLP_USERDATA, 0);
            break;
        case BM_GETCHECK: return st && st->on ? BST_CHECKED : BST_UNCHECKED;
        case BM_SETCHECK:
            if (st) st->on = wp == BST_CHECKED;
            InvalidateRect(h, nullptr, FALSE);
            return 0;
        case WM_GETDLGCODE: return DLGC_BUTTON;
        case WM_MOUSEMOVE:
            if (st && !st->hover) {
                st->hover = true;
                TRACKMOUSEEVENT t = {sizeof t, TME_LEAVE, h, 0};
                TrackMouseEvent(&t);
                InvalidateRect(h, nullptr, FALSE);
            }
            return 0;
        case WM_MOUSELEAVE:
            if (st) st->hover = false;
            InvalidateRect(h, nullptr, FALSE);
            return 0;
        case WM_LBUTTONDOWN: SetFocus(h); return 0;
        case WM_LBUTTONUP:
        case WM_KEYUP:
            if (msg == WM_KEYUP && wp != VK_SPACE) break;
            if (st) {
                st->on = !st->on;
                InvalidateRect(h, nullptr, FALSE);
                SendMessageW(GetParent(h), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(h), BN_CLICKED),
                             reinterpret_cast<LPARAM>(h));
            }
            return 0;
        case WM_SETFOCUS:
        case WM_KILLFOCUS: InvalidateRect(h, nullptr, FALSE); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(h, &ps);
            RECT rc;
            GetClientRect(h, &rc);
            const int w = rc.right, hh = rc.bottom;
            HDC mem = CreateCompatibleDC(dc);
            HBITMAP bmp = CreateCompatibleBitmap(dc, w, hh);
            HGDIOBJ oldBmp = SelectObject(mem, bmp);
            FillRect(mem, &rc, g_brCard);
            {
                Gdiplus::Graphics g(mem);
                g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
                const bool on = st && st->on, hover = st && st->hover;
                const float tw = static_cast<float>(px(kToggleW)), th = static_cast<float>(px(kToggleH));
                const float x = (w - tw) / 2.0f, y = (hh - th) / 2.0f;
                Gdiplus::GraphicsPath track;
                roundRectPath(track, x, y, tw, th, th / 2);
                if (on) {
                    Gdiplus::SolidBrush b(gc(hover ? mix(g_pal.accent, g_dark ? RGB(0, 0, 0) : RGB(255, 255, 255), 10)
                                                   : g_pal.accent));
                    g.FillPath(&b, &track);
                } else {
                    Gdiplus::SolidBrush b(gc(hover ? g_pal.navHover : g_pal.card));
                    g.FillPath(&b, &track);
                    Gdiplus::Pen pen(gc(g_pal.toggleOffBorder), 1.0f);
                    g.DrawPath(&pen, &track);
                }
                const float knob = th - px(hover ? 6 : 8);  // 12px knob, 14px on hover (Win11)
                const float kx = on ? x + tw - th / 2 - knob / 2 : x + th / 2 - knob / 2;
                Gdiplus::SolidBrush kb(gc(on ? g_pal.accentText : g_pal.subtext));
                g.FillEllipse(&kb, kx, y + (th - knob) / 2, knob, knob);
                if (GetFocus() == h) {
                    Gdiplus::GraphicsPath ring;
                    roundRectPath(ring, x - 3, y - 3, tw + 6, th + 6, (th + 6) / 2);
                    Gdiplus::Pen pen(gc(g_pal.text), 2.0f);
                    g.DrawPath(&pen, &ring);
                }
            }
            BitBlt(dc, 0, 0, w, hh, mem, 0, 0, SRCCOPY);
            SelectObject(mem, oldBmp);
            DeleteObject(bmp);
            DeleteDC(mem);
            EndPaint(h, &ps);
            return 0;
        }
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

// ---------------------------------------------------------------- building a page
HWND makeCtl(const wchar_t* cls, const wchar_t* label, DWORD style, int id, DWORD ex = 0) {
    HWND h = CreateWindowExW(ex, cls, label, WS_CHILD | WS_VISIBLE | style, 0, 0, 10, 10, g_page,
                             reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), g_inst, nullptr);
    SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(g_fBody), FALSE);
    return h;
}

HWND makeCombo(int id, const S* labels, int n) {
    HWND h = makeCtl(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, id);
    for (int i = 0; i < n; ++i) SendMessageW(h, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(tr(labels[i])));
    applyControlTheme(h, L"DarkMode_CFD");
    SendMessageW(h, CB_SETITEMHEIGHT, static_cast<WPARAM>(-1), px(32) - px(6));  // 32px like edits/buttons
    return h;
}

// ---- one shared set of themed controls for every page (lists, edits, buttons) ----
enum ButtonKind : LONG_PTR { kBtnSecondary = 0, kBtnPrimary = 1, kBtnDanger = 2, kBtnTile = 10 /* + IconChoice */ };
std::vector<HWND> g_edits;  // edits get a painted Fluent frame (see paintPage)

// Owner-drawn Fluent button: identical in light/dark and on every Windows version.
HWND makeButton(const wchar_t* label, int id, ButtonKind kind = kBtnSecondary) {
    HWND h = makeCtl(L"BUTTON", label, BS_OWNERDRAW | WS_TABSTOP, id);
    SetWindowLongPtrW(h, GWLP_USERDATA, kind);
    return h;
}

void drawButton(const DRAWITEMSTRUCT* di) {
    const LONG_PTR kind = GetWindowLongPtrW(di->hwndItem, GWLP_USERDATA);
    const bool pressed = (di->itemState & ODS_SELECTED) != 0, focus = (di->itemState & ODS_FOCUS) != 0;
    const int w = di->rcItem.right - di->rcItem.left, h = di->rcItem.bottom - di->rcItem.top;
    // Draw into a memory bitmap and blit: GDI+ straight on the owner-draw DC clips the
    // rounded right edge on some systems.
    HDC mem = CreateCompatibleDC(di->hDC);
    HBITMAP bmp = CreateCompatibleBitmap(di->hDC, w, h);
    HGDIOBJ oldBmp = SelectObject(mem, bmp);
    RECT rc = {0, 0, w, h};
    FillRect(mem, &rc, g_brCard);
    const bool tile = kind >= kBtnTile;
    const int choice = tile ? static_cast<int>(kind - kBtnTile) : -1;
    const bool selected = tile && static_cast<int>(parseIconChoice(g_settings.menuIcon)) == choice;
    COLORREF fill = g_pal.ctrlBg, border = g_pal.ctrlBorder, fg = g_pal.text;
    if (kind == kBtnPrimary) fill = border = g_pal.accent, fg = g_pal.accentText;
    if (kind == kBtnDanger) fill = border = g_pal.danger, fg = g_dark ? RGB(0, 0, 0) : RGB(255, 255, 255);
    if (pressed) fill = mix(fill, g_dark ? RGB(0, 0, 0) : RGB(255, 255, 255), 15);
    {
        Gdiplus::Graphics g(mem);
        g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        RECT body = rc;
        if (tile && selected) InflateRect(&body, -1, -1);
        fillRound(g, body, static_cast<float>(px(tile ? 6 : 4)), fill, selected ? g_pal.accent : border, true);
        if (selected) {  // 2px accent ring for the chosen icon
            Gdiplus::GraphicsPath p;
            roundRectPath(p, body.left + 0.5f, body.top + 0.5f, static_cast<float>(body.right - body.left - 1),
                          static_cast<float>(body.bottom - body.top - 1), static_cast<float>(px(6)));
            Gdiplus::Pen pen(gc(g_pal.accent), 2.0f);
            g.DrawPath(&pen, &p);
        }
        if (focus) {
            RECT fr = rc;
            InflateRect(&fr, -px(3), -px(3));
            Gdiplus::GraphicsPath p;
            roundRectPath(p, fr.left + 0.5f, fr.top + 0.5f, static_cast<float>(fr.right - fr.left - 1),
                          static_cast<float>(fr.bottom - fr.top - 1), static_cast<float>(px(3)));
            Gdiplus::Pen pen(gc(tile ? g_pal.text : fg), 1.0f);
            pen.SetDashStyle(Gdiplus::DashStyleDot);
            g.DrawPath(&pen, &p);
        }
    }
    wchar_t buf[128];
    GetWindowTextW(di->hwndItem, buf, 128);
    if (tile) {
        // Preview = the keyboard-profile icon the taskbar / Win+Space list will show.
        const int icon = px(32);
        if (HICON ic = static_cast<HICON>(LoadImageW(g_inst, MAKEINTRESOURCEW(profileIconId(static_cast<IconChoice>(choice))),
                                                     IMAGE_ICON, icon, icon, LR_DEFAULTCOLOR))) {
            // Shown on a taskbar-coloured chip, as it will appear.
            const bool light = tip::TaskbarIsLight();
            RECT chip = {(w - px(44)) / 2, px(10), (w + px(44)) / 2, px(10) + px(44)};
            HBRUSH cb = CreateSolidBrush(light ? RGB(0xEE, 0xEE, 0xEE) : RGB(0x1F, 0x1F, 0x1F));
            FillRect(mem, &chip, cb);
            DeleteObject(cb);
            DrawIconEx(mem, (w - icon) / 2, px(16), ic, icon, icon, 0, nullptr, DI_NORMAL);
            DestroyIcon(ic);
        }
        RECT cap = {px(4), px(58), w - px(4), h - px(4)};
        text(mem, buf, cap, g_fCaption, g_pal.text, DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_END_ELLIPSIS);
    } else {
        text(mem, buf, rc, g_fBody, fg, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
    }
    BitBlt(di->hDC, di->rcItem.left, di->rcItem.top, w, h, mem, 0, 0, SRCCOPY);
    SelectObject(mem, oldBmp);
    DeleteObject(bmp);
    DeleteDC(mem);
}

// Edit: borderless native EDIT inside a painted frame; its placeholder is painted here in
// the palette's secondary colour (EM_SETCUEBANNER's grey is unreadable on dark).
LRESULT CALLBACK editSubclass(HWND h, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR cue) {
    LRESULT r = DefSubclassProc(h, msg, wp, lp);
    switch (msg) {
        case WM_PAINT:
            if (GetWindowTextLengthW(h) == 0 && GetFocus() != h) {
                HDC dc = GetDC(h);
                RECT rc;
                GetClientRect(h, &rc);
                rc.left += 2;
                text(dc, reinterpret_cast<const wchar_t*>(cue), rc, g_fBody, g_pal.subtext,
                     DT_SINGLELINE | DT_VCENTER);
                ReleaseDC(h, dc);
            }
            break;
        case WM_SETFOCUS:
        case WM_KILLFOCUS:
            InvalidateRect(h, nullptr, TRUE);
            InvalidateRect(GetParent(h), nullptr, FALSE);  // frame accent line
            break;
        default: break;
    }
    return r;
}

HWND makeEdit(int id, const wchar_t* cue) {
    HWND h = makeCtl(L"EDIT", L"", ES_AUTOHSCROLL | WS_TABSTOP, id);
    applyControlTheme(h, L"DarkMode_CFD");
    SetWindowSubclass(h, editSubclass, 1, reinterpret_cast<DWORD_PTR>(cue));
    g_edits.push_back(h);
    return h;
}

// ListView header: fully custom-drawn in palette colours (the themed dark header is
// dim-grey-on-black on Windows 10).
LRESULT CALLBACK headerSubclass(HWND h, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
    if (msg == WM_ERASEBKGND) {
        RECT rc;
        GetClientRect(h, &rc);
        FillRect(reinterpret_cast<HDC>(wp), &rc, g_brCard);
        return 1;
    }
    return DefSubclassProc(h, msg, wp, lp);
}

LRESULT CALLBACK listSubclass(HWND h, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
    if (msg == WM_NOTIFY) {
        auto* nm = reinterpret_cast<NMHDR*>(lp);
        if (nm->hwndFrom == ListView_GetHeader(h) && nm->code == NM_CUSTOMDRAW) {
            auto* cd = reinterpret_cast<NMCUSTOMDRAW*>(lp);
            if (cd->dwDrawStage == CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
            if (cd->dwDrawStage == CDDS_ITEMPREPAINT) {
                RECT rc = cd->rc;
                FillRect(cd->hdc, &rc, g_brCard);
                wchar_t buf[128] = {};
                HDITEMW item = {};
                item.mask = HDI_TEXT;
                item.pszText = buf;
                item.cchTextMax = 128;
                Header_GetItem(nm->hwndFrom, static_cast<int>(cd->dwItemSpec), &item);
                RECT tr1 = rc;
                tr1.left += px(12);
                text(cd->hdc, buf, tr1, g_fSection, g_pal.text, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
                RECT line = {rc.left, rc.bottom - 1, rc.right, rc.bottom};
                HBRUSH b = CreateSolidBrush(g_pal.divider);
                FillRect(cd->hdc, &line, b);
                if (cd->dwItemSpec == 0) {  // column separator
                    RECT sep = {rc.right - 1, rc.top + px(6), rc.right, rc.bottom - px(6)};
                    FillRect(cd->hdc, &sep, b);
                }
                DeleteObject(b);
                return CDRF_SKIPDEFAULT;
            }
        }
    }
    return DefSubclassProc(h, msg, wp, lp);
}

HWND makeList(int id, const wchar_t* c1, const wchar_t* c2) {
    HWND h = makeCtl(WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_NOSORTHEADER | WS_TABSTOP,
                     id);
    ListView_SetExtendedListViewStyle(h, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
    applyControlTheme(h, L"DarkMode_Explorer");
    if (HWND hdr = ListView_GetHeader(h)) {
        applyControlTheme(hdr, L"DarkMode_ItemsView");
        SetWindowSubclass(hdr, headerSubclass, 1, 0);
    }
    SetWindowSubclass(h, listSubclass, 1, 0);
    // Body = the card colour, so the list reads as part of the card (framed in paintPage).
    ListView_SetBkColor(h, g_pal.card);
    ListView_SetTextBkColor(h, g_pal.card);
    ListView_SetTextColor(h, g_pal.text);
    LVCOLUMNW col = {};
    col.mask = LVCF_TEXT | LVCF_WIDTH;
    col.cx = px(200);
    col.pszText = const_cast<LPWSTR>(c1);
    ListView_InsertColumn(h, 0, &col);
    col.cx = px(360);
    col.pszText = const_cast<LPWSTR>(c2);
    ListView_InsertColumn(h, 1, &col);
    return h;
}

void fitColumns() {
    if (!g_list) return;
    RECT rc;
    GetClientRect(g_list, &rc);
    ListView_SetColumnWidth(g_list, 0, rc.right * 2 / 5);
    ListView_SetColumnWidth(g_list, 1, LVSCW_AUTOSIZE_USEHEADER);  // last column fills the rest
}

void createControls() {
    g_list = g_edit1 = g_edit2 = g_combo = nullptr;
    g_blockButtons.clear();
    g_edits.clear();
    for (Item& it : g_items) {
        if (it.kind == ItemKind::Setting) {
            if (it.ctl == Ctl::Toggle) {
                it.hwnd = CreateWindowExW(0, kToggleClass, tr(it.title), WS_CHILD | WS_VISIBLE | WS_TABSTOP, 0, 0,
                                          10, 10, g_page,
                                          reinterpret_cast<HMENU>(static_cast<INT_PTR>(IdToggleBase + it.toggle)),
                                          g_inst, nullptr);
            } else if (it.ctl == Ctl::Combo) {
                switch (it.ctlId) {
                    case IdComboMethod: {
                        const S m[] = {S::Telex, S::Vni};
                        it.hwnd = makeCombo(it.ctlId, m, 2);
                        break;
                    }
                    case IdComboHotkey: it.hwnd = makeCombo(it.ctlId, kHotkeyLabels, 4); break;
                    case IdComboLang: {
                        it.hwnd = makeCtl(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP, it.ctlId);
                        SendMessageW(it.hwnd, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"Tiếng Việt"));
                        SendMessageW(it.hwnd, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"English"));
                        applyControlTheme(it.hwnd, L"DarkMode_CFD");
                        SendMessageW(it.hwnd, CB_SETITEMHEIGHT, static_cast<WPARAM>(-1), px(32) - px(6));
                        break;
                    }
                    default: break;
                }
            } else if (it.ctl == Ctl::Button) {
                if (it.ctlId == IdUninstall) it.hwnd = makeButton(tr(S::UninstallButton), it.ctlId, kBtnDanger);
                else it.hwnd = makeButton(tr(it.ctlId == IdCheckNow ? S::CheckButton : it.title), it.ctlId);
            }
        } else if (it.kind == ItemKind::IconPicker) {
            for (int i = 0; i < kIconChoiceCount; ++i) {
                HWND t = makeCtl(L"BUTTON", tr(kIconLabels[i]), BS_OWNERDRAW | WS_TABSTOP, IdIconTile + i);
                SetWindowLongPtrW(t, GWLP_USERDATA, kBtnTile + i);
                g_blockButtons.push_back(t);
            }
        } else if (it.kind == ItemKind::Block) {
            const bool sc = g_tab == 2;
            g_list = sc ? makeList(IdScList, tr(S::ShortcutKey), tr(S::ShortcutValue))
                        : makeList(IdAppList, tr(S::AppExe), tr(S::AppModeLabel));
            g_edit1 = sc ? makeEdit(IdScKey, tr(S::ShortcutKey)) : makeEdit(IdAppExe, tr(S::AppExe));
            if (sc) g_edit2 = makeEdit(IdScValue, tr(S::ShortcutValue));
            else g_combo = makeCombo(IdAppMode, kModeLabels, 4);
            g_blockButtons.push_back(makeButton(tr(S::Add), sc ? IdScAdd : IdAppAdd, kBtnPrimary));
            g_blockButtons.push_back(makeButton(tr(S::Remove), sc ? IdScRemove : IdAppRemove));
            if (sc) {
                g_blockButtons.push_back(makeButton(tr(S::Import), IdScImport));
                g_blockButtons.push_back(makeButton(tr(S::Export), IdScExport));
            }
        }
    }
}

// Computes rects (page coordinates) and the total content height.
void layout() {
    RECT client;
    GetClientRect(g_page, &client);
    const int x0 = px(kPad), x1 = client.right - px(kPad);
    const int cardW = x1 - x0;
    int y = px(24) + px(40) + px(16);  // page title block
    for (Item& it : g_items) {
        switch (it.kind) {
            case ItemKind::Section:
                y += (&it == &g_items.front()) ? 0 : px(kSectionGap - kCardGap);
                it.rc = {x0, y, x1, y + px(32)};
                y = it.rc.bottom;
                break;
            case ItemKind::Setting: {
                const int ctlW = it.ctl == Ctl::Toggle ? px(kToggleW + 56) : it.ctl == Ctl::None ? 0 : px(kControlW);
                const int textW = cardW - 2 * px(kCardPadX) - ctlW - px(24);
                int h = textHeight(tr(it.title), textW, g_fBody);
                if (it.desc != S::Count) h += px(2) + textHeight(tr(it.desc), textW, g_fCaption);
                h = std::max(h + 2 * px(kCardPadY), px(68));
                it.rc = {x0, y, x1, y + h};
                y = it.rc.bottom + px(kCardGap);
                break;
            }
            case ItemKind::Block: {
                const int textW = cardW - 2 * px(kCardPadX);
                int head = textHeight(tr(it.title), textW, g_fSection) + px(4) + textHeight(tr(it.desc), textW, g_fCaption);
                it.rc = {x0, y, x1, y + 2 * px(kCardPadY) + head + px(16) + px(it.blockHeight)};
                y = it.rc.bottom + px(kCardGap);
                break;
            }
            case ItemKind::IconPicker: {
                const int textW = cardW - 2 * px(kCardPadX);
                const int head = textHeight(tr(it.title), textW, g_fBody) + px(2) + textHeight(tr(it.desc), textW, g_fCaption);
                it.rc = {x0, y, x1, y + 2 * px(kCardPadY) + head + px(12) + px(kTileH)};
                y = it.rc.bottom + px(kCardGap);
                break;
            }
            case ItemKind::About: {
                const int textW = cardW - px(24 + 64 + 20 + 24);
                const int h = px(20) + px(28) + px(20) + px(4) + textHeight(tr(S::AboutText), textW, g_fCaption) + px(20);
                it.rc = {x0, y, x1, y + std::max(h, px(112))};
                y = it.rc.bottom + px(kCardGap);
                break;
            }
            case ItemKind::Links:
                y += px(16);
                it.rc = {x0, y, x1, y + px(24)};
                y = it.rc.bottom;
                break;
        }
    }
    g_contentH = y + px(32);
}

void placeControls() {
    HDWP dwp = BeginDeferWindowPos(24);
    auto put = [&](HWND h, int x, int y, int w, int hh) {
        if (h) dwp = DeferWindowPos(dwp, h, nullptr, x, y - g_scroll, w, hh, SWP_NOZORDER | SWP_NOACTIVATE);
    };
    for (Item& it : g_items) {
        const RECT& r = it.rc;
        const int midY = (r.top + r.bottom) / 2;
        if (it.kind == ItemKind::Setting && it.hwnd) {
            if (it.ctl == Ctl::Toggle) {
                const int w = px(kToggleW + 8), h = px(kToggleH + 8);
                put(it.hwnd, r.right - px(kCardPadX) - w, midY - h / 2, w, h);
            } else if (it.ctl == Ctl::Combo) {
                put(it.hwnd, r.right - px(kCardPadX) - px(kControlW), midY - px(16), px(kControlW), px(320));
            } else if (it.ctl == Ctl::Button) {
                put(it.hwnd, r.right - px(kCardPadX) - px(kControlW), midY - px(16), px(kControlW), px(32));
            }
        } else if (it.kind == ItemKind::IconPicker) {
            int x = r.left + px(kCardPadX);
            const int y = r.bottom - px(kCardPadY) - px(kTileH);
            for (HWND t : g_blockButtons) {
                put(t, x, y, px(kTileW), px(kTileH));
                x += px(kTileW + 8);
            }
        } else if (it.kind == ItemKind::Block) {
            const int left = r.left + px(kCardPadX), right = r.right - px(kCardPadX);
            int y = r.bottom - px(kCardPadY) - px(it.blockHeight);
            const int listH = px(it.blockHeight) - px(32 + 8 + 32 + 8);
            put(g_list, left, y, right - left, listH);
            y += listH + px(8);
            const int half = (right - left - px(8)) / 2;
            // Edits sit inside a painted 32px frame: 10px side padding, one text line tall.
            const int lineH = px(20), inset = (px(32) - lineH) / 2;
            put(g_edit1, left + px(10), y + inset, half - px(20), lineH);
            put(g_edit2, left + half + px(8) + px(10), y + inset, half - px(20), lineH);
            if (g_combo) put(g_combo, left + half + px(8), y, half, px(320));
            y += px(32 + 8);
            int bx = left;
            for (HWND b : g_blockButtons) {
                put(b, bx, y, px(112), px(32));
                bx += px(112 + 8);
            }
        }
    }
    EndDeferWindowPos(dwp);
    fitColumns();
}

void updateScrollbar() {
    RECT rc;
    GetClientRect(g_page, &rc);
    const int maxScroll = std::max(0, g_contentH - static_cast<int>(rc.bottom));
    g_scroll = std::min(g_scroll, maxScroll);
    SCROLLINFO si = {};
    si.cbSize = sizeof si;
    si.fMask = SIF_RANGE | SIF_PAGE | SIF_POS;
    si.nMax = g_contentH - 1;
    si.nPage = static_cast<UINT>(rc.bottom);
    si.nPos = g_scroll;
    SetScrollInfo(g_page, SB_VERT, &si, TRUE);
}

void scrollTo(int pos) {
    RECT rc;
    GetClientRect(g_page, &rc);
    pos = std::max(0, std::min(pos, std::max(0, g_contentH - static_cast<int>(rc.bottom))));
    if (pos == g_scroll) return;
    g_scroll = pos;
    placeControls();
    updateScrollbar();
    InvalidateRect(g_page, nullptr, TRUE);
}

// ---------------------------------------------------------------- state sync
int modeIndex(AppMode m) {
    for (int i = 0; i < 4; ++i)
        if (kModes[i] == m) return i;
    return 0;
}

void addRow(HWND list, int row, const std::wstring& a, const std::wstring& b) {
    LVITEMW it = {};
    it.mask = LVIF_TEXT;
    it.iItem = row;
    it.pszText = const_cast<LPWSTR>(a.c_str());
    ListView_InsertItem(list, &it);
    ListView_SetItemText(list, row, 1, const_cast<LPWSTR>(b.c_str()));
}

std::wstring rowText(HWND list, int row, int col) {
    wchar_t buf[1024] = {};
    ListView_GetItemText(list, row, col, buf, 1024);
    return buf;
}

void fillList() {
    if (!g_list) return;
    ListView_DeleteAllItems(g_list);
    int row = 0;
    if (g_tab == 2) {
        for (const auto& kv : g_settings.shortcuts) addRow(g_list, row++, u16w(kv.first), u16w(kv.second));
    } else {
        for (const auto& kv : g_settings.appModes)
            addRow(g_list, row++, widen(kv.first), tr(kModeLabels[modeIndex(kv.second)]));
    }
    fitColumns();
}

void sync() {
    if (!g_page) return;
    g_syncing = true;
    for (const Item& it : g_items) {
        if (!it.hwnd) continue;
        if (it.ctl == Ctl::Toggle) {
            SendMessageW(it.hwnd, BM_SETCHECK, (g_settings.*kToggles[it.toggle].field) ? BST_CHECKED : BST_UNCHECKED, 0);
            continue;
        }
        int sel = 0;
        switch (it.ctlId) {
            case IdComboMethod: sel = g_settings.vniMode ? 1 : 0; break;
            case IdComboHotkey:
                for (int i = 0; i < 4; ++i)
                    if (g_settings.switchHotkey == kHotkeys[i]) sel = i;
                break;
            case IdComboLang: sel = g_settings.uiLanguage == "en" ? 1 : 0; break;
            default: continue;
        }
        SendMessageW(it.hwnd, CB_SETCURSEL, static_cast<WPARAM>(sel), 0);
    }
    if (g_combo) SendMessageW(g_combo, CB_SETCURSEL, 0, 0);
    fillList();
    g_syncing = false;
    InvalidateRect(g_page, nullptr, FALSE);
    for (HWND b : g_blockButtons) InvalidateRect(b, nullptr, FALSE);
}

void buildPage() {
    if (!g_page) return;
    // Destroy the previous page's controls.
    HWND child = GetWindow(g_page, GW_CHILD);
    while (child) {
        HWND next = GetWindow(child, GW_HWNDNEXT);
        DestroyWindow(child);
        child = next;
    }
    g_items = pageItems(g_tab);
    g_scroll = 0;
    createControls();
    layout();
    placeControls();
    updateScrollbar();
    sync();
    InvalidateRect(g_page, nullptr, TRUE);
}

// ---------------------------------------------------------------- painting
void paintControlFrames(HDC dc, Gdiplus::Graphics& g);

void paintPage(HDC dc, const RECT& client) {
    FillRect(dc, &client, g_brBg);
    g_links.clear();
    Gdiplus::Graphics g(dc);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    const float radius = g_win11 ? static_cast<float>(px(6)) : 0.0f;
    const int off = -g_scroll;
    RECT title = {px(kPad), px(24) + off, client.right - px(kPad), px(24 + 40) + off};
    text(dc, tr(kPageTitles[g_tab]), title, g_fTitle, g_pal.text, DT_SINGLELINE | DT_VCENTER);
    for (const Item& it : g_items) {
        RECT r = it.rc;
        OffsetRect(&r, 0, off);
        if (r.bottom < 0 || r.top > client.bottom) continue;
        switch (it.kind) {
            case ItemKind::Section:
                text(dc, tr(it.title), r, g_fSection, g_pal.text, DT_SINGLELINE | DT_VCENTER);
                break;
            case ItemKind::Setting: {
                fillRound(g, r, radius, g_pal.card, g_pal.cardBorder, true);
                const int ctlW = it.ctl == Ctl::Toggle ? px(kToggleW + 56) : it.ctl == Ctl::None ? 0 : px(kControlW);
                const int textW = (r.right - r.left) - 2 * px(kCardPadX) - ctlW - px(24);
                const int th = textHeight(tr(it.title), textW, g_fBody);
                const int dh = it.desc != S::Count ? px(2) + textHeight(tr(it.desc), textW, g_fCaption) : 0;
                int ty = (r.top + r.bottom - th - dh) / 2;
                RECT tr1 = {r.left + px(kCardPadX), ty, r.left + px(kCardPadX) + textW, ty + th};
                text(dc, tr(it.title), tr1, g_fBody, g_pal.text, DT_WORDBREAK);
                if (dh) {
                    RECT tr2 = {tr1.left, tr1.bottom + px(2), tr1.right, tr1.bottom + dh};
                    text(dc, tr(it.desc), tr2, g_fCaption, g_pal.subtext, DT_WORDBREAK);
                }
                if (it.ctl == Ctl::Toggle && it.hwnd) {  // "Bật"/"Tắt" left of the switch
                    const bool on = SendMessageW(it.hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED;
                    RECT lr = {r.right - px(kCardPadX) - px(kToggleW + 8) - px(56), r.top,
                               r.right - px(kCardPadX) - px(kToggleW + 8) - px(8), r.bottom};
                    text(dc, tr(on ? S::On : S::Off), lr, g_fBody, g_pal.text, DT_SINGLELINE | DT_VCENTER | DT_RIGHT);
                }
                break;
            }
            case ItemKind::Block: {
                fillRound(g, r, radius, g_pal.card, g_pal.cardBorder, true);
                const int textW = (r.right - r.left) - 2 * px(kCardPadX);
                RECT tr1 = {r.left + px(kCardPadX), r.top + px(kCardPadY), r.left + px(kCardPadX) + textW, r.bottom};
                const int th = textHeight(tr(it.title), textW, g_fSection);
                text(dc, tr(it.title), tr1, g_fSection, g_pal.text, DT_WORDBREAK);
                tr1.top += th + px(4);
                text(dc, tr(it.desc), tr1, g_fCaption, g_pal.subtext, DT_WORDBREAK);
                break;
            }
            case ItemKind::IconPicker: {
                fillRound(g, r, radius, g_pal.card, g_pal.cardBorder, true);
                const int textW = (r.right - r.left) - 2 * px(kCardPadX);
                RECT tr1 = {r.left + px(kCardPadX), r.top + px(kCardPadY), r.left + px(kCardPadX) + textW, r.bottom};
                const int th = textHeight(tr(it.title), textW, g_fBody);
                text(dc, tr(it.title), tr1, g_fBody, g_pal.text, DT_WORDBREAK);
                tr1.top += th + px(2);
                text(dc, tr(it.desc), tr1, g_fCaption, g_pal.subtext, DT_WORDBREAK);
                break;
            }
            case ItemKind::About: {
                fillRound(g, r, radius, g_pal.card, g_pal.cardBorder, true);
                const int icon = px(64);
                if (g_bigIcon)
                    DrawIconEx(dc, r.left + px(24), (r.top + r.bottom - icon) / 2, g_bigIcon, icon, icon, 0, nullptr,
                               DI_NORMAL);
                RECT tr1 = {r.left + px(24) + icon + px(20), r.top + px(20), r.right - px(24), r.top + px(48)};
                text(dc, L"VietTelex", tr1, g_fHeader, g_pal.text, DT_SINGLELINE | DT_VCENTER);
                RECT tr2 = {tr1.left, tr1.bottom, tr1.right, tr1.bottom + px(20)};
                text(dc, std::wstring(tr(S::Version)) + L" " + widen(versionForDisplay(VTX_VER_STRING)), tr2,
                     g_fCaption, g_pal.subtext,
                     DT_SINGLELINE | DT_VCENTER);
                RECT tr3 = {tr1.left, tr2.bottom + px(4), tr1.right, r.bottom - px(12)};
                text(dc, tr(S::AboutText), tr3, g_fCaption, g_pal.subtext, DT_WORDBREAK);
                break;
            }
            case ItemKind::Links: {
                struct L {
                    S label;
                    const wchar_t* url;
                };
                const L links[] = {{S::LinkWebsite, L"https://viettelex.com"},
                                   {S::LinkSource, L"https://github.com/ptrinh/viettelex"},
                                   {S::LinkLearn, L"https://viettelex.com/hoc-go-telex"}};
                int x = r.left;
                HDC mdc = dc;
                HGDIOBJ old = SelectObject(mdc, g_fBody);
                for (const L& l : links) {
                    SIZE sz;
                    const wchar_t* s = tr(l.label);
                    GetTextExtentPoint32W(mdc, s, lstrlenW(s), &sz);
                    RECT lr = {x, r.top, x + sz.cx, r.bottom};
                    text(dc, s, lr, g_fBody, g_pal.accent, DT_SINGLELINE | DT_VCENTER);
                    RECT hit = lr;
                    OffsetRect(&hit, 0, g_scroll);
                    g_links.push_back({hit, l.url});
                    x += sz.cx + px(24);
                }
                SelectObject(mdc, old);
                break;
            }
        }
    }
    paintControlFrames(dc, g);
}

// Fluent text-box frames around the borderless edits, and a frame around each list.
void paintControlFrames(HDC dc, Gdiplus::Graphics& g) {
    auto frameOf = [&](HWND h, int padX, int padY) {
        RECT r;
        GetWindowRect(h, &r);
        MapWindowPoints(nullptr, g_page, reinterpret_cast<POINT*>(&r), 2);
        InflateRect(&r, padX, padY);
        return r;
    };
    const float radius = static_cast<float>(px(4));
    for (HWND e : g_edits) {
        if (!IsWindowVisible(e)) continue;
        const int inset = (px(32) - px(20)) / 2;
        RECT r = frameOf(e, px(10), inset);
        fillRound(g, r, radius, g_pal.ctrlBg, g_pal.ctrlBorder, true);
        const bool focus = GetFocus() == e;
        RECT line = {r.left + px(1), r.bottom - (focus ? px(2) : 1), r.right - px(1), r.bottom};
        HBRUSH b = CreateSolidBrush(focus ? g_pal.accent : g_pal.toggleOffBorder);
        FillRect(dc, &line, b);
        DeleteObject(b);
    }
    if (g_list && IsWindowVisible(g_list)) {
        RECT r = frameOf(g_list, 1, 1);
        Gdiplus::GraphicsPath path;
        roundRectPath(path, r.left + 0.5f, r.top + 0.5f, static_cast<float>(r.right - r.left - 1),
                      static_cast<float>(r.bottom - r.top - 1), radius);
        Gdiplus::Pen pen(gc(g_pal.ctrlBorder), 1.0f);
        g.DrawPath(&pen, &path);
    }
}

void paintNav(HDC dc, const RECT& client) {
    RECT nav = {0, 0, px(kNavW), client.bottom};
    FillRect(dc, &nav, g_brBg);
    Gdiplus::Graphics g(dc);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    // Header: app icon + name
    const int icon = px(32);
    if (g_appIcon) DrawIconEx(dc, px(20), px(20), g_appIcon, icon, icon, 0, nullptr, DI_NORMAL);
    RECT hr = {px(20) + icon + px(12), px(20), nav.right - px(12), px(20) + icon};
    text(dc, L"VietTelex", hr, g_fHeader, g_pal.text, DT_SINGLELINE | DT_VCENTER);
    for (int i = 0; i < kPageCount; ++i) {
        RECT r = {px(8), px(84) + i * px(40), nav.right - px(8), px(84) + i * px(40) + px(36)};
        if (i == g_tab || i == g_hoverNav)
            fillRound(g, r, static_cast<float>(px(4)), i == g_tab ? g_pal.navSelected : g_pal.navHover, 0, false);
        if (i == g_tab) {  // accent pill, like Win11 Settings
            RECT pill = {r.left, r.top + px(10), r.left + px(3), r.bottom - px(10)};
            fillRound(g, pill, 1.5f * g_dpi / 96, g_pal.accent, 0, false);
        }
        int tx = r.left + px(16);
        if (g_fIcon) {
            RECT ir = {tx, r.top, tx + px(20), r.bottom};
            text(dc, std::wstring(1, kNavGlyphs[i]), ir, g_fIcon, g_pal.text, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            tx += px(20 + 14);
        }
        RECT tr1 = {tx, r.top, r.right - px(8), r.bottom};
        text(dc, tr(kPageTitles[i]), tr1, g_fBody, g_pal.text, DT_SINGLELINE | DT_VCENTER);
    }
}

void paintBuffered(HWND h, void (*fn)(HDC, const RECT&)) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(h, &ps);
    RECT rc;
    GetClientRect(h, &rc);
    HDC mem = CreateCompatibleDC(dc);
    HBITMAP bmp = CreateCompatibleBitmap(dc, std::max(1L, rc.right), std::max(1L, rc.bottom));
    HGDIOBJ old = SelectObject(mem, bmp);
    fn(mem, rc);
    BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY);
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
    EndPaint(h, &ps);
}

// ---------------------------------------------------------------- actions
void changed() {
    if (!g_syncing) settingsChanged();
}

bool validShortcutKey(const std::wstring& k) {
    if (k.empty() || k.size() > 64) return false;
    for (wchar_t c : k)
        if (c == L' ' || c == L'\t' || c == L'\r' || c == L'\n') return false;
    return true;
}

void importShortcuts() {
    wchar_t file[MAX_PATH] = {};
    OPENFILENAMEW ofn = {};
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = g_wnd;
    ofn.lpstrFilter = L"Shortcuts (*.yml;*.yaml;*.txt;*.json)\0*.yml;*.yaml;*.txt;*.json\0All files\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
    if (!GetOpenFileNameW(&ofn)) return;
    HANDLE f = CreateFileW(file, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    std::string data;
    if (f != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER size;
        if (GetFileSizeEx(f, &size) && size.QuadPart > 0 && size.QuadPart < (8 << 20)) {
            data.resize(static_cast<size_t>(size.QuadPart));
            DWORD got = 0;
            if (!ReadFile(f, &data[0], static_cast<DWORD>(data.size()), &got, nullptr)) data.clear();
            data.resize(got);
        }
        CloseHandle(f);
    }
    StringMap m;
    if (data.empty() || !parseShortcutFile(data, m)) {
        MessageBoxW(g_wnd, tr(S::ImportFailed), tr(S::AppName), MB_ICONWARNING);
        return;
    }
    for (const auto& kv : m) g_settings.shortcuts[utf8ToUtf16(kv.first)] = utf8ToUtf16(kv.second);
    changed();
    fillList();
}

void exportShortcuts() {
    wchar_t file[MAX_PATH] = L"viettelex-shortcuts.yml";
    OPENFILENAMEW ofn = {};
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = g_wnd;
    ofn.lpstrFilter = L"YAML (*.yml)\0*.yml\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrDefExt = L"yml";
    ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
    if (!GetSaveFileNameW(&ofn)) return;
    StringMap m;
    for (const auto& kv : g_settings.shortcuts) m[utf16ToUtf8(kv.first)] = utf16ToUtf8(kv.second);
    std::string y = exportShortcutsYaml(m);
    HANDLE f = CreateFileW(file, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    DWORD w = 0;
    WriteFile(f, y.data(), static_cast<DWORD>(y.size()), &w, nullptr);
    CloseHandle(f);
}

void rebuildAll();

bool nativeArm64() {
    SYSTEM_INFO si;
    GetNativeSystemInfo(&si);
    return si.wProcessorArchitecture == 12;  // PROCESSOR_ARCHITECTURE_ARM64
}

std::vector<std::string> msiRelatedProducts(const std::string& upgradeCode) {
    std::vector<std::string> out;
    const std::wstring up = widen(upgradeCode);
    wchar_t code[39];
    for (DWORD i = 0; MsiEnumRelatedProductsW(up.c_str(), 0, i, code) == ERROR_SUCCESS; ++i) out.push_back(narrow(code));
    return out;
}

// "Gỡ cài đặt VietTelex": confirm, then msiexec /x <our ProductCode found by UpgradeCode>
// (msiexec elevates itself) and quit the tray app so its files are not in use. A dev
// build (nothing installed) opens Settings > Apps instead.
void uninstallVietTelex() {
    if (MessageBoxW(g_wnd, tr(S::UninstallConfirm), tr(S::AppName), MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
        return;
    const std::string code = findInstalledProductCode(msiRelatedProducts, nativeArm64());
    if (code.empty()) {
        ShellExecuteW(g_wnd, L"open", L"ms-settings:appsfeatures", nullptr, nullptr, SW_SHOWNORMAL);
        return;
    }
    const std::wstring params = widen(uninstallParameters(code));
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof sei;
    sei.fMask = SEE_MASK_NOASYNC;
    sei.hwnd = g_wnd;
    sei.lpVerb = L"open";
    sei.lpFile = L"msiexec.exe";
    sei.lpParameters = params.c_str();
    sei.nShow = SW_SHOWNORMAL;
    if (ShellExecuteExW(&sei)) {
        if (g_wnd) DestroyWindow(g_wnd);
        if (g_mainWnd) PostMessageW(g_mainWnd, WM_CLOSE, 0, 0);  // tray app exits; typing is unaffected
    }
}

// Keyboard-profile icon (HKLM) — changed by the elevated helper; one UAC prompt. The
// taskbar indicator / tray icon change immediately without it.
void applyProfileIcon(const std::string& name) {
    wchar_t exe[MAX_PATH];
    if (!GetModuleFileNameW(nullptr, exe, MAX_PATH)) return;
    const std::wstring params = L"--set-profile-icon " + widen(name);
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof sei;
    sei.hwnd = g_wnd;
    sei.lpVerb = L"runas";
    sei.lpFile = exe;
    sei.lpParameters = params.c_str();
    sei.nShow = SW_HIDE;
    ShellExecuteExW(&sei);  // declined UAC = only the profile icon stays as it was
}

void onCommand(int id, int code, HWND ctl) {
    if (id >= IdIconTile && id < IdIconTile + kIconChoiceCount && code == BN_CLICKED) {
        const std::string name = iconChoiceName(static_cast<IconChoice>(id - IdIconTile));
        if (parseIconChoice(g_settings.menuIcon) != static_cast<IconChoice>(id - IdIconTile) ||
            g_settings.menuIcon != name) {
            g_settings.menuIcon = name;  // also migrates a retired value ("letter")
            changed();
            for (HWND t : g_blockButtons) InvalidateRect(t, nullptr, FALSE);
            applyProfileIcon(name);
        }
        return;
    }
    if (id >= IdToggleBase && id < IdToggleBase + kToggleCount && code == BN_CLICKED) {
        g_settings.*kToggles[id - IdToggleBase].field = SendMessageW(ctl, BM_GETCHECK, 0, 0) == BST_CHECKED;
        changed();
        InvalidateRect(g_page, nullptr, FALSE);  // "Bật"/"Tắt" label
        return;
    }
    const auto sel = [&]() { return static_cast<int>(SendMessageW(ctl, CB_GETCURSEL, 0, 0)); };
    switch (id) {
        case IdComboMethod:
            if (code == CBN_SELCHANGE) {
                g_settings.vniMode = sel() == 1;
                changed();
            }
            break;
        case IdComboHotkey:
            if (code == CBN_SELCHANGE && sel() >= 0 && sel() < 4) {
                g_settings.switchHotkey = kHotkeys[sel()];
                changed();
            }
            break;
        case IdComboLang:
            if (code == CBN_SELCHANGE) {
                g_settings.uiLanguage = sel() == 1 ? "en" : "vi";
                changed();
                setEnglish(g_settings.uiLanguage == "en");
                PostMessageW(g_wnd, WM_APP + 1, 0, 0);  // rebuild outside this notification
            }
            break;
        case IdScAdd: {
            std::wstring k = trim(windowText(g_edit1)), v = trim(windowText(g_edit2));
            if (!validShortcutKey(k) || v.empty()) {
                MessageBeep(MB_ICONWARNING);
                break;
            }
            g_settings.shortcuts[wu16(k)] = wu16(v);
            changed();
            fillList();
            SetWindowTextW(g_edit1, L"");
            SetWindowTextW(g_edit2, L"");
            break;
        }
        case IdScRemove: {
            int s = ListView_GetNextItem(g_list, -1, LVNI_SELECTED);
            if (s < 0) break;
            g_settings.shortcuts.erase(wu16(rowText(g_list, s, 0)));
            changed();
            fillList();
            break;
        }
        case IdScImport: importShortcuts(); break;
        case IdScExport: exportShortcuts(); break;
        case IdAppAdd: {
            std::string exe = normalizeExeName(narrow(trim(windowText(g_edit1))));
            int m = static_cast<int>(SendMessageW(g_combo, CB_GETCURSEL, 0, 0));
            if (exe.empty() || exe.find('.') == std::string::npos || m < 0 || m > 3) {
                MessageBeep(MB_ICONWARNING);
                break;
            }
            g_settings.appModes[exe] = kModes[m];
            changed();
            fillList();
            SetWindowTextW(g_edit1, L"");
            break;
        }
        case IdAppRemove: {
            int s = ListView_GetNextItem(g_list, -1, LVNI_SELECTED);
            if (s < 0) break;
            g_settings.appModes.erase(narrow(rowText(g_list, s, 0)));
            changed();
            fillList();
            break;
        }
        case IdCheckNow: startUpdateCheck(g_mainWnd, true); break;
        case IdUninstall: uninstallVietTelex(); break;
        default: break;
    }
}

LRESULT onNotify(NMHDR* n) {
    if (n->code == LVN_GETEMPTYMARKUP) {  // centred empty-state text
        auto* em = reinterpret_cast<NMLVEMPTYMARKUP*>(n);
        em->dwFlags = EMF_CENTERED;
        lstrcpynW(em->szMarkup, tr(n->idFrom == IdScList ? S::EmptyShortcuts : S::EmptyApps), L_MAX_URL_LENGTH);
        return TRUE;
    }
    if (n->code != LVN_ITEMCHANGED) return 0;
    auto* lv = reinterpret_cast<NMLISTVIEW*>(n);
    if (!(lv->uNewState & LVIS_SELECTED)) return 0;
    if (n->idFrom == IdScList) {
        SetWindowTextW(g_edit1, rowText(g_list, lv->iItem, 0).c_str());
        SetWindowTextW(g_edit2, rowText(g_list, lv->iItem, 1).c_str());
    } else if (n->idFrom == IdAppList) {
        std::wstring exe = rowText(g_list, lv->iItem, 0);
        SetWindowTextW(g_edit1, exe.c_str());
        auto it = g_settings.appModes.find(narrow(exe));
        if (it != g_settings.appModes.end())
            SendMessageW(g_combo, CB_SETCURSEL, static_cast<WPARAM>(modeIndex(it->second)), 0);
    }
    return 0;
}

LRESULT colorCtl(HDC dc, bool ctrl) {
    SetTextColor(dc, g_pal.text);
    SetBkColor(dc, ctrl ? g_pal.ctrlBg : g_pal.card);
    return reinterpret_cast<LRESULT>(ctrl ? g_brCtrl : g_brCard);
}

LRESULT CALLBACK pageProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_COMMAND: onCommand(LOWORD(wp), HIWORD(wp), reinterpret_cast<HWND>(lp)); return 0;
        case WM_NOTIFY: return onNotify(reinterpret_cast<NMHDR*>(lp));
        case WM_DRAWITEM:
            if (reinterpret_cast<DRAWITEMSTRUCT*>(lp)->CtlType == ODT_BUTTON) {
                drawButton(reinterpret_cast<DRAWITEMSTRUCT*>(lp));
                return TRUE;
            }
            break;
        case WM_CTLCOLOREDIT:
        case WM_CTLCOLORLISTBOX: return colorCtl(reinterpret_cast<HDC>(wp), true);
        case WM_CTLCOLORSTATIC:
        case WM_CTLCOLORBTN: return colorCtl(reinterpret_cast<HDC>(wp), false);
        case WM_ERASEBKGND: return 1;
        case WM_PAINT: paintBuffered(h, paintPage); return 0;
        case WM_SIZE:
            if (!g_items.empty()) {
                layout();
                placeControls();
                updateScrollbar();
            }
            return 0;
        case WM_MOUSEWHEEL:
            scrollTo(g_scroll - GET_WHEEL_DELTA_WPARAM(wp) * px(48) / WHEEL_DELTA);
            return 0;
        case WM_VSCROLL: {
            SCROLLINFO si = {};
            si.cbSize = sizeof si;
            si.fMask = SIF_ALL;
            GetScrollInfo(h, SB_VERT, &si);
            int pos = g_scroll;
            switch (LOWORD(wp)) {
                case SB_LINEUP: pos -= px(40); break;
                case SB_LINEDOWN: pos += px(40); break;
                case SB_PAGEUP: pos -= static_cast<int>(si.nPage); break;
                case SB_PAGEDOWN: pos += static_cast<int>(si.nPage); break;
                case SB_THUMBTRACK:
                case SB_THUMBPOSITION: pos = si.nTrackPos; break;
                default: break;
            }
            scrollTo(pos);
            return 0;
        }
        case WM_LBUTTONUP: {
            POINT pt = {static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp)) + g_scroll};
            for (const LinkHit& l : g_links)
                if (PtInRect(&l.rc, pt)) ShellExecuteW(nullptr, L"open", l.url, nullptr, nullptr, SW_SHOWNORMAL);
            return 0;
        }
        case WM_SETCURSOR: {
            POINT pt;
            GetCursorPos(&pt);
            ScreenToClient(h, &pt);
            pt.y += g_scroll;
            for (const LinkHit& l : g_links)
                if (PtInRect(&l.rc, pt)) {
                    SetCursor(LoadCursorW(nullptr, IDC_HAND));
                    return TRUE;
                }
            break;
        }
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

int navHit(LPARAM lp) {
    const int x = static_cast<short>(LOWORD(lp)), y = static_cast<short>(HIWORD(lp));
    if (x < px(8) || x > px(kNavW - 8)) return -1;
    const int i = (y - px(84)) / px(40);
    if (y < px(84) || i < 0 || i >= kPageCount || (y - px(84)) % px(40) > px(36)) return -1;
    return i;
}

void selectTab(int i) {
    if (i < 0 || i >= kPageCount) return;
    g_tab = i;
    RECT nav = {0, 0, px(kNavW), 10000};
    InvalidateRect(g_wnd, &nav, FALSE);
    buildPage();
}

void applyWindowTheme() {
    BOOL dark = g_dark ? TRUE : FALSE;
    allowDark(g_wnd);
    // DWMWA_USE_IMMERSIVE_DARK_MODE is 20 from Windows 10 20H1; 1809-1909 used 19.
    if (FAILED(DwmSetWindowAttribute(g_wnd, 20, &dark, sizeof dark)))
        DwmSetWindowAttribute(g_wnd, 19, &dark, sizeof dark);
    // Windows 10 only repaints the caption with the new colour after a frame change.
    SetWindowPos(g_wnd, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    if (g_win11) {
        int corner = 2;  // DWMWCP_ROUND
        DwmSetWindowAttribute(g_wnd, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &corner, sizeof corner);
        int backdrop = 2;  // DWMSBT_MAINWINDOW (Mica), Win11 22H2+; ignored where unsupported
        DwmSetWindowAttribute(g_wnd, 38 /* DWMWA_SYSTEMBACKDROP_TYPE */, &backdrop, sizeof backdrop);
    }
    SetWindowTheme(g_page, g_dark ? L"DarkMode_Explorer" : L"Explorer", nullptr);  // scrollbar
}

void rebuildAll() {
    g_dpi = GetDpiForWindow(g_wnd);
    makePalette();
    makeFonts();
    makeBrushes();
    applyWindowTheme();
    if (g_appIcon) DestroyIcon(g_appIcon);
    if (g_bigIcon) DestroyIcon(g_bigIcon);
    g_appIcon = static_cast<HICON>(LoadImageW(g_inst, MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON, px(32), px(32), 0));
    g_bigIcon = static_cast<HICON>(LoadImageW(g_inst, MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON, px(64), px(64), 0));
    RECT rc;
    GetClientRect(g_wnd, &rc);
    MoveWindow(g_page, px(kNavW), 0, rc.right - px(kNavW), rc.bottom, FALSE);
    buildPage();
    InvalidateRect(g_wnd, nullptr, TRUE);
}

LRESULT CALLBACK wndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CREATE:
            g_wnd = h;
            g_page = CreateWindowExW(WS_EX_CONTROLPARENT, kPageClass, L"", WS_CHILD | WS_VISIBLE | WS_VSCROLL |
                                                                             WS_CLIPCHILDREN,
                                     0, 0, 10, 10, h, nullptr, g_inst, nullptr);
            rebuildAll();
            return 0;
        case WM_ERASEBKGND: return 1;
        case WM_PAINT: paintBuffered(h, paintNav); return 0;
        case WM_MOUSEMOVE: {
            int i = navHit(lp);
            if (i != g_hoverNav) {
                g_hoverNav = i;
                TRACKMOUSEEVENT t = {sizeof t, TME_LEAVE, h, 0};
                TrackMouseEvent(&t);
                RECT nav = {0, 0, px(kNavW), 10000};
                InvalidateRect(h, &nav, FALSE);
            }
            return 0;
        }
        case WM_MOUSELEAVE:
            g_hoverNav = -1;
            InvalidateRect(h, nullptr, FALSE);
            return 0;
        case WM_LBUTTONUP: selectTab(navHit(lp)); return 0;
        case WM_SETCURSOR:
            if (LOWORD(lp) == HTCLIENT) {
                POINT pt;
                GetCursorPos(&pt);
                ScreenToClient(h, &pt);
                if (navHit(MAKELPARAM(pt.x, pt.y)) >= 0) {
                    SetCursor(LoadCursorW(nullptr, IDC_HAND));
                    return TRUE;
                }
            }
            break;
        case WM_KEYDOWN:
            if (wp == VK_TAB && GetKeyState(VK_CONTROL) < 0) {  // Ctrl+(Shift+)Tab switches pages
                selectTab((g_tab + (GetKeyState(VK_SHIFT) < 0 ? kPageCount - 1 : 1)) % kPageCount);
                return 0;
            }
            break;
        case WM_DPICHANGED: {
            auto* r = reinterpret_cast<RECT*>(lp);
            SetWindowPos(h, nullptr, r->left, r->top, r->right - r->left, r->bottom - r->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            rebuildAll();
            return 0;
        }
        case WM_SETTINGCHANGE:
            if (lp && lstrcmpW(reinterpret_cast<LPCWSTR>(lp), L"ImmersiveColorSet") == 0) rebuildAll();
            break;
        case WM_DWMCOLORIZATIONCOLORCHANGED: rebuildAll(); break;
        case WM_APP + 1: rebuildAll(); return 0;
        case WM_CLOSE: DestroyWindow(h); return 0;
        case WM_DESTROY:
            g_wnd = g_page = nullptr;
            g_items.clear();
            g_list = g_edit1 = g_edit2 = g_combo = nullptr;
            g_blockButtons.clear();
            return 0;
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

void registerClasses() {
    static bool done = false;
    if (done) return;
    done = true;
    Gdiplus::GdiplusStartupInput in;
    Gdiplus::GdiplusStartup(&g_gdiplusToken, &in, nullptr);
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof wc;
    wc.lpfnWndProc = wndProc;
    wc.hInstance = g_inst;
    wc.hIcon = LoadIconW(g_inst, MAKEINTRESOURCEW(IDI_APP));
    wc.hIconSm = static_cast<HICON>(LoadImageW(g_inst, MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON,
                                               GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kWndClass;
    RegisterClassExW(&wc);
    wc.lpfnWndProc = pageProc;
    wc.hIcon = wc.hIconSm = nullptr;
    wc.lpszClassName = kPageClass;
    RegisterClassExW(&wc);
    wc.lpfnWndProc = toggleProc;
    wc.lpszClassName = kToggleClass;
    RegisterClassExW(&wc);
}

}  // namespace

bool systemUsesDarkApps() { return readDark(); }

void showSettings(Tab tab) {
    registerClasses();
    if (g_wnd) {
        selectTab(static_cast<int>(tab));
        ShowWindow(g_wnd, SW_SHOWNORMAL);
        SetForegroundWindow(g_wnd);
        return;
    }
    g_tab = static_cast<int>(tab);
    g_win11 = isWin11();
    std::wstring title = std::wstring(L"VietTelex — ") + tr(S::MenuSettings);
    if (!title.empty() && title.back() == L'…') title.pop_back();
    const UINT dpi = GetDpiForSystem();
    RECT r = {0, 0, MulDiv(kWinW, static_cast<int>(dpi), 96), MulDiv(kWinH, static_cast<int>(dpi), 96)};
    const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN;
    AdjustWindowRectExForDpi(&r, style, FALSE, WS_EX_CONTROLPARENT, dpi);
    HWND w = CreateWindowExW(WS_EX_CONTROLPARENT, kWndClass, title.c_str(), style, CW_USEDEFAULT, CW_USEDEFAULT,
                             r.right - r.left, r.bottom - r.top, nullptr, nullptr, g_inst, nullptr);
    if (!w) return;
    ShowWindow(w, SW_SHOWNORMAL);
    SetForegroundWindow(w);
}

void refreshSettingsWindow() { sync(); }

bool settingsDialogMessage(MSG* msg) {
    if (!g_wnd) return false;
    if (msg->message == WM_KEYDOWN && msg->wParam == VK_TAB && GetKeyState(VK_CONTROL) < 0) {
        SendMessageW(g_wnd, WM_KEYDOWN, msg->wParam, msg->lParam);
        return true;
    }
    return IsDialogMessageW(g_wnd, msg);
}

}  // namespace vtx::app
