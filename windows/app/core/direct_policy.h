// direct_policy.h — when Direct mode (hook + SendInput) may type in a field, and when a
// field falls back to composition. Pure; unit-tested. See hook_fallback.cpp and
// direct_verify.cpp for the Win32 side.
#pragma once
#include <cstdint>
#include <map>
#include <string>
#include <utility>

namespace vtx {

// (1) UIPI: SendInput from VietTelex.exe cannot reach a HIGHER-integrity process, and a
// token we cannot read is treated as higher. Integrity = mandatory-label RID
// (0x1000 low, 0x2000 medium, 0x3000 high, 0x4000 system).
bool directUsable(bool targetIntegrityKnown, unsigned long targetIntegrity, unsigned long hookIntegrity);

// (3) SendInput result for one batch.
enum class SendOutcome {
    Ok,             // all events inserted
    NothingSent,    // 0 of n (blocked): pass the user's key through, reset, fall back
    Partial,        // screen now unknown: reset the word, fall back
};
SendOutcome classifySend(unsigned sent, unsigned total);

// (3) Injection guard at the moment of SendInput: the foreground must still be the
// window the word started in, and the input desktop the normal one.
bool injectionAllowed(uintptr_t foregroundNow, uintptr_t foregroundOfWord, bool secureDesktop);

// (2) Echo verification. `before` = text the host shows immediately before the caret
// (console buffer row up to the cursor, UIA text range); `expected` = the word Direct
// typed. Console rows are padded with spaces only AFTER the cursor, so compare exactly.
bool echoMatches(const std::u16string& before, const std::u16string& expected);

// UIA ValuePattern gives the whole field value (caret position unknown): the typed word
// must appear in it somewhere.
bool echoInValue(const std::u16string& value, const std::u16string& expected);

enum class Echo { Match, Mismatch, Unverifiable };

// Per field (window handle + control id): 2 mismatches -> composition for the rest of
// the focus. Unverifiable hosts keep Direct (never fall back blindly). A check whose
// edit was overtaken by newer keys (seq moved on) is not evidence either way.
class EchoPolicy {
public:
    static constexpr int kMismatchesToFallBack = 2;
    // Returns true when THIS result makes the field fall back.
    bool record(uintptr_t window, int control, Echo e);
    bool fellBack(uintptr_t window, int control) const;
    void focusChanged();  // new focus: counters and fallbacks start over
private:
    std::map<std::pair<uintptr_t, int>, int> mismatches_;
    std::map<std::pair<uintptr_t, int>, bool> fallen_;
};

// (1.1.5) Which app a foreground window is, for per-app rules and Việt/Anh memory. A
// console window (ConsoleWindowClass) is drawn by conhost.exe but GetWindowThreadProcessId
// reports its CLIENT (cmd.exe, powershell.exe…): the TIP runs in conhost.exe and keys
// everything by that name, so the hook and the tray must too. Lower-case in and out.
std::string hostIdentity(const std::string& windowClass, const std::string& ownerExe);
inline bool isConsoleWindowClass(const std::string& cls) { return cls == "ConsoleWindowClass"; }

// (1.1.5) Is the foreground app in Vietnamese for the hook / tray?
//   tipProp: kTipLangProp on the foreground root (0 absent, 1 Vietnamese, 2 English) —
//            authoritative when present;
//   console: without the prop a console is NOT trusted (its reported thread is cmd's);
//   else     vi-VN keyboard layout on the window's thread AND the stored per-app state.
bool foregroundLanguage(int tipProp, bool console, bool hklIsVietTelex, bool storedVietnamese);

// (1.1.5) When the hook starts typing in a window. Engaged by a foreground change: at once
// (nothing is mid-word). Engaged mid-focus (the TIP handed a field over): the TIP may be
// composing a word right now — wait for a word boundary so the two never type one word.
class HookArming {
public:
    void engaged(bool freshWindow) { armed_ = freshWindow; }
    void disengaged() { armed_ = false; }
    // Called for every user key before the hook acts; true = the hook may handle it.
    // `boundary`: space, Enter, Tab, Esc, navigation, a chord, or a mouse click.
    bool key(bool boundary) {
        if (armed_) return true;
        if (boundary) armed_ = true;
        return false;
    }
    void click() { armed_ = true; }
    bool armed() const { return armed_; }

private:
    bool armed_ = false;
};

// (1.1.5) The TIP's side of the handover, decided at each word start: stay out (the hook
// types) only when Direct is wanted here AND the hook confirmed it types in this window.
inline bool tipStaysOut(bool directWanted, bool hookAcked, bool fieldNoDirect, bool integrityOk) {
    return directWanted && hookAcked && !fieldNoDirect && integrityOk;
}

// Only verify an edit that is still the latest one when the check runs.
inline bool checkStillRelevant(uint64_t editSeqAtSend, uint64_t editSeqNow) { return editSeqAtSend == editSeqNow; }

}  // namespace vtx
