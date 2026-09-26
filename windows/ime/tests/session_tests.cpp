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
    bool setComposition(const std::u16string& t, int absorb) override {
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
    bool setComposition(const std::u16string&, int) override { return false; }
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
