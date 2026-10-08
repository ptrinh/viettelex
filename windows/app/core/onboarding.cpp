#include "onboarding.h"

#include <cstdio>

namespace vtx {

bool parseSetupUserArgs(const std::vector<std::wstring>& args, SetupTrigger& out) {
    bool setup = false, active = false;
    for (const std::wstring& a : args) {
        if (a == L"--setup-user") setup = true;
        else if (a == L"--active-setup") active = true;
    }
    if (!setup) return false;
    out = active ? SetupTrigger::ActiveSetup : SetupTrigger::Installer;
    return true;
}

UserSetupPlan planUserSetup(SetupTrigger trigger, const UserSetupState& s) {
    UserSetupPlan p;
    if (s.systemAccount) return p;
    if (trigger == SetupTrigger::Installer) {
        p.addKeyboard = p.autostart = p.markDone = true;
        p.welcomePending = !s.setupDone && !s.welcomeShown;
        return p;
    }
    if (s.setupDone) return p;  // set up before: respect what the user changed since
    p.addKeyboard = p.autostart = p.markDone = true;
    // AppStart shows the welcome in the same run (decideWelcome sees setupDone == false).
    p.welcomePending = trigger == SetupTrigger::ActiveSetup && !s.welcomeShown;
    return p;
}

WelcomeAction decideWelcome(bool interactive, bool welcomePending, bool welcomeShown, bool setupDoneBeforeThisRun) {
    if (welcomeShown) return WelcomeAction::Nothing;
    if (welcomePending || !setupDoneBeforeThisRun) return interactive ? WelcomeAction::Show : WelcomeAction::Nothing;
    return WelcomeAction::MarkShown;  // upgraded from a version without onboarding
}

namespace {
struct ImeExe {
    const char* exe;
    ConflictKind kind;
};
// Image names of the hook-based Vietnamese IMEs (lower-case). UniKey 4.x ships UniKeyNT.exe
// (older builds UniKey.exe); EVKey and OpenKey ship 32/64-bit builds.
const ImeExe kImeExes[] = {
    {"unikeynt.exe", ConflictKind::UniKey},     {"unikey.exe", ConflictKind::UniKey},
    {"unikey64.exe", ConflictKind::UniKey},     {"evkey64.exe", ConflictKind::EVKey},
    {"evkey.exe", ConflictKind::EVKey},         {"evkey32.exe", ConflictKind::EVKey},
    {"openkey64.exe", ConflictKind::OpenKey},   {"openkey.exe", ConflictKind::OpenKey},
    {"openkey32.exe", ConflictKind::OpenKey},   {"vkey.exe", ConflictKind::VKey},
    {"gotiengviet.exe", ConflictKind::GoTiengViet},
};

std::string upper(std::string s) {
    for (char& c : s)
        if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
    return s;
}
}  // namespace

bool classifyImeProcess(const std::string& exeLower, ConflictKind& out) {
    for (const ImeExe& e : kImeExes)
        if (exeLower == e.exe) {
            out = e.kind;
            return true;
        }
    return false;
}

const char* conflictName(ConflictKind k) {
    switch (k) {
        case ConflictKind::UniKey: return "UniKey";
        case ConflictKind::EVKey: return "EVKey";
        case ConflictKind::OpenKey: return "OpenKey";
        case ConflictKind::VKey: return "VKey";
        case ConflictKind::GoTiengViet: return "GoTiengViet";
        case ConflictKind::MicrosoftVietnamese: return "Microsoft Vietnamese";
    }
    return "";
}

bool isOtherVietnameseProfile(const ViProfile& p, const std::string& ourClsid) {
    if ((p.langId & 0xFFFF) != 0x042A || !p.enabled) return false;
    if (p.isTip) return !p.clsid.empty() && upper(p.clsid) != upper(ourClsid);
    return true;  // a keyboard layout for vi-VN (VietTelex is a TIP, never a layout)
}

std::string layoutOrTipSpec(const ViProfile& p) {
    char buf[128];
    const unsigned lang = p.langId & 0xFFFF;
    if (p.isTip) {
        if (p.clsid.size() != 38 || p.profile.size() != 38) return {};
        std::snprintf(buf, sizeof buf, "%04X:%s%s", lang, upper(p.clsid).c_str(), upper(p.profile).c_str());
        return buf;
    }
    // Plain layouts only (device id == language: 0x042A042A -> KLID 0000042A). Variant
    // layouts (0xF0xx device ids) map to KLIDs through the registry; not expressible here.
    if (((p.hkl >> 16) & 0xFFFF) != (p.hkl & 0xFFFF)) return {};
    std::snprintf(buf, sizeof buf, "%04X:%08X", lang, static_cast<unsigned>(p.hkl & 0xFFFF));
    return buf;
}

}  // namespace vtx
