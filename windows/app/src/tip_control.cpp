#include "tip_control.h"

#include <windows.h>

#include <string>

namespace vtx::app {

namespace {
// Must match CLSID_VietTelexTIP / GUID_VietTelexProfile in ime/src/globals.cpp.
constexpr wchar_t kTip[] = L"042A:{A93425B6-980D-4BB2-83C4-2DA555A30D85}{A4D93021-292F-4C97-97A1-45F50D970649}";
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"VietTelex";
constexpr DWORD ILOT_UNINSTALL_ = 0x00000001;

using InstallLayoutOrTipFn = BOOL(WINAPI*)(LPCWSTR, DWORD);

bool callInstall(DWORD flags) {
    HMODULE input = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!input) return false;
    auto fn = reinterpret_cast<InstallLayoutOrTipFn>(
        reinterpret_cast<void*>(GetProcAddress(input, "InstallLayoutOrTip")));
    bool ok = fn && fn(kTip, flags);
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
