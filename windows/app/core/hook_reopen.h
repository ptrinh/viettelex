// hook_reopen.h — "Sửa dấu từ đã gõ" by ⌫ for the keyboard hook (portable build, Direct /
// hook-fallback apps): ⌫ back into a word just typed reopens it in the engine, like the TIP
// does ("toan␣ ⌫ s" -> "toán"). The TIP proves the word is still there by reading the text
// before the caret; the hook cannot read anything. Instead it keeps the TRAIL of what it saw
// typed since the last moment the caret position was certain: the last few words it
// committed (raw keys + the exact text left on screen) and the separator characters that
// reached the app after each one. ⌫ that deletes the last separator after a word, with
// nothing in between but keys the trail accounts for, puts that word back in the engine.
//
// Wrongly reopening is worse than not reopening (the next tone key would edit the wrong
// characters), so ANYTHING the trail cannot account for drops it: a click, arrows / Home /
// End / Delete / Insert, Enter / Tab / Esc, any Ctrl / Alt / Win combination (paste, undo,
// switching windows or keyboards), Alt or Win pressed alone, F-keys and other keys, a focus
// or foreground change, someone else's injected input, English mode / a yielding or password
// field (the hook does not type there), game suspension, a settings change, the hook being
// reinstalled, a separator outside the short list below, and any edit the session could not
// make. Pure (unit-tested on any OS); hook_fallback.cpp calls it around each key.
//
//   before(k, session)   every key the hook routes to the session (after its own checks)
//   after(k, session, …) once the session handled / passed the key
//   invalidate()         every event above that is not a key routed to the session
#pragma once
#include <cstddef>
#include <cstdint>

#include "keymap.h"

namespace vtx {
class TypingSession;
}

namespace vtx::app {

// Characters the trail follows after a word: space and sentence punctuation. They are one
// UTF-16 unit on screen per key on common layouts and never dead keys; quotes, brackets,
// digits and symbols (dead keys on international layouts, auto-paired by editors) drop it.
bool isTrailSeparator(char32_t c);
// A modifier pressed alone: Shift / Ctrl / Caps Lock keep the trail (Shift types "!" "?",
// Ctrl+Shift switches Việt/Anh — English typing then drops the trail anyway); Alt (menu
// bar) and Win (Start, Win+Space) drop it.
bool modifierDropsTrail(uint32_t vkCode);

class ReopenTrail {
public:
    static constexpr int kMaxWords = 3;       // words ⌫ can walk back through
    static constexpr int kMaxUnits = 64;      // VTX_MAX_TEXT: raw keys / text per word
    static constexpr int kMaxSeparators = 4;  // separators after one word ("word, " = 2)

    // "Sửa dấu từ đã gõ" (Settings::reEditWord). Off = nothing recorded, ⌫ never reopens.
    void setEnabled(bool on) {
        enabled_ = on;
        if (!on) invalidate();
    }
    bool enabled() const { return enabled_; }
    void invalidate() {
        count_ = 0;
        inWord_ = false;
        popped_ = false;
    }

    enum class Before : uint8_t {
        Normal,    // hand the key to the session as usual
        Popped,    // ⌫ deletes one of several separators: pass it to the app untouched
        Reopened,  // ⌫ deletes the last separator: the word is back in the session's engine;
                   // pass the ⌫ to the app untouched (it deletes that separator)
    };
    // Called for every key the hook routes to the session, before wantsKey / handleKey.
    // Chords, navigation, Enter / Tab / Esc and "other" keys invalidate here (a modifier
    // alone never reaches the session: the hook asks modifierDropsTrail).
    Before before(const KeyInput& k, TypingSession& s);
    // After the session handled the key (`handled`: handleKey ran; `eaten`: the key itself
    // did not reach the app; `edits`: the hook injected edits for it) or passed it by
    // (handled = eaten = edits = false).
    void after(const KeyInput& k, const TypingSession& s, bool handled, bool eaten, bool edits);

    // Introspection (tests, debug log).
    int words() const { return count_; }
    bool inWord() const { return inWord_; }
    int separatorsAfterLast() const { return count_ ? words_[count_ - 1].sepLen : 0; }

private:
    struct Word {
        char16_t raw[kMaxUnits];
        char16_t text[kMaxUnits];
        char16_t sep[kMaxSeparators];
        uint8_t rawLen = 0, textLen = 0, sepLen = 0;
    };
    void push(const char16_t* raw, int rawLen, const char16_t* text, int textLen, char16_t sep);

    Word words_[kMaxWords];
    int count_ = 0;
    // A word is in progress right after the last separator (a new one, or a reopened one).
    bool inWord_ = false;
    bool enabled_ = true;
    // State of the key between before() and after().
    bool popped_ = false;
    bool wordBefore_ = false;
    size_t shownBefore_ = 0;
};

}  // namespace vtx::app
