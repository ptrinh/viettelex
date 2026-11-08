// debug_log.h — format, rotation and compaction rules of %LOCALAPPDATA%\VietTelex\debug.log
// (1.1.5; compact format 1.3.18). Portable (no Win32): unit-tested on the host.
//
// Every VietTelex component (the TIP in any host process, the app, its hook and the
// Direct verifier) appends one line per event when settings.debugLogging is on:
//   === 2026-11-08 ===                                    (first line of each day in the file)
//   14:03:07.123 4312 conhost.exe [tip] message
//   14:03:07.180 4312 conhost.exe [tip] ^ repeated 8x more until 14:03:07.170
// time (local, ms) · pid · exe of the writing process · component · message. The pid and
// exe stay on every line: several processes append to the same file at once.
// Each process starts with a context block (debug_header.h): its version, architecture,
// Windows build, integrity — the app adds the full header (install kind, TIP DLL version,
// settings, …). Messages carry decisions, key classes and lengths only — never typed text.
#pragma once
#include <cstdint>
#include <map>
#include <string>

namespace vtx {

struct LogStamp {
    int year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0, millis = 0;
};

constexpr uint64_t kDebugLogMaxBytes = 1024 * 1024;                // then debug.log -> debug.1.log
constexpr int64_t kDebugLogMaxIdleSeconds = 7 * 24 * 3600;         // older file: rotated away
constexpr uint64_t kDebugLogRepeatWindowMs = 60 * 1000;            // collapse identical lines

// One complete line (CRLF-terminated). Control characters in `msg` become spaces so an
// entry can never span lines.
std::string formatLogLine(const LogStamp& t, unsigned long pid, const std::string& exe, const char* component,
                          const std::string& msg);
// "=== 2026-11-08 ===\r\n": the date the following time-only lines belong to.
std::string formatDayLine(const LogStamp& t);
// "14:03:07.180 4312 conhost.exe [tip] ^ repeated 8x more until 14:03:07.170\r\n".
std::string formatRepeatLine(const LogStamp& now, const LogStamp& last, unsigned long pid, const std::string& exe,
                             const char* component, unsigned count);

// Rotate (debug.log -> debug.1.log, the one old file kept) before appending `adding`
// bytes to a file of `size` bytes last written `idleSeconds` ago?
inline bool logNeedsRotation(uint64_t size, uint64_t adding, int64_t idleSeconds = 0) {
    if (size == 0) return false;
    return size + adding > kDebugLogMaxBytes || idleSeconds > kDebugLogMaxIdleSeconds;
}
// The file is empty or was last written on another day: write formatDayLine() first.
bool logNeedsDayLine(uint64_t size, const LogStamp& lastWrite, const LogStamp& now);

// Per-writer (per-process) collapse of consecutive identical lines: the first one is
// written, repeats within kDebugLogRepeatWindowMs of the previous one are only counted,
// and the count is written as a formatRepeatLine() before the next different line (or by
// drain()). Not thread-safe: the writer calls it under its lock.
class LogCollapser {
public:
    // What to append for this event ("" = a counted repeat). `nowMs` is any monotonic clock.
    std::string offer(const LogStamp& t, uint64_t nowMs, unsigned long pid, const std::string& exe,
                      const char* component, const std::string& msg);
    // The pending repeat count as a line ("" when none); resets it.
    std::string drain(const LogStamp& now, unsigned long pid, const std::string& exe);
    unsigned pending() const { return repeats_; }

private:
    std::string key_;        // component + '\0' + message of the last written line
    std::string component_;
    LogStamp lastStamp_;
    uint64_t lastMs_ = 0;
    unsigned repeats_ = 0;
};

// "Log only when it changes" for values that are re-announced on every focus change
// (per-app Việt/Anh restore, tray state): true when `value` differs from the last one
// seen for `key` (or the key is new). Bounded: forgets everything past `cap` keys.
// Not thread-safe.
class LogChangeGate {
public:
    explicit LogChangeGate(size_t cap = 64) : cap_(cap) {}
    bool changed(const std::string& key, const std::string& value);

private:
    size_t cap_;
    std::map<std::string, std::string> last_;
};

}  // namespace vtx
