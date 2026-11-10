#include "debug_file.h"

#include <windows.h>

#include "debug_header.h"
#include "debug_log.h"
#include "version.h"

namespace vtx {

namespace {

SRWLOCK g_lock = SRWLOCK_INIT;
std::wstring g_path;  // chosen on first write
std::string g_exe;
bool g_resolved = false;
std::string g_context;              // "# context: …" of this process (built on first use)
std::vector<std::string> g_header;  // VietTelex.exe's header messages (debugFileSetHeader)
int g_contextDay = 0;               // yyyymmdd of this process's last context block, 0 = none yet
LogCollapser g_collapse;

std::wstring env(const wchar_t* name) {
    wchar_t buf[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(name, buf, MAX_PATH);
    return (n > 0 && n < MAX_PATH) ? std::wstring(buf, n) : std::wstring();
}

std::string lowerBase(const wchar_t* path) {
    const wchar_t* base = path;
    for (const wchar_t* p = path; *p; ++p)
        if (*p == L'\\' || *p == L'/') base = p + 1;
    std::string s;
    for (; *base; ++base) {
        wchar_t c = *base;
        if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
        s.push_back(c < 0x80 ? static_cast<char>(c) : '_');
    }
    return s;
}

std::string exeBase() {
    wchar_t path[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return "?";
    return lowerBase(path);
}

LogStamp stampOf(const SYSTEMTIME& st) {
    return LogStamp{st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds};
}

int dayOf(const LogStamp& t) { return t.year * 10000 + t.month * 100 + t.day; }

// The machine this code was compiled for (IMAGE_FILE_MACHINE_*). ARM64EC first: MSVC
// also defines _M_X64 there.
uint16_t builtMachine() {
#if defined(_M_ARM64EC) || defined(__arm64ec__)
    return 0xA641;
#elif defined(_M_ARM64) || defined(__aarch64__)
    return 0xAA64;
#elif defined(_M_X64) || defined(__x86_64__)
    return 0x8664;
#elif defined(_M_IX86) || defined(__i386__)
    return 0x014C;
#else
    return 0;
#endif
}

// One-time, cheap: module name, version, OS build, architecture, token facts.
std::string buildContext() {
    ProcessContext c;
    c.version = VTX_VER_STRING;
    HMODULE self = nullptr;
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(&g_lock), &self)) {
        wchar_t path[MAX_PATH];
        DWORD n = GetModuleFileNameW(self, path, MAX_PATH);
        if (n > 0 && n < MAX_PATH) c.module = lowerBase(path);
    }
    c.processMachine = builtMachine();
    using IsWow64Process2Fn = BOOL(WINAPI*)(HANDLE, USHORT*, USHORT*);
    if (auto wow = reinterpret_cast<IsWow64Process2Fn>(
            reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "IsWow64Process2")))) {
        USHORT pm = 0, nm = 0;
        if (wow(GetCurrentProcess(), &pm, &nm)) c.osMachine = nm;
    }
    using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
    OSVERSIONINFOW vi = {};
    vi.dwOSVersionInfoSize = sizeof vi;
    if (auto fn = reinterpret_cast<RtlGetVersionFn>(
            reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"))))
        if (fn(&vi) == 0) {
            c.osMajor = vi.dwMajorVersion;
            c.osMinor = vi.dwMinorVersion;
            c.osBuild = vi.dwBuildNumber;
        }
    HANDLE tok = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
        DWORD_PTR buf[16];  // TOKEN_MANDATORY_LABEL + its SID, pointer-aligned
        DWORD len = 0;
        if (GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof buf, &len)) {
            PSID sid = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf)->Label.Sid;
            const UCHAR count = *GetSidSubAuthorityCount(sid);
            if (count) c.integrityRid = *GetSidSubAuthority(sid, count - 1);
        }
        TOKEN_ELEVATION el = {};
        if (GetTokenInformation(tok, TokenElevation, &el, sizeof el, &len)) c.elevated = el.TokenIsElevated != 0;
        DWORD ac = 0;
        if (GetTokenInformation(tok, TokenIsAppContainer, &ac, sizeof ac, &len)) c.appContainer = ac != 0;
        CloseHandle(tok);
    }
    return formatProcessContext(c);
}

// This process's context line + VietTelex.exe's header, as log lines.
std::string contextBlock(const LogStamp& t, const char* component) {
    const unsigned long pid = GetCurrentProcessId();
    const char* comp = g_header.empty() ? component : "app";
    std::string out = formatLogLine(t, pid, g_exe, comp, g_context);
    for (const std::string& h : g_header) out += formatLogLine(t, pid, g_exe, comp, h);
    return out;
}

HANDLE openForAppend(const std::wstring& path) {
    return CreateFileW(path.c_str(), FILE_APPEND_DATA | FILE_READ_ATTRIBUTES,
                       FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_ALWAYS,
                       FILE_ATTRIBUTE_NORMAL, nullptr);
}

// Appends `body`, preceded by a day line (file empty or last written another day) and by
// this process's context block (`wantContext`, or the file is new). `wroteContext` tells
// the caller the block went out.
bool appendTo(const std::wstring& path, const std::string& body, bool wantContext, const LogStamp& t,
              const char* component, bool& wroteContext) {
    HANDLE f = openForAppend(path);
    if (f == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size = {};
    uint64_t sz = GetFileSizeEx(f, &size) ? static_cast<uint64_t>(size.QuadPart) : 0;
    LogStamp last;
    int64_t idle = 0;
    FILETIME written = {};
    if (sz > 0 && GetFileTime(f, nullptr, nullptr, &written)) {
        FILETIME nowFt;
        GetSystemTimeAsFileTime(&nowFt);
        ULARGE_INTEGER a, b;
        a.LowPart = written.dwLowDateTime;
        a.HighPart = written.dwHighDateTime;
        b.LowPart = nowFt.dwLowDateTime;
        b.HighPart = nowFt.dwHighDateTime;
        idle = b.QuadPart > a.QuadPart ? static_cast<int64_t>((b.QuadPart - a.QuadPart) / 10000000ull) : 0;
        SYSTEMTIME utc, local;
        if (FileTimeToSystemTime(&written, &utc) && SystemTimeToTzSpecificLocalTime(nullptr, &utc, &local))
            last = stampOf(local);
    }
    if (logNeedsRotation(sz, body.size() + 1024, idle)) {
        CloseHandle(f);
        MoveFileExW(path.c_str(), (path.substr(0, path.size() - 4) + L".1.log").c_str(), MOVEFILE_REPLACE_EXISTING);
        f = openForAppend(path);
        if (f == INVALID_HANDLE_VALUE) return false;
        sz = GetFileSizeEx(f, &size) ? static_cast<uint64_t>(size.QuadPart) : 0;
    }
    std::string out;
    if (logNeedsDayLine(sz, last, t)) out += formatDayLine(t);
    const bool context = wantContext || sz == 0;
    if (context) out += contextBlock(t, component);
    out += body;
    DWORD wrote = 0;  // one WriteFile per block: appends from several processes never interleave
    const bool ok = out.empty() || (WriteFile(f, out.data(), static_cast<DWORD>(out.size()), &wrote, nullptr) &&
                                    wrote == out.size());
    CloseHandle(f);
    if (ok && context) wroteContext = true;
    return ok;
}

// Candidate paths in order: the real %LOCALAPPDATA% (from USERPROFILE: inside an
// AppContainer LOCALAPPDATA is redirected), then this process's temp folder.
bool writeLocked(const std::string& body, bool wantContext, const LogStamp& t, const char* component) {
    bool wroteContext = false;
    bool ok = false;
    if (!g_resolved) {
        g_resolved = true;
        std::wstring home = env(L"USERPROFILE");
        std::wstring primary = home.empty() ? env(L"LOCALAPPDATA") + L"\\VietTelex\\debug.log"
                                            : home + L"\\AppData\\Local\\VietTelex\\debug.log";
        std::wstring dir = primary.substr(0, primary.find_last_of(L'\\'));
        CreateDirectoryW(dir.c_str(), nullptr);
        if (appendTo(primary, body, wantContext, t, component, wroteContext)) {
            g_path = primary;
            ok = true;
        } else {
            wchar_t tmp[MAX_PATH];
            DWORD n = GetTempPathW(MAX_PATH, tmp);
            if (n > 0 && n < MAX_PATH) {
                std::wstring fallback = std::wstring(tmp, n) + L"VietTelex-debug.log";
                if (appendTo(fallback, body, wantContext, t, component, wroteContext)) {
                    g_path = fallback;
                    ok = true;
                }
            }
        }
    } else {
        ok = !g_path.empty() && appendTo(g_path, body, wantContext, t, component, wroteContext);
    }
    if (wroteContext) g_contextDay = dayOf(t);
    return ok;
}

void ensureIdentityLocked() {
    if (g_exe.empty()) g_exe = exeBase();
    if (g_context.empty()) g_context = buildContext();
}

}  // namespace

void debugFileWrite(const char* component, const std::string& msg) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    debugFileWriteAt(component, msg, stampOf(st), GetTickCount64());
}

void debugFileWriteAt(const char* component, const std::string& msg, const LogStamp& t, uint64_t ms) {
    AcquireSRWLockExclusive(&g_lock);
    ensureIdentityLocked();
    const std::string body = g_collapse.offer(t, ms, GetCurrentProcessId(), g_exe, component, msg);
    const bool wantContext = g_contextDay != dayOf(t);
    if (!body.empty() || wantContext) writeLocked(body, wantContext, t, component);
    ReleaseSRWLockExclusive(&g_lock);
    if (!body.empty()) OutputDebugStringA(body.c_str());
}

void debugFileSetHeader(std::vector<std::string> lines, bool emitNow) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    const LogStamp t = stampOf(st);
    AcquireSRWLockExclusive(&g_lock);
    g_header = std::move(lines);
    if (emitNow) {
        ensureIdentityLocked();
        writeLocked(g_collapse.drain(t, GetCurrentProcessId(), g_exe), true, t, "app");
    }
    ReleaseSRWLockExclusive(&g_lock);
}

void debugFileFlush() {
    SYSTEMTIME st;
    GetLocalTime(&st);
    const LogStamp t = stampOf(st);
    AcquireSRWLockExclusive(&g_lock);
    if (g_collapse.pending()) {
        const std::string body = g_collapse.drain(t, GetCurrentProcessId(), g_exe);
        writeLocked(body, false, t, "app");
    }
    ReleaseSRWLockExclusive(&g_lock);
}

std::wstring debugFilePath() {
    AcquireSRWLockShared(&g_lock);
    std::wstring p = g_path;
    ReleaseSRWLockShared(&g_lock);
    return p;
}

}  // namespace vtx
