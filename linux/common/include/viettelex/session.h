// session.h — the frontend-independent typing state machine.
//
// One Session per input context. The Fcitx5 addon and the IBus engine translate their
// native events into KeyEvent + calls below and implement InputContext on top of their
// client API; every typing decision lives here (unit-tested with a mock context).
#pragma once

#include "viettelex/keys.h"
#include "viettelex/settings.h"

#include <functional>
#include <string>

struct vt_engine;

namespace viettelex {

class InputContext {
public:
    virtual ~InputContext() = default;
    // Show `utf8` as the (underlined) composition; empty = hide it.
    virtual void setPreedit(const std::string &utf8) = 0;
    // Insert committed text at the caret (preedit already hidden by the Session).
    virtual void commit(const std::string &utf8) = 0;
    // Delete `nchars` Unicode characters immediately before the caret.
    virtual void deleteBeforeCursor(int nchars) = 0;
    // Text before the caret (UTF-8), when the client reports surrounding text.
    virtual bool textBeforeCursor(std::string &out) { (void)out; return false; }
    // The client has a selection (or cannot tell): deleting "before the caret" would eat
    // the selection instead (URL bars select the whole URL / the autocompleted tail).
    virtual bool hasSelection() { return false; }
};

class Session {
public:
    Session();
    ~Session();
    Session(const Session &) = delete;
    Session &operator=(const Session &) = delete;

    // Push a settings snapshot (engine flags, shortcuts, hotkey). Safe mid-word.
    void applySettings(const Settings &s);
    // Mid-word the change is deferred to the next word: switching then would split the word
    // being composed (e.g. the first surrounding-text update arrives after its first key).
    void setDisplayMode(DisplayMode m, InputContext &ic);
    DisplayMode displayMode() const { return mode_; }
    // Password field / [app_modes] off: keys pass through literally.
    void setPassthrough(bool on, InputContext &ic);
    // AppPolicy.allowSurroundingEdits: may re-edit / ⌫ reopen read back and delete text
    // before the caret? False for terminals, generic app ids and unproven surrounding.
    void setSurroundingEdits(bool on) { surroundingEdits_ = on; }
    void setVietnamese(bool on, InputContext &ic);
    bool vietnamese() const { return vietnamese_; }
    // Called with the new state whenever the toggle hotkey flips it.
    std::function<void(bool)> onToggle;

    // True when `ev` is the Vi/En toggle hotkey (press). Frontends whose framework grabs
    // the same chord first (Fcitx5 trigger key) check this early and route it here.
    bool isToggleHotkey(const KeyEvent &ev) const;

    // Returns true when the key was consumed (the app must not see it).
    bool processKey(const KeyEvent &ev, InputContext &ic);

    // Focus left / cursor moved / app reset: finish the word as displayed.
    // commitPreedit=false when the framework commits the preedit itself (IBus
    // PREEDIT_COMMIT mode); the state is dropped either way.
    void finish(InputContext &ic, bool commitPreedit = true);
    // New field/app: forget the previous word's English context.
    void focusIn();

    bool composing() const;
    std::string preedit() const { return preedit_; }

private:
    bool handleLetter(uint32_t ch, InputContext &ic);
    bool handleBackspace(InputContext &ic);
    void endWord(InputContext &ic, bool suppressRestore, bool allowShortcuts);
    void showPreedit(InputContext &ic);
    void hidePreedit(InputContext &ic);
    bool isWordKey(uint32_t ch) const;
    std::string composed() const;
    std::string raw() const;

    vt_engine *e_;
    DisplayMode mode_ = DisplayMode::Preedit;
    DisplayMode pendingMode_ = DisplayMode::Preedit;
    bool hasPendingMode_ = false;
    void applyPendingMode();
    bool autoRestore_ = true;
    bool shortcutsEnabled_ = true;
    bool reEdit_ = true;
    bool vni_ = false;
    bool bracketVowels_ = false;
    bool passthrough_ = false;
    bool surroundingEdits_ = true;
    bool vietnamese_ = true;
    bool gluedToDigit_ = false;
    bool caretMoved_ = true;           // caret may sit after an existing word (re-edit)
    bool lastWasBoundaryChar_ = false; // previous key typed one boundary char (reopen)
    uint32_t hotkeySym_ = 0, hotkeyMods_ = 0;
    bool hotkeyValid_ = false;
    std::shared_ptr<const ShortcutTable> shortcuts_;
    std::string preedit_;
};

}  // namespace viettelex
