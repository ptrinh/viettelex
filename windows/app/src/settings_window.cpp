// settings_window.cpp — Cài đặt: Kiểu gõ · Chính tả · Gõ tắt · Ứng dụng · Giới thiệu.
// Plain Win32 + Common Controls v6, laid out in code (DPI-aware: rebuilt on
// WM_DPICHANGED), dark title bar/background when Windows apps use dark mode.
// Every change applies immediately (like macOS) through settingsChanged().
#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <uxtheme.h>

#include <string>
#include <vector>

#include "app.h"
#include "shortcuts.h"
#include "settings_store.h"
#include "strings.h"
#include "updater.h"
#include "utf.h"
#include "version.h"

namespace vtx::app {

namespace {

constexpr wchar_t kWndClass[] = L"VietTelexSettings";
constexpr wchar_t kPageClass[] = L"VietTelexSettingsPage";
constexpr int kTabCount = 5;

enum Id : int {
    IdTab = 90,
    IdRadioTelex = 100,
    IdRadioVni,
    IdCheckBase = 200,  // + index into kChecks
    IdComboHotkey = 300,
    IdComboIcon,
    IdComboLang,
    IdScList = 400,
    IdScKey,
    IdScValue,
    IdScAdd,
    IdScRemove,
    IdScImport,
    IdScExport,
    IdAppList = 500,
    IdAppExe,
    IdAppMode,
    IdAppAdd,
    IdAppRemove,
    IdCheckNow = 600,
    IdLink,
};

struct CheckDef {
    Tab tab;
    bool Settings::*field;
    S label;
};
const CheckDef kChecks[] = {
    {Tab::Typing, &Settings::simpleTelex, S::SimpleTelex},
    {Tab::Typing, &Settings::freeMarking, S::FreeMarking},
    {Tab::Typing, &Settings::quickTelex, S::QuickTelex},
    {Tab::Typing, &Settings::modernOrthography, S::ModernOrthography},
    {Tab::Typing, &Settings::bracketVowels, S::BracketVowels},
    {Tab::Spelling, &Settings::autoRestore, S::AutoRestore},
    {Tab::Spelling, &Settings::liveSpellCheck, S::LiveSpellCheck},
    {Tab::Spelling, &Settings::contextualEnglish, S::ContextualEnglish},
    {Tab::Spelling, &Settings::collisionPrefersVietnamese, S::CollisionPrefersVi},
    {Tab::Spelling, &Settings::teencode, S::Teencode},
    {Tab::Spelling, &Settings::reEditWord, S::ReEditWord},
    {Tab::About, &Settings::autoUpdateCheck, S::AutoUpdateCheck},
    {Tab::About, &Settings::debugLogging, S::DebugLogging},
};
constexpr int kCheckCount = static_cast<int>(sizeof(kChecks) / sizeof(kChecks[0]));

const char* const kHotkeys[] = {"ctrl-shift", "win-space", "alt-z", "off"};
const S kHotkeyLabels[] = {S::HotkeyCtrlShift, S::HotkeyWinSpace, S::HotkeyAltZ, S::HotkeyOff};
const AppMode kModes[] = {AppMode::Composition, AppMode::InPlace, AppMode::HookFallback, AppMode::Off};
const S kModeLabels[] = {S::ModeComposition, S::ModeInPlace, S::ModeHook, S::ModeOff};

HWND g_wnd = nullptr;
HWND g_tabCtl = nullptr;
HWND g_pages[kTabCount] = {};
HFONT g_font = nullptr;
HBRUSH g_bg = nullptr;
bool g_dark = false;
UINT g_dpi = 96;
int g_tab = 0;
bool g_syncing = false;

int px(int dip) { return MulDiv(dip, static_cast<int>(g_dpi), 96); }

HWND ctl(int id) {
    for (HWND p : g_pages)
        if (HWND h = p ? GetDlgItem(p, id) : nullptr) return h;
    return nullptr;
}

std::wstring text(HWND h) {
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

std::wstring u16w(const std::u16string& s) { return widen(utf16ToUtf8(s)); }
std::u16string wu16(const std::wstring& s) { return utf8ToUtf16(narrow(s)); }

// ------------------------------------------------------------ layout helpers

struct Flow {
    HWND page;
    int x, y, w;
};

HWND add(Flow& f, const wchar_t* cls, const wchar_t* label, DWORD style, int id, int hDip, int wDip = -1,
         int xDip = 0, bool advance = true, DWORD exStyle = 0) {
    int w = wDip < 0 ? f.w - px(xDip) : px(wDip);
    HWND h = CreateWindowExW(exStyle, cls, label, WS_CHILD | WS_VISIBLE | style, f.x + px(xDip), f.y, w, px(hDip),
                             f.page, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), g_inst, nullptr);
    SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), FALSE);
    if (g_dark) {
        const bool isButton = lstrcmpW(cls, L"BUTTON") == 0;
        const bool pushButton = isButton && (style & 0xF) == BS_PUSHBUTTON;
        // Unthemed check/radio so WM_CTLCOLORSTATIC can make their text light.
        if (isButton && !pushButton) SetWindowTheme(h, L"", L"");
        else SetWindowTheme(h, L"DarkMode_Explorer", nullptr);
    }
    if (advance) f.y += px(hDip) + px(6);
    return h;
}

HWND label(Flow& f, const wchar_t* s, int hDip = 20) { return add(f, L"STATIC", s, SS_LEFT, -1, hDip); }

HWND check(Flow& f, int idx) {
    return add(f, L"BUTTON", tr(kChecks[idx].label), BS_AUTOCHECKBOX | WS_TABSTOP, IdCheckBase + idx, 22);
}

HWND combo(Flow& f, int id, const S* items, int n, int wDip, int xDip) {
    HWND h = add(f, L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, id, 200, wDip, xDip, false);
    for (int i = 0; i < n; ++i) SendMessageW(h, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(tr(items[i])));
    f.y += px(30);
    return h;
}

HWND listView(Flow& f, int id, int hDip, const wchar_t* c1, const wchar_t* c2) {
    HWND h = add(f, WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_TABSTOP | WS_BORDER, id,
                 hDip);
    ListView_SetExtendedListViewStyle(h, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
    RECT rc;
    GetClientRect(h, &rc);
    LVCOLUMNW col = {};
    col.mask = LVCF_TEXT | LVCF_WIDTH;
    col.pszText = const_cast<LPWSTR>(c1);
    col.cx = (rc.right - rc.left) * 2 / 5;
    ListView_InsertColumn(h, 0, &col);
    col.pszText = const_cast<LPWSTR>(c2);
    col.cx = (rc.right - rc.left) * 3 / 5 - px(4);
    ListView_InsertColumn(h, 1, &col);
    return h;
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

// ------------------------------------------------------------ pages

void buildTyping(HWND page, int width) {
    Flow f{page, px(16), px(14), width - px(32)};
    label(f, tr(S::InputMethod));
    add(f, L"BUTTON", tr(S::Telex), BS_AUTORADIOBUTTON | WS_GROUP | WS_TABSTOP, IdRadioTelex, 22, 120, 16, false);
    add(f, L"BUTTON", tr(S::Vni), BS_AUTORADIOBUTTON, IdRadioVni, 22, 120, 150);
    f.y += px(4);
    for (int i = 0; i < kCheckCount; ++i)
        if (kChecks[i].tab == Tab::Typing) check(f, i);
    f.y += px(8);
    label(f, tr(S::SwitchHotkey));
    combo(f, IdComboHotkey, kHotkeyLabels, 4, 300, 16);
    label(f, tr(S::HotkeyNote), 36);
    const S icons[] = {S::MenuIconVt, S::MenuIconLetter};
    label(f, tr(S::MenuIcon));
    combo(f, IdComboIcon, icons, 2, 160, 16);
    label(f, tr(S::UiLanguage));
    HWND lang = add(f, L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP, IdComboLang, 200, 160, 16, false);
    SendMessageW(lang, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"Tiếng Việt"));
    SendMessageW(lang, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"English"));
}

void buildSpelling(HWND page, int width) {
    Flow f{page, px(16), px(14), width - px(32)};
    for (int i = 0; i < kCheckCount; ++i)
        if (kChecks[i].tab == Tab::Spelling) check(f, i);
}

void buildShortcuts(HWND page, int width) {
    Flow f{page, px(16), px(14), width - px(32)};
    listView(f, IdScList, 250, tr(S::ShortcutKey), tr(S::ShortcutValue));
    const int half = (f.w - px(8)) / 2 * 96 / static_cast<int>(g_dpi);
    add(f, L"EDIT", L"", ES_AUTOHSCROLL | WS_TABSTOP, IdScKey, 24, half, 0, false, WS_EX_CLIENTEDGE);
    add(f, L"EDIT", L"", ES_AUTOHSCROLL | WS_TABSTOP, IdScValue, 24, half, half + 8, true, WS_EX_CLIENTEDGE);
    SendMessageW(ctl(IdScKey), EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(tr(S::ShortcutKey)));
    SendMessageW(ctl(IdScValue), EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(tr(S::ShortcutValue)));
    add(f, L"BUTTON", tr(S::Add), BS_PUSHBUTTON | WS_TABSTOP, IdScAdd, 28, 90, 0, false);
    add(f, L"BUTTON", tr(S::Remove), BS_PUSHBUTTON | WS_TABSTOP, IdScRemove, 28, 90, 98, false);
    add(f, L"BUTTON", tr(S::Import), BS_PUSHBUTTON | WS_TABSTOP, IdScImport, 28, 90, 216, false);
    add(f, L"BUTTON", tr(S::Export), BS_PUSHBUTTON | WS_TABSTOP, IdScExport, 28, 90, 314);
}

void buildApps(HWND page, int width) {
    Flow f{page, px(16), px(14), width - px(32)};
    listView(f, IdAppList, 230, tr(S::AppExe), tr(S::AppModeLabel));
    add(f, L"EDIT", L"", ES_AUTOHSCROLL | WS_TABSTOP, IdAppExe, 24, 220, 0, false, WS_EX_CLIENTEDGE);
    SendMessageW(ctl(IdAppExe), EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(tr(S::AppExe)));
    HWND mode = add(f, L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP, IdAppMode, 200, 220, 228);
    for (S s : kModeLabels) SendMessageW(mode, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(tr(s)));
    SendMessageW(mode, CB_SETCURSEL, 0, 0);
    f.y += px(2);
    add(f, L"BUTTON", tr(S::Add), BS_PUSHBUTTON | WS_TABSTOP, IdAppAdd, 28, 90, 0, false);
    add(f, L"BUTTON", tr(S::Remove), BS_PUSHBUTTON | WS_TABSTOP, IdAppRemove, 28, 90, 98);
    label(f, tr(S::AppsNote), 40);
}

void buildAbout(HWND page, int width) {
    Flow f{page, px(16), px(14), width - px(32)};
    std::wstring about = std::wstring(L"VietTelex ") + VTX_VER_STRING_W + L"\n\n" + tr(S::AboutText);
    label(f, about.c_str(), 80);
    for (int i = 0; i < kCheckCount; ++i)
        if (kChecks[i].tab == Tab::About) check(f, i);
    f.y += px(6);
    add(f, L"BUTTON", tr(S::CheckNow), BS_PUSHBUTTON | WS_TABSTOP, IdCheckNow, 28, 180);
    add(f, L"SysLink", L"<a href=\"https://viettelex.com\">viettelex.com</a> · "
                     L"<a href=\"https://github.com/ptrinh/viettelex\">GitHub</a>",
        WS_TABSTOP, IdLink, 22);
}

// ------------------------------------------------------------ state sync

void fillShortcuts() {
    HWND list = ctl(IdScList);
    if (!list) return;
    ListView_DeleteAllItems(list);
    int row = 0;
    for (const auto& kv : g_settings.shortcuts) addRow(list, row++, u16w(kv.first), u16w(kv.second));
}

int modeIndex(AppMode m) {
    for (int i = 0; i < 4; ++i)
        if (kModes[i] == m) return i;
    return 0;
}

void fillApps() {
    HWND list = ctl(IdAppList);
    if (!list) return;
    ListView_DeleteAllItems(list);
    int row = 0;
    for (const auto& kv : g_settings.appModes) addRow(list, row++, widen(kv.first), tr(kModeLabels[modeIndex(kv.second)]));
}

void sync() {
    if (!g_wnd) return;
    g_syncing = true;
    CheckRadioButton(g_pages[0], IdRadioTelex, IdRadioVni, g_settings.vniMode ? IdRadioVni : IdRadioTelex);
    for (int i = 0; i < kCheckCount; ++i)
        if (HWND h = ctl(IdCheckBase + i))
            SendMessageW(h, BM_SETCHECK, (g_settings.*kChecks[i].field) ? BST_CHECKED : BST_UNCHECKED, 0);
    int hk = 0;
    for (int i = 0; i < 4; ++i)
        if (g_settings.switchHotkey == kHotkeys[i]) hk = i;
    SendMessageW(ctl(IdComboHotkey), CB_SETCURSEL, static_cast<WPARAM>(hk), 0);
    SendMessageW(ctl(IdComboIcon), CB_SETCURSEL, g_settings.menuIcon == "letter" ? 1 : 0, 0);
    SendMessageW(ctl(IdComboLang), CB_SETCURSEL, g_settings.uiLanguage == "en" ? 1 : 0, 0);
    fillShortcuts();
    fillApps();
    g_syncing = false;
}

// ------------------------------------------------------------ build / theme

bool readDarkPreference() {
    DWORD v = 1, sz = sizeof v;
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                     L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &v, &sz) != ERROR_SUCCESS)
        return false;
    return v == 0;
}

void applyTitleBarTheme() {
    BOOL dark = g_dark ? TRUE : FALSE;
    DwmSetWindowAttribute(g_wnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &dark, sizeof dark);
}

void showTab(int i) {
    g_tab = i;
    for (int k = 0; k < kTabCount; ++k) ShowWindow(g_pages[k], k == i ? SW_SHOW : SW_HIDE);
}

void build() {
    // Tear down the previous controls (DPI/language/theme change rebuilds everything).
    if (g_tabCtl) DestroyWindow(g_tabCtl);
    for (HWND& p : g_pages) {
        if (p) DestroyWindow(p);
        p = nullptr;
    }
    if (g_font) DeleteObject(g_font);
    if (g_bg) DeleteObject(g_bg);

    g_dpi = GetDpiForWindow(g_wnd);
    g_dark = readDarkPreference();
    g_bg = CreateSolidBrush(g_dark ? RGB(32, 32, 32) : GetSysColor(COLOR_WINDOW));
    NONCLIENTMETRICSW ncm = {};
    ncm.cbSize = sizeof ncm;
    SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, g_dpi);
    g_font = CreateFontIndirectW(&ncm.lfMessageFont);
    applyTitleBarTheme();

    RECT rc;
    GetClientRect(g_wnd, &rc);
    g_tabCtl = CreateWindowExW(0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_TABSTOP, px(8),
                               px(8), rc.right - px(16), rc.bottom - px(16), g_wnd,
                               reinterpret_cast<HMENU>(static_cast<INT_PTR>(IdTab)), g_inst, nullptr);
    SendMessageW(g_tabCtl, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), FALSE);
    const S names[kTabCount] = {S::TabTyping, S::TabSpelling, S::TabShortcuts, S::TabApps, S::TabAbout};
    for (int i = 0; i < kTabCount; ++i) {
        TCITEMW it = {};
        it.mask = TCIF_TEXT;
        it.pszText = const_cast<LPWSTR>(tr(names[i]));
        TabCtrl_InsertItem(g_tabCtl, i, &it);
    }
    RECT page = {px(8), px(8), rc.right - px(8), rc.bottom - px(8)};
    TabCtrl_AdjustRect(g_tabCtl, FALSE, &page);
    const int w = page.right - page.left, h = page.bottom - page.top;
    for (int i = 0; i < kTabCount; ++i)
        g_pages[i] = CreateWindowExW(WS_EX_CONTROLPARENT, kPageClass, L"", WS_CHILD, page.left, page.top, w, h, g_wnd,
                                     nullptr, g_inst, nullptr);
    buildTyping(g_pages[0], w);
    buildSpelling(g_pages[1], w);
    buildShortcuts(g_pages[2], w);
    buildApps(g_pages[3], w);
    buildAbout(g_pages[4], w);
    TabCtrl_SetCurSel(g_tabCtl, g_tab);
    showTab(g_tab);
    sync();
}

// ------------------------------------------------------------ actions

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
    fillShortcuts();
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

void onCommand(int id, int code) {
    if (id >= IdCheckBase && id < IdCheckBase + kCheckCount && code == BN_CLICKED) {
        g_settings.*kChecks[id - IdCheckBase].field = SendMessageW(ctl(id), BM_GETCHECK, 0, 0) == BST_CHECKED;
        changed();
        return;
    }
    switch (id) {
        case IdRadioTelex:
        case IdRadioVni:
            if (code == BN_CLICKED) {
                g_settings.vniMode = id == IdRadioVni;
                changed();
            }
            break;
        case IdComboHotkey:
            if (code == CBN_SELCHANGE) {
                LRESULT i = SendMessageW(ctl(id), CB_GETCURSEL, 0, 0);
                if (i >= 0 && i < 4) g_settings.switchHotkey = kHotkeys[i];
                changed();
            }
            break;
        case IdComboIcon:
            if (code == CBN_SELCHANGE) {
                g_settings.menuIcon = SendMessageW(ctl(id), CB_GETCURSEL, 0, 0) == 1 ? "letter" : "vt";
                changed();
            }
            break;
        case IdComboLang:
            if (code == CBN_SELCHANGE) {
                g_settings.uiLanguage = SendMessageW(ctl(id), CB_GETCURSEL, 0, 0) == 1 ? "en" : "vi";
                changed();
                setEnglish(g_settings.uiLanguage == "en");
                PostMessageW(g_wnd, WM_APP + 1, 0, 0);  // rebuild outside this notification
            }
            break;
        case IdScAdd: {
            std::wstring k = trim(text(ctl(IdScKey))), v = trim(text(ctl(IdScValue)));
            if (!validShortcutKey(k) || v.empty()) {
                MessageBeep(MB_ICONWARNING);
                break;
            }
            g_settings.shortcuts[wu16(k)] = wu16(v);
            changed();
            fillShortcuts();
            SetWindowTextW(ctl(IdScKey), L"");
            SetWindowTextW(ctl(IdScValue), L"");
            break;
        }
        case IdScRemove: {
            int sel = ListView_GetNextItem(ctl(IdScList), -1, LVNI_SELECTED);
            if (sel < 0) break;
            g_settings.shortcuts.erase(wu16(rowText(ctl(IdScList), sel, 0)));
            changed();
            fillShortcuts();
            break;
        }
        case IdScImport: importShortcuts(); break;
        case IdScExport: exportShortcuts(); break;
        case IdAppAdd: {
            std::string exe = normalizeExeName(narrow(trim(text(ctl(IdAppExe)))));
            LRESULT m = SendMessageW(ctl(IdAppMode), CB_GETCURSEL, 0, 0);
            if (exe.empty() || exe.find('.') == std::string::npos || m < 0 || m > 3) {
                MessageBeep(MB_ICONWARNING);
                break;
            }
            g_settings.appModes[exe] = kModes[m];
            changed();
            fillApps();
            SetWindowTextW(ctl(IdAppExe), L"");
            break;
        }
        case IdAppRemove: {
            int sel = ListView_GetNextItem(ctl(IdAppList), -1, LVNI_SELECTED);
            if (sel < 0) break;
            g_settings.appModes.erase(narrow(rowText(ctl(IdAppList), sel, 0)));
            changed();
            fillApps();
            break;
        }
        case IdCheckNow: startUpdateCheck(g_mainWnd, true); break;
        default: break;
    }
}

void onNotify(NMHDR* n) {
    if (n->idFrom == IdTab && n->code == TCN_SELCHANGE) {
        showTab(TabCtrl_GetCurSel(g_tabCtl));
    } else if (n->idFrom == IdLink && (n->code == NM_CLICK || n->code == NM_RETURN)) {
        auto* link = reinterpret_cast<NMLINK*>(n);
        ShellExecuteW(nullptr, L"open", link->item.szUrl, nullptr, nullptr, SW_SHOWNORMAL);
    } else if (n->code == LVN_ITEMCHANGED) {
        auto* lv = reinterpret_cast<NMLISTVIEW*>(n);
        if (!(lv->uNewState & LVIS_SELECTED)) return;
        if (n->idFrom == IdScList) {
            SetWindowTextW(ctl(IdScKey), rowText(ctl(IdScList), lv->iItem, 0).c_str());
            SetWindowTextW(ctl(IdScValue), rowText(ctl(IdScList), lv->iItem, 1).c_str());
        } else if (n->idFrom == IdAppList) {
            std::wstring exe = rowText(ctl(IdAppList), lv->iItem, 0);
            SetWindowTextW(ctl(IdAppExe), exe.c_str());
            auto it = g_settings.appModes.find(narrow(exe));
            if (it != g_settings.appModes.end())
                SendMessageW(ctl(IdAppMode), CB_SETCURSEL, static_cast<WPARAM>(modeIndex(it->second)), 0);
        }
    }
}

LRESULT colorCtl(HDC dc) {
    if (g_dark) {
        SetTextColor(dc, RGB(235, 235, 235));
        SetBkColor(dc, RGB(32, 32, 32));
    } else {
        SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
        SetBkColor(dc, GetSysColor(COLOR_WINDOW));
    }
    return reinterpret_cast<LRESULT>(g_bg);
}

LRESULT CALLBACK pageProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_COMMAND: onCommand(LOWORD(wp), HIWORD(wp)); return 0;
        case WM_NOTIFY: onNotify(reinterpret_cast<NMHDR*>(lp)); return 0;
        case WM_CTLCOLORSTATIC:
        case WM_CTLCOLORBTN: return colorCtl(reinterpret_cast<HDC>(wp));
        case WM_CTLCOLOREDIT:
        case WM_CTLCOLORLISTBOX:
            if (g_dark) return colorCtl(reinterpret_cast<HDC>(wp));
            break;
        case WM_ERASEBKGND: {
            RECT rc;
            GetClientRect(h, &rc);
            FillRect(reinterpret_cast<HDC>(wp), &rc, g_bg);
            return 1;
        }
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

LRESULT CALLBACK wndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_NOTIFY: onNotify(reinterpret_cast<NMHDR*>(lp)); return 0;
        case WM_DPICHANGED: {
            auto* r = reinterpret_cast<RECT*>(lp);
            SetWindowPos(h, nullptr, r->left, r->top, r->right - r->left, r->bottom - r->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            build();
            return 0;
        }
        case WM_SETTINGCHANGE:
            if (lp && lstrcmpW(reinterpret_cast<LPCWSTR>(lp), L"ImmersiveColorSet") == 0) build();
            break;
        case WM_APP + 1: build(); return 0;
        case WM_ERASEBKGND: {
            RECT rc;
            GetClientRect(h, &rc);
            FillRect(reinterpret_cast<HDC>(wp), &rc, g_bg ? g_bg : GetSysColorBrush(COLOR_WINDOW));
            return 1;
        }
        case WM_CLOSE: DestroyWindow(h); return 0;
        case WM_DESTROY:
            g_wnd = nullptr;
            g_tabCtl = nullptr;
            for (HWND& p : g_pages) p = nullptr;
            return 0;
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

void registerClasses() {
    static bool done = false;
    if (done) return;
    done = true;
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof wc;
    wc.lpfnWndProc = wndProc;
    wc.hInstance = g_inst;
    wc.hIcon = LoadIconW(g_inst, MAKEINTRESOURCEW(1));
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kWndClass;
    RegisterClassExW(&wc);
    wc.lpfnWndProc = pageProc;
    wc.hIcon = nullptr;
    wc.lpszClassName = kPageClass;
    RegisterClassExW(&wc);
}

}  // namespace

bool systemUsesDarkApps() { return readDarkPreference(); }

void showSettings(Tab tab) {
    registerClasses();
    g_tab = static_cast<int>(tab);
    if (g_wnd) {
        TabCtrl_SetCurSel(g_tabCtl, g_tab);
        showTab(g_tab);
        ShowWindow(g_wnd, SW_SHOWNORMAL);
        SetForegroundWindow(g_wnd);
        return;
    }
    std::wstring title = std::wstring(L"VietTelex — ") + tr(S::MenuSettings);
    if (!title.empty() && title.back() == L'…') title.pop_back();
    UINT dpi = GetDpiForSystem();
    RECT r = {0, 0, MulDiv(580, static_cast<int>(dpi), 96), MulDiv(560, static_cast<int>(dpi), 96)};
    const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    AdjustWindowRectExForDpi(&r, style, FALSE, WS_EX_CONTROLPARENT, dpi);
    g_wnd = CreateWindowExW(WS_EX_CONTROLPARENT, kWndClass, title.c_str(), style, CW_USEDEFAULT, CW_USEDEFAULT,
                            r.right - r.left, r.bottom - r.top, nullptr, nullptr, g_inst, nullptr);
    if (!g_wnd) return;
    build();
    ShowWindow(g_wnd, SW_SHOWNORMAL);
    SetForegroundWindow(g_wnd);
}

void refreshSettingsWindow() { sync(); }

bool settingsDialogMessage(MSG* msg) { return g_wnd && IsDialogMessageW(g_wnd, msg); }

}  // namespace vtx::app
