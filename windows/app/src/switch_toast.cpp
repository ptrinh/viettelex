#include "switch_toast.h"

#include <windows.h>

#include <string>

#include "app.h"
#include "game_logic.h"

namespace vtx::app {

namespace {

constexpr wchar_t kToastClass[] = L"VietTelexSwitchToast";
constexpr UINT_PTR kTimerHide = 1;
HWND g_toast = nullptr;
std::wstring g_text;
HFONT g_font = nullptr;
UINT g_fontDpi = 0;

int scale(int v, UINT dpi) { return MulDiv(v, static_cast<int>(dpi), 96); }

HFONT fontFor(UINT dpi) {
    if (g_font && g_fontDpi == dpi) return g_font;
    if (g_font) DeleteObject(g_font);
    g_font = CreateFontW(-scale(20, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                         OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    g_fontDpi = dpi;
    return g_font;
}

LRESULT CALLBACK toastProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_NCHITTEST: return HTTRANSPARENT;  // click-through (WS_EX_TRANSPARENT too)
        case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
        case WM_TIMER:
            if (wp == kTimerHide) {
                KillTimer(h, kTimerHide);
                ShowWindow(h, SW_HIDE);
            }
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(h, &ps);
            RECT rc;
            GetClientRect(h, &rc);
            const bool dark = systemUsesDarkApps();
            HBRUSH bg = CreateSolidBrush(dark ? RGB(0x2B, 0x2B, 0x2B) : RGB(0xF9, 0xF9, 0xF9));
            FillRect(dc, &rc, bg);
            DeleteObject(bg);
            SetBkMode(dc, TRANSPARENT);
            SetTextColor(dc, dark ? RGB(0xFF, 0xFF, 0xFF) : RGB(0x1A, 0x1A, 0x1A));
            HGDIOBJ old = SelectObject(dc, fontFor(GetDpiForWindow(h)));
            DrawTextW(dc, g_text.c_str(), static_cast<int>(g_text.size()), &rc,
                      DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
            SelectObject(dc, old);
            EndPaint(h, &ps);
            return 0;
        }
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

bool ensureWindow() {
    if (g_toast) return true;
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof wc;
    wc.lpfnWndProc = toastProc;
    wc.hInstance = g_inst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kToastClass;
    RegisterClassExW(&wc);
    g_toast = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                              kToastClass, L"", WS_POPUP, 0, 0, 10, 10, nullptr, nullptr, g_inst, nullptr);
    if (!g_toast) return false;
    SetLayeredWindowAttributes(g_toast, 0, 235, LWA_ALPHA);
    return true;
}

// Caret of the foreground thread in screen coordinates, if the app reports one (Win32
// edits do; Chromium / UWP usually not -> corner).
bool foregroundCaret(RECT& out, HWND& where) {
    HWND fg = GetForegroundWindow();
    where = fg;
    if (!fg) return false;
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    if (!GetGUIThreadInfo(GetWindowThreadProcessId(fg, nullptr), &gi) || !gi.hwndCaret) return false;
    RECT r = gi.rcCaret;
    if (r.right <= r.left && r.bottom <= r.top) return false;
    MapWindowPoints(gi.hwndCaret, nullptr, reinterpret_cast<POINT*>(&r), 2);
    out = r;
    where = gi.hwndCaret;
    return true;
}

}  // namespace

void toastShow(const wchar_t* text) {
    if (!text || !ensureWindow()) return;
    g_text = text;
    RECT caret = {};
    HWND where = nullptr;
    const bool caretKnown = foregroundCaret(caret, where);
    MONITORINFO mi = {};
    mi.cbSize = sizeof mi;
    HMONITOR mon = caretKnown ? MonitorFromRect(&caret, MONITOR_DEFAULTTONEAREST)
                              : MonitorFromWindow(where, MONITOR_DEFAULTTOPRIMARY);
    if (!GetMonitorInfoW(mon, &mi)) return;
    UINT dpiX = 96, dpiY = 96;
    using GetDpiForMonitorFn = HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);
    static GetDpiForMonitorFn getDpi = [] {
        HMODULE m = LoadLibraryExW(L"shcore.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        return m ? reinterpret_cast<GetDpiForMonitorFn>(reinterpret_cast<void*>(GetProcAddress(m, "GetDpiForMonitor")))
                 : nullptr;
    }();
    if (!getDpi || FAILED(getDpi(mon, 0 /* MDT_EFFECTIVE_DPI */, &dpiX, &dpiY))) dpiX = GetDpiForSystem();
    // Size: square for one letter, wider for words.
    HDC dc = GetDC(g_toast);
    HGDIOBJ old = SelectObject(dc, fontFor(dpiX));
    SIZE ts = {};
    GetTextExtentPoint32W(dc, g_text.c_str(), static_cast<int>(g_text.size()), &ts);
    SelectObject(dc, old);
    ReleaseDC(g_toast, dc);
    const int h = scale(40, dpiX);
    const int w = ts.cx + scale(24, dpiX) > h ? ts.cx + scale(24, dpiX) : h;
    const RECT& wa = mi.rcWork;
    const Point p = toastPosition(caretKnown, Rect{caret.left, caret.top, caret.right, caret.bottom},
                                  Rect{wa.left, wa.top, wa.right, wa.bottom}, w, h, scale(8, dpiX));
    HRGN rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, scale(8, dpiX), scale(8, dpiX));
    SetWindowRgn(g_toast, rgn, FALSE);  // the window owns the region now
    SetWindowPos(g_toast, HWND_TOPMOST, p.x, p.y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(g_toast, nullptr, TRUE);
    SetTimer(g_toast, kTimerHide, kSwitchToastMs, nullptr);
}

void toastShutdown() {
    if (g_toast) DestroyWindow(g_toast);
    g_toast = nullptr;
    if (g_font) DeleteObject(g_font);
    g_font = nullptr;
}

}  // namespace vtx::app
