// End-to-end plumbing tests: key sequence -> TypingSession -> FakeDocument, in both
// output modes, against the real C++ engine (windows/engine).
#include <viettelex/vtx_engine.h>

#include "caret_hints.h"
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
        o.underlineMisspelled = settings.underlineMisspelled;
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
        send(k);
    }
    void send(const KeyInput& k) {
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

// #124: numpad digits are never VNI marks — they end the word and reach the app; the
// number row keeps marking.
TEST(session_vni_numpad_digits_are_boundaries) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        Rig r(m);
        r.settings.vniMode = true;
        r.apply();
        r.type("a");
        r.send(classifyKey(vk::Numpad0 + 1, Modifiers{}));
        r.type("a1 ");
        r.send(classifyKey(vk::Numpad0, Modifiers{}));
        CHECK_EQ(r.text(), std::string("a1\xc3\xa1 0"));
        CHECK(!r.doc.comp);
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

namespace {
// Win10 conhost (cmd.exe / PowerShell) TSF semantics, as in microsoft/terminal's
// ConsoleTSF: the document is only the composition; letters the TIP lets through go
// straight to the shell as WM_CHAR, text inserted outside a composition is sent as
// typed and can never be deleted, and nothing already sent can be read back.
struct ConsoleDoc : TextSink {
    std::u16string shell;     // what cmd.exe received
    std::u16string compText;  // live composition
    bool comp = false;
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& ins) override {
        if (!expect.empty()) return false;  // nothing to delete in the document
        shell += ins;                       // insert-only
        return true;
    }
    bool compositionActive() override { return comp; }
    bool setComposition(const std::u16string& t, int absorb, bool) override {
        if (absorb) return false;
        comp = true;
        compText = t;
        return true;
    }
    void endComposition(const std::u16string& t) override {
        if (comp) shell += t;
        comp = false;
        compText.clear();
    }
    void endCompositionAsIs() override { endComposition(compText); }
};

std::string typeConsole(TypingSession& s, ConsoleDoc& d, const char* keys) {
    for (const char* p = keys; *p; ++p) {
        KeyInput k;
        k.kind = KeyKind::Char;
        k.ch = static_cast<unsigned char>(*p);
        const bool eaten = s.wantsKey(k) && s.handleKey(k, d);
        if (!eaten) d.shell += static_cast<char16_t>(*p);  // WM_CHAR to the shell
    }
    return utf16ToUtf8(d.shell);
}

void configureDefaults(TypingSession& s, const Settings& st) {
    SessionOptions o;
    o.engineFlags = st.engineFlags();
    o.autoRestore = st.autoRestore;
    o.reEditWord = st.reEditWord;
    o.shortcuts = &st.shortcuts;
    s.configure(o);
}
}  // namespace

TEST(console_cmd_types_vietnamese_via_composition) {
    // 1.1.0 repro on Win10 cmd.exe: "thuwr gox tieengs vieetj" -> "thuưr gox tieengs Vieetj".
    Settings st;
    TypingSession s;  // in-place is the app default...
    configureDefaults(s, st);
    s.setCompositionOnlyContext(true);  // ...but the TIP saw TF_TMAE_CONSOLE / TF_SS_TRANSITORY
    ConsoleDoc d;
    CHECK_EQ(typeConsole(s, d, "thuwr gox tieengs vieetj "), std::string("thử gõ tiếng việt "));
    CHECK(s.wordMode() == OutputMode::Composition);
}

TEST(console_unflagged_host_recovers_after_first_word) {
    // A console-like host we did NOT recognise (e.g. mintty via IMM): at the 2nd key the
    // field shows none of the typed text -> composition for the rest of the field. The
    // first letter was already passed through, so only a word whose FIRST two keys form
    // one letter ("dd" -> đ) can come out as typed. Never "thuưr" garbage, never the rest
    // of the line raw.
    Settings st;
    TypingSession s;
    configureDefaults(s, st);
    ConsoleDoc d;
    CHECK_EQ(typeConsole(s, d, "thuwr gox tieengs vieetj "), std::string("thử gõ tiếng việt "));
    CHECK(s.contextFellBack());
    TypingSession s2;
    configureDefaults(s2, st);
    ConsoleDoc d2;
    CHECK_EQ(typeConsole(s2, d2, "ddi dduwowngf "), std::string("ddi đường "));
}

TEST(console_never_reads_back_for_reedit_or_reopen) {
    Settings st;
    TypingSession s;
    configureDefaults(s, st);
    s.setCompositionOnlyContext(true);
    ConsoleDoc d;
    typeConsole(s, d, "thays ");
    KeyInput bs;
    bs.kind = KeyKind::Backspace;
    const bool eaten = s.wantsKey(bs) && s.handleKey(bs, d);
    CHECK(!eaten);  // the shell deletes the space itself; no re-open of "tháy"
    CHECK(!s.wordActive());
}

TEST(host_text_policy) {
    ContextInfo c;
    CHECK(classifyContext(c) == HostText::Normal);                 // Word, WPF, Firefox
    c.transitory = true;
    CHECK(classifyContext(c) == HostText::Normal);                 // Chromium: transitory but full (1.1.1 regression)
    c.cuasEmulated = true;
    CHECK(classifyContext(c) == HostText::CompositionOnly);        // IMM32 app via CUAS (Qt, Java, Adobe…)
    c.cuasEmulated = false;
    c.hasParent = true;
    c.parentTransitory = false;
    CHECK(classifyContext(c) == HostText::NormalViaParent);        // classic Edit/RichEdit
    c.parentTransitory = true;
    CHECK(classifyContext(c) == HostText::CompositionOnly);
    ContextInfo con;
    con.console = true;
    con.transitory = true;
    CHECK(classifyContext(con) == HostText::CompositionOnly);      // conhost / Windows Terminal
    ContextInfo ro;
    ro.readOnly = true;
    CHECK(classifyContext(ro) == HostText::Literal);
    ContextInfo dis;
    dis.keyboardDisabled = true;
    CHECK(classifyContext(dis) == HostText::Literal);              // games / canvases
    ContextInfo ansi;
    ansi.unicodeWindow = false;
    CHECK(classifyContext(ansi) == HostText::Literal);             // VBA editor, ANSI apps
    ContextInfo none;
    none.hasContext = false;
    CHECK(classifyContext(none) == HostText::Ignore);
    std::map<std::string, AppMode> no;
    // consoles/terminals: Direct (hook types, no underline; composition if the app is off)
    for (const char* exe : {"conhost.exe", "openconsole.exe", "windowsterminal.exe", "mintty.exe", "alacritty.exe",
                            "wezterm-gui.exe", "conemu64.exe", "putty.exe", "kitty.exe", "tabby.exe"}) {
        CHECK(resolveAppMode(exe, no) == AppMode::Direct);
        CHECK(hookTypes(resolveAppMode(exe, no)));
    }
    for (const char* exe : {"vmware.exe", "vmware-vmx.exe", "vmware-view.exe", "virtualboxvm.exe", "wfica32.exe",
                            "cdviewer.exe", "ultraviewer_desktop.exe", "moonlight.exe"})
        CHECK(resolveAppMode(exe, no) == AppMode::Off);
    // search bars and browsers are ordinary readable stores: in-place, verified, fallback
    for (const char* exe : {"searchhost.exe", "searchapp.exe", "searchui.exe", "explorer.exe", "chrome.exe",
                            "msedge.exe", "systemsettings.exe", "powertoys.powerlauncher.exe", "everything.exe"})
        CHECK(resolveAppMode(exe, no) == AppMode::InPlace);
}

TEST(chromium_shaped_store_stays_in_place) {
    // Chromium reports TF_SS_TRANSITORY yet is fully readable, with a forward-selected
    // omnibox suggestion after each key. Classification keeps it in-place, and typing
    // works through the suggestion without falling back.
    ContextInfo chrome;
    chrome.transitory = true;
    CHECK(classifyContext(chrome) == HostText::Normal);
    Rig r(OutputMode::InPlace);
    for (const char* p = "vieetj"; *p; ++p) {
        r.key(*p);
        if (r.doc.hi() != r.doc.lo()) {  // drop the previous suggestion
            r.doc.text.erase(r.doc.lo(), r.doc.hi() - r.doc.lo());
            r.doc.caret = r.doc.anchor = r.doc.lo();
        }
        r.doc.text += u"nam.vn";
        r.doc.anchor = r.doc.text.size();
    }
    CHECK_EQ(utf16ToUtf8(r.doc.text.substr(0, r.doc.lo())), std::string("việt"));
    CHECK(r.s.wordMode() == OutputMode::InPlace);
    CHECK(!r.s.contextFellBack());
}

namespace {
// Chromium's native address bar as the TIP really sees it (2026-10 field report, Edge:
// "theêz"). OmniboxViewViews selects the inline suggestion REVERSED (cursor at the end of
// the user text, anchor at the end of the suggestion), and TSFTextStore commits an
// in-place SetText as ExtendSelectionAndDelete(n, 0) + InsertText.
// Textfield::ExtendSelectionAndDelete extends the reversed range — [hi - n, lo] — so it
// deletes inside the suggestion and keeps the n characters we meant to replace. The TSF
// call itself succeeds: only the screen afterwards shows what happened.
struct ChromiumOmniboxDoc : FakeDocument {
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& ins) override {
        const size_t lo_ = lo(), hi_ = hi(), n = expect.size();
        if (comp || n > lo_ || text.compare(lo_ - n, n, expect) != 0) return false;
        if (hi_ == lo_) return FakeDocument::replaceBeforeCaret(expect, ins);  // no suggestion: fine
        if (hi_ - lo_ >= n) text.erase(lo_, hi_ - lo_ - n);  // deletes [lo, hi - n)
        text.insert(lo_, ins);                               // InsertText at the cursor
        caret = anchor = lo_ + ins.size();
        ++edits;
        return true;
    }
};
}  // namespace

TEST(chromium_omnibox_dropped_deletion_moves_field_to_composition) {
  // async: how the TIP flags a Chromium context since the 2026-10 Messenger report.
  for (bool async : {false, true}) {
    Settings st;
    TypingSession s;
    s.setOutputMode(OutputMode::InPlace);
    SessionOptions o;
    o.engineFlags = st.engineFlags();
    s.configure(o);
    s.setAsyncStore(async);
    ChromiumOmniboxDoc doc;
    auto key = [&](char c) {
        KeyInput k;
        k.kind = KeyKind::Char;
        k.ch = static_cast<unsigned char>(c);
        if (!(s.wantsKey(k) && s.handleKey(k, doc))) doc.appInsert(static_cast<char16_t>(c));
        s.verifyScreen(doc);  // OnEndEdit after the app processed the key
    };
    for (char c : std::string("the")) key(c);
    doc.text += u"verge.com";  // inline autocomplete, selected after the caret
    doc.anchor = doc.text.size();
    key('e');  // engine: replace "e" by "ê" -> the app keeps the "e"
    CHECK_EQ(utf16ToUtf8(doc.text.substr(0, doc.lo())), std::string("theê"));  // the reported damage, once
    CHECK(s.prefersComposition());  // ... and this field now composes
    CHECK(!s.contextFellBack());    // never handed to the hook (Direct races autocomplete)
    CHECK(!s.wordActive());         // the damaged word is dropped, not edited blindly
    // The user clears the bar and types again: composition, suggestion or not.
    doc.setText(u"");
    for (char c : std::string("thees")) {
        key(c);
        if (!doc.comp) {  // the omnibox only suggests outside a composition
            doc.text += u"verge.com";
            doc.anchor = doc.text.size();
        }
    }
    CHECK(s.wordMode() == OutputMode::Composition);
    CHECK_EQ(utf16ToUtf8(doc.text.substr(doc.compStart, doc.compEnd - doc.compStart)), std::string("thế"));
    key(' ');
    CHECK_EQ(utf16ToUtf8(doc.text), std::string("thế "));
    s.resetContext();  // another field: in-place again
    CHECK(!s.prefersComposition());
  }
}

TEST(stale_screen_without_dropped_deletion_keeps_in_place) {
    // A click / app rewrite is not the dropped-deletion signature: forget the word only.
    Rig r(OutputMode::InPlace);
    r.type("vieet");
    r.doc.setText(u"something else");
    r.s.verifyScreen(r.doc);
    CHECK(!r.s.wordActive());
    CHECK(!r.s.prefersComposition());
    r.type(" thees ");
    CHECK_EQ(r.text(), std::string("something else thế "));
    CHECK(r.s.wordMode() == OutputMode::InPlace);
}

TEST(omnibox_field_prefers_composition_through_selected_suggestion) {
    // The TIP's rule for the address bar: composition from the first letter. A suggestion
    // already selected when a word starts is replaced by the composition (= typing over it).
    Rig r(OutputMode::InPlace);
    r.s.setPreferComposition(true);
    r.type("thees ");
    r.doc.text += u"giới thiệu";  // suggestion after "thế "
    r.doc.anchor = r.doc.text.size();
    r.type("gioiws ");
    CHECK_EQ(r.text(), std::string("thế giới "));
    CHECK(!r.s.contextFellBack());
}

TEST(field_prefers_composition_only_for_chromium_address_bars) {
    const int url[] = {1};
    const int urlAndDefault[] = {0, 1};
    const int plain[] = {0};
    const int search[] = {50};
    CHECK(fieldPrefersComposition("msedge.exe", url, 1));
    CHECK(fieldPrefersComposition("chrome.exe", urlAndDefault, 2));
    CHECK(fieldPrefersComposition("brave.exe", url, 1));
    CHECK(fieldPrefersComposition("browser.exe", url, 1));      // Cốc Cốc
    CHECK(!fieldPrefersComposition("msedge.exe", plain, 1));    // web page text fields stay in-place
    CHECK(!fieldPrefersComposition("msedge.exe", search, 1));
    CHECK(!fieldPrefersComposition("msedge.exe", nullptr, 0));  // scopes unknown
    CHECK(!fieldPrefersComposition("vivaldi.exe", url, 1));     // web-UI address bar: fine per report
    CHECK(!fieldPrefersComposition("firefox.exe", url, 1));
    CHECK(!fieldPrefersComposition("notepad.exe", url, 1));
    CHECK(!fieldPrefersComposition("msedgewebview2.exe", url, 1));  // WebView2 has no omnibox
}

TEST(search_box_rewriting_its_text_each_key_stays_in_sync) {
    // Explorer / Settings / Start search boxes re-set their own text on every keystroke
    // (same text, caret at the end). That is not a change of OUR word: keep composing.
    Rig r(OutputMode::InPlace);
    for (const char* p = "tieengs vieetj"; *p; ++p) {
        r.key(*p);
        std::u16string t = r.doc.text;  // app re-sets identical text, caret to end
        r.doc.setText(t);
    }
    CHECK_EQ(r.text(), std::string("tiếng việt"));
    CHECK(!r.s.contextFellBack());
}

TEST(webview2_resolves_to_owning_app) {
    CHECK_EQ(appIdentity("msedgewebview2.exe", "ms-teams.exe"), std::string("ms-teams.exe"));
    CHECK_EQ(appIdentity("msedgewebview2.exe", "olk.exe"), std::string("olk.exe"));
    CHECK_EQ(appIdentity("msedgewebview2.exe", ""), std::string("msedgewebview2.exe"));
    CHECK_EQ(appIdentity("chrome.exe", "chrome.exe"), std::string("chrome.exe"));
    CHECK_EQ(appIdentity("notepad.exe", "explorer.exe"), std::string("notepad.exe"));  // only WebView2 hosts
}

namespace {
// What SendInput does to a console / IMM app: backspaces delete, Unicode inserts, and
// NOTHING can be read back (blind sink, like the hook's).
struct BlindKeyboardDoc : TextSink {
    std::u16string screen;
    int batches = 0;
    bool blind() override { return true; }
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& ins) override {
        ++batches;  // one SendInput batch: backspaces first, then the text
        for (size_t i = 0; i < expect.size() && !screen.empty(); ++i) screen.pop_back();
        screen += ins;
        return true;
    }
    bool compositionActive() override { return false; }
    bool setComposition(const std::u16string&, int, bool) override { return false; }
    void endComposition(const std::u16string&) override {}
    void endCompositionAsIs() override {}
};

std::string typeBlind(TypingSession& s, BlindKeyboardDoc& d, const char* keys) {
    for (const char* p = keys; *p; ++p) {
        KeyInput k;
        if (*p == '\b') k.kind = KeyKind::Backspace;
        else {
            k.kind = KeyKind::Char;
            k.ch = static_cast<unsigned char>(*p);
        }
        const bool eaten = s.wantsKey(k) && s.handleKey(k, d);
        if (!eaten) {  // the real key reaches the app
            if (k.kind == KeyKind::Backspace) {
                if (!d.screen.empty()) d.screen.pop_back();
            } else {
                d.screen += static_cast<char16_t>(*p);
            }
        }
    }
    return utf16ToUtf8(d.screen);
}
}  // namespace

TEST(direct_mode_console_types_without_underline) {
    // Direct mode (hook, SendInput): no composition at all, no read-back.
    Settings st;
    TypingSession s;
    configureDefaults(s, st);  // in-place
    BlindKeyboardDoc d;
    CHECK_EQ(typeBlind(s, d, "thuwr gox tieengs vieetj "), std::string("thử gõ tiếng việt "));
    CHECK(!s.contextFellBack());      // blind sinks never trip the verification fallback
    CHECK(s.wordMode() == OutputMode::InPlace);
}

TEST(direct_mode_backspace_mid_word) {
    Settings st;
    TypingSession s;
    configureDefaults(s, st);
    BlindKeyboardDoc d;
    // "tieengs" -> "tiếng"; ⌫ deletes the displayed 'g'; "s" is no longer... retype "g"
    CHECK_EQ(typeBlind(s, d, "tieengs\b"), std::string("tiến"));
    CHECK_EQ(typeBlind(s, d, "g "), std::string("tiếng "));
    BlindKeyboardDoc d2;
    TypingSession s2;
    configureDefaults(s2, st);
    CHECK_EQ(typeBlind(s2, d2, "khoo\ba "), std::string("kha "));
}

TEST(own_injected_events_are_ignored) {
    CHECK(isOwnInjected(kInjectedMagic));
    CHECK(!isOwnInjected(0));
    CHECK(!isOwnInjected(1));  // OpenKey/UniKey's marker is someone else's input
}

// ---- "Gạch đỏ âm tiết sai chính tả khi gõ" (opt-in red squiggle on the composition) ----

TEST(underline_off_by_default_asks_for_no_attribute) {
    Rig r(OutputMode::Composition);
    CHECK(!r.settings.underlineMisspelled);
    r.type("ddc");                       // "đc": flagged when the option is on
    CHECK(r.doc.comp);
    CHECK(!r.doc.misspelled);
    CHECK_EQ(r.doc.misspelledSets, 0);
    r.type(" ");
    CHECK_EQ(r.text(), std::string("đc "));
}

TEST(underline_follows_the_composed_word) {
    Rig r(OutputMode::Composition);
    r.settings.underlineMisspelled = true;
    r.apply();
    r.type("dd");
    CHECK(r.doc.comp && !r.doc.misspelled);   // "đ": still being typed
    r.type("c");
    CHECK(r.doc.misspelled);                  // "đc": no letter can fix it
    r.key('\b');
    CHECK(r.doc.comp && !r.doc.misspelled);   // back to "đ"
    r.type("c");
    CHECK(r.doc.misspelled);
    r.type(" ");                              // committed text carries no attribute
    CHECK(!r.doc.comp && !r.doc.misspelled);
    CHECK_EQ(r.text(), std::string("đc "));
}

TEST(underline_never_marks_valid_english_or_restored_words) {
    Rig r(OutputMode::Composition);
    r.settings.underlineMisspelled = true;
    r.apply();
    r.type("dduwowcj nghieengf khuya quoocs gif gieengs hello hopsng kaf ");
    CHECK_EQ(r.doc.misspelledSets, 0);
    CHECK_EQ(r.text(), std::string("được nghiềng khuya quốc gì giếng hello hopsng kaf "));
}

TEST(underline_judges_kept_words_when_auto_restore_is_off) {
    Rig r(OutputMode::Composition);
    r.settings.underlineMisspelled = true;
    r.settings.autoRestore = false;
    r.apply();
    r.type("kaf");                            // "kà" stays at the boundary now
    CHECK(r.doc.misspelled);
}

TEST(underline_in_place_does_nothing) {
    Rig r(OutputMode::InPlace);
    r.settings.underlineMisspelled = true;
    r.apply();
    r.type("ddc ");
    CHECK_EQ(r.text(), std::string("đc "));
    CHECK_EQ(r.doc.misspelledSets, 0);
}

TEST(underline_reopened_word_keeps_its_mark) {
    Rig r(OutputMode::Composition);
    r.settings.underlineMisspelled = true;
    r.apply();
    r.type("ddc \b");                       // ⌫ right after the space re-opens "đc"
    CHECK(r.doc.comp);
    CHECK_EQ(r.text(), std::string("đc"));
    CHECK(r.doc.misspelled);
}

// Gợi ý từ (word prediction): what the TIP reads from the session when it arms a
// prediction, and accepting a completion over the word being typed in place
// (caret_hints.h predictSuggestion / hintStillValid; the TIP's applyHint does exactly
// replaceBeforeCaret(replace, insert) + session reset).
TEST(session_prediction_replaces_word_in_progress) {
    Rig r(OutputMode::InPlace);
    r.type("tooi dduw");
    CHECK(r.s.wordActive());
    CHECK(r.s.wordMode() == OutputMode::InPlace);
    CHECK_EQ(utf16ToUtf8(r.s.shown()), std::string("đư"));
    CHECK_EQ(utf16ToUtf8(r.s.rawKeys()), std::string("dduw"));
    CHECK_EQ(r.text(), std::string("tôi đư"));
    const std::u32string before = hints::toU32(r.doc.textBeforeCaret(64));
    auto sug = hints::predictSuggestion(before, hints::toU32(r.s.shown()), u"được");
    CHECK(sug.has_value());
    if (!sug) return;
    CHECK(hints::hintStillValid(*sug, before));
    // Tab / click: the one suggestion
    CHECK(r.doc.replaceBeforeCaret(sug->replace, sug->insert));
    r.s.reset();
    CHECK_EQ(r.text(), std::string("tôi được "));
    r.type("ddi ");  // typing goes on normally after the accepted word
    CHECK_EQ(r.text(), std::string("tôi được đi "));
    // next-word suggestion right after the space: insert only
    auto next = hints::predictSuggestion(hints::toU32(r.doc.textBeforeCaret(64)), U"", u"đâu");
    CHECK(next && next->replace.empty() && next->insert == u"đâu ");
    CHECK(r.doc.replaceBeforeCaret(next->replace, next->insert));
    CHECK_EQ(r.text(), std::string("tôi được đi đâu "));
}

TEST(session_prediction_never_replaces_a_composition) {
    Rig r(OutputMode::Composition);
    r.type("dduw");
    CHECK(r.doc.comp);
    CHECK(r.s.wordMode() == OutputMode::Composition);  // the TIP arms no completion here
    // and the document refuses an in-place replace while composing (applyHint bails too)
    CHECK(!r.doc.replaceBeforeCaret(u"đư", u"được "));
}

TEST(session_prediction_english_context) {
    Rig r(OutputMode::InPlace);
    r.type("this is the ");
    CHECK(r.s.previousWordEnglish());
    Rig v(OutputMode::InPlace);
    v.type("xin ");
    CHECK(!v.s.previousWordEnglish());
}

// ---------------------------------------------------------------- Tự sửa từ phía trước
// (retroactiveEnglish, core/retro_english.h). Desktop: auto-apply at the boundary when the
// text before the caret verifies, ⌫ next reverts; switch off = nothing.

namespace {
struct RetroRig : Rig {
    RetroRig(OutputMode m, bool on, bool contextual = true) : Rig(m) {
        settings.retroactiveEnglish = on;
        settings.contextualEnglish = contextual;
        apply();
    }
};
}  // namespace

TEST(retro_settings_gate) {
    Settings s;
    CHECK(!s.retroactiveEnglish);  // experimental: default OFF
    CHECK(!(s.engineFlags() & VTX_RETRO_ENGLISH));
    s.retroactiveEnglish = true;
    CHECK(s.engineFlags() & VTX_RETRO_ENGLISH);
    s.contextualEnglish = false;  // depends on Quyết định theo ngữ cảnh
    CHECK(!(s.engineFlags() & VTX_RETRO_ENGLISH));
    CHECK(retro::flagWanted(true, true));
    CHECK(!retro::flagWanted(true, false));
    CHECK(!retro::flagWanted(false, true));
}

TEST(retro_auto_applies_both_modes) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        RetroRig r(m, true);
        r.type("His car is very fast ");
        CHECK_EQ(r.text(), std::string("His car is very fast "));
        CHECK(r.s.retroUndoArmed());
        RetroRig off(m, false);
        off.type("His car is very fast ");
        CHECK_EQ(off.text(), std::string("Hí cả í very fast "));
        CHECK(!off.s.retroUndoArmed());
        RetroRig noCtx(m, true, false);  // contextualEnglish off: the switch is inert
        RetroRig noCtxOff(m, false, false);
        noCtx.type("His car is very fast ");
        noCtxOff.type("His car is very fast ");
        CHECK_EQ(noCtx.text(), noCtxOff.text());
    }
}

TEST(retro_punctuation_boundary) {
    RetroRig r(OutputMode::InPlace, true);
    r.type("His car is very fast.");
    CHECK_EQ(r.text(), std::string("His car is very fast."));
    // Enter / Tab only end the phrase: no rewrite behind the user's back, no undo.
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        RetroRig e(m, true);
        e.type("His car is very fast\n");
        CHECK_EQ(e.text(), std::string("Hí cả í very fast\n"));
        CHECK(!e.s.retroUndoArmed());
    }
}

TEST(retro_backspace_reverts) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        RetroRig r(m, true);
        r.type("His car is very fast \b");
        CHECK_EQ(r.text(), std::string("Hí cả í very fast "));  // exact previous text, boundary kept
        CHECK(!r.s.retroUndoArmed());
        r.key('\b');  // a second ⌫ is an ordinary one
        CHECK_EQ(r.text(), std::string("Hí cả í very fast"));
        // Reverted: the phrase is not rewritten again by the next words.
        RetroRig q(m, true);
        q.type("His car is very fast \bnow ");
        CHECK_EQ(q.text(), std::string("Hí cả í very fast now "));
    }
}

TEST(retro_undo_only_for_the_next_key) {
    RetroRig r(OutputMode::InPlace, true);
    r.type("His car is very fast x\b");
    CHECK_EQ(r.text(), std::string("His car is very fast "));
    r.key('\b');  // not armed any more: plain ⌫
    CHECK_EQ(r.text(), std::string("His car is very fast"));
}

TEST(retro_undo_skipped_when_text_changed) {
    RetroRig r(OutputMode::InPlace, true);
    r.type("His car is very fast ");
    r.doc.setText(r.doc.text + u"!");  // something the session did not see
    r.key('\b');
    CHECK_EQ(r.text(), std::string("His car is very fast "));  // ordinary ⌫ deleted "!"
}

TEST(retro_skipped_when_text_does_not_verify) {
    for (OutputMode m : {OutputMode::Composition, OutputMode::InPlace}) {
        RetroRig r(m, true);
        r.type("His car is very ");
        // The app changed text the engine counts on ("cả" -> "ca"): never rewrite blindly.
        std::u16string t = r.doc.text;
        const size_t at = t.find(u"cả");
        CHECK(at != std::u16string::npos);
        if (at == std::u16string::npos) continue;
        t.replace(at, 2, u"ca");
        r.doc.setText(t);
        r.type("fast ");
        CHECK_EQ(r.text(), std::string("Hí ca í very fast "));
        CHECK(!r.s.retroUndoArmed());
    }
}

TEST(retro_skipped_in_unreadable_or_composition_only_fields) {
    RetroRig r(OutputMode::Composition, true);
    r.s.setCompositionOnlyContext(true);  // console / transitory document
    r.type("His car is very fast ");
    CHECK_EQ(r.text(), std::string("Hí cả í very fast "));
    RetroRig u(OutputMode::Composition, true);
    u.doc.unreadable = true;
    u.type("His car is very fast ");
    CHECK_EQ(u.text(), std::string("Hí cả í very fast "));
}

TEST(retro_decide_apply) {
    const std::u16string before = u"Hí cả í very fast", expected = u"í cả í very fast";
    const int n = static_cast<int>(expected.size());
    retro::Field f;
    CHECK(retro::decideApply(f, before, expected, n) == retro::Apply::Apply);
    CHECK(retro::decideApply(f, u"Hí ca í very fast", expected, n) == retro::Apply::Mismatch);
    CHECK(retro::decideApply(f, u"í very fast", expected, n) == retro::Apply::Mismatch);
    CHECK(retro::decideApply(f, before, expected, n - 1) == retro::Apply::Mismatch);
    CHECK(retro::decideApply(f, u"", u"", 0) == retro::Apply::Mismatch);
    retro::Field g = f;
    g.blind = true;
    CHECK(retro::decideApply(g, before, expected, n) == retro::Apply::Unverifiable);
    g = f;
    g.compositionOnly = true;
    CHECK(retro::decideApply(g, before, expected, n) == retro::Apply::Unverifiable);
    g = f;
    g.canRead = false;
    CHECK(retro::decideApply(g, before, expected, n) == retro::Apply::Unverifiable);
    g = f;
    g.hasSelection = true;
    CHECK(retro::decideApply(g, before, expected, n) == retro::Apply::Unverifiable);
    g = f;
    g.compositionActive = true;
    CHECK(retro::decideApply(g, before, expected, n) == retro::Apply::Unverifiable);
}

TEST(retro_undo_decision) {
    const retro::Undo u = retro::makeUndo(u"í cả í very fast", u"is car is very fast", u' ');
    CHECK(u.armed());
    CHECK(u.applied == u"is car is very fast ");
    CHECK(u.original == u"í cả í very fast ");
    retro::Field f;
    CHECK(retro::undoApplies(u, f, u"His car is very fast "));
    CHECK(!retro::undoApplies(u, f, u"His car is very fast !"));
    CHECK(!retro::undoApplies(u, f, u"His car is very fast"));
    retro::Field sel = f;
    sel.hasSelection = true;
    CHECK(!retro::undoApplies(u, sel, u"His car is very fast "));
    retro::Field blind = f;
    blind.blind = true;
    CHECK(!retro::undoApplies(u, blind, u"His car is very fast "));
    CHECK(!retro::makeUndo(u"í", u"is", 0).armed());  // Enter / Tab ended the word: no undo
    retro::Undo none;
    CHECK(!retro::undoApplies(none, f, u"anything"));
}

TEST(retro_never_in_terminals_or_remote_viewers) {
    CHECK(!retro::allowedForApp("windowsterminal.exe"));
    CHECK(!retro::allowedForApp("conhost.exe"));
    CHECK(!retro::allowedForApp("mintty.exe"));
    CHECK(!retro::allowedForApp("mstsc.exe"));
    CHECK(retro::allowedForApp("notepad.exe"));
    CHECK(retro::allowedForApp("chrome.exe"));
}

TEST(retro_snapshot_bit_roundtrip) {
    Settings s;
    s.retroactiveEnglish = true;
    const std::vector<uint8_t> b = serialize(s);
    Settings t;
    CHECK(deserialize(b.data(), b.size(), t));
    CHECK(t.retroactiveEnglish);
    CHECK(t == s);
}
