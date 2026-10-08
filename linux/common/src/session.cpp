// session.cpp — see session.h. Behaviour is ported from the macOS controller
// (App/Sources/TelexInputController.swift): the marked-text path maps to Preedit, the
// in-place path to Surrounding.
#include "viettelex/session.h"

#include "telexcore.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <ctime>
#include <vector>

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

bool endsWithBytes(const std::string &s, const std::string &suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// A combining mark (U+0300–U+036F): the host keeps the text decomposed (NFD).
bool isCombiningMark(uint32_t c) { return c >= 0x300 && c <= 0x36f; }

// Verify-before-delete: what the host reports right before the caret vs. `expected`, the
// text the Session put there. Byte-exact on purpose: deletes count characters, so an NFD
// host (same letters, more code points) is a mismatch, not a match.
//   Match    — the expected text is there.
//   Stale    — the host has not applied our latest commits yet: it ends with a strict prefix
//              of `expected` (or reports nothing at all). The IM channel is ordered, so a
//              delete sent now still lands after those commits — but nothing proves it.
//   Mismatch — anything else: the text was changed under us.
// Never waits for the host to catch up (fcitx5-lotus #487: sleeping in the key path).
// `expected` is one word (<= 32 keys): the prefix scan is a handful of short compares.
enum class Screen { Match, Stale, Mismatch };
Screen checkScreen(const std::string &before, const std::string &expected) {
    if (endsWithBytes(before, expected)) return Screen::Match;
    if (before.empty()) return Screen::Stale;
    size_t k = expected.size();
    while (k > 0) {
        --k;
        while (k > 0 && (static_cast<unsigned char>(expected[k]) & 0xc0) == 0x80) --k;
        if (k > 0 && before.size() >= k && before.compare(before.size() - k, k, expected, 0, k) == 0)
            return Screen::Stale;
    }
    return Screen::Mismatch;
}

}  // namespace

bool InputContext::textBeforeCursorTail(size_t maxChars, std::string &out) {
    if (!textBeforeCursor(out)) return false;
    size_t i = out.size();
    for (size_t n = 0; i > 0 && n < maxChars; ++n) {
        --i;
        while (i > 0 && (static_cast<unsigned char>(out[i]) & 0xc0) == 0x80) --i;
    }
    out.erase(0, i);
    return true;
}

Session::Session() : e_(vt_engine_new()) {
    nowMs_ = [] {
        using namespace std::chrono;
        return int64_t(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
    };
    applySettings(Settings());
}

void Session::distrust() {
    if (distrusted_) return;
    distrusted_ = true;
    surroundingEdits_ = false;
    ackDrop();
    if (mode_ == DisplayMode::Surrounding) {
        // Callers have just dropped the word (vt_reset): switch now, else at the word's end.
        pendingMode_ = DisplayMode::Preedit;
        hasPendingMode_ = true;
        applyPendingMode();
    } else if (hasPendingMode_ && pendingMode_ == DisplayMode::Surrounding) {
        pendingMode_ = DisplayMode::Preedit;
    }
}

bool Session::inPlaceAllowed(InputContext &ic, const std::string &expected) {
    if (mode_ != DisplayMode::Surrounding || expected.empty()) return true;
    // Key edits not shown yet, but everything the host shows is one of the states our
    // ordered operations pass through (checkKeyEdit, this key event): BackSpaces sent now
    // land after them.
    if (deleteWithKeys_ && ackLagging_) return true;
    // Key edits keep a trail of what was typed before the word too: a host still behind the
    // boundary ("việt" shown, "việt l" typed) is then recognised as lagging, not as wrong.
    const std::string &want = deleteWithKeys_ && endsWithBytes(ackTrail_, expected) ? ackTrail_ : expected;
    std::string before;
    // A host that reports nothing cannot be checked: as before (Surrounding is only chosen
    // where the text was proven).
    if (!ic.textBeforeCursorTail(utf8Chars(want), before)) return true;
    if (checkScreen(before, want) != Screen::Mismatch) return true;  // Stale: ordered channel
    distrust();
    return false;
}

void Session::replace(InputContext &ic, int backspaces, const std::string &insert, const std::string &base) {
    if (mode_ == DisplayMode::Direct) {
        if (backspaces > 0 || !insert.empty()) ic.directReplace(backspaces, insert);
    } else {
        replaceBeforeCursor(ic, backspaces, insert, base);
    }
}

// Surrounding-mode edit. A delete with nothing to insert is followed by an empty commit:
// Wayland text-input-v3 applies delete_surrounding_text only together with a commit
// (Keyman engine.c apply_changes). Key edits need no such commit.
void Session::replaceBeforeCursor(InputContext &ic, int backspaces, const std::string &insert,
                                  const std::string &base) {
    if (deleteWithKeys_ && mode_ == DisplayMode::Surrounding) {
        if (backspaces > 0) ic.forwardBackspaces(backspaces);
        if (!insert.empty()) ic.commit(insert);
        if (backspaces > 0) ackArm(base, backspaces, insert);
        else if (!insert.empty()) ackAppend(insert);
        return;
    }
    if (backspaces > 0) ic.deleteBeforeCursor(backspaces);
    if (!insert.empty()) ic.commit(insert);
    else if (backspaces > 0) ic.commit("");
}

// MARK: - key-edit confirmation ([experimental] no_underline = "forward-keys")

namespace {
constexpr size_t kAckKeepChars = 48;  // a word + its boundary + the next word, more than enough
constexpr size_t kAckMaxStates = 16;  // a host lagging further than this is not followed
constexpr size_t kAckContext = 8;     // host text kept before our own, once confirmed

// Keeps the last kAckKeepChars characters; false when something was cut.
bool keepTail(std::string &s) {
    if (utf8Chars(s) <= kAckKeepChars) return true;
    size_t i = s.size();
    for (size_t n = 0; i > 0 && n < kAckKeepChars; ++n) {
        --i;
        while (i > 0 && (static_cast<unsigned char>(s[i]) & 0xc0) == 0x80) --i;
    }
    s.erase(0, i);
    return false;
}
}  // namespace

bool Session::tracking() const { return deleteWithKeys_ && mode_ == DisplayMode::Surrounding; }

void Session::ackTrim() {
    if (!keepTail(ackTrail_)) ackWhole_ = false;
}

void Session::ackPushTrail() {
    // "" would match any host text: an empty trail is simply not a state.
    if (ackTrail_.empty() || (!ackStates_.empty() && ackStates_.back() == ackTrail_)) return;
    ackStates_.push_back(ackTrail_);
    if (ackStates_.size() > kAckMaxStates) ackStates_.erase(ackStates_.begin());
}

void Session::ackArm(const std::string &base, int backspaces, const std::string &insert) {
    // The trail lost track of what is before the caret (caret moved mid-word…): restart from
    // the word itself, unanchored.
    if (!endsWithBytes(ackTrail_, base)) {
        ackStates_.clear();
        ackTrail_ = base;
        ackAnchored_ = ackWhole_ = ackSeeded_ = false;  // the seed was for another start
    }
    ackPushTrail();  // the host may not have applied this edit yet
    if (!ackPending_) {
        ackPending_ = true;
        ackSinceMs_ = nowMs_ ? nowMs_() : 0;
    }
    std::string last;
    for (int i = 0; i < backspaces; ++i) {
        if (!popChar(ackTrail_, last)) {  // deleting past what we know: the result is unknown
            ackDrop();
            return;
        }
        ackPushTrail();  // the app handles each BackSpace key on its own
    }
    ackTrail_ += insert;
    ackTrim();
    ackPushTrail();
}

void Session::ackAppend(const std::string &s) {
    if (!tracking() || s.empty()) return;
    if (ackStates_.empty()) ackPushTrail();
    ackTrail_ += s;
    ackTrim();
    ackPushTrail();
}

void Session::ackPop() {
    if (!tracking()) return;
    std::string last;
    if (!popChar(ackTrail_, last) || ackTrail_.empty()) {
        ackDrop();  // ⌫ past the text we know: nothing left to compare
        return;
    }
    ackPushTrail();
}

Session::Ack Session::checkKeyEdit(InputContext &ic) {
    // Nothing typed since the host last showed the trail, and it is anchored: nothing to do.
    if (ackStates_.size() < 2 && !ackPending_ && (ackAnchored_ || ackTrail_.empty())) return Ack::None;
    // Not anchored yet but seeded: every state is preceded by what the host showed when the
    // trail started. Without that, "yỳ" would pass for "ỳ" (the first edit's BackSpace lost)
    // and a lone " " would match the host's own space.
    const bool seeded = !ackAnchored_ && ackSeeded_;
    const std::string prefix = seeded ? ackSeed_ : std::string();
    // All the text there is before the caret is known: compare whole strings, not suffixes.
    const bool whole = ackAnchored_ ? ackWhole_ : seeded && ackSeedWhole_;
    size_t longest = utf8Chars(ackTrail_);  // an older state may be longer ("yfn" → "ỳ")
    for (const std::string &st : ackStates_) longest = std::max(longest, utf8Chars(st));
    const size_t asked = utf8Chars(prefix) + longest + kAckContext;
    std::string before;
    // A host that stops reporting (or reports nothing) cannot confirm: lagging until timeout.
    bool reported = ic.textBeforeCursorTail(asked, before) && !before.empty();
    auto shows = [&](const std::string &st) {
        std::string full = prefix + st;
        return whole ? before == full : endsWithBytes(before, full);
    };
    if (reported && shows(ackTrail_)) {
        // The host shows everything we sent: from here the trail also covers the host's own
        // text before it (a BackSpace lost there later shows up).
        ackTrail_ = before;
        ackWhole_ = utf8Chars(before) < asked;
        ackAnchored_ = true;
        ackSeeded_ = false;
        ackTrim();
        ackStates_.assign(1, ackTrail_);
        ackPending_ = false;
        return Ack::Confirmed;
    }
    // Lagging = the host shows exactly one of the states our ordered operations passed through
    // (every BackSpace, commit and app-typed key is one), or — seeded — none of them yet.
    // Unanchored and unseeded (the host reported nothing when the trail started), a strict
    // prefix of the oldest state also counts (checkScreen's Stale).
    bool consistent = !reported;
    for (size_t i = 0; reported && !consistent && i < ackStates_.size(); ++i) consistent = shows(ackStates_[i]);
    if (reported && !consistent && seeded) consistent = whole ? before == prefix : endsWithBytes(before, prefix);
    if (reported && !consistent && !ackAnchored_ && !seeded && !ackStates_.empty())
        consistent = checkScreen(before, ackStates_.front()) == Screen::Stale;
    if (!consistent) {
        if (ackPending_) return Ack::Failed;
        // Only plain typing since the last confirmation: the page changed its own text
        // (autocomplete, emoji…) — nothing of ours to blame. Start over.
        ackDrop();
        return Ack::None;
    }
    int64_t now = nowMs_ ? nowMs_() : 0;
    if (ackPending_ && now - ackSinceMs_ > kKeyEditAckTimeoutMs) return Ack::Failed;  // doubt
    return Ack::Lagging;
}

// The host's text is not what our key edits made (lost / doubled BackSpace, duplicated or
// dropped commit, the page rewrote it) or never caught up: stop editing in place for this
// focus. The word being typed is left on screen as it is; the next keys compose in preedit.
void Session::failKeyEdit() {
    ackDrop();
    vt_reset(e_);
    preedit_.clear();
    distrust();
}

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
    underlineMisspelled_ = s.underlineMisspelled;
    shortcutsEnabled_ = s.shortcutsEnabled;
    reEdit_ = s.reEditWord;
    vni_ = s.vni;
    bracketVowels_ = s.bracketVowels;
    shortcuts_ = s.shortcuts ? s.shortcuts : std::make_shared<ShortcutTable>();
    Hotkey hk;
    hotkeyValid_ = parseHotkey(s.toggleHotkey, hk);
    hotkeySym_ = hk.keysym;
    hotkeyMods_ = hk.mods;
    Hotkey at;
    addTonesValid_ = parseHotkey(s.addTonesHotkey, at) &&
                     !(hotkeyValid_ && at.keysym == hotkeySym_ && at.mods == hotkeyMods_);
    addTonesSym_ = at.keysym;
    addTonesMods_ = at.mods;
    hintFlags_.math = s.mathResults;
    hintFlags_.number = s.numberChips;
    hintFlags_.typo = s.typoHints;
    hintFlags_.tones = s.toneHints;
    hintFlags_.date = s.dateHints;
    // TypoFixLogic.EngineFlags(bits:) order (Serve.swift) — the helper composes candidates
    // with the same engine settings as the typing engine.
    const bool bits[] = {s.freeMarking, s.modernTone,      s.spellCheck,        s.simpleTelex,
                         s.quickTelex,  s.vni,             s.bracketVowels,     s.contextualEnglish,
                         s.collisionPrefersVietnamese,      s.teencode};
    engineBits_.clear();
    for (bool b : bits) engineBits_ += b ? '1' : '0';
    updateHintsOn();
    if (!hintsOn_) tailReset();
}

// MARK: - caret suggestions (caret_hints.h)

namespace {
constexpr size_t kTailKeep = 320;  // ToneRunLogic.window
const char *const kUnknownHead = "\xef\xbf\xbc";  // U+FFFC: text before the tail is unknown

bool endsWith(const std::string &s, const std::string &suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// Byte offset of the last `n` characters of s (0 when s is shorter).
size_t lastCharsOffset(const std::string &s, size_t n) {
    size_t i = s.size();
    while (i > 0 && n > 0) {
        --i;
        while (i > 0 && (static_cast<unsigned char>(s[i]) & 0xc0) == 0x80) --i;
        --n;
    }
    return i;
}

bool isTailSpace(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
}  // namespace

void Session::setHintSink(std::function<void(const HintRequest &)> sink) {
    hintSink_ = std::move(sink);
    updateHintsOn();
    if (!hintsOn_) tailReset();
}

std::string Session::typedBefore() const {
    switch (tailHead_) {
    case TailHead::Start: return tail_;
    case TailHead::Newline: return "\n" + tail_;
    default: return kUnknownHead + tail_;
    }
}

void Session::tailReset() {
    tail_.clear();
    tailHead_ = TailHead::Unknown;
    tailSeeded_ = false;
    toneTracker_.reset();
}

void Session::tailAppend(const std::string &s) {
    tail_ += s;
    if (tail_.size() > kTailKeep * 4 || utf8Chars(tail_) > kTailKeep + 64) {
        tail_.erase(0, lastCharsOffset(tail_, kTailKeep));
        tailHead_ = TailHead::Unknown;
    }
}

void Session::tailPop(size_t chars) {
    if (utf8Chars(tail_) < chars) {
        // Deleting into text we never saw: what is before the caret is unknown now.
        tail_.clear();
        tailHead_ = TailHead::Unknown;
        return;
    }
    tail_.resize(lastCharsOffset(tail_, chars));
}

// First key after the caret moved: the text before it, when the client reports it reliably.
void Session::seedTail(InputContext &ic) {
    tailSeeded_ = true;
    tail_.clear();
    tailHead_ = TailHead::Unknown;
    std::string before;
    // Mid-word (hints just turned on): the word is not on screen as such — start blind.
    if (!vt_is_empty(e_) || mode_ == DisplayMode::Direct || !surroundingEdits_ || !ic.textBeforeCursor(before))
        return;
    if (utf8Chars(before) <= kTailKeep) {
        tail_ = before;
        tailHead_ = TailHead::Start;
    } else {
        tail_ = before.substr(lastCharsOffset(before, kTailKeep));
    }
}

void Session::requestHint(std::vector<std::string> fields, int delayMs) {
    if (!hintSink_) return;
    HintRequest r;
    r.line = hints::request(fields);
    r.delayMs = delayMs;
    r.gen = keyGen_->load();
    r.liveGen = keyGen_;
    hintSink_(r);
}

// A printable boundary (or Enter / Tab / navigation) was just handled: keep the typed tail
// in step with the screen, then fire the cheap triggers (MathHint.swift afterEquals /
// afterNumberSpace, CaretSuggestions.swift afterWord — same order: date, typo, tones).
void Session::afterBoundary(uint32_t ch, uint32_t keysym) {
    if (isNewlineKey(keysym)) {
        tail_.clear();
        tailHead_ = TailHead::Newline;
        tailSeeded_ = true;
        toneTracker_.reset();
        return;
    }
    if (ch == 0x1b || ch == 0x7f) return;  // Esc / Delete: nothing typed, caret stays
    if (ch < 0x20 || keysym == ks::Tab) {  // navigation, Tab (focus may move), other keys
        tailReset();
        return;
    }
    // The run just committed before this boundary, and the one before it (ShortcutTail.run).
    size_t end = tail_.size(), s = end;
    while (s > 0 && !isTailSpace(tail_[s - 1])) --s;
    std::string run = tail_.substr(s);
    size_t pe = s;
    while (pe > 0 && isTailSpace(tail_[pe - 1])) --pe;
    size_t ps = pe;
    while (ps > 0 && !isTailSpace(tail_[ps - 1])) --ps;
    std::string prevRun = tail_.substr(ps, pe - ps);
    std::string boundary = encode(ch);
    tailAppend(boundary);

    hints::ToneTrigger tt = hintFlags_.tones ? toneTracker_.feed(run, ch) : hints::ToneTrigger::None;
    // The text the helper sees is built only when a trigger fires.
    if (ch == '=') {
        if (hintFlags_.math) requestHint({"math", typedBefore()});
        return;
    }
    // Everything else replaces committed text: only where the Session may edit before the
    // caret (surrounding proven, or Direct's blind BackSpaces) — macOS `canReplace`.
    if (mode_ != DisplayMode::Direct && !surroundingEdits_) return;
    if (hintFlags_.number && hints::numberWorthChecking(ch, run, prevRun)) {
        requestHint({"number", typedBefore()});
        return;
    }
    if (hintFlags_.date && hints::dateCandidate(ch, prevRun, run)) {
        std::time_t t = std::time(nullptr);
        std::tm lt{};
        localtime_r(&t, &lt);
        requestHint({"date", typedBefore(), prevRun, run, boundary, std::to_string(lt.tm_year + 1900),
                     std::to_string(lt.tm_mon + 1), std::to_string(lt.tm_mday), std::to_string(lt.tm_hour),
                     std::to_string(lt.tm_min)});
        return;
    }
    if (hintFlags_.typo && lastEnded_.ended && !lastEnded_.raw.empty() && lastEnded_.text == run &&
        hints::typoWorthChecking(ch, lastEnded_.raw, run) && !rejectedTypos_.contains(run) &&
        // An unaccented syllable ("hoc" = học/hóc) is never a typo for TypoFixLogic (the
        // lexicon has a toned completion); skipping it here keeps it from masking Thêm dấu.
        !vt_is_unaccented_syllable(run.c_str())) {
        requestHint({"typo", typedBefore(), run, boundary, lastEnded_.raw, engineBits_});
        return;
    }
    if (tt != hints::ToneTrigger::None)
        requestHint({"tones", typedBefore()}, tt == hints::ToneTrigger::Pause ? 900 : 0);  // ToneRunLogic.pauseDelay
}

void Session::deliverHint(uint64_t gen, const CaretSuggestion &s, InputContext &ic) {
    if (!hintsOn_ || gen != keyGen_->load() || passthrough_ || !vietnamese_ || !vt_is_empty(e_)) return;
    if (!s.replace.empty() && mode_ != DisplayMode::Direct && !surroundingEdits_) return;
    if (!endsWith(tail_, s.replace)) return;  // the typed text moved on
    if (s.kind == CaretSuggestion::Kind::Tones && !declinedTones_.empty() &&
        s.replace.compare(0, declinedTones_.size(), declinedTones_) == 0)
        return;
    hint_ = s;
    ic.showHint(hints::label(s));
}

void Session::dismissHint(InputContext &ic) {
    if (!hint_) return;
    hint_.reset();
    ic.hideHint();
}

// Esc: sửa lỗi gõ ⇒ không gợi ý lại từ đó trong phiên; thêm dấu ⇒ không mời lại cụm bắt đầu
// bằng cụm vừa từ chối (CaretHint.decline).
void Session::declineHint(InputContext &ic) {
    if (!hint_) return;
    if (hint_->kind == CaretSuggestion::Kind::Typo) {
        std::string w = hint_->replace, last;
        popChar(w, last);  // drop the boundary
        rejectedTypos_.add(w);
    } else if (hint_->kind == CaretSuggestion::Kind::Tones) {
        declinedTones_ = hint_->replace;
    }
    dismissHint(ic);
}

// Tab (math: Enter too). False = the screen no longer matches: dismissed, key goes on.
bool Session::applyHint(InputContext &ic) {
    CaretSuggestion s = *hint_;
    dismissHint(ic);
    if (!s.replace.empty() && mode_ != DisplayMode::Direct) {
        // Read the screen back before replacing (macOS: like shortcuts / number chips).
        std::string before;
        if (ic.textBeforeCursor(before) && !endsWith(before, s.replace)) return false;
        if (ic.hasSelection()) return false;
    }
    size_t n = utf8Chars(s.replace);
    replace(ic, int(n), s.insert, s.replace);
    tailPop(n);
    tailAppend(s.insert);
    vt_forget_last_commit(e_);  // ⌫ must not re-open the word that was replaced
    lastWasBoundaryChar_ = false;
    lastEnded_ = EndedWord();
    toneTracker_.reset();
    return true;
}

void Session::setDisplayMode(DisplayMode m, InputContext &ic) {
    requestedMode_ = m;
    if (distrusted_ && m == DisplayMode::Surrounding) m = DisplayMode::Preedit;
    hasPendingMode_ = false;
    if (m == mode_) return;
    ackDrop();
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
    // Off = no validation call at all.
    const bool bad = underlineMisspelled_ && vt_has_spelling_error(e_, autoRestore_);
    if (c == preedit_ && bad == preeditMisspelled_) return;
    preedit_ = c;
    preeditMisspelled_ = bad;
    ic.setPreedit(c, bad);
}

void Session::hidePreedit(InputContext &ic) {
    if (preedit_.empty()) return;
    preedit_.clear();
    preeditMisspelled_ = false;
    ic.setPreedit("", false);
}

void Session::focusIn() {
    vt_reset_context(e_);
    if (distrusted_) {
        distrusted_ = false;
        surroundingEdits_ = requestedEdits_;
        if (requestedMode_ != mode_) {
            pendingMode_ = requestedMode_;
            hasPendingMode_ = true;
            applyPendingMode();
        }
    }
    ackDrop();
    hint_.reset();  // the frontend hid it on focus-out (finish)
    if (hintsOn_) keyGen_->fetch_add(1);
    tailReset();
    caretMoved_ = true;
    lastWasBoundaryChar_ = false;
}

void Session::finish(InputContext &ic, bool commitPreedit) {
    dismissHint(ic);
    if (hintsOn_) keyGen_->fetch_add(1);  // answers still on their way are stale now
    tailReset();
    ackDrop();  // the caret moved / focus left: nothing to compare any more
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

bool Session::selectionAtCaret(InputContext &ic) {
    if (selectionMemo_ < 0) selectionMemo_ = ic.selectionAtCaret() ? 1 : 0;
    return selectionMemo_ == 1;
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
    // What stays on screen for this word — the typed tail of caret suggestions.
    auto ended = [this](const std::string &text, const std::string &rawKeys) {
        if (!hintsOn_) return;
        lastEnded_.ended = true;
        lastEnded_.text = text;
        lastEnded_.raw = rawKeys;
        tailAppend(text);
    };
    if (allowShortcuts && shortcutsEnabled_ && !word.empty() && shortcuts_) {
        auto it = shortcuts_->find(word);
        if (it == shortcuts_->end()) it = shortcuts_->find(rawWord);
        // Surrounding deletes the word to expand it: never with a selection at the caret.
        if (it != shortcuts_->end() && (mode_ != DisplayMode::Surrounding ||
                                        (!selectionAtCaret(ic) && inPlaceAllowed(ic, word)))) {
            std::string expansion = it->second;
            vt_reset(e_);
            ended(expansion, std::string());
            if (mode_ == DisplayMode::Preedit) {
                if (!expansion.empty()) ic.commit(expansion);
                hidePreedit(ic);
            } else {
                replace(ic, int(onScreen), expansion, word);
            }
            return;
        }
    }
    bool autoRestore = autoRestore_ && !suppressRestore;
    if (mode_ == DisplayMode::Preedit) {
        char buf[256];
        size_t n = vt_commit_text(e_, autoRestore, buf, sizeof buf);
        std::string text(buf, n < sizeof buf ? n : sizeof buf - 1);
        if (!text.empty()) ic.commit(text);
        hidePreedit(ic);
        ended(text, rawWord);
    } else {
        std::string finalText;
        if (hintsOn_) {
            char buf[256];
            size_t n = vt_peek(e_, autoRestore, buf, sizeof buf);
            finalText.assign(buf, n < sizeof buf ? n : sizeof buf - 1);
        }
        vt_action a;
        vt_commit(e_, autoRestore, &a);
        // Auto-restore deletes the word: with a selection at the caret the delete would hit
        // the selection — leave the word as typed.
        if (mode_ == DisplayMode::Surrounding && a.kind == VT_ACTION_REPLACE && a.backspaces > 0 &&
            (selectionAtCaret(ic) || !inPlaceAllowed(ic, word))) {
            vt_reset(e_);
            ended(word, rawWord);
            return;
        }
        ended(finalText, rawWord);
        if (a.kind == VT_ACTION_REPLACE)
            replace(ic, a.backspaces, std::string(a.insert, size_t(a.insert_len > 0 ? a.insert_len : 0)), word);
    }
}

bool Session::processKey(const KeyEvent &ev, InputContext &ic) {
    if (ev.forwarded) return false;  // our own forwarded key: the app must get it untouched
    if (ev.release) return false;
    if (ks::isModifierOnly(ev.keysym)) return false;
    selectionMemo_ = -1;
    applyPendingMode();
    // Key edits ([experimental] no_underline): confirm the last ones before anything else.
    ackLagging_ = false;
    if (!ackStates_.empty() || ackPending_) {
        if (!tracking()) {
            ackDrop();
        } else {
            switch (checkKeyEdit(ic)) {
            case Ack::Failed: failKeyEdit(); break;
            case Ack::Lagging: ackLagging_ = true; break;
            default: break;
            }
        }
    }
    // A trail starts with this key: remember what the host shows before it (see checkKeyEdit).
    if (ackTrail_.empty() && !ackSeeded_ && tracking() && vietnamese_ && !passthrough_) {
        std::string before;
        if (ic.textBeforeCursorTail(kAckContext, before)) {
            ackSeed_ = before;
            ackSeedWhole_ = utf8Chars(before) < kAckContext;
            ackSeeded_ = true;
        }
    }

    // Caret suggestion showing: Tab applies (math: Enter too), Esc declines, any other key
    // dismisses it and is handled as usual (CaretHintLogic.action).
    if (hintsOn_) keyGen_->fetch_add(1);
    if (hint_) {
        switch (hints::keyAction(hint_->kind, ev.keysym, ev.mods)) {
        case hints::KeyAction::Accept:
            if (applyHint(ic)) return true;
            break;
        case hints::KeyAction::DismissConsume:
            declineHint(ic);
            return true;
        case hints::KeyAction::DismissPass:
            dismissHint(ic);
            break;
        }
    }

    // Vi/En toggle hotkey (Ctrl+Space by default).
    if (isToggleHotkey(ev)) {
        finish(ic);
        vietnamese_ = !vietnamese_;
        if (onToggle) onToggle(vietnamese_);
        return true;
    }

    if (!vietnamese_ || passthrough_) {
        ackDrop();
        if (!vt_is_empty(e_)) finish(ic);
        if (tailSeeded_) tailReset();
        return false;
    }
    if (hintsOn_ && !tailSeeded_) seedTail(ic);
    lastEnded_.ended = false;

    // Shortcut chords (Ctrl/Alt/Super + key): commit the word, hand the key to the app.
    if (ev.mods & (VT_MOD_CTRL | VT_MOD_ALT | VT_MOD_SUPER)) {
        endWord(ic, false, false);
        ackDrop();  // Ctrl+V / Ctrl+Z / Ctrl+left: the text before the caret is unknown
        vt_forget_last_commit(e_);
        if (hintsOn_) tailReset();  // Ctrl+V / Ctrl+Z / Ctrl+←: the text before the caret is unknown
        gluedToDigit_ = false;
        caretMoved_ = true;
        lastWasBoundaryChar_ = false;
        return false;
    }

    if (ev.keysym == ks::BackSpace) {
        bool r = handleBackspace(ic);
        if (!r) ackPop();  // the app's own BackSpace removes one character
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
    if (hintsOn_) afterBoundary(ch, ev.keysym);
    if (printable && mode_ == DisplayMode::Surrounding) ackAppend(encode(ch));  // the app types it
    else ackDrop();
    if (printable) {
        gluedToDigit_ = gluesShortcutToken(ch);
        lastWasBoundaryChar_ = true;
        lastBoundary_ = char(ch);
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

bool Session::isAddTonesHotkey(const KeyEvent &ev) const {
    if (!addTonesValid_ || ev.release || ev.forwarded) return false;
    uint32_t sym = ev.keysym;
    if (sym >= 'A' && sym <= 'Z') sym += 0x20;
    return sym == addTonesSym_ &&
           (ev.mods & (VT_MOD_CTRL | VT_MOD_ALT | VT_MOD_SHIFT | VT_MOD_SUPER)) == addTonesMods_;
}

bool Session::handleLetter(uint32_t ch, InputContext &ic) {
    // RE-EDIT: a diacritic-only key right where the caret landed after a move, directly
    // after a word on screen, adds the diacritic to that word ("toan" + s → "toán").
    // Never with a selection at the caret (Ctrl+A / double-click, then a tone key): the key
    // replaces the selection like any letter — the delete would eat the wrong text. Asked
    // last, only when a word really sits before the caret.
    if (vt_is_empty(e_) && reEdit_ && surroundingEdits_ && caretMoved_ && isDiacriticOnlyKey(ch, vni_) &&
        !ic.hasSelection()) {
        std::string before;
        if (ic.textBeforeCursorTail(14, before)) {
            std::string word, c;
            size_t n = 0;
            bool tooLong = false, decomposed = false;
            while (popChar(before, c)) {
                uint32_t cp = decodeOne(c);
                if (!isWordLetter(cp)) {
                    // NFD host ("toa" U+0300 "n"): the scan would stop inside the word and the
                    // delete count (in characters) would not match what is shown.
                    decomposed = isCombiningMark(cp);
                    break;
                }
                word.insert(0, c);
                if (++n > 12) { tooLong = true; break; }
            }
            if (decomposed) {
                distrust();
            } else if (!word.empty() && !tooLong && !selectionAtCaret(ic) && vt_seed(e_, word.c_str())) {
                if (hintsOn_) tailPop(n);  // the word is being edited again (back in the engine)
                if (mode_ == DisplayMode::Preedit) {
                    ic.deleteBeforeCursor(int(n));
                    preedit_.clear();
                }
            }
        }
    }

    // The word as it is on screen right now (Surrounding: what we committed), for
    // verify-before-delete. O(word), like showPreedit's per-key composed() in Preedit.
    std::string shown;
    if (mode_ == DisplayMode::Surrounding && !vt_is_empty(e_)) shown = composed();
    vt_action a;
    vt_feed(e_, ch, &a);
    if (a.kind == VT_ACTION_PASSTHROUGH && vt_is_overflowed(e_)) {
        if (hintsOn_) tailReset();
        // Word longer than the engine's 32 keys: never lose text. Preedit: finalise what
        // is composed and continue the tail as a fresh word (macOS commitAndPassThrough).
        if (mode_ == DisplayMode::Preedit) {
            std::string text = composed();
            vt_reset(e_);
            ic.commit(text + encode(ch));
            hidePreedit(ic);
        } else if (mode_ == DisplayMode::Direct) {
            ic.directReplace(0, encode(ch));
        } else {
            ic.commit(encode(ch));
            ackAppend(encode(ch));
        }
        return true;
    }
    if (mode_ == DisplayMode::Preedit) {
        showPreedit(ic);
        return true;
    }
    if (mode_ == DisplayMode::Direct) {
        // Blind: the engine's own record of the word is the only truth, no selection check
        // (a terminal has none) and no read-back. Even an unchanged letter goes through the
        // forwarded-key channel so it cannot overtake an earlier forwarded BackSpace.
        if (a.kind == VT_ACTION_PASSTHROUGH) ic.directReplace(0, encode(ch));
        else if (a.kind == VT_ACTION_REPLACE)
            replace(ic, a.backspaces, std::string(a.insert, size_t(a.insert_len > 0 ? a.insert_len : 0)),
                    std::string());
        return true;
    }
    switch (a.kind) {
    case VT_ACTION_PASSTHROUGH:
        ic.commit(encode(ch));
        ackAppend(encode(ch));
        break;
    case VT_ACTION_REPLACE:
        if (a.backspaces > 0 && (ic.hasSelection() || !inPlaceAllowed(ic, shown))) {
            // Never delete into a selection, nor text that is not what we typed (the Session
            // then composes in preedit): type the key literally, start a new word.
            vt_reset(e_);
            applyPendingMode();  // distrusted: this very key already goes on as preedit text
            if (hintsOn_ && distrusted_) tailReset();
            ackDrop();  // typed over a selection (or distrusted): nothing to compare
            ic.commit(encode(ch));
            break;
        }
        replaceBeforeCursor(ic, a.backspaces, std::string(a.insert, size_t(a.insert_len > 0 ? a.insert_len : 0)),
                            shown);
        break;
    default: break;
    }
    return true;
}

bool Session::handleBackspace(InputContext &ic) {
    if (vt_is_empty(e_)) {
        // ⌫ over the boundary right after a word re-opens it ("tháy" ␣ ⌫ a → "thấy",
        // issue #40) — only when the client's text proves the word is still there.
        // Verify-before-delete: the host must show exactly the word AND the boundary we
        // typed. Stale (our commit / the boundary not applied yet) → plain ⌫, no reopen;
        // anything else → plain ⌫ and the surrounding text is distrusted for this focus.
        if (vt_can_reopen(e_) && lastWasBoundaryChar_ && lastBoundary_ && surroundingEdits_ &&
            !ic.hasSelection()) {
            std::string before;
            if (ic.textBeforeCursorTail(64, before)) {
                char buf[256];
                long n = vt_reopen(e_, buf, sizeof buf);
                if (n > 0 && size_t(n) < sizeof buf) {
                    std::string word(buf, size_t(n));
                    Screen v = checkScreen(before, word + lastBoundary_);
                    if (v == Screen::Mismatch) distrust();
                    if (v == Screen::Match && !selectionAtCaret(ic)) {
                        if (hintsOn_) tailPop(1 + utf8Chars(word));  // boundary gone, word back in the engine
                        if (mode_ == DisplayMode::Surrounding) {
                            replaceBeforeCursor(ic, 1, std::string(), word + lastBoundary_);
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
                applyPendingMode();
                if (hintsOn_) tailPop(1);
                return false;
            }
        }
        vt_forget_last_commit(e_);
        if (hintsOn_) tailPop(1);  // the app's own ⌫ deletes one character
        return false;
    }
    std::string shown;
    if (mode_ == DisplayMode::Surrounding) shown = composed();
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
    // Surrounding / Direct: .none / .passthrough / a pure one-char delete → the app's own ⌫.
    if (a.kind != VT_ACTION_REPLACE) return false;
    if (a.insert_len == 0 && a.backspaces == 1) return false;
    if (mode_ == DisplayMode::Surrounding && a.backspaces > 0 &&
        (ic.hasSelection() || !inPlaceAllowed(ic, shown))) {
        vt_reset(e_);  // the app's own ⌫ removes the selection / one character
        applyPendingMode();
        return false;
    }
    replace(ic, a.backspaces, std::string(a.insert, size_t(a.insert_len > 0 ? a.insert_len : 0)), shown);
    return true;
}

}  // namespace viettelex
