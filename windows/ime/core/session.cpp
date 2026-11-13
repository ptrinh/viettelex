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

char16_t lastOf(const std::u16string& s) { return s.empty() ? 0 : s.back(); }

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
        if (!asyncLagged_ && opt_.log)
            opt_.log("in-place: this app's web store lags -> its web fields compose from now on");
        asyncLagged_ = true;
        return;
    }
    if (!contextFallback_ && opt_.log) opt_.log(why);
    contextFallback_ = true;
}

void TypingSession::note(const char* msg) const {
    if (opt_.log) opt_.log(msg);
}

// "<what> (read N, word M)": lengths only, never the text.
std::string TypingSession::staleNote(const char* what, size_t readLen) const {
    return std::string(what) + " (read " + std::to_string(readLen) + ", word " + std::to_string(shown_.size()) + ")";
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
    undoneSig_.clear();
    wordStartCtx_.clear();
    rewritePending_ = false;
    overflow_ = false;
    reopenArmed_ = false;
    retroUndo_.clear();
    retroOffer_.clear();
    runBreak();  // the caret may have moved: the text before it is unknown
}

void TypingSession::setCompositionOnlyContext(bool on) {
    compositionOnly_ = on;
    if (vtx_is_empty(engine_)) wordMode_ = effectiveMode();
}

void TypingSession::setHostDropsPassedKeys(bool on) {
    dropsPassedKeys_ = on;
    if (on) reopenArmed_ = false;
}

void TypingSession::setAsyncStore(bool on) {
    asyncStore_ = on;
    // A store of this app already lagged in another field (#139): do not pay the first
    // word again, compose from the first letter.
    if (on && asyncLagged_ && !preferComposition_) setPreferComposition(true);
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
    // An app that undoes / ignores the edit shows the word as it was (takeFieldUnreliable).
    undoneSig_ = oldShown;
}

size_t TypingSession::staleReadLen() const {
    size_t n = shown_.size();
    if (droppedSig_.size() > n) n = droppedSig_.size();
    if (undoneSig_.size() > n) n = undoneSig_.size();
    return n;
}

bool TypingSession::screenShowsUndone(const std::u16string& before) const {
    if (asyncStore_|| undoneSig_.empty() || undoneSig_ == shown_) return false;
    return before.size() >= undoneSig_.size() &&
           before.compare(before.size() - undoneSig_.size(), undoneSig_.size(), undoneSig_) == 0;
}

bool TypingSession::screenMidRewrite(const std::u16string& before, TextSink& sink) const {
    if (asyncStore_) return false;
    // Emptied, or everything selected (the insertion point is the selection START: the
    // field's start) — the first half of an app's select-all + replace / clear + insert.
    if (before.empty() || sink.hasSelection()) return true;
    // Part of the word back (an app restoring its text piece by piece): the screen ends with
    // a non-empty proper prefix of the word as it was before our replace, or as we left it.
    auto endsWithPrefixOf = [&](const std::u16string& w) {
        for (size_t n = 1; n < w.size(); ++n)
            if (before.size() >= n && before.compare(before.size() - n, n, w, 0, n) == 0) return true;
        return false;
    };
    return endsWithPrefixOf(undoneSig_) || endsWithPrefixOf(shown_);
}

void TypingSession::noteUndone() {
    if (!preferComposition_ && opt_.log)
        opt_.log("in-place: the field undid our last replace (it shows the word as before it) -> "
                 "word re-taken into a composition, composition for this field");
    preferComposition_ = true;
    fieldUnreliable_ = true;
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
        if (!asyncStore_) fieldUnreliable_ = true;  // a sync store: remember the control kind
    }
    return true;
}

void TypingSession::verifyScreen(TextSink& sink) {
    if (!wordActive() || wordMode_ != OutputMode::InPlace || sink.blind()) return;
    const bool preferred = preferComposition_;
    const std::u16string before = sink.textBeforeCaret(static_cast<int>(staleReadLen()));
    if (!screenStale(before)) {
        rewritePending_ = false;
        return;
    }
    if (screenShowsUndone(before)) {
        // The app undid our last replace (search-as-you-type re-setting its text): keep the
        // word — the next key re-takes it into a composition (handleWordKey).
        rewritePending_ = false;
        noteUndone();
        return;
    }
    if (screenMidRewrite(before, sink)) {
        // The field is half-way through putting its own text back (TSF delivers an app's
        // "set text" as several edits: emptied / all selected, then the text). Dropping the
        // word here lost the undo the next state shows (1.3.19, Word's Navigation search box
        // through the TIP: "đầu mối" still "đàu môi"). Decide on the finished text.
        if (!rewritePending_ && opt_.verboseLog) note("in-place: field mid-way through re-setting its text -> wait");
        rewritePending_ = true;
        return;
    }
    // An async store (Chromium) reports the page renderer round trips late, often with a
    // state OLDER than our own last edit: not a change of the word. Keep it; the next key
    // re-checks and, if the store is still behind, stops editing in place (handleWordKey).
    // Forgetting the word here made the next key start a "word" in the middle of one,
    // edited against the stale view (model: "trinhf" -> "triìn", the h lost).
    if (asyncStore_ && preferred == preferComposition_) return;
    note("in-place: the field changed around the word (edit outside the TIP) -> word dropped");
    reset();
}

void TypingSession::resetContext() {
    reset();
    contextFallback_ = false;
    compositionOnly_ = false;
    preferComposition_ = false;
    asyncStore_ = false;
    dropsPassedKeys_ = false;
    passedKeysReachApp_ = false;
    notTextField_ = false;
    compositionMustShow_ = false;
    emptyStoreHits_ = 0;
    storeMisreads_ = false;
    passingWord_ = false;
    if (engine_) vtx_reset_context(engine_);
}

void TypingSession::swapEngine(vtx_engine* e) {
    if (engine_) vtx_destroy(engine_);
    engine_ = e;
}

bool TypingSession::wantsKey(const KeyInput& k) const {
    if (!engine_ || notTextField_) return false;
    if (passingWord_ && k.kind == KeyKind::Char && isWordKey(k)) return false;  // see passingWord()
    switch (k.kind) {
        case KeyKind::Char:
            // Retro English: boundary characters declined here reach the engine through
            // noteKeyPassedBy() (no edit session for them).
            // A space right after a symbol key ("=>␣"): no word, but an expansion.
            // No word in progress: a key Telex does not transform ("#", "?", "/", digits)
            // is never claimed — the app gets the genuine key event, not one the TIP let
            // through or retyped (2026-11: Gmail's "#" = delete did nothing in V mode; a
            // web page's single-key shortcuts listen to keydown). An armed ⌫ re-open /
            // retro undo is disarmed by noteKeyPassedBy() instead.
            return isWordKey(k) || wordActive() || (isShortcutSpace(k.ch) && tokenCandidate());
        case KeyKind::Backspace:
            return wordActive() || retroUndo_.armed() ||
                   (opt_.reEditWord && reopenArmed_ && vtx_can_reopen_last_commit(engine_));
        case KeyKind::Boundary:
        case KeyKind::Navigation:
        case KeyKind::Chord:
            // Same: with no word, only a symbol shortcut key claims Enter / Tab (an armed
            // re-open / retro undo is disarmed by noteKeyPassedBy()).
            return wordActive() || (k.kind == KeyKind::Boundary && tokenCandidate());
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
    if (!engine_ || notTextField_) return false;
    if (passingWord_) {  // see passingWord(): its letters go to the app as typed
        if (k.kind == KeyKind::Char && isWordKey(k)) return false;
        if (k.kind != KeyKind::Modifier && k.kind != KeyKind::Other) passingWord_ = false;
    }
    switch (k.kind) {
        case KeyKind::Char:
            if (isWordKey(k)) return handleWordKey(k.ch, sink);
            return commitWord(sink, KeyKind::Char, k.ch);
        case KeyKind::Backspace:
            runBreak();
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
    if (passingWord_) {
        // The word in progress reaching the app as typed: its letters are no boundary.
        if ((k.kind == KeyKind::Char && isWordKey(k)) || k.kind == KeyKind::Modifier || k.kind == KeyKind::Other)
            return;
        passingWord_ = false;  // anything else ends that word
    }
    retroOffer_.clear();
    lastRetroWords_ = 0;
    // ⌫ re-opens the last word only right after its boundary: any other key disarms it
    // (wantsKey no longer claims a key just to disarm it). Shift / Caps Lock do not.
    if (k.kind != KeyKind::Modifier && k.kind != KeyKind::Other) reopenArmed_ = false;
    // Any other key drops the one-key undo (retro rewrite or boundary restore), and the
    // engine hears about every boundary character even with retro off: it also uses them
    // for glued separators ("my_var", "os.path", "100W").
    retroUndo_.clear();
    switch (k.kind) {
        case KeyKind::Char:
            vtx_note_boundary(engine_, k.ch != 0 && k.ch <= 0xFFFF ? k.ch : U'\n');
            runAppend(k.ch);  // "=" ">" of "=>": the app types them
            break;
        case KeyKind::Backspace:
        case KeyKind::Boundary:
        case KeyKind::Navigation:
        case KeyKind::Chord:
            vtx_note_boundary(engine_, U'\n');  // ends the phrase (the text may change)
            runBreak();
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
    int absorb = 0;  // units of an undone in-place word to pull into the composition
    if (!vtx_is_empty(engine_) && !sink.blind()) {
        // Our picture of the screen went stale (composition ended behind our back, the
        // app changed the text before the caret): start over rather than edit blindly.
        // A selection AFTER the caret (Chrome/Edge omnibox autocomplete suffix) is the
        // app's: it does not invalidate the word, which ends at the insertion point.
        bool stale;
        if (wordMode_ == OutputMode::Composition) {
            stale = !sink.compositionActive();
            if (stale) note("composition: ended outside the TIP -> word dropped, this key starts a new word");
        } else {
            const std::u16string before = sink.textBeforeCaret(static_cast<int>(staleReadLen()));
            stale = screenStale(before);
            // The field was seen re-setting its text after our replace (verifyScreen): it IS
            // a text field showing our edits — whatever it shows now is a change of the word,
            // never the empty / misreading-store evidence below.
            const bool afterRewrite = rewritePending_;
            rewritePending_ = false;
            if (!stale) emptyStoreHits_ = 0;  // the store shows our word: a text field after all
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
                        note("in-place (async store): view behind the page, key only appends -> word kept");
                        return false;
                    }
                    vtx_destroy(t);
                }
                // A key that needs an edit goes to the page as typed (in order, after the
                // keys still in flight): at worst one word without its accent, never a
                // letter deleted or misplaced.
                note(staleNote("in-place (async store): view behind the page, key needs an edit -> as typed, word dropped",
                               before.size()).c_str());
                reset();
                return false;
            }
            // The app undid our last replace (sync store: what it reads is the field): the
            // screen holds the word as it was before it. Pull exactly that into a composition
            // set to the whole word (this key included) — nothing lost — and compose this
            // field from now on (noteUndone). 2026-11, Word's Navigation search box.
            if (stale && screenShowsUndone(before)) {
                noteUndone();
                absorb = static_cast<int>(undoneSig_.size());
                undoneSig_.clear();
                wordMode_ = OutputMode::Composition;
                stale = false;
            }
            // The store does not show the letters we let through, the app's own window does
            // (Win10 Notepad's Edit with text in it, read through its transitory-extension
            // parent, 2026-11): the keys DID reach the app — the store misreads this field.
            // Composing there shows nowhere ("Vietnamese letters never appear"), and the
            // #134 path below would also type the letters already on screen a second time.
            // The word goes on as typed; the TIP leaves that store (storeMisreads).
            if (stale && afterRewrite)
                note(staleNote("in-place: the field re-set its text to something else -> word dropped, "
                               "this key starts a new word",
                               before.size()).c_str());
            else if (stale && !shown_.empty() && !dropsPassedKeys_ &&
                     sink.appTextEndsWith(shown_) == AppView::Shows) {
                if (!storeMisreads_ && opt_.log)
                    opt_.log("in-place: the store does not show the typed text, the app's window does -> "
                             "the store misreads this field, word goes on as typed");
                storeMisreads_ = true;
                reset();
                passingWord_ = true;
                return false;
            }
            // NOTHING before the caret although we just let letters through: the store
            // does not show the app's text. In-place can never work in this field — use
            // composition for the rest of it. (An async store — xterm.js' hidden
            // textarea — returned above.) This is an IMM32 app through CUAS (WinForms:
            // MISA SME, mintty): the letters we let through were claimed in
            // OnTestKeyDown, so the app never got them (#134: "first letter lost").
            // Keep the word and compose all of it, from this key on.
            if (stale && !afterRewrite && before.empty() && !shown_.empty() && passedKeysReachApp_ &&
                !dropsPassedKeys_) {
                // The app got the letters (a TSF-native store never drops them) but its store
                // shows none: the store is not this element's text. Composing would type into
                // nothing (WPF type-to-filter list: "markdown" -> nothing at all). This word
                // goes on as typed; a second such word in this focus = not a text field.
                if (++emptyStoreHits_ >= 2) {
                    notTextField_ = true;
                    if (opt_.log) opt_.log("in-place: the store never shows the keys the app gets -> not a text field, keys pass through");
                } else if (opt_.log) {
                    opt_.log("in-place: the store shows none of the typed keys although the app got them -> word as typed");
                }
                reset();
                return false;
            }
            if (stale && !afterRewrite && before.empty() && !shown_.empty()) {
                fallBack("in-place: the field shows none of the typed text -> composition for this field");
                if (!dropsPassedKeys_ && opt_.log)
                    opt_.log("in-place: letters let through never reached the app (IMM host) -> composing them");
                setHostDropsPassedKeys(true);
                wordMode_ = OutputMode::Composition;
                stale = false;
            }
            // The same IMM host, the caret after EXISTING text (2026-11, Edge's Save As: the
            // file name edited at its end, "read 1, word 1" on every key — no key ever typed):
            // the first letter of the word was let through and lost, the store shows exactly
            // what it showed before that letter. Not empty, so the branch above never saw it;
            // each next key dropped the word and was lost the same way. Same answer: keep the
            // word and compose all of it, this field composes from now on.
            if (stale && !afterRewrite && !before.empty() && shown_.size() == 1 && !dropsPassedKeys_ &&
                !passedKeysReachApp_ && !wordStartCtx_.empty() &&
                sink.textBeforeCaret(kWordStartCtx) == wordStartCtx_) {
                fallBack("in-place: the first letter never reached the field -> composition for this field");
                if (opt_.log)
                    opt_.log("in-place: letters let through never reached the app (IMM host) -> composing them");
                setHostDropsPassedKeys(true);
                wordMode_ = OutputMode::Composition;
                stale = false;
            }
            if (stale && !afterRewrite)
                note(staleNote("in-place: text before the caret no longer ends with the word -> word dropped, "
                               "this key starts a new word",
                               before.size()).c_str());
        }
        if (stale) reset();
    }
    droppedSig_.clear();
    if (vtx_is_empty(engine_)) {
        undoneSig_.clear();
        wordMode_ = effectiveMode();
        // What stands before the caret as this word starts — only where a letter let
        // through may be lost (an IMM host not yet proven, see "the first letter never
        // reached the field" above): one short read per word there, none elsewhere.
        wordStartCtx_.clear();
        if (wordMode_ == OutputMode::InPlace && !sink.blind() && !dropsPassedKeys_ && !passedKeysReachApp_ &&
            !asyncStore_ && !notTextField_)
            wordStartCtx_ = sink.textBeforeCaret(kWordStartCtx);
        if (wordMode_ == OutputMode::InPlace && !sink.blind() && !sink.canReadContext()) {
            fallBack("in-place: cannot read the text around the caret -> composition for this field");
            wordMode_ = OutputMode::Composition;
        }
    }
    const bool comp = wordMode_ == OutputMode::Composition;
    if (vtx_is_empty(engine_) && mayReEdit() && !sink.hasSelection() &&
        (!comp || !sink.compositionActive())) {
        if (tryReEdit(c, sink)) return true;
    } else if (opt_.verboseLog && vtx_is_empty(engine_) && opt_.reEditWord &&
               isDiacriticOnlyKey(c, (opt_.engineFlags & VTX_VNI) != 0) && !sink.blind() &&
               isWordCharForReEdit(lastOf(sink.textBeforeCaret(1)))) {
        // A tone key right after a word (no space) cannot reach back into it here.
        std::string why = "re-edit: a tone key right after a word, reaching back is off here (";
        why += asyncStore_ ? "async store" : compositionOnly_ ? "composition-only context"
                           : dropsPassedKeys_ ? "IMM host" : "selection / composition open";
        why += ") -> new word";
        note(why.c_str());
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
            undoneSig_.clear();
            return false;
        }
    }

    if (comp) {
        const bool starting = !sink.compositionActive();
        if (!sink.setComposition(now, starting ? absorb : 0, misspelled(engine_))) {
            note("composition: the field refused it -> word dropped, key as typed");
            reset();
            return false;
        }
        std::u16string held;
        if (starting && compositionMustShow_ && sink.compositionText(held) && held.empty()) {
            // The store took the composition but holds none of it: not this element's text
            // (session.h setCompositionMustShow). Nothing of it was ever visible.
            sink.endCompositionAsIs();
            notTextField_ = true;
            dropsPassedKeys_ = false;  // this key and the next go to the app as typed
            if (opt_.log) opt_.log("composition: the store holds none of it -> not a text field, keys pass through");
            reset();
            return false;
        }
        shown_ = now;
        return true;
    }

    // In-place.
    if (a.kind == VTX_PASSTHROUGH) {
        shown_ = now;  // the app inserts the key itself
        if (!undoneSig_.empty()) undoneSig_ += static_cast<char16_t>(c);
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
    // From here on the key IS a re-edit candidate: every refusal names its reason in the
    // debug log (#163 — silent exits made the feature look dead; lengths only, never text).
    // Caret inside a word ("việ|t"): seeding the left half would rewrite half a word.
    if (isWordCharForReEdit(sink.charAfterCaret())) {
        note("re-edit: skipped (caret inside a word) -> new word");
        return false;
    }
    std::u16string before = sink.textBeforeCaret(kMaxReEditWord + 1);
    size_t start = before.size();
    while (start > 0 && isWordCharForReEdit(before[start - 1])) --start;
    const size_t len = before.size() - start;
    if (len == 0) {
        note("re-edit: skipped (no word right before the caret) -> new word");
        return false;
    }
    // Word longer than what we read (no separator found) -> could be a longer token.
    if (len > static_cast<size_t>(kMaxReEditWord) ||
        (start == 0 && before.size() == static_cast<size_t>(kMaxReEditWord + 1))) {
        note("re-edit: skipped (word before the caret too long) -> new word");
        return false;
    }
    // Glued to a token opener ("5h", "#tag") -> not a standalone word.
    if (start > 0 && gluesShortcutToken(before[start - 1])) {
        note("re-edit: skipped (word glued to a token opener) -> new word");
        return false;
    }
    const std::u16string word = before.substr(start);

    vtx_engine* t = vtx_clone(engine_);
    if (!t) {
        note("re-edit: skipped (engine clone failed) -> new word");
        return false;
    }
    if (!vtx_seed(t, reinterpret_cast<const uint16_t*>(word.data()), static_cast<int32_t>(word.size()))) {
        vtx_destroy(t);
        note(("re-edit: the word before the caret does not round-trip (len " + std::to_string(len) + ") -> new word")
                 .c_str());
        return false;
    }
    vtx_action a;
    vtx_feed(t, c, &a);
    std::u16string now = composedOf(t);
    if (a.kind == VTX_PASSTHROUGH || now == word + static_cast<char16_t>(c)) {
        vtx_destroy(t);  // the key does not transform the word: ordinary new word
        note(("re-edit: skipped (the key does not change the word before the caret, len " + std::to_string(len) +
              ") -> new word")
                 .c_str());
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
        note("re-edit: the field refused the edit -> new word");
        return false;
    }
    swapEngine(t);
    shown_ = now;
    if (opt_.verboseLog)
        note(("re-edit: a tone key reached back into the word before the caret (len " + std::to_string(len) + ")")
                 .c_str());
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
        if (reopenArmed_ && vtx_can_reopen_last_commit(engine_)) {
            if (mayReadBack()) return tryReopen(sink);
            // #163: a candidate refused by policy names its reason (lengths / kinds only).
            if (opt_.reEditWord)
                note(compositionOnly_ ? "⌫ re-open: skipped (composition-only context: text not readable)"
                                      : "⌫ re-open: skipped (IMM host: text not readable)");
        }
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
        if (!undoneSig_.empty()) undoneSig_.pop_back();  // the app deletes it either way
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
    // Every exit names its reason in the debug log (#163; lengths only, never text).
    auto refuse = [&](vtx_engine* t, const char* why) {
        if (t) vtx_destroy(t);
        vtx_forget_last_commit(engine_);
        note(why);
        return false;
    };
    // A blind sink (the hook) reads nothing back: its own trail decides (reopenCommitted).
    if (sink.blind()) return refuse(nullptr, "⌫ re-open: skipped (blind sink: the hook's trail decides)");
    vtx_engine* t = vtx_clone(engine_);
    if (!t) return refuse(nullptr, "⌫ re-open: skipped (engine clone failed)");
    uint16_t buf[VTX_MAX_TEXT + 1];
    int32_t n = vtx_reopen_last_commit(t, buf, VTX_MAX_TEXT + 1);
    if (n <= 0) return refuse(t, "⌫ re-open: skipped (replay mismatch)");
    std::u16string word = toU16(buf, n);
    if (sink.hasSelection()) return refuse(t, "⌫ re-open: skipped (selection)");
    if (sink.compositionActive()) return refuse(t, "⌫ re-open: skipped (a composition is open)");
    std::u16string before = sink.textBeforeCaret(n + 1);
    // Screen must read exactly "<word><one boundary char>".
    if (before.size() != static_cast<size_t>(n) + 1 || before.compare(0, word.size(), word) != 0)
        return refuse(t, before.empty() ? "⌫ re-open: skipped (text before the caret unreadable)"
                                        : "⌫ re-open: skipped (text before the caret is not the word + boundary)");
    if (!sink.replaceBeforeCaret(before.substr(word.size()), std::u16string()))
        return refuse(t, "⌫ re-open: skipped (the field refused deleting the boundary)");
    if (wordMode_ == OutputMode::Composition && !sink.setComposition(word, n, misspelled(t))) {
        // Boundary char is gone but the composition failed: the word is plain text
        // now, which is exactly what a normal ⌫ would have left.
        vtx_destroy(t);
        reset();
        note("⌫ re-open: boundary deleted, the field refused the composition -> word left as text");
        return true;
    }
    swapEngine(t);
    shown_ = word;
    if (opt_.verboseLog)
        note(("⌫ re-open: " + std::to_string(n) + " chars back in the engine").c_str());
    return true;
}

bool TypingSession::reopenCommitted(const char16_t* raw, int rawLen, const char16_t* text, int textLen) {
    if (!engine_ || notTextField_ || overflow_ || !vtx_is_empty(engine_)) return false;
    if (rawLen <= 0 || textLen <= 0 || rawLen > VTX_MAX_TEXT || textLen > VTX_MAX_TEXT) return false;
    if (effectiveMode() != OutputMode::InPlace) return false;  // the word must be plain text on screen
    auto same = [](const uint16_t* a, int32_t n, const char16_t* b, int m) {
        if (n != m) return false;
        for (int i = 0; i < m; ++i)
            if (a[i] != static_cast<uint16_t>(b[i])) return false;
        return true;
    };
    uint16_t buf[VTX_MAX_TEXT + 1];
    uint16_t keys[VTX_MAX_TEXT + 1];
    vtx_engine* t = vtx_clone(engine_);
    if (!t) return false;
    bool ok = false;
    // The engine's own record of its last word also brings back that word's English context.
    if (vtx_can_reopen_last_commit(t)) {
        const int32_t n = vtx_reopen_last_commit(t, buf, VTX_MAX_TEXT + 1);
        ok = n > 0 && same(buf, n, text, textLen) &&
             same(keys, vtx_raw_keystrokes(t, keys, VTX_MAX_TEXT + 1), raw, rawLen);
        if (!ok) {
            vtx_destroy(t);
            t = vtx_clone(engine_);
            if (!t) return false;
        }
    }
    if (!ok) {
        // An older word (or the record is gone): replay its keys into a fresh word.
        vtx_reset(t);
        vtx_action a;
        for (int i = 0; i < rawLen && !vtx_is_overflowed(t); ++i) vtx_feed(t, raw[i], &a);
        ok = !vtx_is_overflowed(t) && same(buf, vtx_composed(t, buf, VTX_MAX_TEXT + 1), text, textLen) &&
             same(keys, vtx_raw_keystrokes(t, keys, VTX_MAX_TEXT + 1), raw, rawLen);
    }
    if (!ok) {
        vtx_destroy(t);
        return false;
    }
    swapEngine(t);
    shown_.assign(text, static_cast<size_t>(textLen));
    wordMode_ = OutputMode::InPlace;
    droppedSig_.clear();
    reopenArmed_ = false;
    retroUndo_.clear();
    retroOffer_.clear();
    runBreak();
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
        // Flip-back ("Đoán từ trùng theo tần suất": "His hửng" -> "hí hửng") undoes the
        // engine's own guess: applied automatically even in offer mode, and also at Enter /
        // Tab / Esc — before the key goes through (the app gets it after this edit).
        const bool flip = c.flip_back != 0;
        const bool offer = opt_.retroOffer && !flip;
        // Offer: a few more units, for the start of the first word in the hint ("H" of "Hí").
        const int want = static_cast<int>(expected.size()) + (offer ? 24 : 0);
        const std::u16string before = canRead ? sink.textBeforeCaret(want) : std::u16string();
        bool applied = false;
        // Only at a typed boundary: Enter / Tab may send the message or leave the field —
        // no rewrite behind the user's back (and no ⌫ to undo it).
        const retro::Apply d = printable || (flip && kind == KeyKind::Boundary)
                                   ? retro::decideApply(f, before, expected, c.backspaces)
                                   : retro::Apply::Unverifiable;
        switch (d) {
            case retro::Apply::Apply:
                if (offer) {
                    retroOffer_ = retro::makeOffer(before, expected, insert, static_cast<char16_t>(ch), c.words);
                    if (opt_.log) opt_.log(retroOffer_.empty() ? "retro: nothing to offer" : "retro: offered");
                    break;
                }
                applied = sink.replaceBeforeCaret(expected, insert);
                if (!applied && opt_.log) opt_.log("retro: the field refused the rewrite");
                if (applied && flip && opt_.log) opt_.log("retro: flip-back applied");
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
    forgetAfterRetro_ = false;
    const bool r = commitWordInner(sink, kind, ch);
    const bool printable = kind == KeyKind::Char && ch != 0 && ch <= 0xFFFF;
    // The boundary character lands after the word (or after the expansion).
    if (printable) runAppend(ch);
    else runBreak();
    if (retroOn()) finishRetro(sink, kind, ch);
    else vtx_note_boundary(engine_, printable ? ch : U'\n');   // glue: see noteKeyPassedBy
    if (forgetAfterRetro_) {
        forgetAfterRetro_ = false;
        vtx_forget_last_commit(engine_);
    }
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

void TypingSession::runAppend(char32_t c) {
    if (c == 0 || c > 0xFFFF) {
        runBreak();
        return;
    }
    runAppendText(std::u16string(1, static_cast<char16_t>(c)));
}

void TypingSession::runAppendText(const std::u16string& t) {
    for (char16_t c : t) {
        if (isShortcutSpace(c)) {  // an expansion / restored word may hold spaces too
            tokenRun_.clear();
            tokenAnchored_ = true;
        } else {
            tokenRun_.push_back(c);
        }
    }
    // Longer than any key (64): keep the tail, but where it starts is no longer known.
    constexpr size_t kMaxRun = 64;
    if (tokenRun_.size() > kMaxRun) {
        tokenRun_.erase(0, tokenRun_.size() - kMaxRun);
        tokenAnchored_ = false;
    }
}

bool TypingSession::tokenCandidate() const {
    return opt_.shortcuts && !tokenRun_.empty() && findTokenShortcut(*opt_.shortcuts, tokenRun_);
}

bool TypingSession::tryTokenShortcut(TextSink& sink) {
    if (!opt_.shortcuts || tokenRun_.empty()) return false;
    const bool word = !vtx_is_empty(engine_) && !overflow_;
    const std::u16string token = tokenRun_ + (word ? shown_ : std::u16string());
    std::u16string expansion;
    if (!findTokenShortcut(*opt_.shortcuts, token, &expansion)) return false;
    const bool comp = word && wordMode_ == OutputMode::Composition;
    if (sink.blind()) {
        // Nothing can be read back (the hook): only a run that provably starts after a
        // whitespace this session saw — never the tail of "x=>".
        if (!tokenAnchored_ || comp) return false;
    } else {
        // Read back: the run (and an in-place word) must be right before the caret, standing
        // alone (start of the text, or after whitespace) — "a->b", "x=>" never expand.
        if (compositionOnly_ || dropsPassedKeys_ || !sink.canReadContext() || sink.hasSelection()) return false;
        if (comp && !sink.compositionActive()) return false;
        const std::u16string& onScreen = comp ? tokenRun_ : token;
        const std::u16string before = sink.textBeforeCaret(static_cast<int>(onScreen.size()) + 1);
        if (before.size() < onScreen.size() ||
            before.compare(before.size() - onScreen.size(), onScreen.size(), onScreen) != 0)
            return false;
        if (before.size() > onScreen.size() && !isShortcutSpace(before.front())) return false;
    }
    if (comp) {
        // Commit the word as typed, then replace the whole run (committed text only).
        sink.endComposition(shown_);
        const bool ok = sink.replaceBeforeCaret(token, expansion);
        if (opt_.log) opt_.log(ok ? "shortcut: symbol key expanded" : "shortcut: the field refused the symbol key");
        reset();
        return true;  // the word is committed either way
    }
    if (!sink.replaceBeforeCaret(token, expansion)) {
        if (opt_.log) opt_.log("shortcut: the field refused the symbol key");
        return false;
    }
    if (opt_.log) opt_.log("shortcut: symbol key expanded");
    reset();
    return true;
}

bool TypingSession::commitWordInner(TextSink& sink, KeyKind kind, char32_t ch) {
    if (wordMode_ == OutputMode::InPlace && !overflow_ && !asyncStore_ && (!undoneSig_.empty() || rewritePending_) &&
        !vtx_is_empty(engine_) && !sink.blind()) {
        // The word's last replace may have been undone by the app after its key (the last
        // word of a search: "mối" left as "môi"). One read per word that had an edit; when
        // the screen shows the word as before that edit, re-take it into a composition and
        // commit it from there (noteUndone).
        const std::u16string before = sink.textBeforeCaret(static_cast<int>(staleReadLen()));
        const bool stale = screenStale(before);
        if (stale && screenShowsUndone(before)) {
            noteUndone();
            if (sink.setComposition(shown_, static_cast<int>(undoneSig_.size()), misspelled(engine_)))
                wordMode_ = OutputMode::Composition;
        } else if (stale && rewritePending_) {
            // Seen mid-rewrite, and the field now shows something else: what OnEndEdit used
            // to conclude at once — the word is gone, nothing to commit or expand.
            note(staleNote("in-place: the field re-set its text to something else -> word dropped", before.size())
                     .c_str());
            reset();
            return false;
        }
        rewritePending_ = false;
        undoneSig_.clear();
    }
    const bool comp = wordMode_ == OutputMode::Composition;
    const bool printable = kind == KeyKind::Char;
    // #134: a host that drops claimed keys gets the printable boundary inside the result
    // string ("word␣", one WM_IME_COMPOSITION) and the key is eaten — no retyped key that
    // could land after keys already queued behind it.
    const bool boundaryInResult = comp && dropsPassedKeys_ && printable && ch != 0 && ch <= 0xFFFF;
    const std::u16string boundary = boundaryInResult ? std::u16string(1, static_cast<char16_t>(ch)) : std::u16string();
    // Symbol / digit shortcut keys expand at whitespace only (space, Enter, Tab).
    const bool tokenTrigger = (printable && isShortcutSpace(ch)) || kind == KeyKind::Boundary;
    if (overflow_) {
        vtx_action a;
        vtx_commit_boundary(engine_, 0, &a);
        vtx_forget_last_commit(engine_);
        overflow_ = false;
        shown_.clear();
        reopenArmed_ = false;
        runBreak();  // the raw rest of the word: not tracked
        return false;
    }
    if (vtx_is_empty(engine_)) {
        if (comp && sink.compositionActive()) sink.endCompositionAsIs();
        reopenArmed_ = false;
        // "=>␣": no word at all — only the run of symbols before the caret.
        if (tokenTrigger) tryTokenShortcut(sink);
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
        std::u16string expansion;
        if (findShortcut(*opt_.shortcuts, shown_, raw, before, expansion)) {
            if (comp) sink.endComposition(expansion + boundary);
            else sink.replaceBeforeCaret(shown_, expansion);
            reset();
            return boundaryInResult;
        }
    }
    // A symbol key ending in the word in progress (":D", "->a" — run + word).
    if (tokenTrigger && tryTokenShortcut(sink)) return false;

    const std::u16string raw = printable ? rawOf(engine_) : std::u16string();
    std::u16string finalText;
    bool committed = true;
    // The character ending the word: an apostrophe keeps an English contraction stem
    // ("doesn't", not "doén't"). 0 = not a typed character.
    const uint32_t endChar = printable ? static_cast<uint32_t>(ch) : 0;
    if (comp) {
        uint16_t buf[VTX_MAX_TEXT + 1];
        int32_t n = vtx_commit_text_before(engine_, opt_.autoRestore ? 1 : 0, endChar, buf, VTX_MAX_TEXT + 1);
        finalText = toU16(buf, n);
        sink.endComposition(finalText + boundary);
    } else {
        vtx_action a;
        vtx_commit_boundary_before(engine_, opt_.autoRestore ? 1 : 0, endChar, &a);
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
    if (committed) runAppendText(finalText);
    else runBreak();
    if (committed && (printable || kind == KeyKind::Boundary)) lastWord_ = finalText;
    shown_.clear();
    undoneSig_.clear();
    // ⌫ re-open reads "<word><boundary>" back: impossible where keys are dropped (nothing
    // readable), and claiming the next key there would lose it.
    reopenArmed_ = printable && !dropsPassedKeys_;
    if (!printable) {
        // Enter / Tab / Esc: after finishRetro (commitWord) — it may still apply a flip-back.
        if (kind == KeyKind::Boundary) forgetAfterRetro_ = true;
        else vtx_forget_last_commit(engine_);
    }
    return boundaryInResult;
}

}  // namespace vtx
