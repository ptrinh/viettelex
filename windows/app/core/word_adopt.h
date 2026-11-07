// word_adopt.h — the hook takes over a word in progress (1.3.16, WPF list).
//
// A TIP handover arrives a few milliseconds after the first letter of a word: in WPF's
// default store (One Commander's type-to-filter file list) the TIP lets every key reach the
// app as typed and records them (ime/core/typed_word.h, kTypedWordProp on the focus root).
// The hook normally waits for a word boundary when engaged mid-focus (direct_policy.h
// HookArming) — the TIP might be composing — but here nothing is composed and the filter is
// one word: the hook would never accent it. So, only for such a handover (AppCommand::
// DirectMode with kDirectAdoptTyped), at the FIRST key it handles the hook:
//   * reads the TIP's record of the word so far (the letters on screen, as typed);
//   * feeds those keys to its engine with no output: the session now believes the screen
//     shows its own rendering of them ("doj" -> "dọ");
//   * owes the screen that difference: the next key's batch starts with the backspaces +
//     text that turn the raw letters into the session's text, then the key's own edit.
//     A ⌫ first deletes the last raw letter (the app does it) and the word is re-adopted
//     from the rest.
// An unknown record (too long, a key the TIP could not record) keeps the old rule: wait for
// a boundary. A click, a foreground change, a dropped word or a non-typing key (arrows,
// chords) ends the adoption. Pure; hook_fallback.cpp calls it, tests replay it.
#pragma once
#include <cstdint>
#include <string>

#include "keymap.h"

namespace vtx {
class TypingSession;
}

namespace vtx::app {

class WordAdoption {
public:
    // kCmdForeground engaged the hook: `adopt` = mid-focus TIP handover with kDirectAdoptTyped.
    void engaged(bool adopt) {
        drop();
        pending_ = adopt;
    }
    // Click, foreground / focus change, suspension, the word dropped: nothing to adopt.
    void drop() {
        pending_ = false;
        owed_ = false;
        raw_.clear();
        believed_.clear();
    }
    bool pending() const { return pending_; }
    bool owes() const { return owed_; }

    enum class Start : uint8_t {
        Adopted,  // the session holds the word: the hook types from this key on
        Nothing,  // no word in progress (or this key ends it): the hook types from this key on
        Unknown,  // a word of unknown keys is on screen: wait for a boundary (old rule)
    };
    // The first key the hook handles after engaged(true), before anything else is done with
    // it. `typedWord` = the kTypedWordProp value on the foreground root (0 = none).
    Start begin(uint32_t typedWord, const KeyInput& k, TypingSession& s);

    // While owes(): ⌫ — the app deletes the last raw letter (pass the key through untouched);
    // the rest of the word is adopted again.
    void backspace(TypingSession& s);
    // While owes(), any other key: the edit to send FIRST in this key's batch — delete
    // `expect` (the raw letters that differ), type `insert` (the session's text) — then the
    // key's own handling. Ends the debt.
    struct Fix {
        std::u16string expect, insert;
    };
    Fix takeFix();

    // Introspection (tests, log).
    const std::u16string& raw() const { return raw_; }
    const std::u16string& believed() const { return believed_; }

private:
    bool adopt(TypingSession& s);

    bool pending_ = false;
    bool owed_ = false;
    std::u16string raw_;       // what the screen shows (the keys as typed)
    std::u16string believed_;  // what the session believes it shows
};

}  // namespace vtx::app
