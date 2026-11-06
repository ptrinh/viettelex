// idle_trim.h — when VietTelex.exe hands its idle working set back to Windows (GitHub #153:
// "can it use less RAM?", most visibly the portable build, which opens Settings on start).
//
// The tray app spends nearly all its life idle: a keyboard hook, a hidden window, the tray icon.
// Its start and its windows (Settings with GDI+, the welcome page) touch many pages it will not
// need again until the next window opens — they stay in its working set (Task Manager's
// "Memory") although nothing uses them. Once nothing is on screen and the user has been idle
// for a moment, the app asks Windows to trim its working set (SetProcessWorkingSetSize(-1, -1),
// main.cpp). Nothing is freed or reloaded: pages come back on first touch, from the standby
// list (a soft fault, microseconds). The quiet gap keeps the trim away from active typing, so
// the keyboard hook's pages are not paged out between two keys.
//
// Pure decision (unit-tested on any OS); main.cpp owns the timer and the Win32 calls.
#pragma once
#include <cstdint>

namespace vtx::idletrim {

constexpr unsigned kDelayMs = 5000;   // after a background start / after the last window closed
constexpr unsigned kQuietMs = 2000;   // no keyboard / mouse input for this long (GetLastInputInfo)
constexpr unsigned kRetryMs = 5000;   // Wait: ask again this much later
constexpr int kMaxRetries = 60;       // a user typing non-stop for 5 min: give up until next time

struct State {
    bool windowOpen = false;    // Settings or the welcome window is on screen
    bool textJobBusy = false;   // a text tool (Thêm dấu …) is between hotkey and result
    uint32_t idleMs = 0;        // since the last input event (session-wide)
    int retries = 0;            // Waits so far for this request
};

enum class Decision {
    Trim,  // trim now
    Wait,  // ask again in kRetryMs
    Drop,  // not now: a window is open (its closing asks again) or too many retries
};

inline Decision decide(const State& s) {
    if (s.windowOpen) return Decision::Drop;
    if (s.textJobBusy || s.idleMs < kQuietMs) return s.retries >= kMaxRetries ? Decision::Drop : Decision::Wait;
    return Decision::Trim;
}

}  // namespace vtx::idletrim
