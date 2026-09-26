// app_quit.h — close running VietTelex.exe instances (upgrade / single-instance handoff).
#pragma once
#include <windows.h>

namespace vtx::app {

constexpr wchar_t kAppWindowClassName[] = L"VietTelexAppWindow";

// Posts WM_CLOSE to every VietTelex main window (class kAppWindowClassName) except those
// owned by `exceptPid`, waits up to `graceMs` for their processes to exit, then
// terminates the ones still alive — only if their image is VietTelex.exe. Returns the
// number of processes that were asked to quit.
int closeRunningApps(DWORD exceptPid, unsigned graceMs);

}  // namespace vtx::app
