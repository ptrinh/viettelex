#include "debug_context.h"

#include <windows.h>

#include <cstdio>
#include <ctime>
#include <string>
#include <utility>
#include <vector>

#include "debug_file.h"
#include "debug_header.h"
#include "foreground.h"
#include "registration.h"
#include "settings_store.h"
#include "setup_helper_logic.h"
#include "tip_control.h"
#include "version.h"

namespace vtx::app {

namespace {

bool g_on = false;           // logging was on at the last apply
std::string g_lastSettings;  // formatSettingsSummary at the last apply (while on)

std::string envUtf8(const wchar_t* name) {
    wchar_t buf[MAX_PATH];
    const DWORD n = GetEnvironmentVariableW(name, buf, MAX_PATH);
    return (n > 0 && n < MAX_PATH) ? narrow(std::wstring(buf, n)) : std::string();
}

std::string regString(HKEY root, const wchar_t* key, const wchar_t* value) {
    wchar_t buf[512];
    DWORD sz = sizeof buf;
    if (RegGetValueW(root, key, value, RRF_RT_REG_SZ, nullptr, buf, &sz) != ERROR_SUCCESS) return std::string();
    return narrow(buf);
}

DWORD regDword(HKEY root, const wchar_t* key, const wchar_t* value) {
    DWORD v = 0, sz = sizeof v;
    return RegGetValueW(root, key, value, RRF_RT_REG_DWORD, nullptr, &v, &sz) == ERROR_SUCCESS ? v : 0;
}

std::string hex4(unsigned v) {
    char b[8];
    std::snprintf(b, sizeof b, "%04x", v & 0xFFFF);
    return b;
}

bool packaged() {
    using Fn = LONG(WINAPI*)(UINT32*, PWSTR);
    auto fn = reinterpret_cast<Fn>(
        reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetCurrentPackageFullName")));
    if (!fn) return false;
    UINT32 len = 0;
    return fn(&len, nullptr) != 15700L;  // APPMODEL_ERROR_NO_PACKAGE: not packaged (MSIX)
}

std::string windowsVersion() {
    using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
    OSVERSIONINFOW vi = {};
    vi.dwOSVersionInfoSize = sizeof vi;
    if (auto fn = reinterpret_cast<RtlGetVersionFn>(
            reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"))))
        fn(&vi);
    const wchar_t* cv = L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
    return formatWindowsVersion(vi.dwMajorVersion, vi.dwMinorVersion, vi.dwBuildNumber,
                                regDword(HKEY_LOCAL_MACHINE, cv, L"UBR"),
                                regString(HKEY_LOCAL_MACHINE, cv, L"DisplayVersion"),
                                regString(HKEY_LOCAL_MACHINE, cv, L"EditionID"));
}

// "1.3.15 (viettelextip_1_3_15.dll)" + a warning when it is not this app's release.
std::string tipDll(const std::string& home) {
    const std::wstring key = L"CLSID\\" + widen(reg::kClsid) + L"\\InprocServer32";
    wchar_t buf[MAX_PATH];
    DWORD sz = sizeof buf;
    if (RegGetValueW(HKEY_CLASSES_ROOT, key.c_str(), nullptr, RRF_RT_REG_SZ, nullptr, buf, &sz) != ERROR_SUCCESS)
        return "not registered for this process's view";
    const std::wstring path = buf;
    const std::string version = tipDllVersion(path);
    std::string s = (version.empty() ? std::string("?") : version) + " (" + redactUserPath(narrow(path), home) + ")";
    if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) s += ", FILE MISSING";
    if (!sameRelease(VTX_VER_STRING, version)) s += ", DIFFERS FROM THE APP";
    return s;
}

std::string installKind(const std::string& home) {
    const std::wstring self = selfExePath();
    const std::string exe = narrow(self);
    std::vector<std::string> machine;
    for (const wchar_t* v : {L"ProgramFiles", L"ProgramW6432", L"ProgramFiles(x86)"}) {
        std::string r = envUtf8(v);
        if (!r.empty()) machine.push_back(r);
    }
    const InstallKind k = classifyInstall(portableMode(), packaged(), exe, machine, envUtf8(L"LOCALAPPDATA"));
    const std::string dir = exe.substr(0, exe.find_last_of("\\/"));
    return std::string(installKindName(k)) + ", " + redactUserPath(dir, home);
}

std::string uiLanguage() {
    wchar_t name[LOCALE_NAME_MAX_LENGTH] = {};
    const LANGID ui = GetUserDefaultUILanguage();
    if (LCIDToLocaleName(MAKELCID(ui, SORT_DEFAULT), name, LOCALE_NAME_MAX_LENGTH, 0) > 0) return narrow(name);
    return hex4(ui);
}

std::string keyboards() {
    std::string s;
    for (uintptr_t hkl : keyboardLayouts()) {
        char b[24];
        std::snprintf(b, sizeof b, "%s%08llx", s.empty() ? "" : " ", static_cast<unsigned long long>(hkl) & 0xFFFFFFFFull);
        s += b;
    }
    bool registered = false;
    const bool inList = vietTelexInUserList(registered);
    s += std::string(" | VietTelex ") + (inList ? "in the list" : registered ? "NOT in the list" : "NOT registered");
    s += " | default input language " + hex4(defaultInputLangId());
    return s;
}

std::string otherTextServices() {
    const std::vector<unsigned> langs = otherEnabledTextServiceLangs();
    std::string s = std::to_string(langs.size());
    if (!langs.empty()) {
        s += " (lang";
        for (unsigned l : langs) s += " " + hex4(l);
        s += ")";
    }
    return s;
}

std::string dpi() {
    using Fn = UINT(WINAPI*)();
    UINT d = 0;
    if (auto fn = reinterpret_cast<Fn>(
            reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForSystem"))))
        d = fn();
    if (!d) {
        HDC dc = GetDC(nullptr);
        d = dc ? static_cast<UINT>(GetDeviceCaps(dc, LOGPIXELSX)) : 0;
        if (dc) ReleaseDC(nullptr, dc);
    }
    char b[48];
    std::snprintf(b, sizeof b, "%u dpi (%u%%), %d monitor(s)", d, d ? d * 100 / 96 : 0,
                  GetSystemMetrics(SM_CMONITORS));
    return b;
}

std::string updates(const Settings& s) {
    std::string out = std::string("auto check ") + (s.autoUpdateCheck ? "on" : "off") +
                      ", channel stable (viettelex.com/stable.json), last auto check ";
    const unsigned long long last = readQword(L"lastAutoUpdateCheckAt");
    const unsigned long long now = static_cast<unsigned long long>(time(nullptr));
    if (!last) return out + "never";
    if (now < last) return out + "in the future (clock changed)";
    return out + std::to_string((now - last) / 3600) + " h ago";
}

std::vector<std::string> buildHeader(const Settings& s) {
    const std::string home = envUtf8(L"USERPROFILE");
    std::vector<std::pair<std::string, std::string>> f;
    f.emplace_back("app", std::string(VTX_VER_STRING));
    f.emplace_back("TIP DLL", tipDll(home));
    f.emplace_back("install", installKind(home));
    f.emplace_back("windows", windowsVersion());
    f.emplace_back("ui language", uiLanguage());
    f.emplace_back("keyboards", keyboards());
    f.emplace_back("other enabled text services", otherTextServices());
    f.emplace_back("display", dpi());
    f.emplace_back("settings", formatSettingsSummary(s));
    f.emplace_back("updates", updates(s));
    return formatDebugHeader(f);
}

}  // namespace

void debugContextApply(const Settings& s) {
    appSetLogging(s.debugLogging);
    if (!s.debugLogging) {
        g_on = false;
        return;
    }
    const std::string summary = formatSettingsSummary(s);
    if (!g_on) {
        g_on = true;
        g_lastSettings = summary;
        debugFileSetHeader(buildHeader(s), true);
    } else if (summary != g_lastSettings) {
        g_lastSettings = summary;
        appLog("app", "settings changed: " + summary);
        debugFileSetHeader(buildHeader(s), false);  // what the next file / day starts with
    }
}

void debugContextShutdown() {
    if (g_on) debugFileFlush();
}

}  // namespace vtx::app
