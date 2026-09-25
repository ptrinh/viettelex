// breaker.h — cascade breaker for the hook fallback (lesson of macOS 1.2.1: a
// synthetic-event feedback loop froze the whole keyboard). If more than `limit`
// synthetic events are emitted inside `windowMs`, the breaker trips and refuses all
// output for `cooldownMs`; the hook then passes every key through untouched.
#pragma once
#include <cstdint>

namespace vtx {

class RateBreaker {
public:
    RateBreaker(uint32_t limit = 120, uint32_t windowMs = 250, uint32_t cooldownMs = 3000)
        : limit_(limit), windowMs_(windowMs), cooldownMs_(cooldownMs) {}

    // Account `count` synthetic events at `nowMs`. False = tripped (do not emit).
    bool allow(uint64_t nowMs, uint32_t count) {
        if (tripped(nowMs)) return false;
        if (nowMs - windowStart_ >= windowMs_) {
            windowStart_ = nowMs;
            inWindow_ = 0;
        }
        inWindow_ += count;
        if (inWindow_ > limit_) {
            trippedUntil_ = nowMs + cooldownMs_;
            ++trips_;
            return false;
        }
        return true;
    }
    bool tripped(uint64_t nowMs) const { return nowMs < trippedUntil_; }
    uint32_t trips() const { return trips_; }

private:
    uint32_t limit_, windowMs_, cooldownMs_;
    uint64_t windowStart_ = 0;
    uint32_t inWindow_ = 0;
    uint64_t trippedUntil_ = 0;
    uint32_t trips_ = 0;
};

}  // namespace vtx
