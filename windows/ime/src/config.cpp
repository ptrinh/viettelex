#include "config.h"

#include <vector>

namespace vtx::tip::config {

namespace {

SRWLOCK g_lock = SRWLOCK_INIT;
bool g_inited = false;
bool g_secure = false;
bool g_appContainer = false;
std::string g_exe;
Settings g_settings;
AppMode g_mode = AppMode::Composition;
unsigned long g_gen = 1;
FILETIME g_stamp = {0, 0};
volatile LONG g_vietnamese = 1;
volatile LONG g_debug = 0;

constexpr wchar_t kRegAppLang[] = L"Software\\VietTelex\\AppLanguage";

bool detectAppContainer() {
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) return false;
    DWORD isAc = 0, len = 0;
    BOOL ok = GetTokenInformation(tok, TokenIsAppContainer, &isAc, sizeof isAc, &len);
    CloseHandle(tok);
    return ok && isAc != 0;
}

std::string narrowLower(const wchar_t* w) {
    std::string s;
    for (; *w; ++w) {
        wchar_t c = *w;
        if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
        s.push_back(c < 0x80 ? static_cast<char>(c) : '_');
    }
    return s;
}

std::wstring exeNameW() {
    wchar_t path[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return L"";
    const wchar_t* base = path;
    for (const wchar_t* p = path; *p; ++p)
        if (*p == L'\\' || *p == L'/') base = p + 1;
    return base;
}

// %LOCALAPPDATA%\VietTelex\settings.bin — inside an AppContainer LOCALAPPDATA points
// into the package, so derive it from USERPROFILE (not redirected). Avoids loading
// shell32 into every process just for SHGetKnownFolderPath.
std::wstring settingsPath() {
    wchar_t buf[MAX_PATH];
    DWORD n;
    if (!g_appContainer) {
        n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
        if (n > 0 && n < MAX_PATH) return std::wstring(buf) + L"\\VietTelex\\settings.bin";
    }
    n = GetEnvironmentVariableW(L"USERPROFILE", buf, MAX_PATH);
    if (n > 0 && n < MAX_PATH) return std::wstring(buf) + L"\\AppData\\Local\\VietTelex\\settings.bin";
    return L"";
}

bool readFile(const std::wstring& path, std::vector<uint8_t>& out) {
    HANDLE f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size;
    bool ok = GetFileSizeEx(f, &size) && size.QuadPart > 0 && size.QuadPart < (4 << 20);
    if (ok) {
        out.resize(static_cast<size_t>(size.QuadPart));
        DWORD got = 0;
        ok = ReadFile(f, out.data(), static_cast<DWORD>(out.size()), &got, nullptr) && got == out.size();
    }
    CloseHandle(f);
    return ok;
}

bool canUseRegistry() { return !g_secure && !g_appContainer; }

void loadVietnameseLocked() {
    if (!canUseRegistry()) return;
    std::wstring exe = exeNameW();
    DWORD v = 1, sz = sizeof v;
    if (RegGetValueW(HKEY_CURRENT_USER, kRegAppLang, exe.c_str(), RRF_RT_REG_DWORD, nullptr, &v, &sz) ==
        ERROR_SUCCESS)
        InterlockedExchange(&g_vietnamese, v ? 1 : 0);
}

}  // namespace

void init(bool secure) {
    AcquireSRWLockExclusive(&g_lock);
    if (!g_inited) {
        g_inited = true;
        g_secure = secure;
        g_appContainer = detectAppContainer();
        std::wstring exe = exeNameW();
        g_exe = narrowLower(exe.c_str());
        g_mode = resolveAppMode(g_exe, g_settings.appModes);
        loadVietnameseLocked();
    } else if (secure) {
        g_secure = true;  // never downgrade from secure within a process
    }
    ReleaseSRWLockExclusive(&g_lock);
    refresh();
}

unsigned long refresh() {
    AcquireSRWLockExclusive(&g_lock);
    unsigned long gen = g_gen;
    if (g_secure) {
        ReleaseSRWLockExclusive(&g_lock);
        return gen;
    }
    std::wstring path = settingsPath();
    WIN32_FILE_ATTRIBUTE_DATA fa;
    if (!path.empty() && GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &fa)) {
        if (CompareFileTime(&fa.ftLastWriteTime, &g_stamp) != 0) {
            std::vector<uint8_t> bytes;
            Settings s;
            if (readFile(path, bytes) && deserialize(bytes.data(), bytes.size(), s)) {
                g_settings = std::move(s);
                g_mode = resolveAppMode(g_exe, g_settings.appModes);
                InterlockedExchange(&g_debug, g_settings.debugLogging ? 1 : 0);
                g_stamp = fa.ftLastWriteTime;
                gen = ++g_gen;
            }
        }
    }
    ReleaseSRWLockExclusive(&g_lock);
    return gen;
}

unsigned long generation() {
    AcquireSRWLockShared(&g_lock);
    unsigned long g = g_gen;
    ReleaseSRWLockShared(&g_lock);
    return g;
}

Settings copySettings() {
    AcquireSRWLockShared(&g_lock);
    Settings s = g_settings;
    ReleaseSRWLockShared(&g_lock);
    if (g_secure) s.shortcuts.clear();
    return s;
}

bool secureMode() { return g_secure; }
bool inAppContainer() { return g_appContainer; }
const std::string& exeName() { return g_exe; }

AppMode appMode() {
    AcquireSRWLockShared(&g_lock);
    AppMode m = g_mode;
    ReleaseSRWLockShared(&g_lock);
    return m;
}

bool vietnamese() { return InterlockedCompareExchange(&g_vietnamese, 0, 0) != 0; }

void setVietnamese(bool on) {
    InterlockedExchange(&g_vietnamese, on ? 1 : 0);
    if (!canUseRegistry()) return;
    std::wstring exe = exeNameW();
    if (exe.empty()) return;
    HKEY k;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegAppLang, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) ==
        ERROR_SUCCESS) {
        DWORD v = on ? 1 : 0;
        RegSetValueExW(k, exe.c_str(), 0, REG_DWORD, reinterpret_cast<const BYTE*>(&v), sizeof v);
        RegCloseKey(k);
    }
}

void reloadVietnamese() {
    AcquireSRWLockShared(&g_lock);
    loadVietnameseLocked();
    ReleaseSRWLockShared(&g_lock);
}

void log(const char* msg) {
    if (!InterlockedCompareExchange(&g_debug, 0, 0) || !msg) return;
    char buf[512];
    wsprintfA(buf, "[VietTelexTIP %lu] %s\n", GetCurrentProcessId(), msg);
    OutputDebugStringA(buf);
}

}  // namespace vtx::tip::config
