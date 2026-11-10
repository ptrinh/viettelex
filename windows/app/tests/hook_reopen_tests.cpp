// ⌫ re-open for the keyboard hook (core/hook_reopen.h): the hook's per-key glue around the
// TypingSession, replayed against a fake app screen that only the keys and the hook's
// injected edits change (nothing is ever read back, like SendInput).
#include <viettelex/vtx_engine.h>

#include <string>

#include "direct_policy.h"
#include "hook_reopen.h"
#include "keymap.h"
#include "session.h"
#include "settings.h"
#include "test.h"

using namespace vtx;
using namespace vtx::app;

namespace {

// An app's text field: text + caret. Keys the hook lets through are typed at the caret by
// the app; the hook's edits are VK_BACKs + Unicode text at the caret.
struct Screen {
    std::u16string text;
    size_t caret = 0;
    void insert(const std::u16string& t) {
        text.insert(caret, t);
        caret += t.size();
    }
    void backspace() {
        if (caret == 0) return;
        text.erase(caret - 1, 1);
        --caret;
    }
};

class InjectSink final : public TextSink {
public:
    explicit InjectSink(Screen& s) : s_(s) {}
    bool blind() override { return true; }
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) override {
        for (size_t i = 0; i < expect.size(); ++i) s_.backspace();
        s_.insert(insert);
        sent = true;
        return true;
    }
    bool compositionActive() override { return false; }
    bool setComposition(const std::u16string&, int, bool) override { return false; }
    void endComposition(const std::u16string&) override {}
    void endCompositionAsIs() override {}
    bool sent = false;

private:
    Screen& s_;
};

constexpr char kLeft = '\x01', kRight = '\x02', kHome = '\x03', kEnd = '\x04', kDelete = '\x05';
constexpr char kCtrlV = '\x06', kEnter = '\n', kTab = '\t', kEsc = '\x1b', kF2 = '\x07';

// The hook (hook_fallback.cpp keyboardProc / mouseProc / commands), minus Win32.
struct HookRig {
    Settings st;
    TypingSession s;
    ReopenTrail trail;
    Screen screen;
    bool english = false;  // Việt/Anh state of the foreground app
    int reopens = 0;

    explicit HookRig(bool vni = false) {
        st.vniMode = vni;
        configure();
        s.setOutputMode(OutputMode::InPlace);
    }
    void configure() {  // hook_fallback.cpp configureSession
        SessionOptions o;
        o.engineFlags = st.engineFlags() & ~static_cast<uint32_t>(VTX_RETRO_ENGLISH);
        o.autoRestore = st.autoRestore;
        o.reEditWord = false;
        o.shortcuts = &st.shortcuts;
        s.configure(o);
        trail.setEnabled(st.reEditWord);
        trail.invalidate();
    }
    // The app's own handling of a key that reached it.
    void appKey(const KeyInput& k, char c) {
        switch (k.kind) {
            case KeyKind::Char: screen.insert(std::u16string(1, static_cast<char16_t>(k.ch))); break;
            case KeyKind::Backspace: screen.backspace(); break;
            case KeyKind::Boundary:
                if (c == kEnter) screen.insert(u"\n");
                if (c == kTab) screen.insert(u"\t");
                break;
            case KeyKind::Navigation:
                if (c == kLeft && screen.caret) --screen.caret;
                if (c == kRight && screen.caret < screen.text.size()) ++screen.caret;
                if (c == kHome) screen.caret = 0;
                if (c == kEnd) screen.caret = screen.text.size();
                if (c == kDelete && screen.caret < screen.text.size()) screen.text.erase(screen.caret, 1);
                break;
            case KeyKind::Chord:
                if (c == kCtrlV) screen.insert(u"xyz");  // paste
                break;
            default: break;
        }
    }
    void send(const KeyInput& k, char c) {
        if (k.kind == KeyKind::Modifier || k.kind == KeyKind::Other) {
            if (k.kind == KeyKind::Other) trail.invalidate();
            return;
        }
        if (!s.wordActive() && english) {  // not typed by us
            trail.invalidate();
            appKey(k, c);
            return;
        }
        switch (trail.before(k, s)) {
            case ReopenTrail::Before::Reopened:
                ++reopens;
                appKey(k, c);
                return;
            case ReopenTrail::Before::Popped:
                s.noteKeyPassedBy(k);
                appKey(k, c);
                return;
            case ReopenTrail::Before::Normal: break;
        }
        if (!s.wantsKey(k)) {
            s.noteKeyPassedBy(k);
            trail.after(k, s, false, false, false);
            appKey(k, c);
            return;
        }
        InjectSink sink(screen);
        const bool eaten = s.handleKey(k, sink);
        if (!eaten) appKey(k, c);  // passed, or replayed at the end of the batch
        trail.after(k, s, true, eaten, sink.sent);
    }
    void key(char c) {
        KeyInput k;
        switch (c) {
            case '\b': k.kind = KeyKind::Backspace; break;
            case kEnter: case kTab: case kEsc: k.kind = KeyKind::Boundary; break;
            case kLeft: case kRight: case kHome: case kEnd: case kDelete: k.kind = KeyKind::Navigation; break;
            case kCtrlV: k.kind = KeyKind::Chord; break;
            case kF2: k.kind = KeyKind::Other; break;
            default: k.kind = KeyKind::Char; k.ch = static_cast<unsigned char>(c); break;
        }
        send(k, c);
    }
    void type(const char* keys) {
        for (const char* p = keys; *p; ++p) key(*p);
    }
    // A modifier pressed and released alone.
    void modifier(uint32_t vkCode) {
        if (modifierDropsTrail(vkCode)) trail.invalidate();
    }
    // mouseProc: a click (caret somewhere else, here: where it was).
    void click() {
        s.reset();
        trail.invalidate();
    }
    // kCmdForeground / applyWanted: another window or field, back again.
    void focusChange() {
        trail.invalidate();
        s.resetContext();
    }
    // Someone else's injected key (LLKHF_INJECTED): passes, the word is dropped.
    void foreignInjected(char16_t c) {
        s.reset();
        trail.invalidate();
        screen.insert(std::u16string(1, c));
    }
    std::string text() const { return utf16ToUtf8(screen.text); }
};

// What the same keys give when typed fresh (no ⌫ trick): the reopened word must behave alike.
std::string fresh(const char* keys, bool vni = false) {
    HookRig r(vni);
    r.type(keys);
    return r.text();
}

}  // namespace

TEST(hook_reopen_separators) {
    for (char32_t c : {U' ', U'.', U',', U';', U':', U'!', U'?'}) CHECK(isTrailSeparator(c));
    for (char32_t c : {U'(', U')', U'"', U'\'', U'-', U'1', U'a', U'\n', U'\t', U'`', U'~', U'^'})
        CHECK(!isTrailSeparator(c));
    for (uint32_t v : {vk::Menu, vk::LMenu, vk::RMenu, vk::LWin, vk::RWin}) CHECK(modifierDropsTrail(v));
    for (uint32_t v : {vk::Shift, vk::LShift, vk::RShift, vk::Control, vk::LControl, vk::RControl, vk::Capital})
        CHECK(!modifierDropsTrail(v));
}

// "toan␣ ⌫ s" -> "toán": the ⌫ deletes the space (the app does it), the word is back in the
// engine, the tone key edits it.
TEST(hook_reopen_basic) {
    HookRig r;
    r.type("toan ");
    CHECK_EQ(r.text(), std::string("toan "));
    CHECK_EQ(r.trail.words(), 1);
    r.type("\b");
    CHECK_EQ(r.reopens, 1);
    CHECK_EQ(r.text(), std::string("toan"));
    CHECK(r.s.wordActive());
    r.type("s");
    CHECK_EQ(r.text(), std::string("toán"));
    // Keeps editing like a word never left: change the tone, commit again, reopen again.
    r.type("f");
    CHECK_EQ(r.text(), fresh("toansf"));
    r.type(" \bx ");
    CHECK_EQ(r.text(), fresh("toansfx "));
    CHECK_EQ(r.reopens, 2);
    // Plain letters after a reopen continue the word.
    HookRig l;
    l.type("vie \betj");
    CHECK_EQ(l.text(), fresh("vieetj"));
    CHECK_EQ(l.text(), std::string("việt"));
}

TEST(hook_reopen_after_space_and_punctuation) {
    HookRig r;
    r.type("toan, ");
    CHECK_EQ(r.trail.separatorsAfterLast(), 2);
    r.type("\b");  // deletes " ": still one separator after the word
    CHECK_EQ(r.reopens, 0);
    CHECK_EQ(r.text(), std::string("toan,"));
    r.type("\b");  // deletes ",": the word is back
    CHECK_EQ(r.reopens, 1);
    r.type("s");
    CHECK_EQ(r.text(), std::string("toán"));

    for (const char* keys : {"toan. \b\bs", "toan! \b\bs", "toan? \b\bs", "toan: \b\bs", "toan; \b\bs"}) {
        HookRig p;
        p.type(keys);
        CHECK_EQ(p.text(), std::string("toán"));
    }
    // A punctuation key right after the word, no space.
    HookRig q;
    q.type("toan.\bs");
    CHECK_EQ(q.text(), std::string("toán"));
    // More separators than the trail keeps: not followed.
    HookRig m;
    m.type("toan.... \b\b\b\b\bs");
    CHECK_EQ(m.reopens, 0);
    CHECK_EQ(m.text(), std::string("toans"));
    // A separator the trail does not follow (brackets, quotes: auto-paired / dead keys).
    for (const char* keys : {"toan( \b\bs", "toan\" \b\bs", "toan' \b\bs", "toan1 \b\bs"}) {
        HookRig n;
        n.type(keys);
        CHECK_EQ(n.reopens, 0);
        CHECK_EQ(n.text(), std::string("toans"));
    }
}

// ⌫ past the start of the reopened word walks into the word before it; past the first word
// the trail knows nothing more and ⌫ is a plain ⌫.
TEST(hook_reopen_backspace_past_word_start) {
    HookRig r;
    r.type("toan viet ");
    r.type("\b");  // reopens "viet"
    CHECK_EQ(r.reopens, 1);
    r.type("\b\b\b\b");  // erases it letter by letter
    CHECK_EQ(r.text(), std::string("toan "));
    CHECK(!r.s.wordActive());
    r.type("\b");  // the space after "toan": reopens it
    CHECK_EQ(r.reopens, 2);
    r.type("s");
    CHECK_EQ(r.text(), std::string("toán"));

    // Erase the first word too: what is before it is unknown — no more reopening.
    HookRig f;
    f.screen.insert(u"ab");  // text that was there before the hook saw anything
    f.type("toan ");
    f.type("\b\b\b\b\b");  // space (reopen), then n a o t
    CHECK_EQ(f.text(), std::string("ab"));
    f.type("\bs");  // a plain ⌫ deletes "b"
    CHECK_EQ(f.reopens, 1);
    CHECK_EQ(f.text(), std::string("as"));

    // Partly erased reopened word: same result as typing what is left.
    HookRig p;
    p.type("toan \b\bs");
    CHECK_EQ(p.text(), fresh("toas"));

    // A new word typed after the separator and erased again: back after the separator.
    HookRig n;
    n.type("toan ab\b\b\bs");
    CHECK_EQ(n.text(), std::string("toán"));
    CHECK_EQ(n.reopens, 1);

    // Only the last kMaxWords words are kept.
    HookRig w;
    w.type("mot hai ba bon ");
    CHECK_EQ(w.trail.words(), ReopenTrail::kMaxWords);
}

// Each uncertain event in between drops the trail: the ⌫ is a plain ⌫, the tone key a
// letter ("toans"), never an edit of characters the hook can no longer vouch for.
TEST(hook_reopen_invalidated_by_uncertainty) {
    struct Case {
        const char* name;
        void (*between)(HookRig&);
        const char* want;
    };
    const Case cases[] = {
        {"click", [](HookRig& r) { r.click(); }, "toans"},
        {"left+right arrows", [](HookRig& r) { r.type("\x01\x02"); }, "toans"},
        {"home+end", [](HookRig& r) { r.type("\x03\x04"); }, "toans"},
        {"delete key", [](HookRig& r) { r.type("\x05"); }, "toans"},
        {"focus change", [](HookRig& r) { r.focusChange(); }, "toans"},
        {"enter", [](HookRig& r) { r.type("\n\b"); }, "toans"},
        {"tab", [](HookRig& r) { r.type("\t\b"); }, "toans"},
        {"esc", [](HookRig& r) { r.type("\x1b"); }, "toans"},
        {"paste (ctrl+v)", [](HookRig& r) { r.type("\x06\b\b\b"); }, "toans"},
        {"alt alone", [](HookRig& r) { r.modifier(vk::LMenu); }, "toans"},
        {"win alone (start, win+space)", [](HookRig& r) { r.modifier(vk::LWin); }, "toans"},
        {"other key (F2)", [](HookRig& r) { r.type("\x07"); }, "toans"},
        {"foreign injected key", [](HookRig& r) { r.foreignInjected(u'q'); r.screen.backspace(); }, "toans"},
        {"english mode keys", [](HookRig& r) { r.english = true; r.type("x\b"); r.english = false; }, "toans"},
        {"settings change", [](HookRig& r) { r.configure(); }, "toans"},
    };
    for (const Case& c : cases) {
        HookRig r;
        r.type("toan ");
        c.between(r);
        r.type("\bs");
        if (r.text() != c.want) std::printf("  case: %s\n", c.name);
        CHECK_EQ(r.text(), std::string(c.want));
        CHECK_EQ(r.reopens, 0);
    }
    // Shift / Ctrl / Caps Lock alone keep it (Shift is how "!" "?" are typed).
    HookRig k;
    k.type("toan ");
    k.modifier(vk::LShift);
    k.modifier(vk::LControl);
    k.modifier(vk::Capital);
    k.type("\bs");
    CHECK_EQ(k.text(), std::string("toán"));
    // English mode toggled and back without typing anything: nothing changed, still reopens.
    HookRig e;
    e.type("toan ");
    e.english = true;
    e.english = false;
    e.type("\bs");
    CHECK_EQ(e.text(), std::string("toán"));
    // "Sửa dấu từ đã gõ" off: never.
    HookRig off;
    off.st.reEditWord = false;
    off.configure();
    off.type("toan \bs");
    CHECK_EQ(off.text(), std::string("toans"));
    CHECK_EQ(off.reopens, 0);
    CHECK(!off.trail.enabled());
}

// Words whose screen text is not what their keys compose (English restore, shortcut
// expansion) are never reopened.
TEST(hook_reopen_only_composed_words) {
    HookRig g;
    g.type("dduoc ");  // not a syllable: restored to the keys at the space
    CHECK_EQ(g.text(), std::string("dduoc "));
    g.type("\bs");
    CHECK_EQ(g.reopens, 0);
    CHECK_EQ(g.text(), std::string("dduocs"));
    // A word the engine already shows as typed while composing (eager English restore) IS
    // its keys' composition: reopening it gives what typing on would have.
    HookRig e;
    e.type("google \bs");
    CHECK_EQ(e.text(), fresh("googles"));
    HookRig k;
    k.st.shortcuts[u"ko"] = u"không";
    k.configure();
    k.type("ko ");
    CHECK_EQ(k.text(), std::string("không "));
    k.type("\bs");
    CHECK_EQ(k.reopens, 0);
    CHECK_EQ(k.text(), std::string("khôngs"));
}

TEST(hook_reopen_vni) {
    HookRig r(true);
    r.type("toan \b1");
    CHECK_EQ(r.reopens, 1);
    CHECK_EQ(r.text(), std::string("toán"));
    HookRig p(true);
    p.type("chao, \b\b2");
    CHECK_EQ(p.text(), fresh("chao2", true));
    CHECK_EQ(p.text(), std::string("chào"));
    // Not a syllable yet ("viêt" needs its tone): restored to the keys, never reopened.
    HookRig v(true);
    v.type("vie6t \b5");
    CHECK_EQ(v.reopens, 0);
    CHECK_EQ(v.text(), std::string("vie6t5"));
    // Walk back over two words.
    HookRig w(true);
    w.type("toan viet ");
    w.type("\b\b\b\b\b\b1");
    CHECK_EQ(w.reopens, 2);
    CHECK_EQ(w.text(), std::string("toán"));
    // Change the tone of the reopened word.
    HookRig t(true);
    t.type("toan1 \b2");
    CHECK_EQ(t.text(), fresh("toan12", true));
    // Invalidation works the same.
    HookRig c(true);
    c.type("toan ");
    c.click();
    c.type("\b1");
    CHECK_EQ(c.text(), std::string("toan1"));
}

// 2026-11 audit (portable build): "ba" in Notepad, Win, "w" in Start search typed one
// backspace + "ă" into the search box — kCmdForeground kept the word when the hook was
// already installed for the old window. Another window now drops the word and the context.
TEST(hook_foreground_switch_between_hooked_windows_starts_a_new_word) {
    const uintptr_t notepad = 0x1010, search = 0x2020;
    for (int fixed = 0; fixed < 2; ++fixed) {
        HookRig r;
        r.type("ba");
        CHECK_EQ(r.text(), std::string("ba"));
        r.modifier(0x5B);  // VK_LWIN
        const ForegroundUpdate up = foregroundUpdate(notepad, true, search);
        CHECK(up.resetWord && !up.keepArming);
        r.screen = Screen();  // the Start search box: empty
        if (fixed) {          // hook_fallback.cpp kCmdForeground
            r.s.reset();
            r.trail.invalidate();
            r.s.resetContext();
        }
        r.type("w");
        // Fixed: "w" starts a new word there (Telex: ư). The old bug: "ba" went on, the
        // hook sent backspaces + "ă" into the search box.
        if (fixed) CHECK_EQ(r.text(), std::string("ư"));
        else CHECK(r.text().find("ă") != std::string::npos);
    }
    // The same window (a mid-focus re-publish, a TIP handover): keep its state.
    const ForegroundUpdate same = foregroundUpdate(notepad, true, notepad);
    CHECK(!same.resetWord && same.keepArming);
    // Not hooked before: no arming to keep, nothing to drop in that window.
    const ForegroundUpdate first = foregroundUpdate(notepad, false, notepad);
    CHECK(!first.resetWord && !first.keepArming);
    CHECK(foregroundUpdate(0, false, notepad).resetWord);
}
