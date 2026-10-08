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
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

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
    // Only the last `maxChars` characters of textBeforeCursor (fewer at the start of the
    // text). Asked before every in-place edit, so frontends override it to copy just that
    // tail instead of the whole paragraph; the default trims textBeforeCursor.
    virtual bool textBeforeCursorTail(size_t maxChars, std::string &out);
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
    // [experimental] no_underline = "forward-keys" (Session::setDeleteWithKeys): erase
    // `nchars` characters before the caret with forwarded BackSpace KEY events (press +
    // release, real keycode) through the IM's own key channel; the Session commits the new
    // text right after, so the host must keep forwarded keys and commits in one order
    // (hostOrdersForwardedKeys). The page sees real BackSpace keydowns — what web editors
    // (Draft.js / Lexical) follow, unlike delete-surrounding. Default: delete-surrounding.
    virtual void forwardBackspaces(int nchars) { deleteBeforeCursor(nchars); }
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
    void setSurroundingEdits(bool on) {
        requestedEdits_ = on;
        surroundingEdits_ = on && !distrusted_;
    }
    // The host's text before the caret contradicted what this Session put there (edited
    // under us, duplicated commits, NFD normalisation…): until the next focusIn() no edit
    // reaches back into the text and Surrounding words are composed as preedit instead,
    // whatever the frontend's policy asks. Never persisted.
    bool surroundingDistrusted() const { return distrusted_; }
    // AppPolicy.deleteWithKeys ([experimental] no_underline = "forward-keys"): in Surrounding,
    // every delete before the caret goes out as forwarded BackSpace keys, then the commit
    // (InputContext::forwardBackspaces). Each such edit is then CONFIRMED from the host's text
    // before the caret on the following keys: the text must become what the Session expects
    // (older states are fine while the host lags); anything else — a lost / doubled BackSpace,
    // a duplicated commit — or no confirmation within kKeyEditAckTimeoutMs distrusts the
    // field (back to preedit until the next focusIn). A mismatch with only plain typing since
    // the last confirmation (the page changed its own text) just restarts the tracking.
    // Checked lazily at the start of each key event (one short read of the text before the
    // caret): no timer, never waits.
    void setDeleteWithKeys(bool on) {
        if (deleteWithKeys_ != on) ackDrop();
        deleteWithKeys_ = on;
    }
    bool deleteWithKeys() const { return deleteWithKeys_; }
    static constexpr int64_t kKeyEditAckTimeoutMs = 1000;
    // An edit made with forwarded BackSpaces is still waiting for the host to show it.
    bool keyEditUnconfirmed() const { return ackPending_; }
    // Tests: a fake monotonic clock in milliseconds (default: steady_clock).
    void setClockForTesting(std::function<int64_t()> nowMs) { nowMs_ = std::move(nowMs); }
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
    // New field/app: forget the previous word's English context (and a distrusted
    // surrounding, see surroundingDistrusted()).
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
    // `base`: the text right before the caret that the edit changes (its last `backspaces`
    // characters go) — what the key-edit confirmation starts from.
    void replace(InputContext &ic, int backspaces, const std::string &insert, const std::string &base);
    // Surrounding edit: delete-surrounding (+ empty commit), or forwarded BackSpaces when
    // deleteWithKeys_ (then the result is tracked until the host confirms it).
    void replaceBeforeCursor(InputContext &ic, int backspaces, const std::string &insert, const std::string &base);
    // Key-edit confirmation (deleteWithKeys_). ackTrail_: what this Session typed before the
    // caret since it last moved (last 48 characters) — where the host must end up.
    // ackStates_: every earlier value of it since the host last showed the trail, oldest
    // first — what the host may still legitimately show (it applies our ordered operations
    // late, never out of order). ackPending_: an edit with forwarded BackSpaces is among them.
    enum class Ack { None, Confirmed, Lagging, Failed };
    Ack checkKeyEdit(InputContext &ic);
    void ackArm(const std::string &base, int backspaces, const std::string &insert);
    void ackPushTrail();
    void ackAppend(const std::string &s);  // text the app typed / we committed
    void ackPop();                         // the app's own ⌫ removed one character
    // The text before the caret is unknown from here on (caret moved, focus, mode change).
    void ackDrop() {
        ackStates_.clear();
        ackTrail_.clear();
        ackPending_ = ackAnchored_ = ackWhole_ = ackSeeded_ = false;
        ackSeed_.clear();
    }
    bool tracking() const;  // deleteWithKeys_ and Surrounding
    void ackTrim();         // keep the trail's last 48 characters
    void failKeyEdit();
    bool deleteWithKeys_ = false;
    bool ackLagging_ = false;  // this key event: the host lags behind our key edits, consistently
    std::vector<std::string> ackStates_;
    std::string ackTrail_;
    bool ackPending_ = false;
    // ackAnchored_: the trail starts with host text seen confirmed (not just our own typing).
    // ackWhole_: …and that was all the text before the caret (start of the field).
    bool ackAnchored_ = false, ackWhole_ = false;
    // What the host showed before the caret when the trail started (last 8 characters;
    // ackSeedWhole_: all of it) — checked at the trail's first confirmation.
    std::string ackSeed_;
    bool ackSeeded_ = false, ackSeedWhole_ = false;
    int64_t ackSinceMs_ = 0;  // when the oldest unconfirmed key edit was sent
    std::function<int64_t()> nowMs_;
    void showPreedit(InputContext &ic);
    void hidePreedit(InputContext &ic);
    bool isWordKey(uint32_t ch) const;
    // ic.selectionAtCaret(), asked at most once per key event.
    bool selectionAtCaret(InputContext &ic);
    // Verify-before-delete (Surrounding in-place edits): may the Session delete `expected`,
    // the text it put right before the caret? Mismatch → distrust() and false.
    bool inPlaceAllowed(InputContext &ic, const std::string &expected);
    void distrust();
    int selectionMemo_ = -1;  // -1 = not asked during this key event
    std::string composed() const;
    std::string raw() const;

    vt_engine *e_;
    DisplayMode mode_ = DisplayMode::Preedit;
    DisplayMode requestedMode_ = DisplayMode::Preedit;  // what the frontend's policy asked
    bool requestedEdits_ = true;
    bool distrusted_ = false;
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
    char lastBoundary_ = 0;            // …that char (printable ASCII)
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
