// hook_watchdog.h — detect that Windows silently removed our WH_KEYBOARD_LL hook.
//
// Windows unhooks a low-level hook whose thread does not answer within
// LowLevelHooksTimeout (default 200 ms; Keyman LowLevelHookWatchDog.cpp documents the
// same). The hook then just stops being called — typing in hook/direct mode dies
// silently. Second, independent key signal: raw input (RIDEV_INPUTSINK) on the hook
// thread's window. If raw input keeps seeing keys but the LL hook has not for longer
// than `thresholdMs`, reinstall it. Pure (clock injected) so it is unit-tested.
#pragma once
#include <cstdint>

namespace vtx {

class HookWatchdog {
public:
    explicit HookWatchdog(uint64_t thresholdMs = 1000) : threshold_(thresholdMs) {}
    void hookInstalled(uint64_t now) { lastLowLevel_ = now; }
    void lowLevelKey(uint64_t now) { lastLowLevel_ = now; }
    // A key seen by raw input. True = the hook is dead: reinstall now (then call
    // hookInstalled).
    bool rawKey(uint64_t now) {
        if (!active_) return false;
        return now > lastLowLevel_ && now - lastLowLevel_ >= threshold_;
    }
    void setActive(bool on, uint64_t now) {
        active_ = on;
        lastLowLevel_ = now;
    }
    bool active() const { return active_; }

private:
    uint64_t threshold_;
    uint64_t lastLowLevel_ = 0;
    bool active_ = false;
};

}  // namespace vtx
