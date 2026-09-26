#include "icons.h"

#include "../res/icon_ids.h"

namespace vtx::tip {

namespace {

struct Dib {
    HDC dc = nullptr;
    HBITMAP bmp = nullptr;
    HGDIOBJ old = nullptr;
    DWORD* px = nullptr;
    int size = 0;
    explicit Dib(int s) : size(s) {
        BITMAPINFO bi = {};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = s;
        bi.bmiHeader.biHeight = -s;  // top-down
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        HDC screen = GetDC(nullptr);
        dc = CreateCompatibleDC(screen);
        ReleaseDC(nullptr, screen);
        void* bits = nullptr;
        if (dc) bmp = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        if (bmp) old = SelectObject(dc, bmp);
        px = static_cast<DWORD*>(bits);
    }
    ~Dib() {
        if (dc && old) SelectObject(dc, old);
        if (bmp) DeleteObject(bmp);
        if (dc) DeleteDC(dc);
    }
    bool ok() const { return px != nullptr; }
    HICON toIcon() {  // takes the pixels as straight-alpha BGRA
        SelectObject(dc, old);
        old = nullptr;
        HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
        ICONINFO ii = {};
        ii.fIcon = TRUE;
        ii.hbmColor = bmp;
        ii.hbmMask = mask;
        HICON icon = CreateIconIndirect(&ii);
        if (mask) DeleteObject(mask);
        return icon;
    }
};

}  // namespace

bool TaskbarIsLight() {
    DWORD v = 0, sz = sizeof v;
    return RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                        L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &v, &sz) == ERROR_SUCCESS &&
           v != 0;
}

HICON CreateTextIcon(const wchar_t* text, int size, COLORREF color) {
    if (size <= 0) size = GetSystemMetrics(SM_CXSMICON);
    Dib d(size);
    if (!d.ok()) return nullptr;
    RECT rc = {0, 0, size, size};
    FillRect(d.dc, &rc, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    SetBkMode(d.dc, TRANSPARENT);
    SetTextColor(d.dc, RGB(255, 255, 255));
    // Like the system's ENG/VIE indicator: plain Segoe UI, as large as fits.
    HFONT font = CreateFontW(-(size * 5 / 8), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_SWISS,
                             L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(d.dc, font);
    DrawTextW(d.dc, text, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(d.dc, oldFont);
    DeleteObject(font);
    GdiFlush();
    const DWORD rgb = (static_cast<DWORD>(GetRValue(color)) << 16) | (static_cast<DWORD>(GetGValue(color)) << 8) |
                      GetBValue(color);
    for (int i = 0; i < size * size; ++i) {
        const DWORD p = d.px[i];
        const DWORD cov = ((p & 0xFF) + ((p >> 8) & 0xFF) + ((p >> 16) & 0xFF)) / 3;
        d.px[i] = (cov << 24) | rgb;
    }
    return d.toIcon();
}

HICON CreateDimmedIcon(HICON icon, int size, float opacity) {
    if (!icon) return nullptr;
    Dib d(size);
    if (!d.ok()) return nullptr;
    for (int i = 0; i < size * size; ++i) d.px[i] = 0;
    DrawIconEx(d.dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL);  // premultiplied result
    GdiFlush();
    for (int i = 0; i < size * size; ++i) {
        const DWORD p = d.px[i];
        const DWORD a = p >> 24;
        if (a == 0) continue;
        // un-premultiply, then scale alpha
        const DWORD r = ((p >> 16) & 0xFF) * 255 / a, g = ((p >> 8) & 0xFF) * 255 / a, b = (p & 0xFF) * 255 / a;
        const DWORD na = static_cast<DWORD>(a * opacity + 0.5f);
        d.px[i] = (na << 24) | ((r > 255 ? 255 : r) << 16) | ((g > 255 ? 255 : g) << 8) | (b > 255 ? 255 : b);
    }
    return d.toIcon();
}

HICON CreateStateIcon(HINSTANCE module, const std::string& menuIcon, bool vietnamese, int size) {
    if (size <= 0) size = GetSystemMetrics(SM_CXSMICON);
    const bool light = TaskbarIsLight();
    const IndicatorIcon spec = indicatorIcon(parseIconChoice(menuIcon), vietnamese, light);
    if (spec.resourceId == 0) {
        const COLORREF c = light ? RGB(0x1B, 0x1B, 0x1B) : RGB(255, 255, 255);
        wchar_t w[8] = {};
        for (int i = 0; spec.text && spec.text[i] && i < 7; ++i) w[i] = static_cast<wchar_t>(spec.text[i]);
        return CreateTextIcon(w, size, c);
    }
    HICON icon = static_cast<HICON>(
        LoadImageW(module, MAKEINTRESOURCEW(spec.resourceId), IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
    if (icon && spec.dim) {
        HICON dimmed = CreateDimmedIcon(icon, size, 0.4f);
        DestroyIcon(icon);
        icon = dimmed;
    }
    return icon;
}

}  // namespace vtx::tip
