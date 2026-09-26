#include "app_quit.h"

#include <string>
#include <vector>

#include "setup_helper_logic.h"

namespace vtx::app {

namespace {
struct Found {
    DWORD exceptPid;
    std::vector<DWORD> pids;
};

BOOL CALLBACK enumProc(HWND h, LPARAM lp) {
    auto* f = reinterpret_cast<Found*>(lp);
    wchar_t cls[64];
    if (!GetClassNameW(h, cls, 64) || lstrcmpW(cls, kAppWindowClassName) != 0) return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (!pid || pid == f->exceptPid) return TRUE;
    PostMessageW(h, WM_CLOSE, 0, 0);
    for (DWORD p : f->pids)
        if (p == pid) return TRUE;
    f->pids.push_back(pid);
    return TRUE;
}

std::wstring imageOf(HANDLE process) {
    wchar_t buf[MAX_PATH];
    DWORD n = MAX_PATH;
    return QueryFullProcessImageNameW(process, 0, buf, &n) ? std::wstring(buf, n) : std::wstring();
}
}  // namespace

int closeRunningApps(DWORD exceptPid, unsigned graceMs) {
    Found f{exceptPid, {}};
    EnumWindows(enumProc, reinterpret_cast<LPARAM>(&f));
    std::vector<HANDLE> procs;
    for (DWORD pid : f.pids)
        if (HANDLE p = OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid))
            procs.push_back(p);
    if (!procs.empty()) {
        WaitForMultipleObjects(static_cast<DWORD>(procs.size()), procs.data(), TRUE, graceMs);
        for (HANDLE p : procs) {
            if (WaitForSingleObject(p, 0) == WAIT_TIMEOUT && isAppImage(imageOf(p))) TerminateProcess(p, 0);
            CloseHandle(p);
        }
    }
    return static_cast<int>(f.pids.size());
}

}  // namespace vtx::app
