// welcome.cpp — first-run window (app/core/onboarding.h decideWelcome): typing method,
// switch key, tray icon, other Vietnamese input methods, "Chuyển từ UniKey". Plain native
// controls; every choice applies at once like the Settings window. Shown once per user.
#include <windows.h>
#include <commctrl.h>

#include <string>
#include <vector>

#include "app.h"
#include "conflicts.h"
#include "res/icon_ids.h"
#include "settings_store.h"
#include "strings.h"

namespace vtx::app {

namespace {

constexpr wchar_t kWelcomeClass[] = L"VietTelexWelcome";
enum : int {
    IdTelex = 100,
    IdVni,
    IdSwitch,
    IdTray,
    IdResolve,
    IdImport,
    IdSettings,
};

const char* const kSwitchIds[] = {"ctrl-shift", "win-space", "alt-z", "off"};
const S kSwitchLabels[] = {S::HotkeyCtrlShift, S::HotkeyWinSpace, S::HotkeyAltZ, S::HotkeyOff};

HWND g_wnd = nullptr;
HFONT g_font = nullptr, g_title = nullptr;
UINT g_dpi = 96;
std::vector<FoundConflict> g_found;

int px(int v) { return MulDiv(v, static_cast<int>(g_dpi), 96); }

HWND add(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id = 0,
         HFONT font = nullptr) {
    HWND c = CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, px(x), px(y), px(w), px(h), g_wnd,
                             reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), g_inst, nullptr);
    SendMessageW(c, WM_SETFONT, reinterpret_cast<WPARAM>(font ? font : g_font), TRUE);
    return c;
}

void finish() {
    const bool tray = IsDlgButtonChecked(g_wnd, IdTray) == BST_CHECKED;
    if (tray != g_settings.showTrayIcon) {
        g_settings.showTrayIcon = tray;
        settingsChanged();
        refreshSettingsWindow();
    }
    DestroyWindow(g_wnd);
}

void build() {
    NONCLIENTMETRICSW ncm = {};
    ncm.cbSize = sizeof ncm;
    SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, g_dpi);
    g_font = CreateFontIndirectW(&ncm.lfMessageFont);
    LOGFONTW lf = ncm.lfMessageFont;
    lf.lfHeight = -px(20);
    lf.lfWeight = FW_SEMIBOLD;
    g_title = CreateFontIndirectW(&lf);

    const int W = 480;  // client width (DIP)
    int y = 20;
    add(L"STATIC", tr(S::WelcomeTitle), SS_LEFT, 24, y, W - 48, 30, 0, g_title);
    y += 38;
    add(L"STATIC", tr(S::WelcomeIntro), SS_LEFT, 24, y, W - 48, 40);
    y += 52;

    add(L"STATIC", tr(S::WelcomeMethod), SS_LEFT, 24, y + 3, 170, 20);
    add(L"BUTTON", tr(S::Telex), BS_AUTORADIOBUTTON | WS_GROUP | WS_TABSTOP, 200, y, 90, 24, IdTelex);
    add(L"BUTTON", tr(S::Vni), BS_AUTORADIOBUTTON, 300, y, 90, 24, IdVni);
    CheckRadioButton(g_wnd, IdTelex, IdVni, g_settings.vniMode ? IdVni : IdTelex);
    y += 36;

    add(L"STATIC", tr(S::WelcomeSwitch), SS_LEFT, 24, y + 4, 170, 20);
    HWND combo = add(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL | WS_GROUP, 200, y, 256, 200,
                     IdSwitch);
    int sel = 0;
    for (int i = 0; i < 4; ++i) {
        SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(tr(kSwitchLabels[i])));
        if (g_settings.switchHotkey == kSwitchIds[i]) sel = i;
    }
    SendMessageW(combo, CB_SETCURSEL, static_cast<WPARAM>(sel), 0);
    y += 40;

    // Tray icon: the setting stays OFF by default; the box is pre-ticked only for people
    // coming from UniKey & co. (whose state indicator was a tray icon).
    bool migrating = false;
    for (const FoundConflict& c : g_found) migrating = migrating || isThirdPartyIme(c.kind);
    add(L"BUTTON", tr(S::WelcomeTray), BS_AUTOCHECKBOX | WS_TABSTOP | WS_GROUP, 24, y, W - 48, 24, IdTray);
    CheckDlgButton(g_wnd, IdTray, (g_settings.showTrayIcon || migrating) ? BST_CHECKED : BST_UNCHECKED);
    y += 26;
    add(L"STATIC", tr(S::WelcomeTrayNote), SS_LEFT, 44, y, W - 68, 36);
    y += 46;

    if (!g_found.empty()) {
        const std::wstring msg = std::wstring(tr(S::ConflictTitle)) + L": " + conflictNames(g_found) + L". " +
                                 tr(S::ConflictDesc);
        add(L"STATIC", msg.c_str(), SS_LEFT, 24, y, W - 48 - 120, 60);
        add(L"BUTTON", tr(S::ConflictButton), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 110, y, 110, 30,
            IdResolve);
        y += 70;
    }

    add(L"BUTTON", tr(S::WelcomeImport), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, 24, y, 300, 30, IdImport);
    y += 52;

    add(L"BUTTON", tr(S::WelcomeOpenSettings), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 140 - 8 - 140, y,
        140, 32, IdSettings);
    add(L"BUTTON", tr(S::WelcomeDone), BS_DEFPUSHBUTTON | WS_TABSTOP, W - 24 - 140, y, 140, 32, IDOK);
    y += 32 + 20;

    RECT r = {0, 0, px(W), px(y)};
    const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(g_wnd, GWL_STYLE));
    AdjustWindowRectExForDpi(&r, style, FALSE, WS_EX_CONTROLPARENT, g_dpi);
    RECT wa;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0);
    const int w = r.right - r.left, h = r.bottom - r.top;
    SetWindowPos(g_wnd, nullptr, wa.left + (wa.right - wa.left - w) / 2, wa.top + (wa.bottom - wa.top - h) / 2, w, h,
                 SWP_NOZORDER);
    SetFocus(GetDlgItem(g_wnd, IDOK));
}

LRESULT CALLBACK welcomeProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CTLCOLORSTATIC: {
            HDC dc = reinterpret_cast<HDC>(wp);
            SetBkColor(dc, GetSysColor(COLOR_WINDOW));
            SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
            return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
        }
        case WM_COMMAND: {
            const int id = LOWORD(wp), code = HIWORD(wp);
            switch (id) {
                case IdTelex:
                case IdVni:
                    if (code == BN_CLICKED) {
                        g_settings.vniMode = id == IdVni;
                        settingsChanged();
                        refreshSettingsWindow();
                    }
                    return 0;
                case IdSwitch:
                    if (code == CBN_SELCHANGE) {
                        const int i = static_cast<int>(SendMessageW(reinterpret_cast<HWND>(lp), CB_GETCURSEL, 0, 0));
                        if (i >= 0 && i < 4) {
                            g_settings.switchHotkey = kSwitchIds[i];
                            settingsChanged();
                            refreshSettingsWindow();
                        }
                    }
                    return 0;
                case IdResolve: resolveConflicts(h, g_found); return 0;
                case IdImport: importShortcutsDialog(h); return 0;
                case IdSettings:
                    finish();
                    showSettings(Tab::Typing);
                    return 0;
                case IDOK:
                case IDCANCEL: finish(); return 0;
                default: break;
            }
            break;
        }
        case WM_CLOSE: finish(); return 0;
        case WM_DESTROY:
            g_wnd = nullptr;
            if (g_font) DeleteObject(g_font);
            if (g_title) DeleteObject(g_title);
            g_font = g_title = nullptr;
            return 0;
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

}  // namespace

void showWelcome() {
    if (g_wnd) {
        SetForegroundWindow(g_wnd);
        return;
    }
    // Shown once per user, even if it is closed at once or the app is killed.
    writeFlag(L"welcomeShown", true);
    writeFlag(L"welcomePending", false);
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW wc = {};
        wc.cbSize = sizeof wc;
        wc.lpfnWndProc = welcomeProc;
        wc.hInstance = g_inst;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
        wc.hIcon = LoadIconW(g_inst, MAKEINTRESOURCEW(IDI_APP));
        wc.lpszClassName = kWelcomeClass;
        registered = RegisterClassExW(&wc) != 0;
    }
    g_found = detectConflicts();
    g_dpi = GetDpiForSystem();
    g_wnd = CreateWindowExW(WS_EX_CONTROLPARENT, kWelcomeClass, tr(S::WelcomeTitle),
                            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT,
                            100, 100, nullptr, nullptr, g_inst, nullptr);
    if (!g_wnd) return;
    g_dpi = GetDpiForWindow(g_wnd);
    build();
    ShowWindow(g_wnd, SW_SHOWNORMAL);
    SetForegroundWindow(g_wnd);
}

bool welcomeDialogMessage(MSG* msg) { return g_wnd && IsDialogMessageW(g_wnd, msg); }

}  // namespace vtx::app
