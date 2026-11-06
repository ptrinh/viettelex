// hotkey.h — Vietnamese/English switch hotkey (settings key `switchHotkey`).
//
// Choices (user-selectable, spec "Quyết định đã chốt" #2):
//   "ctrl-shift"  (default)  modifier-only chord handled inside the TIP: press Ctrl+Shift,
//                            release, with no other key or click in between -> toggle.
//   "win-space"               the system input switcher. The TIP registers no hotkey;
//                            the user flips between VietTelex and an English keyboard
//                            with Win+Space (Windows remembers it per app window if the
//                            user enables that in Settings > Time & language > Typing).
//   "alt-z"                   common habit: Alt+Z toggles inside the TIP (PreserveKey).
//   "off"                     no hotkey; the tray / language-bar button still toggles.
// Unknown / corrupt values fall back to the default rather than disabling switching.
#pragma once
#include <cstdint>
#include <string>

namespace vtx {

enum class SwitchHotkey : uint8_t { CtrlShift, WinSpace, AltZ, Off };

SwitchHotkey parseSwitchHotkey(const std::string& s);
const char* switchHotkeyName(SwitchHotkey h);

// Modifier bitmask for the chord recognizer.
enum : uint8_t { kModCtrl = 1, kModShift = 2, kModAlt = 4, kModWin = 8 };

// Pure state machine, port of macOS ModifierChordRecognizer. Feed every modifier
// key down/up (the current held set after the event) and every non-modifier key
// down / mouse click (disarm). Returns true exactly once when the chord completes.
class ModifierChord {
public:
    explicit ModifierChord(uint8_t target = kModCtrl | kModShift) : target_(target) {}
    void setTarget(uint8_t t) { target_ = t; armed_ = false; }
    // `held` = modifiers held AFTER this event.
    bool note(uint8_t held) {
        if (held == target_) { armed_ = true; return false; }
        bool fire = armed_ && (held & ~target_) == 0;
        armed_ = false;
        return fire;
    }
    void disarm() { armed_ = false; }
    bool armed() const { return armed_; }

private:
    uint8_t target_;
    bool armed_ = false;
};

// Alt+Z held down: the keyboard auto-repeats Z and TSF calls OnPreservedKey for every
// repeat, which used to flip Viet/Anh several times a second. One toggle per press: the
// first call latches, repeats are swallowed, and any other key event (Z or Alt released,
// another key or a fresh Alt pressed) re-arms it. Re-arming on more than Z/Alt key-up
// means a key-up the TIP never saw (focus moved mid-press) cannot block the next press.
class PressLatch {
public:
    explicit PressLatch(uint32_t vk = 'Z') : vk_(vk) {}
    // The preserved key fired. True = act on it (first of this press).
    bool fire() {
        if (latched_) return false;
        latched_ = true;
        return true;
    }
    // Every key event the TIP's key sinks see (test and real, down and up). Only a
    // key-down of the latched key itself (auto-repeat) keeps the latch.
    void noteKey(uint32_t vk, bool down) {
        if (!(down && vk == vk_)) latched_ = false;
    }
    void reset() { latched_ = false; }
    bool latched() const { return latched_; }

private:
    uint32_t vk_;
    bool latched_ = false;
};

}  // namespace vtx
