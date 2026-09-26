// End-to-end plumbing tests: key sequence -> TypingSession -> FakeDocument, in both
// output modes, against the real C++ engine (windows/engine).
#include "fake_document.h"
#include "session.h"
#include "settings.h"
#include "app_policy.h"
#include "test.h"

using namespace vtx;
using vtx::test::FakeDocument;

namespace {

constexpr char kLeft = '\x01';   // Left arrow
constexpr char kCtrlZ = '\x02';  // a Ctrl chord

struct Rig {
    Settings settings;
    TypingSession s;
    FakeDocument doc;
    explicit Rig(OutputMode m) {
        s.setOutputMode(m);
        apply();
    }
    void apply() {
        SessionOptions o;
        o.engineFlags = settings.engineFlags();
        o.autoRestore = settings.autoRestore;
        o.reEditWord = settings.reEditWord;
        o.shortcuts = &settings.shortcuts;
        s.configure(o);
    }
    void key(char c) {
        KeyInput k;
        if (c == '\b') k.kind = KeyKind::Backspace;
        else if (c == '\n') k.kind = KeyKind::Boundary;
        else if (c == kLeft) k.kind = KeyKind::Navigation;
        else if (c == kCtrlZ) k.kind = KeyKind::Chord;
        else { k.kind = KeyKind::Char; k.ch = static_cast<unsigned char>(c); }
        bool eaten = s.wantsKey(k) && s.handleKey(k, doc);
        if (eaten) return;
        // Invariant: a key reaching the app never finds a composition open.
        CHECK(!doc.comp);
        switch (k.kind) {
            case KeyKind::Char: doc.appInsert(static_cast<char16_t>(k.ch)); break;
            case KeyKind::Backspace: doc.appBackspace(); break;
            case KeyKind::Boundary: doc.appInsert(u'\n'); break;
            case KeyKind::Navigation:
                if (doc.caret) doc.caret = doc.anchor = doc.caret - 1;
                s.reset();  // the TIP sees a selection change it did not make
                break;
            default: break;
        }
    }
    void type(const char* keys) {
        for (const char* p = keys; *p; ++p) key(*p);
    }
    std::string text() const { return utf16ToUtf8(doc.text); }
};

void bothModes(const char* keys, const char* want) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.type(keys);
        CHECK_EQ(r.text(), std::string(want));
        CHECK(!r.doc.comp || r.s.wordActive());
    }
}

}  // namespace

TEST(session_basic_words) {
    bothModes("tieengs vieetj ", "tiếng việt ");
    bothModes("xin chaof cacs banj.", "xin chào các bạn.");
    bothModes("caacs ", "cấc ");
    bothModes("dduwowngf ", "đường ");
}

TEST(session_composition_holds_word_until_boundary) {
    Rig r(OutputMode::Composition);
    r.type("vieetj");
    CHECK(r.doc.comp);
    CHECK_EQ(r.text(), std::string("việt"));
    r.type(" ");
    CHECK(!r.doc.comp);
    CHECK_EQ(r.text(), std::string("việt "));
}

TEST(session_enter_commits_then_passes) {
    bothModes("vieetj\n", "việt\n");
}

TEST(session_backspace_deletes_displayed_char) {
    bothModes("khoo\b", "kh");
    bothModes("khoo\b\b\ba", "a");
}

TEST(session_auto_restore) {
    bothModes("google ", "google ");
    bothModes("windows ", "windows ");
}

TEST(session_auto_restore_off_keeps_composed) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.settings.autoRestore = false;
        r.apply();
        r.type("google ");
        CHECK(r.text() != "google ");
    }
}

TEST(session_shortcut_expansion) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.settings.shortcuts[u"vn"] = u"Việt Nam";
        r.apply();
        r.type("vn ");
        CHECK_EQ(r.text(), std::string("Việt Nam "));
    }
}

TEST(session_shortcut_not_after_digit_or_token) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.settings.shortcuts[u"h"] = u"giờ";
        r.apply();
        r.type("5h /h #h h ");
        CHECK_EQ(r.text(), std::string("5h /h #h giờ "));
    }
}

TEST(session_reopen_after_space) {
    // issue #40: "tháy ␣ ⌫ a" -> "thấy"
    bothModes("thays \ba", "thấy");
}

TEST(session_reopen_needs_fresh_boundary) {
    // Typing another char after the space disarms the re-open: the two ⌫ are the
    // app's own, and no word is left open in the engine.
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.type("thays .\b\b");
        CHECK_EQ(r.text(), std::string("tháy"));
        CHECK(!r.s.wordActive());
        CHECK(!r.doc.comp);
        r.type("a");  // 'a' is an ordinary letter: no re-edit either
        CHECK_EQ(r.text(), std::string("tháya"));
    }
}

TEST(session_reedit_word_before_caret) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.doc.setText(u"xin chao");
        r.type("f ");
        CHECK_EQ(r.text(), std::string("xin chào "));
    }
}

TEST(session_reedit_disabled) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.settings.reEditWord = false;
        r.apply();
        r.doc.setText(u"chao");
        r.type("f");
        CHECK_EQ(r.text(), std::string("chaof"));
    }
}

TEST(session_reedit_skips_non_transforming_key) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.doc.setText(u"ba");
        r.type("n");
        CHECK_EQ(r.text(), std::string("ban"));
    }
}

TEST(session_inplace_external_change_resyncs_at_next_letter) {
    Rig r(OutputMode::InPlace);
    r.type("vie");
    // The app rewrote the text under us (autocorrect, collaborative edit...).
    r.doc.setText(u"xyz");
    r.type("e");  // our word is gone: a NEW word starts at this letter
    CHECK_EQ(r.text(), std::string("xyze"));
    CHECK(r.s.wordActive());
    CHECK(!r.s.contextFellBack());  // a desync is not a reason to give up in-place
    r.type("e ");
    CHECK_EQ(r.text(), std::string("xyzê "));
}

TEST(session_composition_refused_is_literal) {
    Rig r(OutputMode::Composition);
    r.doc.refuseEdits = true;
    r.type("aa");
    CHECK_EQ(r.text(), std::string("aa"));
}

TEST(session_navigation_commits) {
    bothModes("vieetj" "\x01" "x", "việxt");
}

TEST(session_chord_inplace_resets_without_edit) {
    Rig r(OutputMode::InPlace);
    r.type("chao");
    int edits = r.doc.edits;
    r.key(kCtrlZ);
    CHECK_EQ(r.doc.edits, edits);
    CHECK(!r.s.wordActive());
}

TEST(session_chord_composition_commits) {
    Rig r(OutputMode::Composition);
    r.type("vieetj");
    r.key(kCtrlZ);
    CHECK(!r.doc.comp);
    CHECK_EQ(r.text(), std::string("việt"));
}

TEST(session_overflow_passes_rest_raw) {
    std::string keys(40, 'a');
    keys[1] = 'b';  // "abaaaa..." never transforms into one syllable anyway
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.type(keys.c_str());
        r.type(" ");
        CHECK_EQ(r.doc.text.size(), keys.size() + 1);
        CHECK(!r.doc.comp);
    }
}

TEST(session_flush_on_toggle) {
    Rig r(OutputMode::Composition);
    r.type("vieetj");
    r.s.flush(r.doc);
    CHECK(!r.doc.comp);
    CHECK_EQ(r.text(), std::string("việt"));
    r.type("s");  // English now? no: session is mode-agnostic; caller gates on V/E.
}

TEST(session_vni_mode) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.settings.vniMode = true;
        r.apply();
        r.type("vie65t ");
        CHECK_EQ(r.text(), std::string("việt "));
    }
}

TEST(session_uppercase) {
    bothModes("VIEETJ Nam ", "VIỆT Nam ");
}

TEST(session_wants_key_is_superset) {
    Rig r(OutputMode::InPlace);
    KeyInput space{KeyKind::Char, U' '};
    KeyInput bs{KeyKind::Backspace, 0};
    KeyInput nav{KeyKind::Navigation, 0};
    CHECK(!r.s.wantsKey(space));
    CHECK(!r.s.wantsKey(bs));
    CHECK(!r.s.wantsKey(nav));
    r.type("a");
    CHECK(r.s.wantsKey(space));
    CHECK(r.s.wantsKey(bs));
    CHECK(r.s.wantsKey(nav));
}

TEST(session_orphan_composition_is_closed_not_overwritten) {
    Rig r(OutputMode::Composition);
    r.type("vieetj");
    r.s.reset();  // e.g. the TIP lost track (selection moved) before ending it
    CHECK(r.doc.comp);
    r.type("a");
    CHECK_EQ(r.text(), std::string("việta"));
    r.type(" ");
    CHECK_EQ(r.text(), std::string("việta "));
    CHECK(!r.doc.comp);
}

TEST(session_reedit_only_on_diacritic_keys) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.doc.setText(u"ca");
        r.type("a");  // doubling letter: ordinary letter, no re-edit
        CHECK_EQ(r.text(), std::string("caa"));
        Rig w(m);
        w.doc.setText(u"tu");
        w.type("w");  // horn: diacritic-only
        CHECK_EQ(w.text(), std::string("tư"));
    }
    CHECK(isDiacriticOnlyKey(U'S', false));
    CHECK(!isDiacriticOnlyKey(U'a', false));
    CHECK(isDiacriticOnlyKey(U'6', true));
    CHECK(!isDiacriticOnlyKey(U's', true));
}

TEST(default_mode_is_in_place) {
    TypingSession t;
    CHECK(t.outputMode() == OutputMode::InPlace);
    std::map<std::string, AppMode> none;
    CHECK(resolveAppMode("notepad.exe", none) == AppMode::InPlace);   // implicit default
    CHECK(resolveAppMode("chrome.exe", none) == AppMode::InPlace);
    CHECK(resolveAppMode("mstsc.exe", none) == AppMode::Off);         // built-ins unchanged
}

TEST(migration_keeps_explicit_choices) {
    // A pre-1.0.9 snapshot: one app pinned to composition, one to hook. Implicit apps now
    // resolve to in-place; the explicit choices survive.
    Settings old;
    old.appModes["word.exe"] = AppMode::Composition;
    old.appModes["game.exe"] = AppMode::HookFallback;
    std::vector<uint8_t> b = serialize(old);
    Settings now;
    CHECK(deserialize(b.data(), b.size(), now));
    CHECK(resolveAppMode("word.exe", now.appModes) == AppMode::Composition);
    CHECK(resolveAppMode("game.exe", now.appModes) == AppMode::HookFallback);
    CHECK(resolveAppMode("excel.exe", now.appModes) == AppMode::InPlace);
}

TEST(in_place_falls_back_to_composition_when_unreadable) {
    Rig r(OutputMode::InPlace);
    r.doc.unreadable = true;
    r.type("vieetj ");
    CHECK_EQ(r.text(), std::string("việt "));   // typed through composition, not corrupted
    CHECK(r.s.contextFellBack());
    r.s.resetContext();                          // new field: in-place again
    CHECK(!r.s.contextFellBack());
}

TEST(in_place_verification_failure_falls_back_for_the_field) {
    Rig r(OutputMode::InPlace);
    r.doc.refuseReplace = true;  // the control will not take our in-place edit
    r.type("aa");                // replace refused: this key literal, field -> composition
    CHECK_EQ(r.text(), std::string("aa"));
    CHECK(r.s.contextFellBack());
    r.type(" vieetj ");
    CHECK_EQ(r.text(), std::string("aa việt "));
}

TEST(omnibox_autocomplete_suffix_is_never_deleted) {
    // Chrome/Edge address bar: after each typed key the app selects a suggested suffix
    // AFTER the caret. Our edits touch only the word before the insertion point.
    Rig r(OutputMode::InPlace);
    auto suggest = [&](const std::u16string& suffix) {  // app autocompletes
        r.doc.text += suffix;
        r.doc.anchor = r.doc.text.size();                // selection [caret, end]
    };
    r.type("vie");
    suggest(u"tnam.vn");
    r.type("e");                                         // e -> ê before the caret
    CHECK_EQ(r.text(), std::string("viêtnam.vn"));
    CHECK(r.doc.hi() - r.doc.lo() == 7);                 // suffix still selected
    r.type("t");                                         // typing replaces the suggestion
    suggest(u"nam");
    r.type("j");
    CHECK_EQ(r.text(), std::string("việtnam"));
    CHECK(!r.s.contextFellBack());
}

namespace {
// Chrome/Edge omnibox: after every keystroke the app appends a suggestion and selects it
// (forward selection from the caret); a typed key replaces the selection.
struct Omnibox : Rig {
    std::vector<std::u16string> suggestions;  // one per keystroke, "" = none
    size_t k = 0;
    Omnibox() : Rig(OutputMode::InPlace) {}
    void suggest() {
        if (doc.hi() != doc.lo()) {  // previous suggestion still selected: drop it first
            doc.text.erase(doc.lo(), doc.hi() - doc.lo());
            doc.caret = doc.anchor = doc.lo();
        }
        std::u16string sfx = k < suggestions.size() ? suggestions[k] : u"";
        ++k;
        doc.text.insert(doc.caret, sfx);
        doc.anchor = doc.caret + sfx.size();  // selection [caret, caret+len)
    }
    void typeAc(const char* keys) {
        for (const char* p = keys; *p; ++p) {
            key(*p);
            suggest();
        }
    }
    std::string typedText() const {  // what the user typed (without the live suggestion)
        return utf16ToUtf8(doc.text.substr(0, doc.lo()));
    }
};
}  // namespace

TEST(omnibox_inline_autocomplete_thuwr_vieecj) {
    // real-Windows repro (1.0.8): "thuwr vieecj" gave "thử vieecj" — the second word
    // stayed raw because a forward selection counted as an external edit.
    Omnibox o;
    o.suggestions = {u"iết", u"", u"", u"", u"", u" việc có phải", u"iệc có phải", u"ệc có phải", u"c có phải",
                     u"c có phải", u"c có phải", u" có phải"};
    o.typeAc("thuwr vieecj");
    CHECK_EQ(o.typedText(), std::string("thử việc"));
    CHECK(!o.s.contextFellBack());
}

TEST(omnibox_inline_autocomplete_vieejt_nam) {
    Omnibox o;
    o.suggestions = {u"ietnamnet.vn", u"etnamnet.vn", u"tnamnet.vn", u"", u"", u"", u" nam", u"am", u"m", u""};
    o.typeAc("vieejt nam");
    CHECK_EQ(o.typedText(), std::string("việt nam"));
    CHECK(!o.s.contextFellBack());
}
