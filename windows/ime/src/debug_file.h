// debug_file.h — appends debug-log lines (debug_log.h format) to
// %LOCALAPPDATA%\VietTelex\debug.log. Shared by the TIP (every host process) and
// VietTelex.exe. Callers gate on settings.debugLogging (nothing here runs while it is off).
//
//   * Rotation: to debug.1.log (the only old file kept) past ~1 MB, or when the file was
//     last written more than 7 days ago (an old session's lines are not kept forever).
//   * A `=== yyyy-mm-dd ===` line whenever the file's last write was on another day; the
//     lines themselves carry the time only.
//   * Each process writes its `# context:` line (debug_header.h) before its first line, at
//     the start of a new file and on its first line of a new day; VietTelex.exe's header
//     lines (debugFileSetHeader) follow it.
//   * Identical consecutive lines of one process are collapsed (LogCollapser).
//
// AppContainer / low-IL hosts cannot write there (the folder grants them read only):
// they fall back to their own writable temp folder (…\Packages\<pkg>\AC\Temp\
// VietTelex-debug.log), and if even that fails, to OutputDebugString only.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include "debug_log.h"

namespace vtx {

void debugFileWrite(const char* component, const std::string& msg);
// The same line with the time it happened (local time + GetTickCount64): VietTelex.exe's
// hook thread queues its lines and a writer writes them later (app/core/log_queue.h).
void debugFileWriteAt(const char* component, const std::string& msg, const LogStamp& t, uint64_t tickMs);
// VietTelex.exe: the header messages ("# key: value", debug_header.h formatDebugHeader)
// written after this process's context line. `emitNow`: write context + header right
// away (app start, logging just turned on); otherwise they are kept for the next new
// file / new day.
void debugFileSetHeader(std::vector<std::string> lines, bool emitNow);
// Writes a pending "^ repeated Nx" line (app exit).
void debugFileFlush();
// Where this process writes (empty until the first line). For diagnostics / tests.
std::wstring debugFilePath();

}  // namespace vtx
