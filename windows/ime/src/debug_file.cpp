#include "debug_file.h"

#include <windows.h>

#include "debug_log.h"

namespace vtx {

namespace {

SRWLOCK g_lock = SRWLOCK_INIT;
std::wstring g_path;  // chosen on first write
std::string g_exe;
bool g_resolved = false;

std::wstring env(const wchar_t* name) {
    wchar_t buf[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(name, buf, MAX_PATH);
    return (n > 0 && n < MAX_PATH) ? std::wstring(buf, n) : std::wstring();
}

std::string exeBase() {
    wchar_t path[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return "?";
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

bool appendTo(const std::wstring& path, const std::string& line) {
    HANDLE f = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size = {};
    if (GetFileSizeEx(f, &size) && logNeedsRotation(static_cast<uint64_t>(size.QuadPart), line.size())) {
        CloseHandle(f);
        MoveFileExW(path.c_str(), (path.substr(0, path.size() - 4) + L".1.log").c_str(), MOVEFILE_REPLACE_EXISTING);
        f = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (f == INVALID_HANDLE_VALUE) return false;
    }
    DWORD wrote = 0;  // one WriteFile per line: appends from several processes never interleave
    const bool ok = WriteFile(f, line.data(), static_cast<DWORD>(line.size()), &wrote, nullptr) && wrote == line.size();
    CloseHandle(f);
    return ok;
}

// Candidate paths in order: the real %LOCALAPPDATA% (from USERPROFILE: inside an
// AppContainer LOCALAPPDATA is redirected), then this process's temp folder.
bool writeLocked(const std::string& line) {
    if (!g_resolved) {
        g_resolved = true;
        std::wstring home = env(L"USERPROFILE");
        std::wstring primary = home.empty() ? env(L"LOCALAPPDATA") + L"\\VietTelex\\debug.log"
                                            : home + L"\\AppData\\Local\\VietTelex\\debug.log";
        std::wstring dir = primary.substr(0, primary.find_last_of(L'\\'));
        CreateDirectoryW(dir.c_str(), nullptr);
        if (appendTo(primary, line)) {
            g_path = primary;
            return true;
        }
        wchar_t tmp[MAX_PATH];
        DWORD n = GetTempPathW(MAX_PATH, tmp);
        if (n > 0 && n < MAX_PATH) {
            std::wstring fallback = std::wstring(tmp, n) + L"VietTelex-debug.log";
            if (appendTo(fallback, line)) {
                g_path = fallback;
                return true;
            }
        }
        return false;
    }
    return !g_path.empty() && appendTo(g_path, line);
}

}  // namespace

void debugFileWrite(const char* component, const std::string& msg) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    LogStamp t{st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds};
    AcquireSRWLockExclusive(&g_lock);
    if (g_exe.empty()) g_exe = exeBase();
    const std::string line = formatLogLine(t, GetCurrentProcessId(), g_exe, component, msg);
    writeLocked(line);
    ReleaseSRWLockExclusive(&g_lock);
    OutputDebugStringA(line.c_str());
}

std::wstring debugFilePath() {
    AcquireSRWLockShared(&g_lock);
    std::wstring p = g_path;
    ReleaseSRWLockShared(&g_lock);
    return p;
}

}  // namespace vtx
