#include "app_feel.h"

namespace vtx {

namespace {
constexpr unsigned kVi = 0x042A;
constexpr unsigned kEnUs = 0x0409;
}  // namespace

KeyboardPlan planKeyboardAtStart(const KeyboardStatus& s) {
    KeyboardPlan p;
    if (s.portable || s.systemAccount || !s.tipRegistered) return p;
    if (!s.inUserList || s.firstRun) {
        p.add = p.makeDefault = p.select = p.rememberPrevious = true;
        return p;
    }
    if (s.reselectPending) p.select = p.rememberPrevious = true;
    return p;
}

bool isNewUser(bool settingsStored, bool setupDone, bool welcomeShown) {
    return !settingsStored && !setupDone && !welcomeShown;
}

void applyNewUserDefaults(Settings& s) { s.showTrayIcon = true; }

bool opensSettingsAtStart(bool background, bool explicitSettings, bool startHidden) {
    return explicitSettings || (!background && !startHidden);
}

TrayState trayStateFor(bool portable, int tipProp, bool console, unsigned fgLangId, bool storedVietnamese,
                       bool alwaysEnglish) {
    if (portable) {
        if (tipProp != 0 || fgLangId == kVi) return TrayState::Off;
        if (alwaysEnglish) return TrayState::English;
        return storedVietnamese ? TrayState::Vietnamese : TrayState::English;
    }
    if (tipProp == 1) return TrayState::Vietnamese;
    if (tipProp == 2) return TrayState::English;
    if (console) return TrayState::English;
    if (fgLangId != 0 && fgLangId != kVi) return TrayState::Off;
    if (alwaysEnglish) return TrayState::English;
    return storedVietnamese ? TrayState::Vietnamese : TrayState::English;
}

TrayClick trayClickAction(TrayState state, bool portable) {
    if (state != TrayState::Off) return TrayClick::ToggleLanguage;
    return portable ? TrayClick::SwitchToEnglishKeys : TrayClick::SelectVietTelex;
}

ResolveRow welcomeResolveRow(const std::vector<ConflictKind>& found) {
    bool other = false, windows = false;
    for (ConflictKind k : found) {
        if (k == ConflictKind::MicrosoftVietnamese) windows = true;
        else if (isThirdPartyIme(k)) other = true;
    }
    if (other && windows) return ResolveRow::Both;
    if (other) return ResolveRow::OtherInputMethod;
    if (windows) return ResolveRow::WindowsKeyboard;
    return ResolveRow::None;
}

std::vector<std::string> builtInKeyboardRemovals(const std::vector<ViProfile>& found, const std::string& ourClsid) {
    std::vector<std::string> out;
    for (const ViProfile& p : found) {
        if (!isOtherVietnameseProfile(p, ourClsid)) continue;
        const std::string spec = layoutOrTipSpec(p);
        if (spec.empty()) continue;
        bool dup = false;
        for (const std::string& s : out) dup = dup || s == spec;
        if (!dup) out.push_back(spec);
    }
    return out;
}

BuiltInRemovalOutcome afterBuiltInRemoval(bool removalsDone, bool stillListed, bool vietTelexInList,
                                          bool tipRegistered) {
    BuiltInRemovalOutcome o;
    o.readd = tipRegistered && !vietTelexInList;
    o.ok = removalsDone && !stillListed;
    return o;
}

uintptr_t pickExitLayout(const uintptr_t* hkls, size_t count, uintptr_t saved) {
    if (!hkls) count = 0;
    if (rememberableLayout(saved))
        for (size_t i = 0; i < count; ++i)
            if (hkls[i] == saved) return saved;
    for (size_t i = 0; i < count; ++i)
        if ((hkls[i] & 0xFFFF) == kEnUs) return hkls[i];
    for (size_t i = 0; i < count; ++i)
        if (rememberableLayout(hkls[i])) return hkls[i];
    return 0;
}

}  // namespace vtx
