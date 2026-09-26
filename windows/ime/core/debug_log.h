// debug_log.h — format and rotation rules of %LOCALAPPDATA%\VietTelex\debug.log (1.1.5).
//
// Every VietTelex component (the TIP in any host process, the app, its hook and the
// Direct verifier) appends one line per event when settings.debugLogging is on:
//   2026-09-26 14:03:07.123 pid=4312 conhost.exe [tip] message
// Messages carry decisions, key classes and lengths only — never typed text.
#pragma once
#include <cstdint>
#include <string>

namespace vtx {

struct LogStamp {
    int year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0, millis = 0;
};

constexpr uint64_t kDebugLogMaxBytes = 1024 * 1024;  // then debug.log -> debug.1.log

// One complete line (CRLF-terminated). Control characters in `msg` become spaces so an
// entry can never span lines.
std::string formatLogLine(const LogStamp& t, unsigned long pid, const std::string& exe, const char* component,
                          const std::string& msg);

// Rotate before appending `adding` bytes to a file of `size` bytes?
inline bool logNeedsRotation(uint64_t size, uint64_t adding) { return size > 0 && size + adding > kDebugLogMaxBytes; }

}  // namespace vtx
