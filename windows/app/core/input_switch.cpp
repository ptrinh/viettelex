#include "input_switch.h"

namespace vtx {

HotkeyNote hotkeyNote(SwitchHotkey h, PerAppInput windows) {
    if (h == SwitchHotkey::CtrlShift || h == SwitchHotkey::AltZ) return HotkeyNote::TipRemembers;
    switch (windows) {
        case PerAppInput::On: return HotkeyNote::WindowsPerApp;
        case PerAppInput::Off: return HotkeyNote::WindowsGlobal;
        default: return HotkeyNote::WindowsUnknown;
    }
}

}  // namespace vtx
