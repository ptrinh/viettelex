// WPF list (1.3.16): the hook takes over the word the TIP let through as typed
// (core/word_adopt.h + ime/core/typed_word.h). A fake One Commander filter: the keys that
// reach the app are typed at the end, ⌫ deletes one character; the hook's edits are
// backspaces + Unicode text. Nothing is ever read back (like SendInput).
#include <viettelex/vtx_engine.h>

#include <string>

#include "direct_policy.h"
#include "keymap.h"
#include "session.h"
#include "settings.h"
#include "test.h"
#include "typed_word.h"
#include "word_adopt.h"

using namespace vtx;
using namespace vtx::app;

namespace {

constexpr char kLeft = '\x01', kEnter = '\n', kCtrlA = '\x06';

class FilterSink final : public TextSink {
public:
    explicit FilterSink(std::u16string& t) : t_(t) {}
    bool blind() override { return true; }
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) override {
        for (size_t i = 0; i < expect.size() && !t_.empty(); ++i) t_.pop_back();
        t_ += insert;
        backspaces += static_cast<int>(expect.size());
        sent = true;
        return true;
    }
    bool compositionActive() override { return false; }
    bool setComposition(const std::u16string&, int, bool) override { return false; }
    void endComposition(const std::u16string&) override {}
    void endCompositionAsIs() override {}
    bool sent = false;
    int backspaces = 0;

private:
    std::u16string& t_;
};

// The TIP (keys pass as typed, recorded in TypedWord) + the hook (hook_fallback.cpp
// keyboardProc order), minus Win32.
struct ListRig {
    Settings st;
    TypingSession s;
    HookArming arming;
    WordAdoption adoption;
    TypedWord tip;            // the TIP's record (kTypedWordProp)
    bool hookIn = false;      // the hook is engaged (installed + ack)
    std::u16string filter;    // what the list's filter holds
    int passedByHook = 0;     // keys the hook let through untouched
    int handledByHook = 0;    // keys the hook routed to its session
    WordAdoption::Start lastStart = WordAdoption::Start::Unknown;

    ListRig() {
        SessionOptions o;  // hook_fallback.cpp configureSession
        o.engineFlags = st.engineFlags() & ~static_cast<uint32_t>(VTX_RETRO_ENGLISH);
        o.autoRestore = st.autoRestore;
        o.reEditWord = false;
        o.shortcuts = &st.shortcuts;
        s.configure(o);
        s.setOutputMode(OutputMode::InPlace);
    }
    static KeyInput classify(char c) {
        KeyInput k;
        switch (c) {
            case '\b': k.kind = KeyKind::Backspace; break;
            case kEnter: k.kind = KeyKind::Boundary; break;
            case kLeft: k.kind = KeyKind::Navigation; break;
            case kCtrlA: k.kind = KeyKind::Chord; break;
            default:
                k.kind = KeyKind::Char;
                k.ch = static_cast<unsigned char>(c);
                break;
        }
        return k;
    }
    // The app's handling of a key that reached it; the TIP sees it pass as typed.
    void app(const KeyInput& k) {
        if (k.kind == KeyKind::Char) filter.push_back(static_cast<char16_t>(k.ch));
        if (k.kind == KeyKind::Backspace && !filter.empty()) filter.pop_back();
        tip.note(k);
    }
    // kCmdForeground mid-focus: the TIP's request arrived, the hook is in.
    void engage(bool adopt = true) {
        s.resetContext();
        arming.engaged(false);
        adoption.engaged(adopt);
        hookIn = true;
    }
    // mouseProc: dropWord + arming.click.
    void click() {
        s.reset();
        adoption.drop();
        arming.click();
    }
    void key(char c) {
        const KeyInput k = classify(c);
        if (!hookIn) return app(k);  // before the ack: straight to the app
        if (adoption.pending()) {
            lastStart = adoption.begin(tip.encoded(), k, s);
            if (lastStart != WordAdoption::Start::Unknown) arming.armNow();
        }
        const bool boundary = k.kind == KeyKind::Boundary || k.kind == KeyKind::Navigation ||
                              k.kind == KeyKind::Chord || (k.kind == KeyKind::Char && k.ch == U' ');
        if (!arming.key(boundary)) {
            adoption.drop();
            ++passedByHook;
            return app(k);
        }
        if (adoption.owes() && k.kind == KeyKind::Backspace) {
            adoption.backspace(s);
            ++passedByHook;
            return app(k);
        }
        ++handledByHook;
        FilterSink sink(filter);
        if (adoption.owes()) {
            const WordAdoption::Fix f = adoption.takeFix();
            sink.replaceBeforeCaret(f.expect, f.insert);
        }
        bool eaten = false;
        if (!s.wantsKey(k)) s.noteKeyPassedBy(k);
        else eaten = s.handleKey(k, sink);
        if (sink.sent) tip.invalidate();  // the TIP sees our injected edits
        if (!eaten) {
            if (sink.sent) {  // replayed at the end of the batch (injected: the TIP skips it)
                if (k.kind == KeyKind::Char) filter.push_back(static_cast<char16_t>(k.ch));
            } else {
                app(k);
            }
        }
    }
    void type(const char* keys) {
        for (const char* p = keys; *p; ++p) key(*p);
    }
    std::string text() const { return utf16ToUtf8(filter); }
};

// Focus the list, type `before` (passed as typed, the TIP asked at the first key), the hook
// acks, type `after`.
std::string run(const char* before, const char* after, bool adopt = true) {
    ListRig r;
    r.type(before);
    r.engage(adopt);
    r.type(after);
    return r.text();
}

}  // namespace

TEST(word_adopt_doc_ack_after_two_letters) {
    // The tester's flow: the list gets d, o; then the hook: j = ⌫ + "ọ", c passes.
    ListRig r;
    r.type("do");
    CHECK_EQ(r.text(), std::string("do"));
    r.engage();
    r.key('j');
    CHECK(r.lastStart == WordAdoption::Start::Adopted);
    CHECK_EQ(r.text(), std::string("dọ"));
    r.key('c');
    CHECK_EQ(r.text(), std::string("dọc"));
    CHECK_EQ(r.handledByHook, 2);
    CHECK_EQ(r.passedByHook, 0);
}

TEST(word_adopt_doc_any_ack_point) {
    CHECK_EQ(run("d", "ojc"), std::string("dọc"));
    CHECK_EQ(run("do", "jc"), std::string("dọc"));
    // "doj" raw on screen: the first hook key fixes it ("oj" -> "ọ") in the same batch.
    CHECK_EQ(run("doj", "c"), std::string("dọc"));
    CHECK_EQ(run("", "dojc"), std::string("dọc"));
    CHECK_EQ(run("D", "ojc"), std::string("Dọc"));
}

TEST(word_adopt_fix_is_one_batch_before_the_key) {
    ListRig r;
    r.type("doj");
    r.engage();
    KeyInput c;
    c.kind = KeyKind::Char;
    c.ch = U'c';
    CHECK(r.adoption.begin(r.tip.encoded(), c, r.s) == WordAdoption::Start::Adopted);
    CHECK_EQ(r.adoption.raw(), std::u16string(u"doj"));
    CHECK_EQ(r.adoption.believed(), std::u16string(u"dọ"));
    CHECK(r.s.wordActive());
    CHECK_EQ(r.s.shown(), std::u16string(u"dọ"));
    CHECK(r.adoption.owes());
    const WordAdoption::Fix f = r.adoption.takeFix();
    CHECK_EQ(f.expect, std::u16string(u"oj"));  // 2 backspaces
    CHECK_EQ(f.insert, std::u16string(u"ọ"));
    CHECK(!r.adoption.owes());
}

TEST(word_adopt_tieng) {
    CHECK_EQ(run("t", "ieengs"), std::string("tiếng"));
    CHECK_EQ(run("tie", "engs"), std::string("tiếng"));
    CHECK_EQ(run("tiee", "ngs"), std::string("tiếng"));
    CHECK_EQ(run("tieen", "gs"), std::string("tiếng"));  // 5 keys: the record's limit
    // 6 keys before the ack: unknown -> the old rule (wait for a boundary), never a guess.
    ListRig r;
    r.type("tieeng");
    r.engage();
    r.key('s');
    CHECK(r.lastStart == WordAdoption::Start::Unknown);
    CHECK_EQ(r.text(), std::string("tieengs"));
    r.type(" tieengs");  // after the boundary the hook types
    CHECK_EQ(r.text(), std::string("tieengs tiếng"));
}

TEST(word_adopt_space_after_the_word_passes) {
    ListRig r;
    r.type("d");
    r.engage();
    r.type("ojc");
    const int handled = r.handledByHook;
    r.key(' ');  // ends the filter in One Commander: reaches the app as a plain space
    CHECK_EQ(r.text(), std::string("dọc "));
    CHECK_EQ(r.handledByHook, handled + 1);
    CHECK(!r.s.wordActive());
    // A raw word whose first hook key is the space: fixed, then the space.
    CHECK_EQ(run("doj", " "), std::string("dọ "));
}

TEST(word_adopt_click_resets) {
    ListRig r;
    r.type("do");
    r.engage();
    r.click();  // the caret / filter may have changed: nothing adopted
    CHECK(!r.adoption.pending());
    r.type("jc");
    CHECK_EQ(r.text(), std::string("dojc"));  // "jc" is a word of its own
}

TEST(word_adopt_arrow_or_chord_resets) {
    ListRig r;
    r.type("do");
    r.engage();
    r.key(kLeft);  // the word ends as typed
    CHECK(r.lastStart == WordAdoption::Start::Nothing);
    CHECK(!r.s.wordActive());
    r.type("jc");
    CHECK_EQ(r.text(), std::string("dojc"));
    ListRig c;
    c.type("doj");
    c.engage();
    c.key(kCtrlA);
    CHECK(c.lastStart == WordAdoption::Start::Nothing);
    CHECK(!c.adoption.owes());
    CHECK_EQ(c.text(), std::string("doj"));
    // The TIP's record resets on the arrow too (a later handover adopts nothing old).
    TypedWord w;
    KeyInput d;
    d.kind = KeyKind::Char;
    d.ch = U'd';
    w.note(d);
    KeyInput left;
    left.kind = KeyKind::Navigation;
    w.note(left);
    CHECK_EQ(w.encoded(), 0u);
}

TEST(word_adopt_backspace_while_owing) {
    ListRig r;
    r.type("doj");
    r.engage();
    r.key('\b');  // the list deletes "j"; the rest is adopted again
    CHECK_EQ(r.text(), std::string("do"));
    CHECK(!r.adoption.owes());
    CHECK(r.s.wordActive());
    r.type("jc");
    CHECK_EQ(r.text(), std::string("dọc"));
    // Before the ack: the TIP's record follows the list's ⌫.
    CHECK_EQ(run("dox\b", "jc"), std::string("dọc"));
}

TEST(word_adopt_only_with_the_flag) {
    // A handover without kDirectAdoptTyped (consoles, terminals, CompositionOnly): the TIP
    // may be composing the word — the hook still waits for a boundary.
    CHECK_EQ(run("do", "jc", false), std::string("dojc"));
    CHECK_EQ(run("do", "jc tieengs", false), std::string("dojc tiếng"));
}

TEST(word_adopt_nothing_in_progress) {
    ListRig r;
    r.engage();
    r.key('d');
    CHECK(r.lastStart == WordAdoption::Start::Nothing);
    r.type("ojc");
    CHECK_EQ(r.text(), std::string("dọc"));
    // A finished word before the ack: the next one is typed from its first key.
    CHECK_EQ(run("abc ", "dojc"), std::string("abc dọc"));
}

TEST(word_adopt_no_key_lost_or_doubled) {
    // Every key reaches the list exactly once: before the ack straight, after it through the
    // hook (passed, or replayed after its edit) — the filter holds one character per key
    // whatever the ack point.
    const char* word = "tieengs";
    for (int split = 0; split <= 5; ++split) {
        ListRig r;
        for (int i = 0; i < split; ++i) r.key(word[i]);
        r.engage();
        for (const char* p = word + split; *p; ++p) r.key(*p);
        CHECK_EQ(r.text(), std::string("tiếng"));
        CHECK_EQ(r.handledByHook + r.passedByHook, static_cast<int>(7 - split));
    }
}

TEST(word_adopt_telex_digit_ends_record_word) {
    // "do1" in Telex: the digit ends the word, the record is no word in progress the session
    // can hold -> unknown, wait for a boundary.
    ListRig r;
    r.type("do1");
    r.engage();
    r.key('j');
    CHECK(r.lastStart == WordAdoption::Start::Unknown);
    CHECK_EQ(r.text(), std::string("do1j"));
}
