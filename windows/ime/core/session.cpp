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
    wordMode_ = effectiveMode();
}

void TypingSession::fallBack(const char* why) {
    if (asyncStore_) {
        // Chromium & co: the store is readable, only late. Its failures are lag, not an
        // unreadable field: compose (the IME-native path), never hand the field to the
        // hook — blind backspace+retype into a web editor is what loses letters there.
        if (!preferComposition_ && opt_.log) opt_.log(why);
        preferComposition_ = true;
        return;
    }
    if (!contextFallback_ && opt_.log) opt_.log(why);
    contextFallback_ = true;
}

std::u16string TypingSession::composed() const { return engine_ ? composedOf(engine_) : std::u16string(); }

bool TypingSession::misspelled(const vtx_engine* e) const {
    return opt_.underlineMisspelled && vtx_has_spelling_error(e, opt_.autoRestore ? 1 : 0) != 0;
}

std::u16string TypingSession::rawKeys() const {
    if (!engine_) return {};
    uint16_t buf[VTX_MAX_TEXT + 1];
    const int32_t n = vtx_raw_keystrokes(engine_, buf, VTX_MAX_TEXT + 1);
    return n > 0 ? std::u16string(reinterpret_cast<const char16_t*>(buf), static_cast<size_t>(n)) : std::u16string();
}

bool TypingSession::previousWordEnglish() const { return engine_ && vtx_previous_word_english(engine_) != 0; }

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
    droppedSig_.clear();
    overflow_ = false;
    reopenArmed_ = false;
    retroUndo_.clear();
    retroOffer_.clear();
}

void TypingSession::setCompositionOnlyContext(bool on) {
    compositionOnly_ = on;
    if (vtx_is_empty(engine_)) wordMode_ = effectiveMode();
}

void TypingSession::setHostDropsPassedKeys(bool on) {
    dropsPassedKeys_ = on;
    if (on) reopenArmed_ = false;
}

void TypingSession::setPreferComposition(bool on) {
    preferComposition_ = on;
    if (vtx_is_empty(engine_)) wordMode_ = effectiveMode();
}

void TypingSession::noteReplace(const std::u16string& oldShown, const std::u16string& expect,
                                const std::u16string& insert) {
    // A pure insertion has no deletion to drop.
    if (expect.empty()) droppedSig_.clear();
    else droppedSig_ = oldShown + insert;
}

bool TypingSession::screenStale(const std::u16string& before) {
    auto endsWith = [&](const std::u16string& t) {
        return before.size() >= t.size() && before.compare(before.size() - t.size(), t.size(), t) == 0;
    };
    if (endsWith(shown_)) return false;
    // The app inserted our replacement but kept what it should have deleted ("the" + e ->
    // "theê"): Chromium's views::Textfield (Chrome/Edge address bar) applies TSF's
    // ExtendSelectionAndDelete to its REVERSED inline-autocomplete selection, so the
    // delete lands inside the suggestion. Nothing typed in place can be trusted here.
    if (!droppedSig_.empty() && endsWith(droppedSig_)) {
        if (!preferComposition_ && opt_.log)
            opt_.log("in-place: the app dropped the deletion of a replace -> composition for this field");
        preferComposition_ = true;
    }
    return true;
}

void TypingSession::verifyScreen(TextSink& sink) {
    if (!wordActive() || wordMode_ != OutputMode::InPlace || sink.blind()) return;
    const size_t want = shown_.size() > droppedSig_.size() ? shown_.size() : droppedSig_.size();
    const bool preferred = preferComposition_;
    if (!screenStale(sink.textBeforeCaret(static_cast<int>(want)))) return;
    // An async store (Chromium) reports the page renderer round trips late, often with a
    // state OLDER than our own last edit: not a change of the word. Keep it; the next key
    // re-checks and, if the store is still behind, stops editing in place (handleWordKey).
    // Forgetting the word here made the next key start a "word" in the middle of one,
    // edited against the stale view (model: "trinhf" -> "triìn", the h lost).
    if (asyncStore_ && preferred == preferComposition_) return;
    reset();
}

void TypingSession::resetContext() {
    reset();
    contextFallback_ = false;
    compositionOnly_ = false;
    preferComposition_ = false;
    asyncStore_ = false;
    dropsPassedKeys_ = false;
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
            // Retro English: boundary characters declined here reach the engine through
            // noteKeyPassedBy() (no edit session for them).
            return isWordKey(k) || wordActive() || reopenArmed_;
        case KeyKind::Backspace:
            return wordActive() || retroUndo_.armed() ||
                   (opt_.reEditWord && reopenArmed_ && vtx_can_reopen_last_commit(engine_));
        case KeyKind::Boundary:
        case KeyKind::Navigation:
        case KeyKind::Chord:
            // reopenArmed_ / retro undo: so the key disarms it
            return wordActive() || reopenArmed_ || retroUndo_.armed();
        case KeyKind::Modifier:
        case KeyKind::Other:
            return false;
    }
    return false;
}

bool TypingSession::handleKey(const KeyInput& k, TextSink& sink) {
    lastRaw_.clear();
    lastText_.clear();
    lastWord_.clear();
    lastRetroWords_ = 0;
    retroOffer_.clear();
    // A rewrite can be reverted by the very next key only.
    const retro::Undo undo = std::move(retroUndo_);
    retroUndo_.clear();
    if (!engine_) return false;
    switch (k.kind) {
        case KeyKind::Char:
            if (isWordKey(k)) return handleWordKey(k.ch, sink);
            return commitWord(sink, KeyKind::Char, k.ch);
        case KeyKind::Backspace:
            if (undo.armed() && vtx_is_empty(engine_) && tryRetroUndo(undo, sink)) return true;
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

void TypingSession::noteKeyPassedBy(const KeyInput& k) {
    retroOffer_.clear();
    lastRetroWords_ = 0;
    // Any other key drops the one-key undo (retro rewrite or boundary restore), and the
    // engine hears about every boundary character even with retro off: it also uses them
    // for glued separators ("my_var", "os.path", "100W").
    retroUndo_.clear();
    switch (k.kind) {
        case KeyKind::Char:
            vtx_note_boundary(engine_, k.ch != 0 && k.ch <= 0xFFFF ? k.ch : U'\n');
            break;
        case KeyKind::Backspace:
        case KeyKind::Boundary:
        case KeyKind::Navigation:
        case KeyKind::Chord:
            vtx_note_boundary(engine_, U'\n');  // ends the phrase (the text may change)
            break;
        case KeyKind::Modifier:
        case KeyKind::Other:
            break;
    }
}

bool TypingSession::handleWordKey(char32_t c, TextSink& sink) {
    reopenArmed_ = false;
    if (overflow_) {  // engine is past its 32-key window: the rest of the word is literal
        vtx_action a;
        vtx_feed(engine_, c, &a);
        return false;
    }
    // A composition we no longer track (engine was reset): close it, text stays.
    if (vtx_is_empty(engine_) && sink.compositionActive()) sink.endCompositionAsIs();
    if (!vtx_is_empty(engine_) && !sink.blind()) {
        // Our picture of the screen went stale (composition ended behind our back, the
        // app changed the text before the caret): start over rather than edit blindly.
        // A selection AFTER the caret (Chrome/Edge omnibox autocomplete suffix) is the
        // app's: it does not invalidate the word, which ends at the insertion point.
        bool stale;
        if (wordMode_ == OutputMode::Composition) {
            stale = !sink.compositionActive();
        } else {
            const size_t want = shown_.size() > droppedSig_.size() ? shown_.size() : droppedSig_.size();
            const std::u16string before = sink.textBeforeCaret(static_cast<int>(want));
            stale = screenStale(before);
            if (stale && asyncStore_) {
                // The store has not caught up with the page (or the page changed): an edit
                // computed from it lands at the PAGE's caret, not where we checked — letters
                // lost in Messenger/Facebook. The field composes from the next word on
                // (Chromium keeps its cache in step with a composition itself). A key that
                // only appends needs no edit: let it through and keep the word.
                fallBack("in-place: the store lags the page -> composition for this field");
                const bool dropped = !droppedSig_.empty() && before.size() >= droppedSig_.size() &&
                                     before.compare(before.size() - droppedSig_.size(), droppedSig_.size(),
                                                    droppedSig_) == 0;  // real damage (omnibox), not lag
                if (vtx_engine* t = dropped ? nullptr : vtx_clone(engine_)) {
                    vtx_action pa;
                    vtx_feed(t, c, &pa);
                    const std::u16string next = composedOf(t);
                    const bool append = pa.kind == VTX_PASSTHROUGH && !vtx_is_overflowed(t) &&
                                        next.size() == shown_.size() + 1 &&
                                        next.compare(0, shown_.size(), shown_) == 0 &&
                                        next.back() == static_cast<char16_t>(c);
                    if (append) {
                        swapEngine(t);
                        shown_ = next;
                        droppedSig_.clear();
                        return false;
                    }
                    vtx_destroy(t);
                }
                // A key that needs an edit goes to the page as typed (in order, after the
                // keys still in flight): at worst one word without its accent, never a
                // letter deleted or misplaced.
                reset();
                return false;
            }
            // NOTHING before the caret although we just let letters through: the store
            // does not show the app's text. In-place can never work in this field — use
            // composition for the rest of it. (An async store — xterm.js' hidden
            // textarea — returned above.) This is an IMM32 app through CUAS (WinForms:
            // MISA SME, mintty): the letters we let through were claimed in
            // OnTestKeyDown, so the app never got them (#134: "first letter lost").
            // Keep the word and compose all of it, from this key on.
            if (stale && before.empty() && !shown_.empty()) {
                fallBack("in-place: the field shows none of the typed text -> composition for this field");
                if (!dropsPassedKeys_ && opt_.log)
                    opt_.log("in-place: letters let through never reached the app (IMM host) -> composing them");
                setHostDropsPassedKeys(true);
                wordMode_ = OutputMode::Composition;
                stale = false;
            }
        }
        if (stale) reset();
    }
    droppedSig_.clear();
    if (vtx_is_empty(engine_)) {
        wordMode_ = effectiveMode();
        if (wordMode_ == OutputMode::InPlace && !sink.blind() && !sink.canReadContext()) {
            fallBack("in-place: cannot read the text around the caret -> composition for this field");
            wordMode_ = OutputMode::Composition;
        }
    }
    const bool comp = wordMode_ == OutputMode::Composition;
    if (vtx_is_empty(engine_) && mayReEdit() && !sink.hasSelection() &&
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
        if (!sink.setComposition(now, 0, misspelled(engine_))) {
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
    const std::u16string insert = actionInsert(a);
    if (!tailOf(shown_, a.backspaces, expect) || !sink.replaceBeforeCaret(expect, insert)) {
        // Screen did not match what we typed: this word goes literal (never guess), and
        // the rest of this field uses composition.
        fallBack("in-place: text before the caret did not verify -> composition for this field");
        reset();
        return false;
    }
    noteReplace(shown_, expect, insert);
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
    if (wordMode_ == OutputMode::Composition) {
        ok = sink.setComposition(now, static_cast<int>(word.size()), misspelled(t));
    } else if (a.kind == VTX_REPLACE) {
        std::u16string expect;
        const std::u16string insert = actionInsert(a);
        ok = tailOf(word, a.backspaces, expect) && sink.replaceBeforeCaret(expect, insert);
        if (ok) noteReplace(word, expect, insert);
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
    if (vtx_is_empty(engine_)) wordMode_ = effectiveMode();
    const bool comp = wordMode_ == OutputMode::Composition;
    if (overflow_) {  // stale 32-key view: let the app delete, drop the word
        reset();
        return false;
    }
    if (vtx_is_empty(engine_)) {
        if (mayReadBack() && reopenArmed_ && vtx_can_reopen_last_commit(engine_)) return tryReopen(sink);
        reopenArmed_ = false;
        return false;
    }
    reopenArmed_ = false;
    droppedSig_.clear();
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
        if (!sink.setComposition(now, 0, misspelled(engine_))) {
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
    const std::u16string insert = actionInsert(a);
    if (!tailOf(shown_, a.backspaces, expect) || !sink.replaceBeforeCaret(expect, insert)) {
        reset();
        return false;
    }
    noteReplace(shown_, expect, insert);
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
    if (wordMode_ == OutputMode::Composition && !sink.setComposition(word, n, misspelled(t))) {
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

bool TypingSession::retroOn() const { return engine_ && (opt_.engineFlags & VTX_RETRO_ENGLISH) != 0; }

retro::Field TypingSession::retroField(TextSink& sink) const {
    retro::Field f;
    f.blind = sink.blind();
    f.compositionOnly = compositionOnly_;
    if (f.blind || f.compositionOnly) return f;
    f.canRead = sink.canReadContext();
    f.hasSelection = sink.hasSelection();
    f.compositionActive = sink.compositionActive();
    return f;
}

void TypingSession::finishRetro(TextSink& sink, KeyKind kind, char32_t ch) {
    // Enter / Tab / Esc / navigation / chords end the English phrase (DESIGN.md: anything
    // but a space starts a new one); only a printable boundary (space, punctuation) applies
    // a rewrite.
    const bool printable = kind == KeyKind::Char && ch != 0 && ch <= 0xFFFF;
    vtx_retro_correction c;
    if (vtx_take_retro_correction(engine_, &c)) {
        const std::u16string expected = toU16(c.expected, c.expected_len < VTX_RETRO_MAX ? c.expected_len : 0);
        const std::u16string insert = toU16(c.insert, c.insert_len < VTX_RETRO_MAX ? c.insert_len : 0);
        const retro::Field f = retroField(sink);
        const bool canRead = !f.blind && !f.compositionOnly && f.canRead;
        const bool offer = opt_.retroOffer;
        // Offer: a few more units, for the start of the first word in the hint ("H" of "Hí").
        const int want = static_cast<int>(expected.size()) + (offer ? 24 : 0);
        const std::u16string before = canRead ? sink.textBeforeCaret(want) : std::u16string();
        bool applied = false;
        // Only at a typed boundary: Enter / Tab may send the message or leave the field —
        // no rewrite behind the user's back (and no ⌫ to undo it).
        const retro::Apply d =
            printable ? retro::decideApply(f, before, expected, c.backspaces) : retro::Apply::Unverifiable;
        switch (d) {
            case retro::Apply::Apply:
                if (offer) {
                    retroOffer_ = retro::makeOffer(before, expected, insert, static_cast<char16_t>(ch), c.words);
                    if (opt_.log) opt_.log(retroOffer_.empty() ? "retro: nothing to offer" : "retro: offered");
                    break;
                }
                applied = sink.replaceBeforeCaret(expected, insert);
                if (!applied && opt_.log) opt_.log("retro: the field refused the rewrite");
                break;
            case retro::Apply::Unverifiable:
                if (opt_.log) opt_.log("retro: field not verifiable -> skipped");
                break;
            case retro::Apply::Mismatch:
                if (opt_.log) opt_.log("retro: text before the caret differs -> skipped");
                break;
        }
        if (applied) {
            lastRetroWords_ = c.words;
            if (printable) retroUndo_ = retro::makeUndo(expected, insert, static_cast<char16_t>(ch));
            reopenArmed_ = false;  // ⌫ next reverts the rewrite, never re-opens a word
            vtx_forget_last_commit(engine_);
        } else {
            // The engine already recorded those words as English: its history no longer
            // matches the screen (offer: not until Tab, which resets the session). End the
            // phrase.
            vtx_note_boundary(engine_, U'\n');
        }
    }
    // Report the boundary AFTER taking the correction: the app inserts it after this key,
    // so `expected` / `insert` must not contain it.
    vtx_note_boundary(engine_, printable ? ch : U'\n');
}

bool TypingSession::tryRetroUndo(const retro::Undo& u, TextSink& sink) {
    const retro::Field f = retroField(sink);
    const std::u16string before = (!f.blind && !f.compositionOnly && f.canRead)
                                      ? sink.textBeforeCaret(static_cast<int>(u.applied.size()))
                                      : std::u16string();
    if (!retro::undoApplies(u, f, before) || !sink.replaceBeforeCaret(u.applied, u.original)) return false;
    if (u.restore) {
        // ⌫ right after a restore-to-English: the Vietnamese word is back on screen.
        if (opt_.log) opt_.log("restore undo: Vietnamese put back by backspace");
        ++restoreUndos_;
        reset();
        vtx_restore_undo_applied(engine_);   // the committed word is Vietnamese now
        return true;
    }
    if (opt_.log) opt_.log("retro: reverted by backspace");
    // The engine's word history says English; the screen is back to the old text.
    reset();
    vtx_note_boundary(engine_, U'\n');
    return true;
}

bool TypingSession::commitWord(TextSink& sink, KeyKind kind, char32_t ch) {
    const bool r = commitWordInner(sink, kind, ch);
    const bool printable = kind == KeyKind::Char && ch != 0 && ch <= 0xFFFF;
    if (retroOn()) finishRetro(sink, kind, ch);
    else vtx_note_boundary(engine_, printable ? ch : U'\n');   // glue: see noteKeyPassedBy
    armRestoreUndo(printable ? static_cast<char16_t>(ch) : 0);
    return r;
}

void TypingSession::armRestoreUndo(char16_t boundary) {
    vtx_restore_undo u;
    if (!vtx_take_restore_undo(engine_, &u)) return;
    // Only after a printable boundary on the same line (Enter / Tab may have sent the
    // message or left the field), never over a retro rewrite this key already armed, and
    // only when the screen got the restored word (the commit's own rewrite verified).
    if (boundary == 0 || boundary == u'\n' || boundary == u'\r' || boundary == u'\t' || retroUndo_.armed()) return;
    const std::u16string restored = toU16(u.restored, u.restored_len);
    if (lastText_ != restored) return;
    retroUndo_ = retro::makeUndo(toU16(u.vietnamese, u.vietnamese_len), restored, boundary);
    retroUndo_.restore = true;
}

bool TypingSession::commitWordInner(TextSink& sink, KeyKind kind, char32_t ch) {
    const bool comp = wordMode_ == OutputMode::Composition;
    const bool printable = kind == KeyKind::Char;
    // #134: a host that drops claimed keys gets the printable boundary inside the result
    // string ("word␣", one WM_IME_COMPOSITION) and the key is eaten — no retyped key that
    // could land after keys already queued behind it.
    const bool boundaryInResult = comp && dropsPassedKeys_ && printable && ch != 0 && ch <= 0xFFFF;
    const std::u16string boundary = boundaryInResult ? std::u16string(1, static_cast<char16_t>(ch)) : std::u16string();
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
            if (comp) sink.endComposition(expansion + boundary);
            else sink.replaceBeforeCaret(shown_, expansion);
            reset();
            return boundaryInResult;
        }
    }

    const std::u16string raw = printable ? rawOf(engine_) : std::u16string();
    std::u16string finalText;
    bool committed = true;
    if (comp) {
        uint16_t buf[VTX_MAX_TEXT + 1];
        int32_t n = vtx_commit_text(engine_, opt_.autoRestore ? 1 : 0, buf, VTX_MAX_TEXT + 1);
        finalText = toU16(buf, n);
        sink.endComposition(finalText + boundary);
    } else {
        vtx_action a;
        vtx_commit_boundary(engine_, opt_.autoRestore ? 1 : 0, &a);
        finalText = shown_;
        if (a.kind == VTX_REPLACE) {
            std::u16string expect;
            const std::u16string insert = actionInsert(a);
            if (!tailOf(shown_, a.backspaces, expect) || !sink.replaceBeforeCaret(expect, insert)) {
                vtx_forget_last_commit(engine_);
                committed = false;
            } else {
                finalText = shown_.substr(0, shown_.size() - expect.size()) + insert;
            }
        }
    }
    if (printable && committed) {
        lastRaw_ = raw;
        lastText_ = finalText;
    }
    if (committed && (printable || kind == KeyKind::Boundary)) lastWord_ = finalText;
    shown_.clear();
    // ⌫ re-open reads "<word><boundary>" back: impossible where keys are dropped (nothing
    // readable), and claiming the next key there would lose it.
    reopenArmed_ = printable && !dropsPassedKeys_;
    if (!printable) vtx_forget_last_commit(engine_);
    return boundaryInResult;
}

}  // namespace vtx
