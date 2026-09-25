#include "hotkey.h"

namespace vtx {

SwitchHotkey parseSwitchHotkey(const std::string& s) {
    if (s == "ctrl-shift") return SwitchHotkey::CtrlShift;
    if (s == "win-space") return SwitchHotkey::WinSpace;
    if (s == "alt-z") return SwitchHotkey::AltZ;
    if (s == "off") return SwitchHotkey::Off;
    return SwitchHotkey::CtrlShift;
}

const char* switchHotkeyName(SwitchHotkey h) {
    switch (h) {
        case SwitchHotkey::CtrlShift: return "ctrl-shift";
        case SwitchHotkey::WinSpace: return "win-space";
        case SwitchHotkey::AltZ: return "alt-z";
        case SwitchHotkey::Off: return "off";
    }
    return "ctrl-shift";
}

}  // namespace vtx
