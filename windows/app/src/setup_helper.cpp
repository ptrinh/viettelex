// setup_helper.cpp — VietTelexSetupHelper.exe: runs from the MSI's Binary table (so it
// exists before files are installed) with no window. See core/setup_helper_logic.h.
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <string>
#include <vector>

#include "app_quit.h"
#include "setup_helper_logic.h"

using namespace vtx;

namespace {

std::wstring volumeRoot(const std::wstring& path) {
    wchar_t v[MAX_PATH];
    return GetVolumePathNameW(path.c_str(), v, MAX_PATH) ? std::wstring(v) : std::wstring();
}

// SYSTEM's TEMP folder (C:\Windows\SystemTemp or C:\Windows\Temp), when it lies on the
// same volume as `dir` — a rename cannot cross volumes. Empty otherwise.
std::wstring parkingDir(const std::wstring& dir) {
    wchar_t t[MAX_PATH + 1];
    const DWORD n = GetTempPathW(MAX_PATH + 1, t);
    if (n == 0 || n > MAX_PATH) return std::wstring();
    std::wstring tmp(t, n);
    while (!tmp.empty() && tmp.back() == L'\\') tmp.pop_back();
    if (tmp.empty() || GetFileAttributesW(tmp.c_str()) == INVALID_FILE_ATTRIBUTES) return std::wstring();
    return sameVolumeRoot(volumeRoot(tmp), volumeRoot(dir)) ? tmp : std::wstring();
}

// Gets `path` out of the install folder: renamed into TEMP (allowed even while the DLL is
// mapped by running apps), then deleted now or — still mapped — at the next boot. Only
// when TEMP is on another volume does it fall back to a rename in place. Returns false
// when the file stayed in the install folder.
bool retire(const std::wstring& path, const std::wstring& name, const std::wstring& parking, unsigned tag,
            unsigned long long stamp) {
    if (!parking.empty()) {
        const std::wstring parked = parking + L"\\" + parkedName(name, tag, stamp);
        if (MoveFileExW(path.c_str(), parked.c_str(), MOVEFILE_REPLACE_EXISTING)) {
            if (!DeleteFileW(parked.c_str())) MoveFileExW(parked.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
            return true;
        }
    }
    if (DeleteFileW(path.c_str())) return true;
    const size_t s = path.find_last_of(L'\\');
    const std::wstring moved = isReleasedLeftover(name) ? path : path.substr(0, s + 1) + releaseName(name, stamp);
    if (moved != path && !MoveFileExW(path.c_str(), moved.c_str(), MOVEFILE_REPLACE_EXISTING)) return false;
    if (!DeleteFileW(moved.c_str())) MoveFileExW(moved.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
    return false;
}

// Returns true when every TIP file left the folder (nothing is waiting for a reboot in it).
bool releaseTipDlls(const std::wstring& dir, const std::string& maxVersion, unsigned tag) {
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW((dir + L"\\VietTelexTIP*").c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) return true;
    const unsigned long long stamp = GetTickCount64();
    const std::wstring parking = parkingDir(dir);
    bool clean = true;
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        // Earlier leftovers ("*.old" parked in place by <= 1.3.x helpers) and DLLs of this
        // version or older. Newer DLLs are never touched (see shouldRelease).
        if (isReleasedLeftover(fd.cFileName) || shouldRelease(fd.cFileName, maxVersion))
            if (!retire(dir + L"\\" + fd.cFileName, fd.cFileName, parking, tag, stamp)) clean = false;
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    return clean;
}

std::wstring imageOf(HANDLE process) {
    wchar_t buf[MAX_PATH];
    DWORD n = MAX_PATH;
    return QueryFullProcessImageNameW(process, 0, buf, &n) ? std::wstring(buf, n) : std::wstring();
}

// Uninstall, as SYSTEM: VietTelex.exe instances QuitApp could not close (other sessions,
// hung) would keep VietTelex.exe in use and the folder alive. Only the installed image.
void terminateInstalledApps(const std::vector<std::wstring>& dirs) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return;
    PROCESSENTRY32W pe;
    pe.dwSize = sizeof(pe);
    for (BOOL ok = Process32FirstW(snap, &pe); ok; ok = Process32NextW(snap, &pe)) {
        if (!isAppImage(pe.szExeFile)) continue;
        HANDLE p = OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               pe.th32ProcessID);
        if (!p) continue;
        if (isInstalledAppImage(imageOf(p), dirs) && TerminateProcess(p, 0)) WaitForSingleObject(p, 2000);
        CloseHandle(p);
    }
    CloseHandle(snap);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::vector<std::wstring> args;
    for (int i = 1; argv && i < argc; ++i) args.push_back(argv[i]);
    if (argv) LocalFree(argv);
    const HelperArgs a = parseHelperArgs(args);
    if (a.quitApp) app::closeRunningApps(0, kQuitGraceMs);
    if (a.releaseTip) {
        if (a.uninstall) terminateInstalledApps(a.dirs);  // QuitApp already asked nicely
        unsigned tag = 0;
        for (const std::wstring& d : a.dirs)
            // A file that could only be parked in place keeps the folder until the next
            // boot: on uninstall have the (then empty) folder removed at that boot too.
            if (!releaseTipDlls(d, a.maxVersion, tag++) && a.uninstall)
                MoveFileExW(d.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
    }
    return 0;  // never fail the install: every step is best effort
}
