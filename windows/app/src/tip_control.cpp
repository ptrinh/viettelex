#include "tip_control.h"

#include <windows.h>

#include <cstdio>

#include <string>

#include "registration.h"

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

bool callInstall(DWORD flags) {
    HMODULE input = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!input) return false;
    auto fn = reinterpret_cast<InstallLayoutOrTipFn>(
        reinterpret_cast<void*>(GetProcAddress(input, "InstallLayoutOrTip")));
    bool ok = fn && fn(tipSpec().c_str(), flags);
    FreeLibrary(input);
    return ok;
}

std::wstring selfPath() {
    wchar_t buf[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
    return (n > 0 && n < MAX_PATH) ? std::wstring(buf, n) : std::wstring();
}
}  // namespace

bool addKeyboardForUser() { return callInstall(0); }
bool removeKeyboardForUser() { return callInstall(ILOT_UNINSTALL_); }

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

}  // namespace vtx::app
