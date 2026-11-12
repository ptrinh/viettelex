#include "text_action_logic.h"

#include "app_policy.h"
#include "text_tool_ipc.h"

namespace vtx {

size_t addTonesHotkeyIndex(const std::string& id) {
    for (size_t i = 0; i < kAddTonesHotkeyCount; ++i)
        if (id == kAddTonesHotkeys[i].id) return i;
    return 0;
}

bool addTonesHotkeyKeys(const std::string& id, unsigned& mods, unsigned& vk) {
    const HotkeyChoice& c = kAddTonesHotkeys[addTonesHotkeyIndex(id)];
    mods = c.mods;
    vk = c.vk;
    return c.vk != 0;
}

bool transformText(text::Tool tool, const std::u16string& in, const addtones::LanguageData* data,
                   std::u16string& out) {
    if (in.empty() || in.size() > kTextToolMaxLength) return false;
    const std::u32string s = text::fromUtf16(in);
    std::u32string r;
    if (tool == text::Tool::AddTones) {
        if (!data || !data->ok()) return false;
        r = addtones::restore(text::nfc(s), *data).text;
    } else {
        r = text::apply(tool, s);
    }
    if (r.empty() || r == s) return false;
    out = text::toUtf16(r);
    return true;
}

bool clipboardFallbackAllowed(const std::string& exe, bool console, const std::string& windowClass) {
    if (console || windowClass == "ConsoleWindowClass" || windowClass == "CASCADIA_HOSTING_WINDOW_CLASS") return false;
    AppMode m;
    if (builtInAppMode(exe, m) && (m == AppMode::Direct || m == AppMode::Off)) return false;  // terminals, VMs, RDP
    return true;
}

bool isShellSurfaceClass(const std::string& c) {
    return c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd" || c == "NotifyIconOverflowWindow" ||
           c == "TopLevelWindowForOverflowXamlIsland" || c == "XamlExplorerHostIslandWindow" ||
           c == "Shell_InputSwitchTopLevelWindow" /* Win+Space keyboard list (log 1.3.23: tray flipped to V) */ ||
           c == "Windows.UI.Core.CoreWindow" || c == "Progman" || c == "WorkerW" || c == "#32768" /* menus */;
}

ClipFormatKind clipboardFormatKind(unsigned f) {
    switch (f) {
        case 2:     // CF_BITMAP (synthesised from CF_DIB)
        case 3:     // CF_METAFILEPICT (holds an HMETAFILE inside)
        case 9:     // CF_PALETTE
        case 0x80:  // CF_OWNERDISPLAY
        case 0x82:  // CF_DSPBITMAP
        case 0x83:  // CF_DSPMETAFILEPICT
        case 0x8E:  // CF_DSPENHMETAFILE
            return ClipFormatKind::Skip;
        case 14:  // CF_ENHMETAFILE
            return ClipFormatKind::EnhMetafile;
        default: break;
    }
    if (f == 0) return ClipFormatKind::Skip;
    if (f >= 0x200 && f <= 0x3FF) return ClipFormatKind::Skip;  // CF_PRIVATE*/CF_GDIOBJ*: handles
    return ClipFormatKind::Global;
}

}  // namespace vtx
