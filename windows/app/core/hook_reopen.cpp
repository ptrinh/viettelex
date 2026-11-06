#include "hook_reopen.h"

#include "session.h"

namespace vtx::app {

bool isTrailSeparator(char32_t c) {
    switch (c) {
        case U' ':
        case U'.':
        case U',':
        case U';':
        case U':':
        case U'!':
        case U'?': return true;
        default: return false;
    }
}

bool modifierDropsTrail(uint32_t v) {
    return v == vk::Menu || v == vk::LMenu || v == vk::RMenu || v == vk::LWin || v == vk::RWin;
}

void ReopenTrail::push(const char16_t* raw, int rawLen, const char16_t* text, int textLen, char16_t sep) {
    if (count_ == kMaxWords) {  // forget the oldest: ⌫ stops there
        for (int i = 1; i < kMaxWords; ++i) words_[i - 1] = words_[i];
        --count_;
    }
    Word& w = words_[count_++];
    for (int i = 0; i < rawLen; ++i) w.raw[i] = raw[i];
    for (int i = 0; i < textLen; ++i) w.text[i] = text[i];
    w.rawLen = static_cast<uint8_t>(rawLen);
    w.textLen = static_cast<uint8_t>(textLen);
    w.sep[0] = sep;
    w.sepLen = 1;
}

ReopenTrail::Before ReopenTrail::before(const KeyInput& k, TypingSession& s) {
    popped_ = false;
    if (!enabled_) return Before::Normal;
    wordBefore_ = s.wordActive();
    shownBefore_ = s.shown().size();
    switch (k.kind) {
        case KeyKind::Char: return Before::Normal;
        case KeyKind::Backspace: break;
        default:  // Enter / Tab / Esc, navigation, chords, other keys: caret or text unknown
            invalidate();
            return Before::Normal;
    }
    if (wordBefore_ || count_ == 0) return Before::Normal;  // the session edits its word / nothing known
    // ⌫ with no word in progress. A word "in progress" the session no longer has, or a
    // one-key undo the session would apply to this ⌫ (boundary restore): not ours to guess.
    if (inWord_ || s.retroUndoArmed()) {
        invalidate();
        return Before::Normal;
    }
    Word& w = words_[count_ - 1];
    if (w.sepLen > 1) {
        --w.sepLen;
        popped_ = true;
        return Before::Popped;
    }
    // This ⌫ deletes the only separator left after the word: the caret lands right after it.
    if (!s.reopenCommitted(w.raw, w.rawLen, w.text, w.textLen)) {
        invalidate();
        return Before::Normal;
    }
    --count_;
    inWord_ = true;
    return Before::Reopened;
}

void ReopenTrail::after(const KeyInput& k, const TypingSession& s, bool handled, bool eaten, bool edits) {
    if (!enabled_) return;
    if (popped_) {  // accounted for in before()
        popped_ = false;
        return;
    }
    const bool wordAfter = s.wordActive();
    switch (k.kind) {
        case KeyKind::Char:
            if (wordAfter) {
                if (wordBefore_) return;  // a key of the word in progress
                // A new word starts right after the last separator.
                if (inWord_) invalidate();
                else if (count_ > 0) inWord_ = true;
                return;
            }
            if (wordBefore_) {
                // The word ended at this key: committed in place, then the key itself reached
                // the app (passed, or replayed after the edits) — exactly `text` + `ch`.
                const std::u16string& raw = s.lastCommitRaw();
                const std::u16string& text = s.lastCommitText();
                if (handled && !eaten && isTrailSeparator(k.ch) && !raw.empty() && !text.empty() &&
                    raw.size() <= static_cast<size_t>(kMaxUnits) && text.size() <= static_cast<size_t>(kMaxUnits)) {
                    inWord_ = false;
                    push(raw.data(), static_cast<int>(raw.size()), text.data(), static_cast<int>(text.size()),
                         static_cast<char16_t>(k.ch));
                } else {
                    invalidate();  // shortcut expansion, overflow, a separator not followed
                }
                return;
            }
            // No word before or after: one more separator after the last one.
            if (count_ > 0 && !inWord_ && !eaten && !edits && isTrailSeparator(k.ch) &&
                words_[count_ - 1].sepLen < kMaxSeparators) {
                Word& w = words_[count_ - 1];
                w.sep[w.sepLen++] = static_cast<char16_t>(k.ch);
                return;
            }
            invalidate();
            return;
        case KeyKind::Backspace:
            if (wordBefore_ && wordAfter) return;  // still inside the word
            // The word is gone: back right after the last separator only when this ⌫
            // removed its last character (not an overflowed or dropped word).
            if (wordBefore_ && inWord_ && shownBefore_ == 1) {
                inWord_ = false;
                return;
            }
            invalidate();
            return;
        default: invalidate(); return;
    }
}

}  // namespace vtx::app
