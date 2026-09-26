#include "app_policy.h"

#include <algorithm>
#include <cstring>

namespace vtx {

const char* appModeName(AppMode m) {
    switch (m) {
        case AppMode::Composition: return "composition";
        case AppMode::InPlace: return "inPlace";
        case AppMode::HookFallback: return "hookFallback";
        case AppMode::Off: return "off";
    }
    return "composition";
}

bool parseAppMode(const std::string& s, AppMode& out) {
    if (s == "composition") { out = AppMode::Composition; return true; }
    if (s == "inPlace") { out = AppMode::InPlace; return true; }
    if (s == "hookFallback") { out = AppMode::HookFallback; return true; }
    if (s == "off") { out = AppMode::Off; return true; }
    return false;
}

std::string normalizeExeName(const std::string& p) {
    size_t slash = p.find_last_of("\\/");
    std::string name = slash == std::string::npos ? p : p.substr(slash + 1);
    for (char& c : name)
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return name;
}

namespace {
struct Rule {
    const char* exe;
    AppMode mode;
};
// Built-in defaults. Kept deliberately short: everything not listed uses in-place
// (the default since 1.0.9; composition is a per-app choice). Entries
// here are apps where typing Vietnamese locally is wrong by design (the remote
// machine's IME types) — same reasoning as macOS's remote-desktop passthrough.
// Candidates for InPlace/HookFallback are learned from the §5.2 manual matrix on
// real hardware and added here with a comment naming the symptom.
constexpr Rule kRules[] = {
    // Consoles: their TSF document holds only the composition (text typed so far is
    // already in the shell and unreadable), so in-place can never verify or replace —
    // 1.1.0 in cmd.exe typed "thuưr gox" (ư inserted, u never deleted, then all raw).
    // The TIP also detects this at run time (TF_TMAE_CONSOLE / TF_SS_TRANSITORY).
    {"conhost.exe", AppMode::Composition},        // cmd, PowerShell, WSL console window
    {"openconsole.exe", AppMode::Composition},    // Windows Terminal's bundled conhost
    {"windowsterminal.exe", AppMode::Composition},
    {"mintty.exe", AppMode::Composition},         // Git Bash / MSYS2 / Cygwin (IMM only)
    // Other terminals: GPU/own-rendered, IMM or partial TSF, no readable history.
    {"alacritty.exe", AppMode::Composition},
    {"wezterm-gui.exe", AppMode::Composition},
    {"conemu64.exe", AppMode::Composition},
    {"conemu.exe", AppMode::Composition},
    {"putty.exe", AppMode::Composition},
    {"kitty.exe", AppMode::Composition},        // KiTTY (PuTTY fork)
    {"tabby.exe", AppMode::Composition},
    // Remote / virtual machines: the guest's input method types.
    {"vmware.exe", AppMode::Off},
    {"vmware-vmx.exe", AppMode::Off},
    {"vmware-view.exe", AppMode::Off},
    {"virtualboxvm.exe", AppMode::Off},
    {"wfica32.exe", AppMode::Off},              // Citrix Workspace
    {"cdviewer.exe", AppMode::Off},             // Citrix Desktop Viewer
    {"ultraviewer_desktop.exe", AppMode::Off},
    {"moonlight.exe", AppMode::Off},
    {"mstsc.exe", AppMode::Off},          // Remote Desktop Connection
    {"msrdc.exe", AppMode::Off},          // Remote Desktop (Store/AVD client)
    {"vmconnect.exe", AppMode::Off},      // Hyper-V console
    {"anydesk.exe", AppMode::Off},
    {"teamviewer.exe", AppMode::Off},
    {"rustdesk.exe", AppMode::Off},
    {"parsecd.exe", AppMode::Off},
    {"vncviewer.exe", AppMode::Off},
};
}  // namespace

std::string appIdentity(const std::string& processExe, const std::string& rootOwnerExe) {
    if (processExe == "msedgewebview2.exe" && !rootOwnerExe.empty() && rootOwnerExe != processExe)
        return rootOwnerExe;
    return processExe;
}

bool builtInAppMode(const std::string& exe, AppMode& out) {
    for (const Rule& r : kRules) {
        if (exe == r.exe) { out = r.mode; return true; }
    }
    return false;
}

AppMode resolveAppMode(const std::string& exe, const std::map<std::string, AppMode>& overrides) {
    auto it = overrides.find(exe);
    if (it != overrides.end()) return it->second;
    AppMode m;
    if (builtInAppMode(exe, m)) return m;
    // Default since 1.0.9: in-place (verified edits of the text before the caret; falls
    // back to composition per field when the text cannot be read or verified).
    return AppMode::InPlace;
}

HostText classifyContext(const ContextInfo& c) {
    if (!c.hasContext) return HostText::Ignore;
    if (c.keyboardDisabled || c.readOnly || !c.unicodeWindow) return HostText::Literal;
    if (c.console) return HostText::CompositionOnly;
    if (!c.transitory) return HostText::Normal;
    if (c.hasParent) return c.parentTransitory ? HostText::CompositionOnly : HostText::NormalViaParent;
    if (c.cuasEmulated) return HostText::CompositionOnly;
    return HostText::Normal;  // Chromium & co: transitory by convention, fully readable
}

FieldPolicy classifyInputScopes(const int* scopes, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        switch (scopes[i]) {
            case 4:   // IS_EMAIL_USERNAME
            case 5:   // IS_EMAIL_SMTPEMAILADDRESS
            case 28:  // IS_DIGITS
            case 29:  // IS_NUMBER
            case 31:  // IS_PASSWORD
            case 32: case 33: case 34: case 35:  // IS_TELEPHONE_*
            case 39:  // IS_NUMBER_FULLWIDTH
            case 40:  // IS_ALPHANUMERIC_HALFWIDTH (IDs, codes)
            case 63:  // IS_NUMERIC_PASSWORD
            case 64:  // IS_NUMERIC_PIN
            case 65:  // IS_ALPHANUMERIC_PIN
            case 66:  // IS_ALPHANUMERIC_PIN_SET
                return FieldPolicy::Literal;
            // Deliberately NOT literal:
            //  * IS_URL (1): Chrome/Edge tag the address bar IS_URL, and that is where
            //    people type Vietnamese searches. Auto-restore already turns "google",
            //    "github" etc. back into ASCII at the boundary.
            //  * IS_PRIVATE (61): Edge InPrivate / Chrome incognito mean "do not learn";
            //    VietTelex learns nothing, so Vietnamese must keep working there.
            default: break;
        }
    }
    return FieldPolicy::Normal;
}

}  // namespace vtx
