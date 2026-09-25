#include "session.h"

#include <viettelex/vtx_engine.h>

#include "shortcuts.h"
#include "utf.h"

namespace vtx {

namespace {
constexpr int kMaxReEditWord = 12;  // macOS trailingWord(maxLength: 12)

std::u16string toU16(const uint16_t* buf, int32_t n) {
    std::u16string s;
    if (n > 0) s.assign(reinterpret_cast<const char16_t*>(buf), static_cast<size_t>(n));
    return s;
}

std::u16string composedOf(const vtx_engine* e) {
    uint16_t buf[VTX_MAX_TEXT + 1];
    int32_t n = vtx_composed(e, buf, VTX_MAX_TEXT + 1);
    return toU16(buf, n);
}

std::u16string rawOf(const vtx_engine* e) {
    uint16_t buf[VTX_MAX_TEXT + 1];
    int32_t n = vtx_raw_keystrokes(e, buf, VTX_MAX_TEXT + 1);
    return toU16(buf, n);
}

std::u16string actionInsert(const vtx_action& a) {
    int32_t n = a.insert_len;
    if (n < 0) n = 0;
    if (n > VTX_MAX_TEXT) n = VTX_MAX_TEXT;
    return toU16(a.insert, n);
}

bool tailOf(const std::u16string& s, int32_t n, std::u16string& out) {
    if (n < 0 || static_cast<size_t>(n) > s.size()) return false;
    out = s.substr(s.size() - static_cast<size_t>(n));
    return true;
}
}  // namespace

bool isDiacriticOnlyKey(char32_t c, bool vni) {
    if (vni) return isAsciiDigit(c);
    switch (c | 0x20) {
        case U's': case U'f': case U'r': case U'x': case U'j': case U'z': case U'w':
            return isAsciiLetter(c);
        default:
            return false;
    }
}

bool isWordCharForReEdit(char16_t c) {
    if ((c >= u'a' && c <= u'z') || (c >= u'A' && c <= u'Z')) return true;
    if (c >= 0x00C0 && c <= 0x024F && c != 0x00D7 && c != 0x00F7) return true;  // Latin-1/Ext-A/B letters
    if (c >= 0x1EA0 && c <= 0x1EF9) return true;                                // Vietnamese block
    return false;
}

TypingSession::TypingSession() : engine_(vtx_create()) {
    if (engine_) vtx_set_flags(engine_, opt_.engineFlags);
}

TypingSession::~TypingSession() {
    if (engine_) vtx_destroy(engine_);
}

void TypingSession::configure(const SessionOptions& o) {
    opt_ = o;
    if (engine_) vtx_set_flags(engine_, o.engineFlags);
}

void TypingSession::setOutputMode(OutputMode m) {
    if (m == mode_) return;
    reset();
    mode_ = m;
}

std::u16string TypingSession::composed() const { return engine_ ? composedOf(engine_) : std::u16string(); }

bool TypingSession::wordActive() const { return engine_ && (overflow_ || !vtx_is_empty(engine_)); }

bool TypingSession::isWordKey(char32_t c) const {
    if (isAsciiLetter(c)) return true;
    if ((opt_.engineFlags & VTX_VNI) && isAsciiDigit(c)) return true;
    if ((opt_.engineFlags & VTX_BRACKET_VOWELS) && (c == U'[' || c == U']' || c == U'{' || c == U'}'))
        return true;
    return false;
}

void TypingSession::reset() {
    if (engine_) vtx_reset(engine_);
    shown_.clear();
    overflow_ = false;
    reopenArmed_ = false;
}

void TypingSession::resetContext() {
    reset();
    if (engine_) vtx_reset_context(engine_);
}

void TypingSession::swapEngine(vtx_engine* e) {
    if (engine_) vtx_destroy(engine_);
    engine_ = e;
}

bool TypingSession::wantsKey(const KeyInput& k) const {
    if (!engine_) return false;
    switch (k.kind) {
        case KeyKind::Char:
            return isWordKey(k.ch) || wordActive() || reopenArmed_;
        case KeyKind::Backspace:
            return wordActive() ||
                   (opt_.reEditWord && reopenArmed_ && vtx_can_reopen_last_commit(engine_));
        case KeyKind::Boundary:
        case KeyKind::Navigation:
        case KeyKind::Chord:
            return wordActive() || reopenArmed_;  // reopenArmed_: so the key disarms it
        case KeyKind::Modifier:
        case KeyKind::Other:
            return false;
    }
    return false;
}

bool TypingSession::handleKey(const KeyInput& k, TextSink& sink) {
    if (!engine_) return false;
    switch (k.kind) {
        case KeyKind::Char:
            if (isWordKey(k.ch)) return handleWordKey(k.ch, sink);
            return commitWord(sink, KeyKind::Char);
        case KeyKind::Backspace:
            return handleBackspace(sink);
        case KeyKind::Boundary:
        case KeyKind::Navigation:
        case KeyKind::Chord:
            return commitWord(sink, k.kind);
        case KeyKind::Modifier:
        case KeyKind::Other:
            return false;
    }
    return false;
}

void TypingSession::flush(TextSink& sink) { commitWord(sink, KeyKind::Navigation); }

bool TypingSession::handleWordKey(char32_t c, TextSink& sink) {
    reopenArmed_ = false;
    if (overflow_) {  // engine is past its 32-key window: the rest of the word is literal
        vtx_action a;
        vtx_feed(engine_, c, &a);
        return false;
    }
    const bool comp = mode_ == OutputMode::Composition;
    // A composition we no longer track (engine was reset): close it, text stays.
    if (comp && vtx_is_empty(engine_) && sink.compositionActive()) sink.endCompositionAsIs();
    if (!vtx_is_empty(engine_)) {
        // Our picture of the screen went stale (composition ended behind our back,
        // or the user selected text mid-word): start over rather than edit blindly.
        if ((comp && !sink.compositionActive()) || (!comp && sink.hasSelection())) reset();
    }
    if (vtx_is_empty(engine_) && opt_.reEditWord && !sink.hasSelection() &&
        (!comp || !sink.compositionActive())) {
        if (tryReEdit(c, sink)) return true;
    }

    const size_t prevLen = shown_.size();
    vtx_action a;
    vtx_feed(engine_, c, &a);
    std::u16string now = composed();

    if (a.kind == VTX_PASSTHROUGH) {
        bool plainAppend = now.size() == prevLen + 1 && now.back() == static_cast<char16_t>(c);
        if (vtx_is_overflowed(engine_) || !plainAppend) {
            // Overflow: keep what is on screen, the rest of the word goes through raw.
            overflow_ = true;
            if (comp && sink.compositionActive()) sink.endComposition(shown_);
            shown_.clear();
            return false;
        }
    }

    if (comp) {
        if (!sink.setComposition(now, 0)) {
            reset();
            return false;
        }
        shown_ = now;
        return true;
    }

    // In-place.
    if (a.kind == VTX_PASSTHROUGH) {
        shown_ = now;  // the app inserts the key itself
        return false;
    }
    if (a.kind == VTX_NONE) {
        shown_ = now;
        return true;
    }
    std::u16string expect;
    if (!tailOf(shown_, a.backspaces, expect) || !sink.replaceBeforeCaret(expect, actionInsert(a))) {
        reset();
        return false;
    }
    shown_ = now;
    return true;
}

bool TypingSession::tryReEdit(char32_t c, TextSink& sink) {
    // macOS isDiacriticOnlyKey: only keys that can ONLY add a diacritic reach back into
    // the word before the caret (s f r x j z w; VNI digits). Doubling letters (a e o d)
    // are ordinary letters too — "ca" + "a" must stay "caa".
    if (!isDiacriticOnlyKey(c, (opt_.engineFlags & VTX_VNI) != 0)) return false;
    // Caret inside a word ("việ|t"): seeding the left half would rewrite half a word.
    if (isWordCharForReEdit(sink.charAfterCaret())) return false;
    std::u16string before = sink.textBeforeCaret(kMaxReEditWord + 1);
    size_t start = before.size();
    while (start > 0 && isWordCharForReEdit(before[start - 1])) --start;
    const size_t len = before.size() - start;
    if (len == 0 || len > static_cast<size_t>(kMaxReEditWord)) return false;
    // Word longer than what we read (no separator found) -> could be a longer token.
    if (start == 0 && before.size() == static_cast<size_t>(kMaxReEditWord + 1)) return false;
    // Glued to a token opener ("5h", "#tag") -> not a standalone word.
    if (start > 0 && gluesShortcutToken(before[start - 1])) return false;
    const std::u16string word = before.substr(start);

    vtx_engine* t = vtx_clone(engine_);
    if (!t) return false;
    if (!vtx_seed(t, reinterpret_cast<const uint16_t*>(word.data()), static_cast<int32_t>(word.size()))) {
        vtx_destroy(t);
        return false;
    }
    vtx_action a;
    vtx_feed(t, c, &a);
    std::u16string now = composedOf(t);
    if (a.kind == VTX_PASSTHROUGH || now == word + static_cast<char16_t>(c)) {
        vtx_destroy(t);  // the key does not transform the word: ordinary new word
        return false;
    }
    bool ok;
    if (mode_ == OutputMode::Composition) {
        ok = sink.setComposition(now, static_cast<int>(word.size()));
    } else if (a.kind == VTX_REPLACE) {
        std::u16string expect;
        ok = tailOf(word, a.backspaces, expect) && sink.replaceBeforeCaret(expect, actionInsert(a));
    } else {
        ok = true;  // VTX_NONE: consumed
    }
    if (!ok) {
        vtx_destroy(t);
        return false;
    }
    swapEngine(t);
    shown_ = now;
    return true;
}

bool TypingSession::handleBackspace(TextSink& sink) {
    const bool comp = mode_ == OutputMode::Composition;
    if (overflow_) {  // stale 32-key view: let the app delete, drop the word
        reset();
        return false;
    }
    if (vtx_is_empty(engine_)) {
        if (opt_.reEditWord && reopenArmed_ && vtx_can_reopen_last_commit(engine_)) return tryReopen(sink);
        reopenArmed_ = false;
        return false;
    }
    reopenArmed_ = false;
    if ((comp && !sink.compositionActive()) || (!comp && sink.hasSelection())) {
        reset();
        return false;
    }
    vtx_action a;
    vtx_backspace(engine_, &a);
    std::u16string now = composed();

    if (comp) {
        if (a.kind == VTX_PASSTHROUGH) {  // should not happen with a live word
            sink.endComposition(shown_);
            reset();
            return false;
        }
        if (now.empty()) {
            sink.endComposition(std::u16string());
            reset();
            return true;
        }
        if (!sink.setComposition(now, 0)) {
            reset();
            return false;
        }
        shown_ = now;
        return true;
    }

    if (a.kind == VTX_PASSTHROUGH) {
        if (!shown_.empty()) shown_.pop_back();
        return false;
    }
    if (a.kind == VTX_NONE) {
        shown_ = now;
        return true;
    }
    std::u16string expect;
    if (!tailOf(shown_, a.backspaces, expect) || !sink.replaceBeforeCaret(expect, actionInsert(a))) {
        reset();
        return false;
    }
    shown_ = now;
    if (shown_.empty()) reset();
    return true;
}

bool TypingSession::tryReopen(TextSink& sink) {
    reopenArmed_ = false;
    vtx_engine* t = vtx_clone(engine_);
    if (!t) return false;
    uint16_t buf[VTX_MAX_TEXT + 1];
    int32_t n = vtx_reopen_last_commit(t, buf, VTX_MAX_TEXT + 1);
    if (n <= 0) {
        vtx_destroy(t);
        vtx_forget_last_commit(engine_);
        return false;
    }
    std::u16string word = toU16(buf, n);
    std::u16string before = sink.textBeforeCaret(n + 1);
    // Screen must read exactly "<word><one boundary char>".
    if (before.size() != static_cast<size_t>(n) + 1 || before.compare(0, word.size(), word) != 0 ||
        sink.hasSelection() || sink.compositionActive()) {
        vtx_destroy(t);
        vtx_forget_last_commit(engine_);
        return false;
    }
    if (!sink.replaceBeforeCaret(before.substr(word.size()), std::u16string())) {
        vtx_destroy(t);
        vtx_forget_last_commit(engine_);
        return false;
    }
    if (mode_ == OutputMode::Composition && !sink.setComposition(word, n)) {
        // Boundary char is gone but the composition failed: the word is plain text
        // now, which is exactly what a normal ⌫ would have left.
        vtx_destroy(t);
        reset();
        return true;
    }
    swapEngine(t);
    shown_ = word;
    return true;
}

bool TypingSession::commitWord(TextSink& sink, KeyKind kind) {
    const bool comp = mode_ == OutputMode::Composition;
    const bool printable = kind == KeyKind::Char;
    if (overflow_) {
        vtx_action a;
        vtx_commit_boundary(engine_, 0, &a);
        vtx_forget_last_commit(engine_);
        overflow_ = false;
        shown_.clear();
        reopenArmed_ = false;
        return false;
    }
    if (vtx_is_empty(engine_)) {
        if (comp && sink.compositionActive()) sink.endCompositionAsIs();
        reopenArmed_ = false;
        return false;
    }
    if (kind == KeyKind::Chord && !comp) {
        // Ctrl+Z / Ctrl+A etc. are about to change the document: rewriting the word
        // now would race them. Leave the screen as is.
        reset();
        return false;
    }
    if (comp && !sink.compositionActive()) {
        reset();
        return false;
    }

    // Shortcut expansion (only on typed boundaries: space, punctuation, Enter, Tab).
    if (opt_.shortcuts && (printable || kind == KeyKind::Boundary)) {
        char16_t before = 0;
        std::u16string ctx = sink.textBeforeCaret(static_cast<int>(comp ? 1 : shown_.size() + 1));
        if (comp) {
            if (!ctx.empty()) before = ctx.back();
        } else if (ctx.size() == shown_.size() + 1) {
            before = ctx.front();
        }
        const std::u16string raw = rawOf(engine_);
        if (const std::u16string* exp = findShortcut(*opt_.shortcuts, shown_, raw, before)) {
            std::u16string expansion = *exp;
            if (comp) sink.endComposition(expansion);
            else sink.replaceBeforeCaret(shown_, expansion);
            reset();
            return false;
        }
    }

    if (comp) {
        uint16_t buf[VTX_MAX_TEXT + 1];
        int32_t n = vtx_commit_text(engine_, opt_.autoRestore ? 1 : 0, buf, VTX_MAX_TEXT + 1);
        sink.endComposition(toU16(buf, n));
    } else {
        vtx_action a;
        vtx_commit_boundary(engine_, opt_.autoRestore ? 1 : 0, &a);
        if (a.kind == VTX_REPLACE) {
            std::u16string expect;
            if (!tailOf(shown_, a.backspaces, expect) || !sink.replaceBeforeCaret(expect, actionInsert(a)))
                vtx_forget_last_commit(engine_);
        }
    }
    shown_.clear();
    reopenArmed_ = printable;
    if (!printable) vtx_forget_last_commit(engine_);
    return false;
}

}  // namespace vtx
