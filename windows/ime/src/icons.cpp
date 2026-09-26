#include "icons.h"

#include "../res/icon_ids.h"

namespace vtx::tip {

HICON CreateModeIcon(bool vietnamese, bool vtStyle, int size, COLORREF color) {
    if (size <= 0) size = GetSystemMetrics(SM_CXSMICON);
    if (size <= 0 || size > 256) size = 16;

    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = size;
    bi.bmiHeader.biHeight = -size;  // top-down
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    HDC screen = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(screen);
    ReleaseDC(nullptr, screen);
    if (!dc) return nullptr;
    void* bits = nullptr;
    HBITMAP color32 = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!color32 || !bits) {
        DeleteDC(dc);
        return nullptr;
    }
    HGDIOBJ oldBmp = SelectObject(dc, color32);

    // Render white-on-black coverage, then turn coverage into alpha.
    RECT rc = {0, 0, size, size};
    FillRect(dc, &rc, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));

    const wchar_t* big = vietnamese ? L"V" : L"E";
    HFONT font = CreateFontW(-(size * 7 / 8), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                             DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    if (vietnamese && vtStyle) {
        RECT left = {0, 0, size * 3 / 4, size};
        DrawTextW(dc, big, 1, &left, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
        HFONT small = CreateFontW(-(size / 2), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                  OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                                  DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
        SelectObject(dc, small);
        RECT right = {size / 2, size / 3, size, size};
        DrawTextW(dc, L"T", 1, &right, DT_CENTER | DT_BOTTOM | DT_SINGLELINE | DT_NOPREFIX);
        SelectObject(dc, font);
        DeleteObject(small);
    } else {
        DrawTextW(dc, big, 1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }
    SelectObject(dc, oldFont);
    DeleteObject(font);
    GdiFlush();

    const BYTE r = GetRValue(color), g = GetGValue(color), b = GetBValue(color);
    auto* px = static_cast<DWORD*>(bits);
    for (int i = 0; i < size * size; ++i) {
        DWORD p = px[i];
        BYTE cov = static_cast<BYTE>(((p & 0xFF) + ((p >> 8) & 0xFF) + ((p >> 16) & 0xFF)) / 3);
        // icons take straight (non-premultiplied) BGRA
        px[i] = (static_cast<DWORD>(cov) << 24) | (static_cast<DWORD>(r) << 16) |
                (static_cast<DWORD>(g) << 8) | static_cast<DWORD>(b);
    }
    SelectObject(dc, oldBmp);
    DeleteDC(dc);

    HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
    ICONINFO ii = {};
    ii.fIcon = TRUE;
    ii.hbmColor = color32;
    ii.hbmMask = mask;
    HICON icon = CreateIconIndirect(&ii);
    DeleteObject(color32);
    if (mask) DeleteObject(mask);
    return icon;
}

bool TaskbarIsLight() {
    DWORD v = 0, sz = sizeof v;
    return RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                        L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &v, &sz) == ERROR_SUCCESS &&
           v != 0;
}

HICON CreateStateIcon(HINSTANCE module, const std::string& menuIcon, bool vietnamese, int size) {
    if (size <= 0) size = GetSystemMetrics(SM_CXSMICON);
    const bool light = TaskbarIsLight();
    const int id = glyphIconId(menuIcon, vietnamese, light);
    if (id == 0) return CreateModeIcon(vietnamese, false, size, light ? RGB(0x1B, 0x1B, 0x1B) : RGB(255, 255, 255));
    HICON icon = static_cast<HICON>(LoadImageW(module, MAKEINTRESOURCEW(id), IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
    return icon ? icon : CreateModeIcon(vietnamese, true, size);
}

}  // namespace vtx::tip
