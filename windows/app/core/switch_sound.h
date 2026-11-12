// The Việt/Anh switch tone (setting switchSound): two short notes, rising for Việt, falling
// for Anh. Synthesised (no asset): a complete 16-bit mono PCM WAV file in memory, the
// same notes as macOS (SwitchSound.swift) and Linux (switch_sound.cpp).
#pragma once

#include <cstdint>
#include <vector>

namespace vtx {

constexpr int kSwitchSoundRate = 22050;
constexpr int kSwitchSoundNoteMs = 55;
constexpr double kSwitchSoundLowHz = 659.25;   // E5
constexpr double kSwitchSoundHighHz = 987.77;  // B5

std::vector<uint8_t> switchSoundWav(bool vietnamese);

// Play it? Only for a switch the user made, never while keys pass through (game).
inline bool playsSwitchSound(bool enabled, bool gameSuspended) { return enabled && !gameSuspended; }

}  // namespace vtx
