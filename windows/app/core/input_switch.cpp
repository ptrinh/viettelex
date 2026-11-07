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

namespace {
uint8_t modBitForVk(unsigned vk) {
    switch (vk) {
        case 0x10: case 0xA0: case 0xA1: return kModShift;  // VK_SHIFT, VK_LSHIFT, VK_RSHIFT
        case 0x11: case 0xA2: case 0xA3: return kModCtrl;   // VK_CONTROL, VK_LCONTROL, VK_RCONTROL
        case 0x12: case 0xA4: case 0xA5: return kModAlt;    // VK_MENU, VK_LMENU, VK_RMENU
        case 0x5B: case 0x5C: return kModWin;               // VK_LWIN, VK_RWIN
        default: return 0;
    }
}
}  // namespace

bool isChordModifierVk(unsigned vk) { return modBitForVk(vk) != 0; }

uint8_t chordHeldAfter(uint8_t before, unsigned vk, bool down) {
    const uint8_t b = modBitForVk(vk);
    return down ? static_cast<uint8_t>(before | b) : static_cast<uint8_t>(before & ~b);
}

ForeignChord foreignChordAction(SwitchHotkey h, int tipProp, unsigned fgLangId, bool suspended) {
    if (!chordWatcherWanted(h) || suspended) return ForeignChord::Ignore;
    if (tipProp != 0) return ForeignChord::Ignore;          // the TIP is active: it toggles itself
    if (fgLangId == kLangViVN) return ForeignChord::Ignore; // Vietnamese already (VietTelex or a
                                                            // Microsoft Vietnamese keyboard: Windows'
                                                            // own Ctrl+Shift cycles those)
    return ForeignChord::ActivateVietTelex;
}

uintptr_t pickVietnameseHkl(const uintptr_t* hkls, size_t count) {
    for (size_t i = 0; i < count; ++i)
        if ((hkls[i] & 0xFFFF) == kLangViVN) return hkls[i];
    return 0;
}

DefaultInputAdvice defaultInputAdvice(SwitchHotkey h, unsigned defaultLangId) {
    if (h != SwitchHotkey::CtrlShift && h != SwitchHotkey::AltZ) return DefaultInputAdvice::None;
    if (defaultLangId == 0 || defaultLangId == kLangViVN) return DefaultInputAdvice::None;
    return DefaultInputAdvice::MakeVietTelexDefault;
}

std::string defaultLayoutOrTipSpec(unsigned langId, const std::string& clsid, const std::string& profile) {
    static const char kHex[] = "0123456789ABCDEF";
    std::string s = "0x";
    for (int shift = 12; shift >= 0; shift -= 4) s.push_back(kHex[(langId >> shift) & 0xF]);
    return s + ":" + clsid + profile;
}

std::string inputMethodOverrideSpec(unsigned langId, const std::string& clsid, const std::string& profile) {
    return defaultLayoutOrTipSpec(langId, clsid, profile).substr(2);  // without "0x"
}

namespace {
std::string upperAscii(std::string s) {
    for (char& c : s)
        if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
    return s;
}
}  // namespace

OverrideState overrideState(bool present, const std::string& value, unsigned langId, const std::string& clsid,
                            const std::string& profile) {
    std::string v = upperAscii(value);
    while (!v.empty() && (v.back() == ';' || v.back() == ' ')) v.pop_back();
    while (!v.empty() && v.front() == ' ') v.erase(0, 1);
    if (!present || v.empty()) return OverrideState::None;
    if (v.size() > 2 && v[0] == '0' && v[1] == 'X') v.erase(0, 2);
    return v == upperAscii(inputMethodOverrideSpec(langId, clsid, profile)) ? OverrideState::VietTelex
                                                                            : OverrideState::Other;
}

std::string setOverrideArgs(const std::string& spec) {
    return "-NoProfile -NonInteractive -WindowStyle Hidden -Command \"Set-WinDefaultInputMethodOverride -InputTip '" +
           spec + "'\"";
}

DefaultInputAdvice defaultInputAdvice(SwitchHotkey h, unsigned defaultLangId, OverrideState o) {
    if (h != SwitchHotkey::CtrlShift && h != SwitchHotkey::AltZ) return DefaultInputAdvice::None;
    switch (o) {
        case OverrideState::VietTelex: return DefaultInputAdvice::None;
        case OverrideState::Other: return DefaultInputAdvice::MakeVietTelexDefault;
        case OverrideState::None: break;
    }
    return defaultInputAdvice(h, defaultLangId);
}

WinToggle parseWinToggle(bool present, const std::string& value, WinToggle dflt) {
    if (!present || value.size() != 1 || value[0] < '1' || value[0] > '4') return dflt;
    return static_cast<WinToggle>(value[0] - '0');
}

const char* winToggleValue(WinToggle t) {
    switch (t) {
        case WinToggle::AltShift: return "1";
        case WinToggle::CtrlShift: return "2";
        case WinToggle::None: return "3";
        case WinToggle::Grave: return "4";
    }
    return "3";
}

WinToggles readWinToggles(bool hasLanguage, const std::string& language, bool hasLegacy, const std::string& legacy,
                          bool hasLayout, const std::string& layout) {
    WinToggles w;
    w.language = parseWinToggle(hasLanguage, language, parseWinToggle(hasLegacy, legacy, WinToggle::AltShift));
    w.layout = parseWinToggle(hasLayout, layout, WinToggle::CtrlShift);
    return w;
}

WinHotkeyClash winHotkeyClash(SwitchHotkey ours, const WinToggles& w, bool otherVietnameseKeyboard) {
    if (ours != SwitchHotkey::CtrlShift) return WinHotkeyClash::None;
    if (w.language == WinToggle::CtrlShift) return WinHotkeyClash::LanguageSwitch;
    if (w.layout == WinToggle::CtrlShift && otherVietnameseKeyboard) return WinHotkeyClash::LayoutSwitch;
    return WinHotkeyClash::None;
}

WinToggleFix winToggleFix(const WinToggles& w) {
    WinToggleFix f;
    f.language = w.language == WinToggle::CtrlShift ? WinToggle::AltShift : w.language;
    f.changeLanguage = f.language != w.language;
    f.changeLayout = w.layout == WinToggle::CtrlShift || (w.layout == f.language && w.layout != WinToggle::None);
    f.layout = f.changeLayout ? WinToggle::None : w.layout;
    return f;
}

}  // namespace vtx
