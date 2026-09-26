// setup_helper.cpp — VietTelexSetupHelper.exe: runs from the MSI's Binary table (so it
// exists before files are installed) with no window. See core/setup_helper_logic.h.
#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

#include "app_quit.h"
#include "setup_helper_logic.h"

using namespace vtx;

namespace {

void releaseTipDlls(const std::wstring& dir, const std::string& maxVersion) {
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW((dir + L"\\VietTelexTIP*").c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) return;
    const unsigned long long stamp = GetTickCount64();
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        const std::wstring path = dir + L"\\" + fd.cFileName;
        if (isReleasedLeftover(fd.cFileName)) {
            // Earlier leftovers: delete now if no process maps them any more, else at reboot.
            if (!DeleteFileW(path.c_str())) MoveFileExW(path.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
        } else if (shouldRelease(fd.cFileName, maxVersion)) {
            const std::wstring moved = dir + L"\\" + releaseName(fd.cFileName, stamp);
            if (MoveFileExW(path.c_str(), moved.c_str(), MOVEFILE_REPLACE_EXISTING)) {
                // Not in use (e.g. nobody typed since boot)? Gone right away; else at reboot,
                // silently — the MSI itself never sees a file in use, so it asks nothing.
                if (!DeleteFileW(moved.c_str())) MoveFileExW(moved.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
            }
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
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
    if (a.releaseTip)
        for (const std::wstring& d : a.dirs) releaseTipDlls(d, a.maxVersion);
    return 0;  // never fail the install: every step is best effort
}
