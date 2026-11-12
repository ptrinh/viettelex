// The Việt/Anh switch tone (setting switchSound): two short notes, rising for Việt, falling
// for Anh. Synthesised (no asset): a complete 16-bit mono PCM WAV file in memory, the
// same notes as macOS (SwitchSound.swift) and Linux (switch_sound.cpp).
#pragma once

#include <cstdint>
#include <vector>

namespace vtx {

constexpr int kSwitchSoundRate = 22050;
constexpr int kSwitchSoundLeadMs = 30;   // silence first: the audio device may clip the start
constexpr int kSwitchSoundNoteMs = 90;
constexpr int kSwitchSoundGapMs = 20;    // between the two notes, so they are heard as two
constexpr double kSwitchSoundLowHz = 261.63;   // C4
constexpr double kSwitchSoundHighHz = 392.00;  // G4: low and soft, a fifth apart

std::vector<uint8_t> switchSoundWav(bool vietnamese);

// Play it? Only for a switch the user made, never while keys pass through (game).
inline bool playsSwitchSound(bool enabled, bool gameSuspended) { return enabled && !gameSuspended; }

}  // namespace vtx
