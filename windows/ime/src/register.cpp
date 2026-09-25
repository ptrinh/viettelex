// register.cpp — DllRegisterServer / DllUnregisterServer: COM class, TSF profile,
// TSF categories. Called by the MSI (regsvr32-equivalent custom action) for each
// architecture's DLL. Adding the keyboard to the USER's language list is separate
// (InstallLayoutOrTip, done by VietTelex.exe on first run — per-user).
#include <olectl.h>

#include <string>

#include "com_path.h"
#include "globals.h"
#include "tsf_compat.h"

namespace vtx::tip {

namespace {

std::wstring guidString(REFGUID g) {
    wchar_t buf[64];
    int n = StringFromGUID2(g, buf, 64);
    return n > 0 ? std::wstring(buf) : std::wstring();
}

std::wstring modulePath() {
    wchar_t buf[MAX_PATH];
    DWORD n = GetModuleFileNameW(g_hInst, buf, MAX_PATH);
    return (n > 0 && n < MAX_PATH) ? std::wstring(buf, n) : std::wstring();
}

bool setString(HKEY root, const std::wstring& sub, const wchar_t* name, const std::wstring& value) {
    HKEY k;
    if (RegCreateKeyExW(root, sub.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) != ERROR_SUCCESS)
        return false;
    LONG r = RegSetValueExW(k, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                            static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(k);
    return r == ERROR_SUCCESS;
}

const std::wstring kClsidKey = L"SOFTWARE\\Classes\\CLSID\\";

// ARM64: register the ARM64X forwarder, not the half that is running (com_path.h).
std::wstring serverPath() {
    const std::wstring self = modulePath();
    const std::wstring fwd = forwarderCandidate(self);
    return comServerPath(self, !fwd.empty() && GetFileAttributesW(fwd.c_str()) != INVALID_FILE_ATTRIBUTES);
}

bool registerCom() {
    const std::wstring key = kClsidKey + guidString(CLSID_VietTelexTIP);
    const std::wstring path = serverPath();
    if (path.empty()) return false;
    return setString(HKEY_LOCAL_MACHINE, key, nullptr, L"VietTelex Text Service") &&
           setString(HKEY_LOCAL_MACHINE, key + L"\\InprocServer32", nullptr, path) &&
           setString(HKEY_LOCAL_MACHINE, key + L"\\InprocServer32", L"ThreadingModel", L"Apartment");
}

void unregisterCom() {
    RegDeleteTreeW(HKEY_LOCAL_MACHINE, (kClsidKey + guidString(CLSID_VietTelexTIP)).c_str());
}

bool registerProfile() {
    ITfInputProcessorProfileMgr* mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&mgr));
    if (FAILED(hr) || !mgr) return false;
    // Icon from the module actually running (an ARM64X forwarder has no resources).
    const std::wstring path = modulePath();
    // hklSubstitute = US layout: keys we let through (digits, punctuation) must come
    // out as on a US keyboard, not through the stock Vietnamese layout that maps the
    // number row to ă â ê ô…
    HKL us = reinterpret_cast<HKL>(static_cast<ULONG_PTR>(0x04090409));
    hr = mgr->RegisterProfile(CLSID_VietTelexTIP, kLangId, GUID_VietTelexProfile, kDisplayName,
                              static_cast<ULONG>(lstrlenW(kDisplayName)), path.c_str(),
                              static_cast<ULONG>(path.size()), 0 /* icon index */, us, 0, TRUE, 0);
    mgr->Release();
    return SUCCEEDED(hr);
}

void unregisterProfile() {
    ITfInputProcessorProfileMgr* mgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&mgr))) &&
        mgr) {
        mgr->UnregisterProfile(CLSID_VietTelexTIP, kLangId, GUID_VietTelexProfile, 0);
        mgr->Release();
    }
}

const GUID* const kCategories[] = {
    &GUID_TFCAT_TIP_KEYBOARD,
    &GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
    &GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
    &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,   // Store/UWP apps, Start, Search
    &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,     // input-mode button in the taskbar
    &GUID_TFCAT_TIPCAP_SECUREMODE,         // UAC / lock screen (minimal mode)
    &GUID_TFCAT_TIPCAP_COMLESS,
};

bool registerCategories(bool reg) {
    ITfCategoryMgr* cm = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                reinterpret_cast<void**>(&cm))) ||
        !cm)
        return false;
    bool ok = true;
    for (const GUID* cat : kCategories) {
        HRESULT hr = reg ? cm->RegisterCategory(CLSID_VietTelexTIP, *cat, CLSID_VietTelexTIP)
                         : cm->UnregisterCategory(CLSID_VietTelexTIP, *cat, CLSID_VietTelexTIP);
        if (FAILED(hr)) ok = false;
    }
    cm->Release();
    return ok;
}

}  // namespace

HRESULT RegisterServer() {
    if (!registerCom()) return SELFREG_E_CLASS;
    if (!registerProfile() || !registerCategories(true)) return E_FAIL;
    return S_OK;
}

HRESULT UnregisterServer() {
    registerCategories(false);
    unregisterProfile();
    unregisterCom();
    return S_OK;
}

}  // namespace vtx::tip
