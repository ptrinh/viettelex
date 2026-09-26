// globals.h — module-wide state and GUIDs for VietTelexTIP.dll.
#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <msctf.h>

#ifndef TF_CLIENTID_NULL
#define TF_CLIENTID_NULL ((TfClientId)0)
#endif
#ifndef TF_INVALID_GUIDATOM
#define TF_INVALID_GUIDATOM ((TfGuidAtom)0)
#endif

namespace vtx::tip {

extern HINSTANCE g_hInst;
extern LONG g_dllRefCount;

inline void DllAddRef() { InterlockedIncrement(&g_dllRefCount); }
inline void DllRelease() { InterlockedDecrement(&g_dllRefCount); }

// {A93425B6-980D-4BB2-83C4-2DA555A30D85}
extern const CLSID CLSID_VietTelexTIP;
// {A4D93021-292F-4C97-97A1-45F50D970649}
extern const GUID GUID_VietTelexProfile;
// {4DAA5D7F-65EB-4B15-917A-C6A3AD2AC0F8} display attribute: "input, no decoration"
extern const GUID GUID_DisplayAttributeInput;
// {F58C2872-C456-4CBF-AF2A-8543B6241E0E} preserved key: Alt+Z toggle
extern const GUID GUID_PreservedKeyToggle;

constexpr LANGID kLangId = MAKELANGID(LANG_VIETNAMESE, SUBLANG_VIETNAMESE_VIETNAM);  // 0x042A
constexpr wchar_t kAppWindowClass[] = L"VietTelexAppWindow";
constexpr UINT kAppCommandMsg = WM_APP + 0x56;  // wParam = AppCommand (app/src/ipc.h)

}  // namespace vtx::tip
