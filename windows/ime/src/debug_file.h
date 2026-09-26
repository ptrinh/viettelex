// debug_file.h — appends debug-log lines (debug_log.h format) to
// %LOCALAPPDATA%\VietTelex\debug.log, rotating to debug.1.log at ~1 MB. Shared by the TIP
// (every host process) and VietTelex.exe. Callers gate on settings.debugLogging.
//
// AppContainer / low-IL hosts cannot write there (the folder grants them read only):
// they fall back to their own writable temp folder (…\Packages\<pkg>\AC\Temp\
// VietTelex-debug.log), and if even that fails, to OutputDebugString only.
#pragma once
#include <string>

namespace vtx {

void debugFileWrite(const char* component, const std::string& msg);
// Where this process writes (empty until the first line). For diagnostics / tests.
std::wstring debugFilePath();

}  // namespace vtx
