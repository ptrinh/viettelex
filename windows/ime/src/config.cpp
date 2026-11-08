#include "config.h"

#include <vector>

#include "app_language.h"
#include "debug_file.h"
#include "debug_log.h"
#include "ipc.h"

namespace vtx::tip::config {

namespace {

SRWLOCK g_lock = SRWLOCK_INIT;
bool g_inited = false;
bool g_secure = false;
bool g_appContainer = false;
std::string g_exe;
// Immutable once published: readers share it (one shortcuts map per process).
std::shared_ptr<const Settings> g_settings = std::make_shared<const Settings>();
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

// AppContainer / low IL: the parsed applang.txt mirror and the file time it was read at.
SRWLOCK g_mirrorLock = SRWLOCK_INIT;
AppLanguageStore g_mirror;
FILETIME g_mirrorStamp = {0, 0};

// Debug log: "applang restore" is re-announced at every activation / focus change (dozens
// per second in a browser); only a result that differs from the last one logged for that
// app in this process is written.
SRWLOCK g_applangLogLock = SRWLOCK_INIT;
LogChangeGate g_applangLogged;

std::wstring g_activeExeW;  // app identity (WebView2: the owning app's exe)
std::wstring activeExeW() { return g_activeExeW.empty() ? exeNameW() : g_activeExeW; }

// Where this process's Việt/Anh memory comes from: HKCU (normal processes), the app's
// mirror file (AppContainer / low IL: HKCU is off limits), nothing in secure mode.
void loadVietnameseLocked() {
    const std::wstring exe = activeExeW();
    const std::string id = narrowLower(exe.c_str());
    const char* source = "default";
    // No memory for this app yet: Vietnamese, or English with "Bắt đầu bằng tiếng Anh trong
    // app mới" (settings startEnglish; caller holds g_lock, which guards g_settings).
    bool on = !g_settings->startEnglish;
    if (g_secure) {
        source = "secure desktop (default)";
    } else if (canUseRegistry()) {
        DWORD v = 1, sz = sizeof v;
        if (RegGetValueW(HKEY_CURRENT_USER, kRegAppLang, exe.c_str(), RRF_RT_REG_DWORD, nullptr, &v, &sz) ==
            ERROR_SUCCESS) {
            on = v != 0;
            source = "registry";
        }
    } else {
        // The app's mirror file, parsed again only when VietTelex.exe rewrote it (every
        // focus change lands here: one stat instead of open + read + parse).
        std::wstring path = settingsPath();
        path = path.substr(0, path.find_last_of(L'\\') + 1) + L"applang.txt";
        WIN32_FILE_ATTRIBUTE_DATA fa;
        const bool exists = GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &fa) != FALSE;
        AcquireSRWLockExclusive(&g_mirrorLock);
        if (!exists) {
            g_mirror = AppLanguageStore();
            g_mirrorStamp = {0, 0};
        } else if (CompareFileTime(&fa.ftLastWriteTime, &g_mirrorStamp) != 0) {
            std::vector<uint8_t> bytes;
            AppLanguageStore store;
            if (readFile(path, bytes)) {
                store.parse(std::string(bytes.begin(), bytes.end()));
                g_mirrorStamp = fa.ftLastWriteTime;
            }
            g_mirror = std::move(store);
        }
        if (g_mirror.known(id)) {
            on = g_mirror.vietnamese(id);
            source = "app mirror (AppContainer)";
        }
        ReleaseSRWLockExclusive(&g_mirrorLock);
    }
    InterlockedExchange(&g_vietnamese, on ? 1 : 0);
    if (InterlockedCompareExchange(&g_debug, 0, 0)) {
        const std::string result = std::string(on ? "vi" : "en") + " from " + source;
        AcquireSRWLockExclusive(&g_applangLogLock);
        const bool changed = g_applangLogged.changed(id, result);
        ReleaseSRWLockExclusive(&g_applangLogLock);
        if (changed) debugFileWrite("tip", "applang restore " + id + " -> " + result);
    }
}

}  // namespace

void init(bool secure) {
    AcquireSRWLockExclusive(&g_lock);
    const bool first = !g_inited;
    if (!g_inited) {
        g_inited = true;
        g_secure = secure;
        g_appContainer = detectAppContainer();
        std::wstring exe = exeNameW();
        g_exe = narrowLower(exe.c_str());
        g_mode = resolveAppMode(g_exe, g_settings->appModes);
    } else if (secure) {
        g_secure = true;  // never downgrade from secure within a process
    }
    ReleaseSRWLockExclusive(&g_lock);
    refresh();
    // After refresh(): the default for an app with no memory reads startEnglish.
    if (first) reloadVietnamese();
}

unsigned long refresh() {
    // Common case (every focus change): the file is unchanged — one stat under a SHARED
    // lock, no exclusive section.
    AcquireSRWLockShared(&g_lock);
    unsigned long gen = g_gen;
    const bool secure = g_secure;
    const FILETIME stamp = g_stamp;
    const std::wstring path = secure ? std::wstring() : settingsPath();
    ReleaseSRWLockShared(&g_lock);
    if (secure || path.empty()) return gen;
    WIN32_FILE_ATTRIBUTE_DATA fa;
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &fa) ||
        CompareFileTime(&fa.ftLastWriteTime, &stamp) == 0)
        return gen;
    std::vector<uint8_t> bytes;
    Settings s;
    if (!readFile(path, bytes) || !deserialize(bytes.data(), bytes.size(), s)) return gen;
    auto fresh = std::make_shared<const Settings>(std::move(s));
    AcquireSRWLockExclusive(&g_lock);
    if (CompareFileTime(&fa.ftLastWriteTime, &g_stamp) != 0) {  // another thread may have loaded it
        g_settings = std::move(fresh);
        g_mode = resolveAppMode(narrowLower(activeExeW().c_str()), g_settings->appModes);
        InterlockedExchange(&g_debug, g_settings->debugLogging ? 1 : 0);
        g_stamp = fa.ftLastWriteTime;
        ++g_gen;
    }
    gen = g_gen;
    ReleaseSRWLockExclusive(&g_lock);
    return gen;
}

unsigned long generation() {
    AcquireSRWLockShared(&g_lock);
    unsigned long g = g_gen;
    ReleaseSRWLockShared(&g_lock);
    return g;
}

std::shared_ptr<const Settings> snapshot() {
    AcquireSRWLockShared(&g_lock);
    std::shared_ptr<const Settings> s = g_settings;
    ReleaseSRWLockShared(&g_lock);
    // Secure desktop: never user data (refresh() never loads there; belt and braces).
    if (g_secure && !s->shortcuts.empty()) {
        auto copy = std::make_shared<Settings>(*s);
        copy->shortcuts.clear();
        return copy;
    }
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
    bool stored = false;
    std::wstring exe = activeExeW();
    if (canUseRegistry() && !exe.empty()) {
        HKEY k;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegAppLang, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) ==
            ERROR_SUCCESS) {
            DWORD v = on ? 1 : 0;
            stored = RegSetValueExW(k, exe.c_str(), 0, REG_DWORD, reinterpret_cast<const BYTE*>(&v), sizeof v) ==
                     ERROR_SUCCESS;
            RegCloseKey(k);
        }
    }
    // Tell VietTelex.exe: it refreshes the AppContainer mirror, and stores the value for
    // hosts that cannot (AppContainer / low IL; kAppCommandMsg is allowed through UIPI).
    if (!g_secure)
        if (HWND app = FindWindowW(kAppWindowClass, nullptr))
            PostMessageW(app, kAppCommandMsg, static_cast<WPARAM>(AppCommand::SetAppLanguage),
                         (on ? 1 : 0) | (stored ? 0 : 2));
    if (InterlockedCompareExchange(&g_debug, 0, 0))
        debugFileWrite("tip", "applang save " + narrowLower(exe.c_str()) + " -> " + (on ? "vi" : "en") +
                                  (stored ? " (registry)" : " (via app)"));
}

void setActiveApp(const std::wstring& exeBaseName) {
    AcquireSRWLockExclusive(&g_lock);
    const std::string id = appIdentity(g_exe, narrowLower(exeBaseName.c_str()));
    if (id != narrowLower(activeExeW().c_str())) {
        g_activeExeW = id == g_exe ? std::wstring() : exeBaseName;
        g_mode = resolveAppMode(id, g_settings->appModes);
        loadVietnameseLocked();
    }
    ReleaseSRWLockExclusive(&g_lock);
}

void reloadVietnamese() {
    AcquireSRWLockShared(&g_lock);
    loadVietnameseLocked();
    ReleaseSRWLockShared(&g_lock);
}

void log(const char* msg) {
    if (!InterlockedCompareExchange(&g_debug, 0, 0) || !msg) return;
    debugFileWrite("tip", msg);
}

void log(const std::string& msg) { log(msg.c_str()); }

bool logging() { return InterlockedCompareExchange(&g_debug, 0, 0) != 0; }

}  // namespace vtx::tip::config
