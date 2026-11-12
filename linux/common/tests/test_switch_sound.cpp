// "Phát tiếng khi đổi Việt/Anh" (switch_sound.h): the WAV, where it is kept, the player command.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "viettelex/switch_sound.h"

static int failures = 0;
#define CHECK(c)                                                         \
    do {                                                                 \
        if (!(c)) {                                                      \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); \
            ++failures;                                                  \
        }                                                                \
    } while (0)

static uint32_t u32(const std::vector<uint8_t> &w, size_t at) {
    return static_cast<uint32_t>(w[at]) | (w[at + 1] << 8) | (w[at + 2] << 16) | (static_cast<uint32_t>(w[at + 3]) << 24);
}

static int crossings(const std::vector<uint8_t> &w, size_t from, size_t to) {
    int n = 0;
    int16_t prev = 0;
    for (size_t i = from; i < to; ++i) {
        const int16_t v = static_cast<int16_t>(w[44 + i * 2] | (w[45 + i * 2] << 8));
        CHECK(v < 32767 / 3 && v > -32767 / 3);  // quiet
        if ((prev < 0) != (v < 0)) ++n;
        prev = v;
    }
    return n;
}

int main() {
    using namespace viettelex;
    const std::vector<uint8_t> vi = switchSoundWav(true), en = switchSoundWav(false);
    CHECK(vi.size() == en.size() && vi != en);
    CHECK(std::string(vi.begin(), vi.begin() + 4) == "RIFF");
    CHECK(std::string(vi.begin() + 8, vi.begin() + 12) == "WAVE");
    CHECK(u32(vi, 4) == vi.size() - 8);
    CHECK(u32(vi, 40) == vi.size() - 44);
    CHECK(u32(vi, 24) == static_cast<uint32_t>(kSwitchSoundRate));
    const size_t frames = (vi.size() - 44) / 2;
    CHECK(frames * 1000 / kSwitchSoundRate <= 300);  // short
    CHECK(crossings(vi, 0, frames / 2) < crossings(vi, frames / 2, frames));  // Việt rises
    CHECK(crossings(en, 0, frames / 2) > crossings(en, frames / 2, frames));  // Anh falls

    // Kept in the runtime dir, else the cache; never a fixed name in /tmp.
    CHECK(switchSoundPath(true, "/run/user/1000", "/c", "/home/u") == "/run/user/1000/viettelex-switch-vi.wav");
    CHECK(switchSoundPath(false, nullptr, "/c", "/home/u") == "/c/viettelex/viettelex-switch-en.wav");
    CHECK(switchSoundPath(false, "", nullptr, "/home/u") == "/home/u/.cache/viettelex/viettelex-switch-en.wav");
    CHECK(switchSoundPath(true, nullptr, nullptr, nullptr).empty());
    CHECK(switchSoundPath(true, "relative", "also", "no").empty());

    // PipeWire, then PulseAudio, then ALSA; background; a quote in the path cannot break out.
    const std::string c = switchSoundCommand("/run/user/1000/a.wav");
    CHECK(c == "(pw-play '/run/user/1000/a.wav' || paplay '/run/user/1000/a.wav' || aplay -q '/run/user/1000/a.wav') "
               ">/dev/null 2>&1 &");
    CHECK(switchSoundCommand("/h/it's/a.wav").find("'/h/it'\\''s/a.wav'") != std::string::npos);

    if (failures) return 1;
    std::puts("switch_sound: ok");
    return 0;
}
