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
    for (int i = 0; i < lead; ++i) u16(0);
    for (int n = 0; n < 2; ++n) {
        for (int i = 0; i < perNote; ++i) {
            // Wood block: a struck fundamental plus two inharmonic partials that die faster.
            const double t = static_cast<double>(i) / kSwitchSoundRate;
            const double attack = t < 0.002 ? t / 0.002 : 1.0;
            const double w0 = 2 * pi * notes[n] * t;
            const double v = attack * (0.15 * std::exp(-t / 0.022) * std::sin(w0) +
                                       0.035 * std::exp(-t / 0.008) * std::sin(2.7 * w0) +
                                       0.012 * std::exp(-t / 0.004) * std::sin(5.2 * w0));
            u16(static_cast<uint16_t>(static_cast<int16_t>(std::lround(v * 32767))));
        }
        if (n == 0)
            for (int i = 0; i < gap; ++i) u16(0);
    }
    return w;
}

}  // namespace vtx
