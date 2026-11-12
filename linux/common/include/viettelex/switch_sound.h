// "Phát tiếng khi đổi Việt/Anh" ([general] switch_sound, default OFF): two short notes,
// rising for Việt, falling for Anh, when the USER switches (toggle hotkey, IM menu) — never
// for a per-app restore on focus. Synthesised (no asset), the same notes as macOS
// (SwitchSound.swift) and Windows (switch_sound.cpp).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace viettelex {

constexpr int kSwitchSoundRate = 22050;
constexpr int kSwitchSoundLeadMs = 30;   // silence first: the audio device may clip the start
constexpr int kSwitchSoundNoteMs = 90;
constexpr int kSwitchSoundGapMs = 20;    // between the two notes, so they are heard as two
constexpr double kSwitchSoundLowHz = 261.63;   // C4
constexpr double kSwitchSoundHighHz = 392.00;  // G4: low and soft, a fifth apart

// A complete 16-bit mono PCM WAV file.
std::vector<uint8_t> switchSoundWav(bool vietnamese);

// Where the WAV is kept: $XDG_RUNTIME_DIR, else $XDG_CACHE_HOME / ~/.cache (never /tmp: a
// fixed name there could be someone else's link). "" = nowhere to put it.
std::string switchSoundPath(bool vietnamese, const char *runtimeDir, const char *cacheHome, const char *home);

// sh command: the first player that works (PipeWire, PulseAudio, ALSA), in the background,
// silent when none is installed.
std::string switchSoundCommand(const std::string &path);

// Writes the file once, starts the player and returns at once. Never throws, never blocks
// on the player.
void playSwitchSound(bool vietnamese);

}  // namespace viettelex
