// session.h — the frontend-independent typing state machine.
//
// One Session per input context. The Fcitx5 addon and the IBus engine translate their
// native events into KeyEvent + calls below and implement InputContext on top of their
// client API; every typing decision lives here (unit-tested with a mock context).
#pragma once

#include "viettelex/caret_hints.h"
#include "viettelex/keys.h"
#include "viettelex/settings.h"

#include <atomic>
#include <functional>
#include <memory>
#include <optional>
#include <string>

struct vt_engine;

namespace viettelex {

class InputContext {
public:
    virtual ~InputContext() = default;
    // Show `utf8` as the (underlined) composition; empty = hide it. `misspelled`: draw it
    // with the error style (opt-in Settings::underlineMisspelled; always false when off).
    virtual void setPreedit(const std::string &utf8, bool misspelled) = 0;
    // Insert committed text at the caret (preedit already hidden by the Session).
    virtual void commit(const std::string &utf8) = 0;
    // Delete `nchars` Unicode characters immediately before the caret.
    virtual void deleteBeforeCursor(int nchars) = 0;
    // Text before the caret (UTF-8), when the client reports surrounding text.
    virtual bool textBeforeCursor(std::string &out) { (void)out; return false; }
    // The client has a selection (or cannot tell): deleting "before the caret" would eat
    // the selection instead (URL bars select the whole URL / the autocompleted tail).
    virtual bool hasSelection() { return false; }
    // Thorough check, asked ONLY right before reaching back into text already on screen
    // (re-edit, ⌫ reopen, shortcut / auto-restore delete — rare, never per plain key): also
    // catches selections the cheap check misses. GTK3 reports surrounding text without an
    // anchor, so hasSelection() is always false there; frontends add the PRIMARY selection
    // when it sits against the caret (selectionAtCaret in text_tools.h). May be slow-ish
    // (in-process clipboard cache, or a short xclip / wl-paste read); the Session asks at
    // most once per key event.
    virtual bool selectionAtCaret() { return hasSelection(); }
    // Direct mode (terminals): erase `backspaces` characters before the caret with BackSpace
    // key events, then type `utf8` — all through the SAME ordered channel (forwarded key
    // events), so the app sees them in this order. The Session never reads anything back.
    // Frontends mark the keys they forward (KeyEvent::forwarded) if they come back.
    virtual void directReplace(int backspaces, const std::string &utf8) {
        if (backspaces > 0) deleteBeforeCursor(backspaces);
        if (!utf8.empty()) commit(utf8);
    }
    // Caret suggestion (caret_hints.h) next to the caret — Fcitx5 aux text / IBus auxiliary
    // text, drawn by the candidate popup at the caret; never part of the preedit.
    virtual void showHint(const std::string &label) { (void)label; }
    virtual void hideHint() {}
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
    // True when `ev` is the "Thêm dấu cho vùng chọn" hotkey (Settings::addTonesHotkey, off by
    // default). Frontends check it BEFORE processKey and run the text tool themselves; it
    // never matches the toggle hotkey (that one wins).
    bool isAddTonesHotkey(const KeyEvent &ev) const;

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
    bool preeditMisspelled() const { return preeditMisspelled_; }

    // MARK: caret suggestions (caret_hints.h)
    // Where trigger requests go (the frontend's HintService); unset = hints off whatever the
    // settings say (helper not installed). Results come back through deliverHint.
    void setHintSink(std::function<void(const HintRequest &)> sink);
    // Main thread: a helper answer for the request made at generation `gen`. Shown only when
    // nothing was typed since (the generation still matches) and the typed text still ends
    // with what it would replace.
    void deliverHint(uint64_t gen, const CaretSuggestion &s, InputContext &ic);
    const CaretSuggestion *hint() const { return hint_ ? &*hint_ : nullptr; }
    // Text typed since the caret last moved, as sent to the helper (a leading newline /
    // U+FFFC = line start / unknown text before it). For tests.
    std::string typedBefore() const;

private:
    bool handleLetter(uint32_t ch, InputContext &ic);
    bool handleBackspace(InputContext &ic);
    void endWord(InputContext &ic, bool suppressRestore, bool allowShortcuts);
    // Surrounding: delete-surrounding + commit. Direct: forwarded BackSpace + text.
    void replace(InputContext &ic, int backspaces, const std::string &insert);
    void showPreedit(InputContext &ic);
    void hidePreedit(InputContext &ic);
    bool isWordKey(uint32_t ch) const;
    // ic.selectionAtCaret(), asked at most once per key event.
    bool selectionAtCaret(InputContext &ic);
    int selectionMemo_ = -1;  // -1 = not asked during this key event
    std::string composed() const;
    std::string raw() const;

    vt_engine *e_;
    DisplayMode mode_ = DisplayMode::Preedit;
    DisplayMode pendingMode_ = DisplayMode::Preedit;
    bool hasPendingMode_ = false;
    void applyPendingMode();
    bool autoRestore_ = true;
    bool underlineMisspelled_ = false;  // Settings::underlineMisspelled
    bool preeditMisspelled_ = false;    // style of the preedit last sent
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
    uint32_t addTonesSym_ = 0, addTonesMods_ = 0;
    bool addTonesValid_ = false;
    std::shared_ptr<const ShortcutTable> shortcuts_;
    std::string preedit_;

    // caret suggestions
    struct EndedWord {
        bool ended = false;
        std::string text;  // on screen after the boundary decision (restore / shortcut applied)
        std::string raw;   // raw keys ("" for a shortcut expansion)
    };
    enum class TailHead { Start, Newline, Unknown };
    void afterBoundary(uint32_t ch, uint32_t keysym);
    void requestHint(std::vector<std::string> fields, int delayMs = 0);
    bool applyHint(InputContext &ic);
    void declineHint(InputContext &ic);
    void dismissHint(InputContext &ic);
    void seedTail(InputContext &ic);
    void tailAppend(const std::string &s);
    void tailPop(size_t chars);
    void tailReset();
    void updateHintsOn() { hintsOn_ = hintFlags_.any() && static_cast<bool>(hintSink_); }
    HintFlags hintFlags_;
    bool hintsOn_ = false;
    std::string engineBits_;
    std::function<void(const HintRequest &)> hintSink_;
    std::shared_ptr<std::atomic<uint64_t>> keyGen_ = std::make_shared<std::atomic<uint64_t>>(0);
    std::optional<CaretSuggestion> hint_;
    std::string tail_;
    TailHead tailHead_ = TailHead::Unknown;
    bool tailSeeded_ = false;
    EndedWord lastEnded_;
    hints::ToneTracker toneTracker_;
    hints::Rejected rejectedTypos_;
    std::string declinedTones_;
};

}  // namespace viettelex
