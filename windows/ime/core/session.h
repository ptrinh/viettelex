// session.h — the TIP's typing state machine, free of TSF/COM so it can be unit-tested
// on any OS against a fake document (tests/fake_document.h).
//
// One TypingSession per TSF document context (the TIP keeps one per ITfContext it
// sees focused; switching contexts resets). The session drives a TextSink that the
// TIP implements inside a synchronous read/write edit session:
//
//   Composition mode (default, spec §4.2): the current word lives in a TSF
//     composition whose display attribute has no underline; every key re-sets the
//     composition text to vtx_composed(); a boundary commits vtx_commit_text().
//   In-place mode (per app): no composition. Engine REPLACE actions become "delete
//     N chars before the caret, insert text", guarded by an exact comparison of the
//     N chars against what the session believes it put there. Plain appends are left
//     to the app (key not eaten) — cheapest, and the app's own autocomplete sees a
//     real keystroke.
//
// Every edit is verified; on any mismatch the session resets and lets the key through
// literally, so the worst case is "one word without accents", never garbage.
#pragma once
#include <cstdint>
#include <map>
#include <string>

#include "keymap.h"
#include "retro_english.h"

struct vtx_engine;

namespace vtx {

enum class OutputMode : uint8_t { Composition, InPlace };

class TextSink {
public:
    virtual ~TextSink() = default;
    // Up to `max` UTF-16 units immediately before the insertion point, EXCLUDING any
    // active composition (in composition mode: the text before the composition).
    virtual std::u16string textBeforeCaret(int max) = 0;
    // First UTF-16 unit after the insertion point (after the composition), 0 if none.
    virtual char16_t charAfterCaret() = 0;
    // True when the selection is a non-empty range (typing replaces it).
    virtual bool hasSelection() = 0;
    // Delete expect.size() units before the caret iff they equal `expect`, then insert
    // `insert` there; caret ends after the insert. False = nothing changed.
    virtual bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) = 0;
    virtual bool compositionActive() = 0;
    // Start (if none is active) or update the composition so it shows `text`. When
    // starting, the `absorb` units before the caret are pulled into the composition
    // (re-edit / re-open). Caret ends at the composition end. `misspelled`: draw the
    // composition with the red-squiggle attribute instead of the plain one (opt-in
    // "Gạch đỏ âm tiết sai chính tả khi gõ"; always false when that setting is off).
    virtual bool setComposition(const std::u16string& text, int absorb, bool misspelled) = 0;
    // Set the composition text to `finalText` and end it (no-op without composition).
    virtual void endComposition(const std::u16string& finalText) = 0;
    // End the composition leaving whatever text it holds (orphaned composition).
    virtual void endCompositionAsIs() = 0;
    // In-place needs to read the text before the caret. False = this control cannot
    // (no selection / GetText fails): the session types this context in composition.
    virtual bool canReadContext() { return true; }
    // A sink that types blind (the hook: SendInput, nothing can be read back). The session
    // then trusts its own tracking: no stale checks, no verification fallbacks.
    virtual bool blind() { return false; }
};

struct SessionOptions {
    uint32_t engineFlags = 0;
    bool autoRestore = true;
    bool reEditWord = true;
    // "Gạch đỏ âm tiết sai chính tả khi gõ" (default OFF): composition mode only. OFF =
    // no validation call at all.
    bool underlineMisspelled = false;
    // "Tự sửa từ phía trước" switch OFF while VTX_RETRO_ENGLISH is on (contextualEnglish):
    // a verified correction is offered (retroOffer()) instead of applied.
    bool retroOffer = false;
    const std::map<std::u16string, std::u16string>* shortcuts = nullptr;  // not owned
    void (*log)(const char*) = nullptr;  // debug log (never typed text)
};

class TypingSession {
public:
    TypingSession();
    ~TypingSession();
    TypingSession(const TypingSession&) = delete;
    TypingSession& operator=(const TypingSession&) = delete;

    bool ok() const { return engine_ != nullptr; }

    void configure(const SessionOptions& o);
    OutputMode outputMode() const { return mode_; }
    // Caller must flush() first when a word may be in progress.
    void setOutputMode(OutputMode m);

    // ITfKeyEventSink::OnTestKeyDown. May say true for a key handleKey() later lets
    // through; must never say false for a key handleKey() needs.
    bool wantsKey(const KeyInput& k) const;
    // ITfKeyEventSink::OnKeyDown. Returns "eaten". A key that is not eaten reaches the
    // app normally AFTER the edits made here (commit-then-pass-through).
    bool handleKey(const KeyInput& k, TextSink& sink);

    // Commit the word in progress (auto-restore, no shortcut): VN->EN toggle, focus
    // leaving, mode change.
    void flush(TextSink& sink);
    // Caret/selection moved by something other than us, or the app terminated the
    // composition: forget the word, touch nothing.
    void reset();
    // New field / app: also forget the cross-word English context.
    void resetContext();

    bool wordActive() const;
    const std::u16string& shown() const { return shown_; }
    // Word prediction (caret hints): raw keys of the word in progress ("dduw" for "đư"),
    // and whether the engine took the previous word as English (macOS previousWordEnglish).
    std::u16string rawKeys() const;
    bool previousWordEnglish() const;
    // In-place fell back to composition for this context (unreadable / verification
    // failed); cleared by resetContext() (new field or app).
    bool contextFellBack() const { return contextFallback_; }
    // The focused context cannot be read (console / transitory document): compose, and
    // never reach back into text before the caret (re-edit, ⌫ re-open). Set by the TIP
    // after each focus change; cleared by resetContext().
    void setCompositionOnlyContext(bool on);
    bool compositionOnlyContext() const { return compositionOnly_; }
    // In-place is unsafe in this field although its text reads fine: compose (re-edit and
    // ⌫ re-open stay on). Set by the TIP for a Chromium omnibox (app_policy.h
    // fieldPrefersComposition), or by the session itself when the app dropped the deletion
    // half of a replace (verifyScreen). Unlike contextFellBack() it never asks for the
    // hook: Direct's backspace-retype races the omnibox autocomplete (macOS 1.4.14).
    // Cleared by resetContext().
    void setPreferComposition(bool on);
    bool prefersComposition() const { return preferComposition_; }
    // The store mirrors the app ASYNCHRONOUSLY (Chromium's TSFTextStore: Chrome, Edge,
    // Electron, WebView2 — the transitory contexts classifyContext keeps Normal): what it
    // shows can be renderer round trips behind the page, while an in-place edit lands at
    // the page's caret. In such a store a stale view never seeds an edit (the key goes
    // through as typed and the field composes), failures never hand the field to the hook
    // (fallBack -> preferComposition), and re-edit (seeded from the view) is off. Set by
    // the TIP at each word start; cleared by resetContext().
    void setAsyncStore(bool on) { asyncStore_ = on; }
    bool asyncStore() const { return asyncStore_; }
    // The host DROPS a key the TIP claimed (OnTestKeyDown) and then let through: an IMM32
    // app reached through CUAS (WinForms — MISA SME, #134; the TIP sets it for CUAS-emulated
    // contexts), where a claimed key has already become VK_PROCESSKEY. Set by the session
    // itself when in-place finds the field shows none of the letters it let through (they
    // never arrived): those letters are composed instead of lost. In such a field the
    // session eats what it can — a printable boundary goes out WITH the committed word
    // (one result string, "word␣"), ⌫ never re-opens (nothing readable) — and the TIP
    // retypes any other claimed key it did not eat (keymap.h passedKeyRetype). Cleared by
    // resetContext().
    void setHostDropsPassedKeys(bool on);
    bool hostDropsPassedKeys() const { return dropsPassedKeys_; }
    // In-place word in progress, something changed the field (OnEndEdit): keep the word
    // only if the text before the caret still ends with it. Recognises the "deletion
    // dropped" signature (screen = word before the replace + inserted text) and switches
    // this field to composition (setPreferComposition).
    void verifyScreen(TextSink& sink);
    OutputMode wordMode() const { return wordMode_; }
    // The word the LAST handleKey committed at a printable boundary: its raw keys and the
    // text left on screen (auto-restore applied). Empty after any other key, after a
    // shortcut expansion or when nothing was committed (caret hints: typo gate).
    const std::u16string& lastCommitRaw() const { return lastRaw_; }
    const std::u16string& lastCommitText() const { return lastText_; }
    // "Học từ bạn gõ": the word the LAST handleKey composed and committed at a printable
    // boundary OR Enter / Tab / Esc (text on screen, auto-restore applied); empty otherwise
    // (shortcut expansion, chords, navigation, nothing composed).
    const std::u16string& lastCommitWord() const { return lastWord_; }
    // "Tự sửa từ phía trước" (VTX_RETRO_ENGLISH in engineFlags; core/retro_english.h): the
    // number of words the LAST handleKey rewrote (0 = none), and whether ⌫ next reverts it.
    int lastRetroWords() const { return lastRetroWords_; }
    bool retroUndoArmed() const { return retroUndo_.armed(); }
    // ⌫ right after a boundary restore-to-English ("hí" -> "his", "NÁ" -> "NAS") puts the
    // Vietnamese back (engine vtx_take_restore_undo, armed for exactly one key, verified
    // against the text before the caret). Count of such undos this session (diagnostics).
    bool restoreUndoArmed() const { return retroUndo_.armed() && retroUndo_.restore; }
    int restoreUndoCount() const { return restoreUndos_; }
    // Offer mode (SessionOptions::retroOffer): the correction the LAST handleKey verified and
    // did not apply, for the caret hint (empty = none). The TIP shows it once the app has
    // typed the boundary key and applies it on Tab (caret_hints.h Kind::Retro).
    const retro::Offer& retroOffer() const { return retroOffer_; }
    // A key wantsKey() declined (the TIP lets it through without an edit session): with the
    // retro flag on, the engine still has to hear about it — a boundary character keeps or
    // ends the English phrase, anything else ends it. One engine call, no document access.
    void noteKeyPassedBy(const KeyInput& k);

private:
    bool isWordKey(char32_t c) const;
    // Numpad digits are never VNI marks (UniKey): they end the word like punctuation (#124).
    bool isWordKey(const KeyInput& k) const { return !k.numpad && isWordKey(k.ch); }
    bool handleWordKey(char32_t c, TextSink& sink);
    bool handleBackspace(TextSink& sink);
    // kind: Char (printable boundary), Boundary (Enter/Tab/Esc), Navigation/Chord.
    bool commitWord(TextSink& sink, KeyKind kind, char32_t ch = 0);
    bool commitWordInner(TextSink& sink, KeyKind kind, char32_t ch);
    // Retro English: on with the engine flag (Settings: contextualEnglish + the switch).
    bool retroOn() const;
    retro::Field retroField(TextSink& sink) const;
    // After every boundary: take + apply the engine's correction, then report the boundary
    // character (the app inserts it after this key: it is not on screen yet).
    void finishRetro(TextSink& sink, KeyKind kind, char32_t ch);
    bool tryRetroUndo(const retro::Undo& u, TextSink& sink);
    // After every commit: arm the one-key ⌫ undo with the engine's restore-undo record.
    void armRestoreUndo(char16_t boundary);
    bool tryReEdit(char32_t c, TextSink& sink);
    bool tryReopen(TextSink& sink);
    void swapEngine(vtx_engine* e);
    std::u16string composed() const;
    // Red-underline decision for the word in `e` (the live engine or a re-edit clone).
    bool misspelled(const vtx_engine* e) const;

    vtx_engine* engine_ = nullptr;
    OutputMode mode_ = OutputMode::InPlace;       // app default since 1.0.9
    OutputMode wordMode_ = OutputMode::InPlace;   // mode of the word in progress
    bool contextFallback_ = false;
    bool compositionOnly_ = false;
    bool preferComposition_ = false;
    bool asyncStore_ = false;
    bool dropsPassedKeys_ = false;  // see hostDropsPassedKeys()
    // After an in-place replace: what the screen shows if the app inserted our text but
    // dropped the deletion (Chromium omnibox, 2026-10 field report "theêz"). Empty = none.
    std::u16string droppedSig_;
    OutputMode effectiveMode() const {
        return (contextFallback_ || compositionOnly_ || preferComposition_) ? OutputMode::Composition : mode_;
    }
    // True when `before` (text before the caret) is NOT the word on screen; detects the
    // dropped-deletion signature on the way (-> setPreferComposition).
    bool screenStale(const std::u16string& before);
    void noteReplace(const std::u16string& oldShown, const std::u16string& expect, const std::u16string& insert);
    bool mayReadBack() const { return opt_.reEditWord && !compositionOnly_ && !dropsPassedKeys_; }
    // Re-edit seeds a word from the text before the caret; an async store may show it
    // without the keys still in flight (model of the 2026-10 report: "tuwf" -> "tuưf").
    bool mayReEdit() const { return mayReadBack() && !asyncStore_; }
    void fallBack(const char* why);
    SessionOptions opt_;
    std::u16string shown_;     // what the current word looks like on screen
    bool overflow_ = false;    // engine overflowed: rest of the word passes through raw
    bool reopenArmed_ = false; // last event was a printable boundary after a commit
    std::u16string lastRaw_, lastText_;  // see lastCommitRaw()
    std::u16string lastWord_;            // see lastCommitWord()
    retro::Undo retroUndo_;              // armed for exactly one key after a rewrite
    int lastRetroWords_ = 0;
    int restoreUndos_ = 0;               // see restoreUndoCount()
    retro::Offer retroOffer_;            // see retroOffer()
};

// Characters that may belong to a word already on screen (ASCII letters + Latin
// letters with diacritics). Used to find the word before the caret for re-edit.
bool isWordCharForReEdit(char16_t c);
// Telex s f r x j z w (any case) / VNI digits: keys that can only add a diacritic.
bool isDiacriticOnlyKey(char32_t c, bool vni);

}  // namespace vtx
