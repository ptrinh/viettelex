#include "game_logic.h"

#include <algorithm>

namespace vtx {

bool fullscreenSuspends(bool settingOn, const ForegroundProbe& p) {
    if (!settingOn || p.shellOrDesktop || p.ownProcess) return false;
    if (p.quns == static_cast<int>(Quns::D3DFullScreen)) return true;
    if (p.quns == static_cast<int>(Quns::PresentationMode)) return p.coversMonitor && !p.hasCaption;
    return false;  // Busy (borderless fullscreen browsers / video) and everything else: keep typing
}

bool coversMonitor(const Rect& w, const Rect& m) {
    if (m.right <= m.left || m.bottom <= m.top) return false;
    return w.left <= m.left && w.top <= m.top && w.right >= m.right && w.bottom >= m.bottom;
}

FullscreenTracker::Step FullscreenTracker::update(uintptr_t foreground, bool suspendHere) {
    Step s;
    const uintptr_t want = (suspendHere && foreground) ? foreground : 0;
    if (want == suspended_) return s;
    s.resume = suspended_;
    s.suspend = want;
    suspended_ = want;
    return s;
}

FullscreenTracker::Step FullscreenTracker::clear() {
    Step s;
    s.resume = suspended_;
    suspended_ = 0;
    return s;
}

size_t gameModeHotkeyIndex(const std::string& id) {
    for (size_t i = 0; i < kGameModeHotkeyCount; ++i)
        if (id == kGameModeHotkeys[i].id) return i;
    return 0;
}

bool gameModeHotkeyKeys(const std::string& id, unsigned& mods, unsigned& vk) {
    const GameHotkeyChoice& c = kGameModeHotkeys[gameModeHotkeyIndex(id)];
    mods = c.mods;
    vk = c.vk;
    return c.vk != 0;
}

SwitchIndicator parseSwitchIndicator(const std::string& s) {
    if (s == "on") return SwitchIndicator::On;
    if (s == "off") return SwitchIndicator::Off;
    return SwitchIndicator::Auto;
}

const char* switchIndicatorName(SwitchIndicator v) {
    switch (v) {
        case SwitchIndicator::On: return "on";
        case SwitchIndicator::Off: return "off";
        default: return "auto";
    }
}

bool showSwitchToast(SwitchIndicator setting, bool trayIconShown, bool suspended, int quns) {
    if (suspended) return false;
    if (quns == static_cast<int>(Quns::D3DFullScreen) || quns == static_cast<int>(Quns::PresentationMode)) return false;
    switch (setting) {
        case SwitchIndicator::On: return true;
        case SwitchIndicator::Off: return false;
        default: return !trayIconShown;
    }
}

Point toastPosition(bool caretKnown, const Rect& caret, const Rect& wa, long width, long height, long margin) {
    Point p;
    if (caretKnown) {
        p.x = caret.left;
        p.y = caret.bottom + margin;
        if (p.y + height > wa.bottom) p.y = caret.top - margin - height;  // no room below: above
    } else {
        p.x = wa.right - margin - width;
        p.y = wa.bottom - margin - height;
    }
    p.x = std::max(wa.left + margin, std::min(p.x, wa.right - margin - width));
    p.y = std::max(wa.top + margin, std::min(p.y, wa.bottom - margin - height));
    return p;
}

}  // namespace vtx
