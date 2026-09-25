// tsf_compat.h — declarations the Windows SDK has but mingw-w64's msctf.h/ctfutb.h
// lack. Only used for the mingw cross-compile check; the real build uses MSVC + SDK.
#pragma once
#include "globals.h"

#include <ctfutb.h>
#include <inputscope.h>

#if defined(__MINGW32__)

#ifndef TF_LBI_STYLE_TEXTCOLORICON
#define TF_LBI_STYLE_TEXTCOLORICON 0x00000020
#endif
#ifndef TF_LBI_STYLE_BTN_BUTTON
#define TF_LBI_STYLE_BTN_BUTTON 0x00010000
#endif
#ifndef TF_LBI_STYLE_SHOWNINTRAY
#define TF_LBI_STYLE_SHOWNINTRAY 0x00000002
#endif
#ifndef TF_LBI_ICON
#define TF_LBI_ICON 0x00000001
#define TF_LBI_TEXT 0x00000002
#define TF_LBI_TOOLTIP 0x00000004
#define TF_LBI_STATUS 0x00010000
#endif
#ifndef TF_LBMENUF_CHECKED
#define TF_LBMENUF_CHECKED 0x1
#define TF_LBMENUF_SUBMENU 0x2
#define TF_LBMENUF_SEPARATOR 0x4
#define TF_LBMENUF_RADIOCHECKED 0x8
#define TF_LBMENUF_GRAYED 0x10
#endif

typedef enum { TF_LBI_CLK_RIGHT = 1, TF_LBI_CLK_LEFT = 2 } TfLBIClick;

// {6F8A98E4-AAA0-4F15-8C5B-07E0DF0A3DD8}
DEFINE_GUID(IID_ITfMenu, 0x6f8a98e4, 0xaaa0, 0x4f15, 0x8c, 0x5b, 0x07, 0xe0, 0xdf, 0x0a, 0x3d, 0xd8);
struct ITfMenu : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE AddMenuItem(UINT uId, DWORD dwFlags, HBITMAP hbmp, HBITMAP hbmpMask,
                                                  const WCHAR* pch, ULONG cch, ITfMenu** ppMenu) = 0;
};

// {28C7F1D0-DE25-11D2-AFDD-00105A2799B5}
DEFINE_GUID(IID_ITfLangBarItemButton, 0x28c7f1d0, 0xde25, 0x11d2, 0xaf, 0xdd, 0x00, 0x10, 0x5a, 0x27, 0x99, 0xb5);
struct ITfLangBarItemButton : public ITfLangBarItem {
    virtual HRESULT STDMETHODCALLTYPE OnClick(TfLBIClick click, POINT pt, const RECT* prcArea) = 0;
    virtual HRESULT STDMETHODCALLTYPE InitMenu(ITfMenu* pMenu) = 0;
    virtual HRESULT STDMETHODCALLTYPE OnMenuSelect(UINT wID) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetIcon(HICON* phIcon) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetText(BSTR* pbstrText) = 0;
};

// {6E4E2102-F9CD-433D-B496-303CE03A6507}
DEFINE_GUID(IID_ITfTextInputProcessorEx, 0x6e4e2102, 0xf9cd, 0x433d, 0xb4, 0x96, 0x30, 0x3c, 0xe0, 0x3a, 0x65, 0x07);
struct ITfTextInputProcessorEx : public ITfTextInputProcessor {
    virtual HRESULT STDMETHODCALLTYPE ActivateEx(ITfThreadMgr* ptim, TfClientId tid, DWORD dwFlags) = 0;
};

// {FEE47777-163C-4769-996A-6E9C50AD8F54}
DEFINE_GUID(IID_ITfDisplayAttributeProvider, 0xfee47777, 0x163c, 0x4769, 0x99, 0x6a, 0x6e, 0x9c, 0x50, 0xad, 0x8f, 0x54);
struct ITfDisplayAttributeProvider : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** ppInfo) = 0;
};

DEFINE_GUID(GUID_TFCAT_TIPCAP_SECUREMODE, 0x49d2f9ce, 0x1f5e, 0x11d7, 0xa6, 0xd3, 0x00, 0x06, 0x5b, 0x84, 0x43, 0x5c);
DEFINE_GUID(GUID_TFCAT_TIPCAP_UIELEMENTENABLED, 0x49d2f9cf, 0x1f5e, 0x11d7, 0xa6, 0xd3, 0x00, 0x06, 0x5b, 0x84, 0x43, 0x5c);
DEFINE_GUID(GUID_TFCAT_TIPCAP_COMLESS, 0x364215d9, 0x75bc, 0x11d7, 0xa6, 0xef, 0x00, 0x06, 0x5b, 0x84, 0x43, 0x5c);
DEFINE_GUID(GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT, 0x13a016df, 0x560b, 0x46cd, 0x94, 0x7a, 0x4c, 0x3a, 0xf1, 0xe0, 0xe3, 0x5d);
DEFINE_GUID(GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT, 0x25504fb4, 0x7bab, 0x4bc1, 0x9c, 0x69, 0xcf, 0x81, 0x89, 0x0f, 0x0e, 0xf5);

#endif  // __MINGW32__
