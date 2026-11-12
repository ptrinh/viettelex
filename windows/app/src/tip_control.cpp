#include "tip_control.h"

#include "app_feel.h"

#include <windows.h>
#include <msctf.h>

#include <cstdio>

#include <string>

#include "foreground.h"
#include "input_switch.h"
#include "registration.h"

// Windows SDK msctf.h values (older mingw-w64 headers lack some).
#ifndef TF_IPP_FLAG_ENABLED
#define TF_IPP_FLAG_ENABLED 0x00000002
#endif
#ifndef TF_PROFILETYPE_INPUTPROCESSOR
#define TF_PROFILETYPE_INPUTPROCESSOR 0x0001
#endif
#ifndef TF_PROFILETYPE_KEYBOARDLAYOUT
#define TF_PROFILETYPE_KEYBOARDLAYOUT 0x0002
#endif
#ifndef TF_IPPMF_FORSESSION
#define TF_IPPMF_FORSESSION 0x00000001
#endif
#ifndef TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE
#define TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE 0x00000004
#endif

namespace vtx::app {

namespace {
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"VietTelex";
constexpr DWORD ILOT_UNINSTALL_ = 0x00000001;

using InstallLayoutOrTipFn = BOOL(WINAPI*)(LPCWSTR, DWORD);

// "042A:{CLSID}{PROFILE}" from the shared registration data.
std::wstring tipSpec() {
    char buf[128];
    snprintf(buf, sizeof buf, "%04X:%s%s", static_cast<unsigned>(vtx::reg::kLangId), vtx::reg::kClsid,
             vtx::reg::kProfile);
    std::wstring w;
    for (const char* p = buf; *p; ++p) w.push_back(static_cast<wchar_t>(*p));
    return w;
}

bool callInstall(const std::wstring& spec, DWORD flags) {
    HMODULE input = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!input) return false;
    auto fn = reinterpret_cast<InstallLayoutOrTipFn>(
        reinterpret_cast<void*>(GetProcAddress(input, "InstallLayoutOrTip")));
    bool ok = fn && fn(spec.c_str(), flags);
    FreeLibrary(input);
    return ok;
}

std::wstring selfPath() {
    wchar_t buf[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
    return (n > 0 && n < MAX_PATH) ? std::wstring(buf, n) : std::wstring();
}
}  // namespace

namespace {
// SetDefaultLayoutOrTip (input.dll, documented in the TSF reference; no import library:
// LoadLibrary + GetProcAddress as the documentation shows). Profile-list format
// "0x042A:{CLSID}{PROFILE}"; flags 0 = store it AND apply it to the current session.
bool callSetDefaultLayoutOrTip() {
    const std::string spec = defaultLayoutOrTipSpec(vtx::reg::kLangId, vtx::reg::kClsid, vtx::reg::kProfile);
    const std::wstring w(spec.begin(), spec.end());
    HMODULE input = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!input) return false;
    using SetDefaultFn = BOOL(WINAPI*)(LPCWSTR, DWORD);
    auto fn = reinterpret_cast<SetDefaultFn>(reinterpret_cast<void*>(GetProcAddress(input, "SetDefaultLayoutOrTip")));
    const bool ok = fn && fn(w.c_str(), 0);
    FreeLibrary(input);
    return ok;
}

// "Override for default input method": the per-user registry value the documented
// Set-WinDefaultInputMethodOverride cmdlet stores. Written directly — launching a hidden
// shell for the cmdlet got the exe flagged by antivirus heuristics (issue #157, 1.3.15–1.3.21).
bool writeOverride() {
    const std::string spec = inputMethodOverrideSpec(vtx::reg::kLangId, vtx::reg::kClsid, vtx::reg::kProfile);
    const std::wstring w(spec.begin(), spec.end());
    return RegSetKeyValueW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile", L"InputMethodOverride",
                           REG_SZ, w.c_str(), static_cast<DWORD>((w.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
}
}  // namespace

OverrideState inputMethodOverride() {
    wchar_t buf[256] = {};
    DWORD sz = sizeof buf;
    const bool present = RegGetValueW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile",
                                      L"InputMethodOverride", RRF_RT_REG_SZ, nullptr, buf, &sz) == ERROR_SUCCESS;
    std::string v;
    for (const wchar_t* p = buf; present && *p; ++p) v.push_back(*p < 0x80 ? static_cast<char>(*p) : '?');
    return overrideState(present, v, vtx::reg::kLangId, vtx::reg::kClsid, vtx::reg::kProfile);
}

bool setDefaultKeyboardForUser() {
    // Override first, so SetDefaultLayoutOrTip (which applies to the running session)
    // already sees it.
    const bool wrote = inputMethodOverride() == OverrideState::VietTelex || writeOverride();
    const bool set = callSetDefaultLayoutOrTip();
    const OverrideState after = inputMethodOverride();
    appLog("app", std::string("default input method override: ") + (wrote ? "set" : "write failed") +
                      (after == OverrideState::VietTelex ? " -> VietTelex" : " -> not VietTelex"));
    return after == OverrideState::VietTelex || (!wrote && set && after == OverrideState::None);
}

unsigned defaultInputLangId() {
    HKL hkl = nullptr;
    if (!SystemParametersInfoW(SPI_GETDEFAULTINPUTLANG, 0, &hkl, 0) || !hkl) return 0;
    return LOWORD(reinterpret_cast<ULONG_PTR>(hkl));
}

bool addKeyboardForUser() { return callInstall(tipSpec(), 0); }
bool removeKeyboardForUser() { return callInstall(tipSpec(), ILOT_UNINSTALL_); }
bool removeLayoutOrTipForUser(const std::wstring& spec) { return !spec.empty() && callInstall(spec, ILOT_UNINSTALL_); }

bool removeFromUserLanguageList(const std::string& spec) {
    auto wide = [](const std::string& t) { return std::wstring(t.begin(), t.end()); };  // ASCII specs
    HKEY root;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile", 0,
                      KEY_ENUMERATE_SUB_KEYS, &root) != ERROR_SUCCESS)
        return false;
    bool removed = false;
    wchar_t sub[128];
    for (DWORD i = 0;; ++i) {
        DWORD subLen = 128;
        if (RegEnumKeyExW(root, i, sub, &subLen, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
        HKEY lang;
        if (RegOpenKeyExW(root, sub, 0, KEY_QUERY_VALUE | KEY_SET_VALUE, &lang) != ERROR_SUCCESS) continue;
        std::vector<std::string> names;
        wchar_t name[256];
        for (DWORD v = 0;; ++v) {
            DWORD nameLen = 256;
            if (RegEnumValueW(lang, v, name, &nameLen, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
            std::string n;
            for (DWORD c = 0; c < nameLen; ++c) n.push_back(name[c] < 0x80 ? static_cast<char>(name[c]) : '?');
            names.push_back(n);
        }
        for (const std::string& n : vtx::languageListValuesToRemove(names, spec))
            if (RegDeleteValueW(lang, wide(n).c_str()) == ERROR_SUCCESS) removed = true;
        RegCloseKey(lang);
    }
    RegCloseKey(root);
    if (removed) callInstall(wide(spec), ILOT_UNINSTALL_);  // and out of this session
    return removed;
}

bool runningAsSystem() {
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) return false;
    BYTE buf[256];
    DWORD len = 0;
    bool system = false;
    if (GetTokenInformation(tok, TokenUser, buf, sizeof buf, &len))
        system = IsWellKnownSid(reinterpret_cast<TOKEN_USER*>(buf)->User.Sid, WinLocalSystemSid) != FALSE;
    CloseHandle(tok);
    return system;
}

void setAutostart(bool on) {
    HKEY k;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) !=
        ERROR_SUCCESS)
        return;
    if (on) {
        std::wstring cmd = L"\"" + selfPath() + L"\" --background";
        RegSetValueExW(k, kRunValue, 0, REG_SZ, reinterpret_cast<const BYTE*>(cmd.c_str()),
                       static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
    } else {
        RegDeleteValueW(k, kRunValue);
    }
    RegCloseKey(k);
}

bool autostartEnabled() {
    DWORD sz = 0;
    return RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ, nullptr, nullptr, &sz) == ERROR_SUCCESS;
}

std::wstring autostartValue() {
    wchar_t buf[1024] = {};
    DWORD sz = sizeof buf;
    if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ, nullptr, buf, &sz) != ERROR_SUCCESS)
        return L"";
    return buf;
}

std::wstring selfExePath() { return selfPath(); }

// ---------------------------------------------------------------- app feel (core/app_feel.h)
// Thin glue. NOT exercised on a real Windows machine yet (host unit tests + cross-build
// only): ActivateProfile(TF_IPPMF_FORSESSION) and WM_INPUTLANGCHANGEREQUEST are the
// documented ways; whether every window follows the session switch at once still needs a
// check on Windows 10 and 11.
namespace {
bool guidFrom(const char* s, GUID& out) {
    wchar_t w[64] = {};
    for (int i = 0; s[i] && i < 63; ++i) w[i] = static_cast<wchar_t>(s[i]);
    return SUCCEEDED(CLSIDFromString(w, &out));
}

// `fn(mgr)` with the profile manager, COM initialised on this (UI) thread.
template <class Fn>
bool withProfileMgr(Fn fn) {
    const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ITfInputProcessorProfileMgr* mgr = nullptr;
    bool ok = false;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&mgr))) &&
        mgr) {
        ok = fn(mgr);
        mgr->Release();
    }
    if (SUCCEEDED(init)) CoUninitialize();
    return ok;
}
}  // namespace

bool vietTelexInUserList(bool& registered) {
    registered = false;
    GUID clsid, profile;
    if (!guidFrom(vtx::reg::kClsid, clsid) || !guidFrom(vtx::reg::kProfile, profile)) return false;
    bool enabled = false;
    withProfileMgr([&](ITfInputProcessorProfileMgr* mgr) {
        IEnumTfInputProcessorProfiles* en = nullptr;
        if (FAILED(mgr->EnumProfiles(static_cast<LANGID>(vtx::reg::kLangId), &en)) || !en) return false;
        TF_INPUTPROCESSORPROFILE pr;
        ULONG got = 0;
        while (en->Next(1, &pr, &got) == S_OK && got == 1) {
            if (pr.dwProfileType != TF_PROFILETYPE_INPUTPROCESSOR || !IsEqualGUID(pr.clsid, clsid) ||
                !IsEqualGUID(pr.guidProfile, profile))
                continue;
            registered = true;
            enabled = enabled || (pr.dwFlags & TF_IPP_FLAG_ENABLED) != 0;
        }
        en->Release();
        return true;
    });
    return enabled;
}

std::vector<unsigned> otherEnabledTextServiceLangs() {
    GUID clsid;
    std::vector<unsigned> out;
    if (!guidFrom(vtx::reg::kClsid, clsid)) return out;
    // The languages in the user's list (one per distinct LOWORD of the layouts): text
    // services of other languages are not selectable anyway.
    std::vector<unsigned> langs;
    for (uintptr_t hkl : keyboardLayouts()) {
        const unsigned lang = static_cast<unsigned>(hkl & 0xFFFF);
        bool seen = false;
        for (unsigned l : langs) seen = seen || l == lang;
        if (!seen) langs.push_back(lang);
    }
    withProfileMgr([&](ITfInputProcessorProfileMgr* mgr) {
        for (unsigned lang : langs) {
            IEnumTfInputProcessorProfiles* en = nullptr;
            if (FAILED(mgr->EnumProfiles(static_cast<LANGID>(lang), &en)) || !en) continue;
            TF_INPUTPROCESSORPROFILE pr;
            ULONG got = 0;
            while (en->Next(1, &pr, &got) == S_OK && got == 1)
                if (pr.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR && (pr.dwFlags & TF_IPP_FLAG_ENABLED) &&
                    !IsEqualGUID(pr.clsid, clsid))
                    out.push_back(pr.langid);
            en->Release();
        }
        return true;
    });
    return out;
}

bool selectVietTelexForSession() {
    GUID clsid, profile;
    if (!guidFrom(vtx::reg::kClsid, clsid) || !guidFrom(vtx::reg::kProfile, profile)) return false;
    return withProfileMgr([&](ITfInputProcessorProfileMgr* mgr) {
        return SUCCEEDED(mgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, static_cast<LANGID>(vtx::reg::kLangId),
                                              clsid, profile, nullptr,
                                              TF_IPPMF_FORSESSION | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE));
    });
}

bool activateLayoutForSession(uintptr_t hkl) {
    if (!hkl) return false;
    return withProfileMgr([&](ITfInputProcessorProfileMgr* mgr) {
        return SUCCEEDED(mgr->ActivateProfile(TF_PROFILETYPE_KEYBOARDLAYOUT, static_cast<LANGID>(hkl & 0xFFFF),
                                              GUID_NULL, GUID_NULL, reinterpret_cast<HKL>(hkl),
                                              TF_IPPMF_FORSESSION | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE));
    });
}

uintptr_t defaultInputHkl() {
    HKL hkl = nullptr;
    if (!SystemParametersInfoW(SPI_GETDEFAULTINPUTLANG, 0, &hkl, 0)) return 0;
    return reinterpret_cast<uintptr_t>(hkl);
}

std::vector<uintptr_t> keyboardLayouts() {
    HKL list[64];
    const int n = GetKeyboardLayoutList(64, list);
    std::vector<uintptr_t> out;
    for (int i = 0; i < n; ++i) out.push_back(reinterpret_cast<uintptr_t>(list[i]));
    return out;
}

bool requestInputLanguage(HWND window, uintptr_t hkl) {
    if (!window || !hkl) return false;
    const DWORD tid = GetWindowThreadProcessId(window, nullptr);
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    HWND target = (tid && GetGUIThreadInfo(tid, &gi) && gi.hwndFocus) ? gi.hwndFocus : window;
    return PostMessageW(target, WM_INPUTLANGCHANGEREQUEST, 0, static_cast<LPARAM>(hkl)) != FALSE;
}

}  // namespace vtx::app
