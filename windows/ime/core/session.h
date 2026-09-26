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
    // (re-edit / re-open). Caret ends at the composition end.
    virtual bool setComposition(const std::u16string& text, int absorb) = 0;
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
    // In-place fell back to composition for this context (unreadable / verification
    // failed); cleared by resetContext() (new field or app).
    bool contextFellBack() const { return contextFallback_; }
    // The focused context cannot be read (console / transitory document): compose, and
    // never reach back into text before the caret (re-edit, ⌫ re-open). Set by the TIP
    // after each focus change; cleared by resetContext().
    void setCompositionOnlyContext(bool on);
    bool compositionOnlyContext() const { return compositionOnly_; }
    OutputMode wordMode() const { return wordMode_; }

private:
    bool isWordKey(char32_t c) const;
    bool handleWordKey(char32_t c, TextSink& sink);
    bool handleBackspace(TextSink& sink);
    // kind: Char (printable boundary), Boundary (Enter/Tab/Esc), Navigation/Chord.
    bool commitWord(TextSink& sink, KeyKind kind);
    bool tryReEdit(char32_t c, TextSink& sink);
    bool tryReopen(TextSink& sink);
    void swapEngine(vtx_engine* e);
    std::u16string composed() const;

    vtx_engine* engine_ = nullptr;
    OutputMode mode_ = OutputMode::InPlace;       // app default since 1.0.9
    OutputMode wordMode_ = OutputMode::InPlace;   // mode of the word in progress
    bool contextFallback_ = false;
    bool compositionOnly_ = false;
    OutputMode effectiveMode() const {
        return (contextFallback_ || compositionOnly_) ? OutputMode::Composition : mode_;
    }
    bool mayReadBack() const { return opt_.reEditWord && !compositionOnly_; }
    void fallBack(const char* why);
    SessionOptions opt_;
    std::u16string shown_;     // what the current word looks like on screen
    bool overflow_ = false;    // engine overflowed: rest of the word passes through raw
    bool reopenArmed_ = false; // last event was a printable boundary after a commit
};

// Characters that may belong to a word already on screen (ASCII letters + Latin
// letters with diacritics). Used to find the word before the caret for re-edit.
bool isWordCharForReEdit(char16_t c);
// Telex s f r x j z w (any case) / VNI digits: keys that can only add a diacritic.
bool isDiacriticOnlyKey(char32_t c, bool vni);

}  // namespace vtx
