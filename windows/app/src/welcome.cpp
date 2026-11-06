// welcome.cpp — first-run window (app/core/onboarding.h decideWelcome), one page
// (docs/WINDOWS-APP-FEEL-SPEC.md §4):
//
//   Đã sẵn sàng — gõ thử ở đây
//   [ a box typed through VietTelex itself ]
//   Đổi Việt/Anh: Ctrl+Shift hoặc bấm biểu tượng V/E ở khay.
//   (only when found) one line + "Xử lý…"  — the existing conflict dialog (conflicts.h),
//   which also offers removing Windows' own "Vietnamese Telex" from the keyboard list
//   [Mở Cài đặt…]                [Bắt đầu gõ]
//
// Everything else (typing method, switch key, mixed-typing profile, tray) keeps its
// default and lives in Settings. The keyboard itself was already added, made the default
// and selected by main.cpp (app_feel.h planKeyboardAtStart) before this window opens.
// Portable: the box is typed by the portable hook (it watches our own windows too).
// Shown once per user. Not run on real Windows yet (built + host-tested only).
#include <windows.h>
#include <commctrl.h>

#include <string>
#include <vector>

#include "app.h"
#include "app_feel.h"
#include "conflicts.h"
#include "onboarding.h"
#include "foreground.h"
#include "res/icon_ids.h"
#include "settings_store.h"
#include "strings.h"

namespace vtx::app {

namespace {

constexpr wchar_t kWelcomeClass[] = L"VietTelexWelcome";
enum : int {
    IdTryEdit = 100,
    IdResolve,
    IdSettings,
};

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

void finish() { DestroyWindow(g_wnd); }

// Client size (DIP) -> window size, centred on the work area.
void fitWindow(int W, int H) {
    RECT r = {0, 0, px(W), px(H)};
    const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(g_wnd, GWL_STYLE));
    AdjustWindowRectExForDpi(&r, style, FALSE, WS_EX_CONTROLPARENT, g_dpi);
    RECT wa;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0);
    const int w = r.right - r.left, h = r.bottom - r.top;
    SetWindowPos(g_wnd, nullptr, wa.left + (wa.right - wa.left - w) / 2, wa.top + (wa.bottom - wa.top - h) / 2, w, h,
                 SWP_NOZORDER);
}

void makeFonts() {
    NONCLIENTMETRICSW ncm = {};
    ncm.cbSize = sizeof ncm;
    SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, g_dpi);
    g_font = CreateFontIndirectW(&ncm.lfMessageFont);
    LOGFONTW lf = ncm.lfMessageFont;
    lf.lfHeight = -px(20);
    lf.lfWeight = FW_SEMIBOLD;
    g_title = CreateFontIndirectW(&lf);
}

void build() {
    const int W = 480;  // client width (DIP)
    int y = 20;
    add(L"STATIC", tr(S::ReadyTitle), SS_LEFT, 24, y, W - 48, 30, 0, g_title);
    y += 40;
    // ES_WANTRETURN: Enter types a new line instead of pressing a button.
    add(L"EDIT", L"", ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_BORDER | WS_TABSTOP | WS_GROUP | WS_VSCROLL,
        24, y, W - 48, 72, IdTryEdit);
    y += 82;
    add(L"STATIC", tr(S::ReadySwitchLine), SS_LEFT, 24, y, W - 48, 40);
    y += 44;
    if (portableMode()) {
        add(L"STATIC", tr(S::ReadyPortableNote), SS_LEFT, 24, y, W - 48, 36);
        y += 40;
    }

    std::vector<ConflictKind> kinds;
    for (const FoundConflict& c : g_found) kinds.push_back(c.kind);
    const ResolveRow row = welcomeResolveRow(kinds);
    if (row != ResolveRow::None) {
        std::wstring msg;
        if (row == ResolveRow::OtherInputMethod || row == ResolveRow::Both) msg = tr(S::ResolveOtherIme);
        if (row == ResolveRow::WindowsKeyboard || row == ResolveRow::Both)
            msg += (msg.empty() ? L"" : L" ") + std::wstring(tr(S::ResolveWindowsKb));
        add(L"STATIC", msg.c_str(), SS_LEFT, 24, y, W - 48 - 124, 76);
        add(L"BUTTON", tr(S::ConflictButton), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 110, y, 110, 30,
            IdResolve);
        y += 86;
    }

    y += 8;
    add(L"BUTTON", tr(S::WelcomeOpenSettings), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 140 - 8 - 140, y,
        140, 32, IdSettings);
    add(L"BUTTON", tr(S::WelcomeDone), BS_DEFPUSHBUTTON | WS_TABSTOP, W - 24 - 140, y, 140, 32, IDOK);
    y += 32 + 20;

    fitWindow(W, y);
    SetFocus(GetDlgItem(g_wnd, IdTryEdit));
}

LRESULT CALLBACK welcomeProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CTLCOLORSTATIC: {
            HDC dc = reinterpret_cast<HDC>(wp);
            SetBkColor(dc, GetSysColor(COLOR_WINDOW));
            SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
            return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
        }
        case WM_COMMAND:
            switch (LOWORD(wp)) {
                case IdResolve:
                    resolveConflicts(h, g_found);
                    return 0;
                case IdSettings:
                    finish();
                    showSettings(Tab::Typing);
                    return 0;
                case IDOK:
                case IDCANCEL: finish(); return 0;
                default: break;
            }
            break;
        case WM_CLOSE: finish(); return 0;
        case WM_DESTROY:
            g_wnd = nullptr;
            if (g_font) DeleteObject(g_font);
            if (g_title) DeleteObject(g_title);
            g_font = g_title = nullptr;
            requestIdleTrim();
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
    g_wnd = CreateWindowExW(WS_EX_CONTROLPARENT, kWelcomeClass, tr(S::AppName),
                            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT,
                            100, 100, nullptr, nullptr, g_inst, nullptr);
    if (!g_wnd) return;
    g_dpi = GetDpiForWindow(g_wnd);
    makeFonts();
    build();
    ShowWindow(g_wnd, SW_SHOWNORMAL);
    SetForegroundWindow(g_wnd);
}

bool welcomeDialogMessage(MSG* msg) { return g_wnd && IsDialogMessageW(g_wnd, msg); }
bool welcomeWindowOpen() { return g_wnd != nullptr; }

}  // namespace vtx::app
