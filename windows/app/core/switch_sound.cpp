#include "switch_sound.h"

#include <cmath>

namespace vtx {

std::vector<uint8_t> switchSoundWav(bool vietnamese) {
    const int perNote = kSwitchSoundRate * kSwitchSoundNoteMs / 1000;
    const int lead = kSwitchSoundRate * kSwitchSoundLeadMs / 1000;
    const int gap = kSwitchSoundRate * kSwitchSoundGapMs / 1000;
    const double notes[2] = {vietnamese ? kSwitchSoundLowHz : kSwitchSoundHighHz,
                             vietnamese ? kSwitchSoundHighHz : kSwitchSoundLowHz};
    std::vector<uint8_t> w;
    const uint32_t dataBytes = static_cast<uint32_t>(lead + perNote + gap + perNote) * 2;
    w.reserve(44 + dataBytes);
    auto u16 = [&w](uint32_t v) {
        w.push_back(static_cast<uint8_t>(v & 0xFF));
        w.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    };
    auto u32 = [&u16](uint32_t v) {
        u16(v & 0xFFFF);
        u16(v >> 16);
    };
    auto tag = [&w](const char* t) { w.insert(w.end(), t, t + 4); };
    tag("RIFF"); u32(36 + dataBytes); tag("WAVE");
    tag("fmt "); u32(16); u16(1); u16(1); u32(kSwitchSoundRate); u32(kSwitchSoundRate * 2); u16(2); u16(16);
    tag("data"); u32(dataBytes);
    const double pi = 3.14159265358979323846;
    const int fade = perNote / 5;  // no click at either end of a note
    for (int i = 0; i < lead; ++i) u16(0);
    for (int n = 0; n < 2; ++n) {
        for (int i = 0; i < perNote; ++i) {
            double env = 1.0;
            if (i < fade) env = static_cast<double>(i) / fade;
            else if (i >= perNote - fade) env = static_cast<double>(perNote - 1 - i) / fade;
            const double v = std::sin(2 * pi * notes[n] * i / kSwitchSoundRate) * env * 0.28;
            u16(static_cast<uint16_t>(static_cast<int16_t>(std::lround(v * 32767))));
        }
        if (n == 0)
            for (int i = 0; i < gap; ++i) u16(0);
    }
    return w;
}

}  // namespace vtx
