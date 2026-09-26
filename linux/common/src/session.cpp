// session.cpp — see session.h. Behaviour is ported from the macOS controller
// (App/Sources/TelexInputController.swift): the marked-text path maps to Preedit, the
// in-place path to Surrounding.
#include "viettelex/session.h"

#include "telexcore.h"

#include <cstring>

namespace viettelex {

namespace {

size_t utf8Chars(const std::string &s) {
    size_t n = 0;
    for (unsigned char c : s)
        if ((c & 0xc0) != 0x80) ++n;
    return n;
}

std::string encode(uint32_t cp) {
    std::string o;
    if (cp < 0x80) o += char(cp);
    else if (cp < 0x800) { o += char(0xc0 | (cp >> 6)); o += char(0x80 | (cp & 0x3f)); }
    else if (cp < 0x10000) {
        o += char(0xe0 | (cp >> 12)); o += char(0x80 | ((cp >> 6) & 0x3f)); o += char(0x80 | (cp & 0x3f));
    } else {
        o += char(0xf0 | (cp >> 18)); o += char(0x80 | ((cp >> 12) & 0x3f));
        o += char(0x80 | ((cp >> 6) & 0x3f)); o += char(0x80 | (cp & 0x3f));
    }
    return o;
}

// Removes the last UTF-8 character of s into `last`; false if s is empty.
bool popChar(std::string &s, std::string &last) {
    if (s.empty()) return false;
    size_t i = s.size() - 1;
    while (i > 0 && (static_cast<unsigned char>(s[i]) & 0xc0) == 0x80) --i;
    last = s.substr(i);
    s.resize(i);
    return true;
}

uint32_t decodeOne(const std::string &c) {
    unsigned char b = c[0];
    uint32_t cp;
    size_t n;
    if (b < 0x80) return b;
    if ((b >> 5) == 6) { cp = b & 0x1f; n = 2; }
    else if ((b >> 4) == 14) { cp = b & 0x0f; n = 3; }
    else { cp = b & 0x07; n = 4; }
    for (size_t k = 1; k < n && k < c.size(); ++k) cp = (cp << 6) | (c[k] & 0x3f);
    return cp;
}

bool isAsciiLetter(uint32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool isDigit(uint32_t c) { return c >= '0' && c <= '9'; }
bool isBracket(uint32_t c) { return c == '[' || c == ']' || c == '{' || c == '}' || c == '(' || c == ')'; }
bool isBracketVowelKey(uint32_t c) { return c == '[' || c == ']' || c == '{' || c == '}'; }
// TelexInputController.gluesShortcutToken — #82 số, #87 / # @
bool gluesShortcutToken(uint32_t c) { return isDigit(c) || c == '/' || c == '#' || c == '@'; }

// A letter a Vietnamese word on screen can contain (for re-edit's trailing-word scan).
bool isWordLetter(uint32_t c) {
    return isAsciiLetter(c) || (c >= 0xc0 && c <= 0x24f && c != 0xd7 && c != 0xf7) ||
           (c >= 0x1ea0 && c <= 0x1ef9);
}

// TelexInputController.isDiacriticOnlyKey
bool isDiacriticOnlyKey(uint32_t c, bool vni) {
    if (vni) return isDigit(c);
    switch (c | 0x20) {
    case 's': case 'f': case 'r': case 'x': case 'j': case 'z': case 'w': return true;
    default: return false;
    }
}

bool isNewlineKey(uint32_t k) { return k == ks::Return || k == ks::KP_Enter; }

// Surrounding-mode edit. A delete with nothing to insert is followed by an empty commit:
// Wayland text-input-v3 applies delete_surrounding_text only together with a commit
// (Keyman engine.c apply_changes).
void replaceBeforeCursor(InputContext &ic, int backspaces, const std::string &insert) {
    if (backspaces > 0) ic.deleteBeforeCursor(backspaces);
    if (!insert.empty()) ic.commit(insert);
    else if (backspaces > 0) ic.commit("");
}

}  // namespace

Session::Session() : e_(vt_engine_new()) { applySettings(Settings()); }

Session::~Session() { vt_engine_free(e_); }

void Session::applySettings(const Settings &s) {
    vt_engine_set_flag(e_, VT_FLAG_FREE_MARKING, s.freeMarking);
    vt_engine_set_flag(e_, VT_FLAG_MODERN_TONE, s.modernTone);
    vt_engine_set_flag(e_, VT_FLAG_LIVE_SPELL_CHECK, s.spellCheck);
    vt_engine_set_flag(e_, VT_FLAG_SIMPLE_TELEX, s.simpleTelex);
    vt_engine_set_flag(e_, VT_FLAG_TEENCODE, s.teencode);
    vt_engine_set_flag(e_, VT_FLAG_QUICK_TELEX, s.quickTelex);
    vt_engine_set_flag(e_, VT_FLAG_BRACKET_VOWELS, s.bracketVowels);
    vt_engine_set_flag(e_, VT_FLAG_VNI, s.vni);
    vt_engine_set_flag(e_, VT_FLAG_CONTEXTUAL_ENGLISH, s.contextualEnglish);
    vt_engine_set_flag(e_, VT_FLAG_COLLISION_PREFERS_VIETNAMESE, s.collisionPrefersVietnamese);
    autoRestore_ = s.autoRestore;
    shortcutsEnabled_ = s.shortcutsEnabled;
    reEdit_ = s.reEditWord;
    vni_ = s.vni;
    bracketVowels_ = s.bracketVowels;
    shortcuts_ = s.shortcuts ? s.shortcuts : std::make_shared<ShortcutTable>();
    Hotkey hk;
    hotkeyValid_ = parseHotkey(s.toggleHotkey, hk);
    hotkeySym_ = hk.keysym;
    hotkeyMods_ = hk.mods;
}

void Session::setDisplayMode(DisplayMode m, InputContext &ic) {
    hasPendingMode_ = false;
    if (m == mode_) return;
    if (!vt_is_empty(e_)) {
        pendingMode_ = m;
        hasPendingMode_ = true;
        return;
    }
    finish(ic);
    mode_ = m;
}

void Session::applyPendingMode() {
    if (!hasPendingMode_ || !vt_is_empty(e_)) return;
    hasPendingMode_ = false;
    mode_ = pendingMode_;
}

void Session::setPassthrough(bool on, InputContext &ic) {
    if (on && !passthrough_) finish(ic);
    passthrough_ = on;
}

void Session::setVietnamese(bool on, InputContext &ic) {
    if (!on && vietnamese_) finish(ic);
    vietnamese_ = on;
}

bool Session::composing() const { return !vt_is_empty(e_); }

std::string Session::composed() const {
    char buf[256];
    size_t n = vt_composed(e_, buf, sizeof buf);
    return std::string(buf, n < sizeof buf ? n : sizeof buf - 1);
}

std::string Session::raw() const {
    char buf[256];
    size_t n = vt_raw(e_, buf, sizeof buf);
    return std::string(buf, n < sizeof buf ? n : sizeof buf - 1);
}

void Session::showPreedit(InputContext &ic) {
    std::string c = composed();
    if (c == preedit_) return;
    preedit_ = c;
    ic.setPreedit(c);
}

void Session::hidePreedit(InputContext &ic) {
    if (preedit_.empty()) return;
    preedit_.clear();
    ic.setPreedit("");
}

void Session::focusIn() {
    vt_reset_context(e_);
    caretMoved_ = true;
    lastWasBoundaryChar_ = false;
}

void Session::finish(InputContext &ic, bool commitPreedit) {
    if (mode_ == DisplayMode::Preedit && !vt_is_empty(e_)) {
        std::string text = composed();
        vt_reset(e_);
        // Commit BEFORE hiding the preedit: Messenger / Draft.js / Google Docs drop the
        // word when the composition is cleared first (bamboo engine_preedit.go).
        if (commitPreedit && !text.empty()) ic.commit(text);
        hidePreedit(ic);
    } else {
        vt_reset(e_);
        preedit_.clear();
    }
    gluedToDigit_ = false;
    caretMoved_ = true;
    lastWasBoundaryChar_ = false;
    applyPendingMode();
}

bool Session::isWordKey(uint32_t ch) const {
    return isAsciiLetter(ch) || (vni_ && isDigit(ch)) || (bracketVowels_ && isBracketVowelKey(ch));
}

// TelexInputController.boundary(): shortcut first (composed, then raw keys), then the
// auto-restore decision.
void Session::endWord(InputContext &ic, bool suppressRestore, bool allowShortcuts) {
    if (vt_is_empty(e_)) {
        vt_reset(e_);
        return;
    }
    std::string word = composed();
    std::string rawWord = raw();
    size_t onScreen = utf8Chars(word);
    if (allowShortcuts && shortcutsEnabled_ && !word.empty() && shortcuts_ &&
        (mode_ == DisplayMode::Preedit || !ic.hasSelection())) {
        auto it = shortcuts_->find(word);
        if (it == shortcuts_->end()) it = shortcuts_->find(rawWord);
        if (it != shortcuts_->end()) {
            std::string expansion = it->second;
            vt_reset(e_);
            if (mode_ == DisplayMode::Preedit) {
                if (!expansion.empty()) ic.commit(expansion);
                hidePreedit(ic);
            } else {
                replaceBeforeCursor(ic, int(onScreen), expansion);
            }
            return;
        }
    }
    // Surrounding + selection: a delete would hit the selection — leave the word as typed.
    if (mode_ == DisplayMode::Surrounding && ic.hasSelection()) {
        vt_reset(e_);
        return;
    }
    bool autoRestore = autoRestore_ && !suppressRestore;
    if (mode_ == DisplayMode::Preedit) {
        char buf[256];
        size_t n = vt_commit_text(e_, autoRestore, buf, sizeof buf);
        std::string text(buf, n < sizeof buf ? n : sizeof buf - 1);
        if (!text.empty()) ic.commit(text);
        hidePreedit(ic);
    } else {
        vt_action a;
        vt_commit(e_, autoRestore, &a);
        if (a.kind == VT_ACTION_REPLACE)
            replaceBeforeCursor(ic, a.backspaces, std::string(a.insert, size_t(a.insert_len > 0 ? a.insert_len : 0)));
    }
}

bool Session::processKey(const KeyEvent &ev, InputContext &ic) {
    if (ev.release) return false;
    if (ks::isModifierOnly(ev.keysym)) return false;
    applyPendingMode();

    // Vi/En toggle hotkey (Ctrl+Space by default).
    if (isToggleHotkey(ev)) {
        finish(ic);
        vietnamese_ = !vietnamese_;
        if (onToggle) onToggle(vietnamese_);
        return true;
    }

    if (!vietnamese_ || passthrough_) {
        if (!vt_is_empty(e_)) finish(ic);
        return false;
    }

    // Shortcut chords (Ctrl/Alt/Super + key): commit the word, hand the key to the app.
    if (ev.mods & (VT_MOD_CTRL | VT_MOD_ALT | VT_MOD_SUPER)) {
        endWord(ic, false, false);
        vt_forget_last_commit(e_);
        gluedToDigit_ = false;
        caretMoved_ = true;
        lastWasBoundaryChar_ = false;
        return false;
    }

    if (ev.keysym == ks::BackSpace) {
        bool r = handleBackspace(ic);
        lastWasBoundaryChar_ = false;
        return r;
    }

    uint32_t ch = ev.unicode;
    if (ch && isWordKey(ch)) {
        bool r = handleLetter(ch, ic);
        caretMoved_ = false;
        lastWasBoundaryChar_ = false;
        return r;
    }

    // Boundary: space, punctuation, digits (Telex), Enter/Tab/Esc, navigation, …
    bool printable = ch >= 0x20 && ch < 0x7f;
    bool newline = isNewlineKey(ev.keysym);
    endWord(ic, printable && isBracket(ch), !gluedToDigit_);
    if (newline) vt_reset_context(e_);   // a new line has no preceding word
    if (printable) {
        gluedToDigit_ = gluesShortcutToken(ch);
        lastWasBoundaryChar_ = true;
        caretMoved_ = false;
    } else {
        // Keys that do not leave exactly one character after the word (Enter, Tab,
        // arrows, Delete, non-ASCII) must not let ⌫ re-open it (issue #40).
        vt_forget_last_commit(e_);
        gluedToDigit_ = false;
        lastWasBoundaryChar_ = false;
        caretMoved_ = (ch == 0);  // navigation / Delete / Esc: caret may now sit after a word
    }
    return false;
}

bool Session::isToggleHotkey(const KeyEvent &ev) const {
    if (!hotkeyValid_ || ev.release) return false;
    uint32_t sym = ev.keysym;
    if (sym >= 'A' && sym <= 'Z') sym += 0x20;
    return sym == hotkeySym_ &&
           (ev.mods & (VT_MOD_CTRL | VT_MOD_ALT | VT_MOD_SHIFT | VT_MOD_SUPER)) == hotkeyMods_;
}

bool Session::handleLetter(uint32_t ch, InputContext &ic) {
    // RE-EDIT: a diacritic-only key right where the caret landed after a move, directly
    // after a word on screen, adds the diacritic to that word ("toan" + s → "toán").
    if (vt_is_empty(e_) && reEdit_ && surroundingEdits_ && caretMoved_ && isDiacriticOnlyKey(ch, vni_) &&
        !ic.hasSelection()) {
        std::string before;
        if (ic.textBeforeCursor(before)) {
            std::string word, c;
            size_t n = 0;
            bool tooLong = false;
            while (popChar(before, c)) {
                if (!isWordLetter(decodeOne(c))) break;
                word.insert(0, c);
                if (++n > 12) { tooLong = true; break; }
            }
            if (!word.empty() && !tooLong && vt_seed(e_, word.c_str())) {
                if (mode_ == DisplayMode::Preedit) {
                    ic.deleteBeforeCursor(int(n));
                    preedit_.clear();
                }
            }
        }
    }

    vt_action a;
    vt_feed(e_, ch, &a);
    if (a.kind == VT_ACTION_PASSTHROUGH && vt_is_overflowed(e_)) {
        // Word longer than the engine's 32 keys: never lose text. Preedit: finalise what
        // is composed and continue the tail as a fresh word (macOS commitAndPassThrough).
        if (mode_ == DisplayMode::Preedit) {
            std::string text = composed();
            vt_reset(e_);
            ic.commit(text + encode(ch));
            hidePreedit(ic);
        } else {
            ic.commit(encode(ch));
        }
        return true;
    }
    if (mode_ == DisplayMode::Preedit) {
        showPreedit(ic);
        return true;
    }
    switch (a.kind) {
    case VT_ACTION_PASSTHROUGH: ic.commit(encode(ch)); break;
    case VT_ACTION_REPLACE:
        if (a.backspaces > 0 && ic.hasSelection()) {
            // Never delete into a selection: type the key literally, start a new word.
            vt_reset(e_);
            ic.commit(encode(ch));
            break;
        }
        replaceBeforeCursor(ic, a.backspaces, std::string(a.insert, size_t(a.insert_len > 0 ? a.insert_len : 0)));
        break;
    default: break;
    }
    return true;
}

bool Session::handleBackspace(InputContext &ic) {
    if (vt_is_empty(e_)) {
        // ⌫ over the boundary right after a word re-opens it ("tháy" ␣ ⌫ a → "thấy",
        // issue #40) — only when the client's text proves the word is still there.
        if (vt_can_reopen(e_) && lastWasBoundaryChar_ && surroundingEdits_ && !ic.hasSelection()) {
            std::string before;
            if (ic.textBeforeCursor(before)) {
                char buf[256];
                long n = vt_reopen(e_, buf, sizeof buf);
                if (n > 0 && size_t(n) < sizeof buf) {
                    std::string word(buf, size_t(n)), last;
                    if (popChar(before, last) && before.size() >= word.size() &&
                        before.compare(before.size() - word.size(), word.size(), word) == 0) {
                        if (mode_ == DisplayMode::Surrounding) {
                            replaceBeforeCursor(ic, 1, std::string());
                        } else {
                            ic.deleteBeforeCursor(int(1 + utf8Chars(word)));
                            preedit_.clear();
                            showPreedit(ic);
                        }
                        gluedToDigit_ = false;
                        return true;
                    }
                }
                vt_reset(e_);
                return false;
            }
        }
        vt_forget_last_commit(e_);
        return false;
    }
    vt_action a;
    vt_backspace(e_, &a);
    if (mode_ == DisplayMode::Preedit) {
        if (vt_is_empty(e_)) {
            vt_reset(e_);
            hidePreedit(ic);
        } else {
            showPreedit(ic);
        }
        return true;
    }
    // Surrounding: .none / .passthrough / a pure one-char delete → the app's own ⌫.
    if (a.kind != VT_ACTION_REPLACE) return false;
    if (a.insert_len == 0 && a.backspaces == 1) return false;
    if (a.backspaces > 0 && ic.hasSelection()) {
        vt_reset(e_);  // the app's own ⌫ removes the selection
        return false;
    }
    replaceBeforeCursor(ic, a.backspaces, std::string(a.insert, size_t(a.insert_len > 0 ? a.insert_len : 0)));
    return true;
}

}  // namespace viettelex
