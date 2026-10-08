// onboarding.h — first run: per-user activation, the welcome window, other Vietnamese
// input methods. Portable decisions (unit-tested on any OS); the Win32 side is
// app/src/main.cpp (--setup-user), app/src/welcome.cpp and app/src/conflicts.cpp.
//
// Per-user activation (the README "Store installs" gap). The MSI is per-machine; adding
// the keyboard to a user's language list (InstallLayoutOrTip) and the autostart value are
// per-USER. The MSI's SetupUser action does that for the installing user — but a
// Microsoft Store / Intune / `msiexec /qn` install runs as SYSTEM, so nobody's list got the
// keyboard until they opened VietTelex once.
//
// Fix: Active Setup. The MSI writes
//   HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{kActiveSetupGuid}
//     (Default) = "VietTelex", StubPath = "<exe>" --setup-user --active-setup,
//     Version = kActiveSetupVersion, IsInstalled = 1
// and at every user's next logon Windows (explorer, before the desktop) runs StubPath once
// for that user if HKCU\…\Installed Components\{GUID}\Version is missing or lower.
// Why Active Setup and not the alternatives:
//   * HKLM RunOnce runs for the FIRST user who logs on only, and needs admin to delete.
//   * HKLM Run would run at every logon for every user forever (and would need its own
//     "done" bookkeeping) — Active Setup is exactly "once per user, per version".
//   * A scheduled task "at logon of any user" needs the Task Scheduler COM API from the
//     MSI (wixl cannot author it) and leaves a task behind.
//   * Writing other users' HKCU (loading their hives) from SYSTEM is fragile and misses
//     users created later.
// Limits: it runs at the next LOGON (a user already signed in when the Store installs
// gets the keyboard when they open VietTelex, or at next sign-in), and it runs before the
// desktop exists — so the stub never shows UI: it only marks the welcome window pending,
// and the autostart (HKCU Run, --background) shows it once the desktop is up.
// The version is FIXED (not the release): an upgrade must not re-add a keyboard the user
// removed on purpose. Bump it only if a future release needs every user re-set-up.
#pragma once
#include <string>
#include <vector>

namespace vtx {

// Keep in sync with installer/msi/viettelex.wxs.in (app_tests checks the template).
constexpr const char* kActiveSetupGuid = "{D1246D27-55D1-45DC-96F6-60BF26027142}";
constexpr const char* kActiveSetupVersion = "1,0";
constexpr const char* kActiveSetupArgs = "--setup-user --active-setup";

// Who asked for the per-user setup.
enum class SetupTrigger {
    Installer,    // the MSI's SetupUser action, as the installing user (or SYSTEM)
    ActiveSetup,  // Windows, at a user's logon (StubPath)
    AppStart,     // VietTelex.exe started normally and found this user not set up
};
// `--setup-user` [`--active-setup`] -> the trigger (false: not a setup-user command line).
bool parseSetupUserArgs(const std::vector<std::wstring>& args, SetupTrigger& out);

struct UserSetupState {
    bool systemAccount = false;  // running as LocalSystem: its HKCU is not a person's
    bool setupDone = false;      // HKCU\Software\VietTelex userSetupDone
    bool welcomeShown = false;   // HKCU\Software\VietTelex welcomeShown
};
struct UserSetupPlan {
    bool addKeyboard = false;    // InstallLayoutOrTip (idempotent in Windows itself)
    bool autostart = false;      // HKCU Run --background
    bool markDone = false;       // userSetupDone = 1
    bool welcomePending = false; // welcomePending = 1: the next interactive start shows it
};
// Idempotent: running it twice changes nothing the first run did not.
//   SYSTEM                -> nothing (Active Setup reaches the real users).
//   Installer             -> always ensure keyboard + autostart (an explicit install by
//                            this user); the welcome only the first time.
//   ActiveSetup/AppStart  -> only when this user was never set up: a later run must not
//                            re-add a keyboard the user removed from the language list.
UserSetupPlan planUserSetup(SetupTrigger trigger, const UserSetupState& s);

// Show the welcome window now? `interactive` = a start where a window is fine (not the
// one-shot setup/cleanup commands). Users upgrading from a version without onboarding
// (set up before, nothing pending) are never shown it: MarkShown records that silently.
enum class WelcomeAction { Show, MarkShown, Nothing };
WelcomeAction decideWelcome(bool interactive, bool welcomePending, bool welcomeShown, bool setupDoneBeforeThisRun);

// ---- Other Vietnamese input methods --------------------------------------------------
// Two Vietnamese input methods at once double every tone (both eat the key). Detected,
// shown as a warning with actions; NEVER killed or uninstalled by VietTelex.
enum class ConflictKind {
    UniKey,
    EVKey,
    OpenKey,
    VKey,
    GoTiengViet,
    MicrosoftVietnamese,  // Windows' Vietnamese Telex / Number-key keyboard or the
                          // legacy "Vietnamese" layout, enabled in this user's list
};
// Running process image (lower-case file name) -> a known Vietnamese IME, or false.
bool classifyImeProcess(const std::string& exeLower, ConflictKind& out);
const char* conflictName(ConflictKind k);  // "UniKey", "EVKey", … (product names, not translated)
// The others are hook-based: quitting from their tray icon is enough (they stay installed).
inline bool isThirdPartyIme(ConflictKind k) { return k != ConflictKind::MicrosoftVietnamese; }

// One input profile of the user's vi-VN list (ITfInputProcessorProfileMgr::EnumProfiles).
struct ViProfile {
    unsigned langId = 0;
    bool isTip = false;          // TF_PROFILETYPE_INPUTPROCESSOR (else a keyboard layout)
    bool enabled = false;        // TF_IPP_FLAG_ENABLED
    std::string clsid;           // "{…}" upper-case, TIPs only
    std::string profile;         // "{…}" upper-case, TIPs only
    unsigned long hkl = 0;       // keyboard layouts only
};
// A Vietnamese profile that is not VietTelex and is enabled for this user.
bool isOtherVietnameseProfile(const ViProfile& p, const std::string& ourClsid);
// InstallLayoutOrTip spec that removes it from the user's list (ILOT_UNINSTALL):
// TIP "042A:{CLSID}{PROFILE}", layout "042A:<8-hex KLID>". Empty = cannot express it.
std::string layoutOrTipSpec(const ViProfile& p);

// ms-settings page to remove keyboards by hand (fallback when the API call fails).
constexpr const wchar_t* kLanguageSettingsUri = L"ms-settings:regionlanguage";

}  // namespace vtx
