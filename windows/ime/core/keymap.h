// keymap.h — classify a Win32 virtual-key event into what the typing session needs.
//
// Pure (no Win32 headers): VK codes are plain numbers. Telex composes on the US
// QWERTY layout — the TIP registers its profile with the US layout as substitute
// (hklSubstitute = 0x04090409), and translates keys itself with this table so the
// result never depends on whichever layout Windows would otherwise pair with vi-VN
// (the stock "Vietnamese" layout puts ă â ê ô on the number row — typing "1" would
// give "ă"). Same idea as macOS KeyboardLayoutOverride pinning an ASCII layout.
#pragma once
#include <cstdint>

namespace vtx {

struct Modifiers {
    bool shift = false;
    bool ctrl = false;
    bool alt = false;
    bool win = false;
    bool capsLock = false;
};

enum class KeyKind : uint8_t {
    Char,        // printable character (letter, digit, punctuation, space) -> `ch`
    Backspace,
    Boundary,    // Enter, Tab, Esc: ends the word, key goes to the app
    Navigation,  // arrows, Home/End, PgUp/PgDn, Delete, Insert: ends the word
    Chord,       // Ctrl/Alt/Win + key: app shortcut; ends the word
    Modifier,    // Shift/Ctrl/Alt/Win/Caps alone: ignored (fed to hotkey recognizer)
    Other,       // F-keys, media keys, ...: ignored, never touches the word
};

struct KeyInput {
    KeyKind kind = KeyKind::Other;
    char32_t ch = 0;   // Char only
};

// VK constants used by the classifier (values from WinUser.h).
namespace vk {
constexpr uint32_t Back = 0x08, Tab = 0x09, Return = 0x0D, Shift = 0x10, Control = 0x11,
                   Menu = 0x12, Pause = 0x13, Capital = 0x14, Escape = 0x1B, Space = 0x20,
                   Prior = 0x21, Next = 0x22, End = 0x23, Home = 0x24, Left = 0x25, Up = 0x26,
                   Right = 0x27, Down = 0x28, Insert = 0x2D, Delete = 0x2E, LWin = 0x5B,
                   RWin = 0x5C, Apps = 0x5D, Numpad0 = 0x60, Numpad9 = 0x69, Multiply = 0x6A,
                   Add = 0x6B, Subtract = 0x6D, Decimal = 0x6E, Divide = 0x6F, LShift = 0xA0,
                   RShift = 0xA1, LControl = 0xA2, RControl = 0xA3, LMenu = 0xA4, RMenu = 0xA5,
                   Oem1 = 0xBA, OemPlus = 0xBB, OemComma = 0xBC, OemMinus = 0xBD,
                   OemPeriod = 0xBE, Oem2 = 0xBF, Oem3 = 0xC0, Oem4 = 0xDB, Oem5 = 0xDC,
                   Oem6 = 0xDD, Oem7 = 0xDE, Oem102 = 0xE2, ProcessKey = 0xE5, Packet = 0xE7;
}  // namespace vk

// US-QWERTY character for `vkCode` (0 if not printable). Letters honour Shift XOR Caps.
char32_t usQwertyChar(uint32_t vkCode, bool shift, bool capsLock);

KeyInput classifyKey(uint32_t vkCode, const Modifiers& m);

inline bool isModifierVk(uint32_t v) {
    return v == vk::Shift || v == vk::Control || v == vk::Menu || v == vk::LShift ||
           v == vk::RShift || v == vk::LControl || v == vk::RControl || v == vk::LMenu ||
           v == vk::RMenu || v == vk::LWin || v == vk::RWin || v == vk::Capital;
}

}  // namespace vtx
