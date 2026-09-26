// test_common — unit tests for linux/common: Session (with a mock InputContext),
// settings/shortcuts/hotkey parsing, app policy, app-state store.
// Links the real libtelexcore, so these are end-to-end through the C ABI.

#include "viettelex/app.h"
#include "viettelex/gnome.h"
#include "viettelex/keys.h"
#include "viettelex/session.h"
#include "viettelex/settings.h"
#include "viettelex/watcher.h"

#include <glib.h>

#include <cstdio>
#include <cstdlib>
#include <random>
#include <string>
#include <unistd.h>
#include <vector>

using namespace viettelex;

static int g_fail = 0, g_pass = 0;
#define CHECK_EQ(a, b)                                                                         \
    do {                                                                                       \
        auto _a = (a);                                                                         \
        auto _b = (b);                                                                         \
        if (_a == _b) ++g_pass;                                                                \
        else {                                                                                 \
            ++g_fail;                                                                          \
            std::fprintf(stderr, "%s:%d: CHECK_EQ(%s, %s) failed\n", __FILE__, __LINE__, #a, #b); \
        }                                                                                      \
    } while (0)
#define CHECK(x) CHECK_EQ(bool(x), true)

namespace {

void popChars(std::string &s, int n) {
    while (n-- > 0 && !s.empty()) {
        size_t i = s.size() - 1;
        while (i > 0 && (static_cast<unsigned char>(s[i]) & 0xc0) == 0x80) --i;
        s.resize(i);
    }
}

// A client: `doc` is the text before the caret; the preedit sits at the caret.
struct Mock : InputContext {
    std::string doc, pre;
    bool surrounding = true;
    bool selection = false;
    int deletes = 0, preeditUpdates = 0;
    std::vector<std::string> log;  // "pre:x" / "commit:x" / "del:n", in call order
    void setPreedit(const std::string &s) override { pre = s; ++preeditUpdates; log.push_back("pre:" + s); }
    void commit(const std::string &s) override { doc += s; log.push_back("commit:" + s); }
    void deleteBeforeCursor(int n) override {
        ++deletes;
        popChars(doc, n);
        log.push_back("del:" + std::to_string(n));
    }
    bool textBeforeCursor(std::string &out) override {
        if (!surrounding) return false;
        out = doc;
        return true;
    }
    bool hasSelection() override { return selection; }
    std::string screen() const { return doc + pre; }
};

void press(Session &s, Mock &m, uint32_t keysym, uint32_t unicode, uint32_t mods = 0) {
    KeyEvent ev;
    ev.keysym = keysym;
    ev.unicode = unicode;
    ev.mods = mods;
    bool consumed = s.processKey(ev, m);
    ev.release = true;
    s.processKey(ev, m);
    if (consumed || (mods & (VT_MOD_CTRL | VT_MOD_ALT | VT_MOD_SUPER))) return;
    // What the application does with a key the IM let through:
    if (keysym == ks::BackSpace) popChars(m.doc, 1);
    else if (keysym == ks::Return) m.doc += "\n";
    else if (keysym == ks::Tab) m.doc += "\t";
    else if (unicode >= 0x20 && unicode < 0x7f) m.doc += char(unicode);
}

// '<' = BackSpace, '\n' = Return, '\t' = Tab, '>' = Right arrow (navigation);
// everything else is typed as that ASCII key.
void type(Session &s, Mock &m, const std::string &keys) {
    for (char c : keys) {
        switch (c) {
        case '<': press(s, m, ks::BackSpace, 0); break;
        case '\n': press(s, m, ks::Return, '\r'); break;
        case '\t': press(s, m, ks::Tab, '\t'); break;
        case '>': press(s, m, ks::Right, 0); break;
        default: press(s, m, uint32_t((unsigned char)c), uint32_t((unsigned char)c));
        }
    }
}

Settings defaults() { return Settings(); }

std::string run(const std::string &keys, DisplayMode mode, Settings st = defaults(), bool surrounding = true) {
    Session s;
    Mock m;
    m.surrounding = surrounding;
    s.applySettings(st);
    s.setDisplayMode(mode, m);
    type(s, m, keys);
    return m.screen();
}

void bothModes(const std::string &keys, const std::string &want, Settings st = defaults()) {
    for (auto mode : {DisplayMode::Preedit, DisplayMode::Surrounding}) {
        std::string got = run(keys, mode, st);
        if (got == want) { ++g_pass; continue; }
        ++g_fail;
        std::fprintf(stderr, "[%s] %s: got [%s] want [%s]\n", keys.c_str(),
                     mode == DisplayMode::Preedit ? "preedit" : "surrounding", got.c_str(), want.c_str());
    }
}

// MARK: - Session

void testBasicTyping() {
    bothModes("vieejt nam ", "việt nam ");
    bothModes("Tieesng Vieejt", "Tiếng Việt");
    bothModes("dduwowcj ", "được ");
    bothModes("google ", "google ");                 // auto-restore
    bothModes("vieejt\n", "việt\n");                 // Enter commits then passes
    bothModes("vieejt.", "việt.");
    bothModes("khoong<<", "khô");                    // ⌫ deletes displayed chars
    bothModes("toans<", "tóa");                      // tone re-placed after ⌫
}

void testPreeditIsUnderlinedComposition() {
    Session s;
    Mock m;
    type(s, m, "vieej");
    CHECK_EQ(m.doc, std::string(""));
    CHECK_EQ(m.pre, std::string("việ"));
    type(s, m, "t");
    CHECK_EQ(m.pre, std::string("việt"));
    type(s, m, " ");
    CHECK_EQ(m.pre, std::string(""));
    CHECK_EQ(m.doc, std::string("việt "));
    // ⌫ through the whole preedit, then the next ⌫ reaches the app
    type(s, m, "ab<<<");
    CHECK_EQ(m.screen(), std::string("việt"));
}

void testSurroundingHasNoPreedit() {
    Session s;
    Mock m;
    s.setDisplayMode(DisplayMode::Surrounding, m);
    type(s, m, "vieejt ");
    CHECK_EQ(m.preeditUpdates, 0);
    CHECK(m.deletes > 0);
    CHECK_EQ(m.doc, std::string("việt "));
}

void testShortcuts() {
    Settings st;
    auto t = std::make_shared<ShortcutTable>();
    (*t)["ko"] = "không";
    (*t)["cf"] = "cà phê";      // key is the RAW form ("cf" composes away)
    st.shortcuts = t;
    bothModes("ko ", "không ", st);
    bothModes("cf ", "cà phê ", st);
    bothModes("2ko ", "2ko ", st);   // glued to a digit: no expansion (#82)
    st.shortcutsEnabled = false;
    bothModes("ko ", "ko ", st);
}

void testCtrlChordCommits() {
    Session s;
    Mock m;
    type(s, m, "vieejt");
    press(s, m, 'c', 'c', VT_MOD_CTRL);
    CHECK_EQ(m.pre, std::string(""));
    CHECK_EQ(m.doc, std::string("việt"));
}

void testToggleHotkey() {
    Session s;
    Mock m;
    bool last = true;
    s.onToggle = [&](bool vi) { last = vi; };
    type(s, m, "vieej");
    press(s, m, ks::space, ' ', VT_MOD_CTRL);   // Ctrl+Space
    CHECK(!last);
    CHECK(!s.vietnamese());
    CHECK_EQ(m.doc, std::string("việ"));        // composition committed, not lost
    type(s, m, "t vieejt ");
    CHECK_EQ(m.doc, std::string("việt vieejt "));
    press(s, m, ks::space, ' ', VT_MOD_CTRL);
    CHECK(last);
    type(s, m, "vieejt");
    CHECK_EQ(m.screen(), std::string("việt vieejt việt"));
    // custom hotkey
    Settings st;
    st.toggleHotkey = "Alt+z";
    s.applySettings(st);
    press(s, m, ks::space, ' ', VT_MOD_CTRL);   // no longer the hotkey: a chord
    CHECK(s.vietnamese());
    press(s, m, 'z', 'z', VT_MOD_ALT);
    CHECK(!s.vietnamese());
}

void testPasswordLiteral() {
    Session s;
    Mock m;
    s.setPassthrough(true, m);
    type(s, m, "vieejt ");
    CHECK_EQ(m.screen(), std::string("vieejt "));
    s.setPassthrough(false, m);
    type(s, m, "vieejt");
    CHECK_EQ(m.screen(), std::string("vieejt việt"));
}

void testReopenAfterBoundary() {
    // "tháy" ␣ ⌫ a → "thấy" (issue #40), when the client reports surrounding text
    bothModes("thays <a", "thấy");
    // without surrounding text the word cannot be proven on screen: plain ⌫
    CHECK_EQ(run("thays <a", DisplayMode::Preedit, defaults(), false), std::string("tháya"));
}

void testReEditAfterCaretMove() {
    for (auto mode : {DisplayMode::Preedit, DisplayMode::Surrounding}) {
        Session s;
        Mock m;
        s.setDisplayMode(mode, m);
        m.doc = "toi toan";      // existing text; caret arrives there by navigation
        type(s, m, ">s ");
        CHECK_EQ(m.screen(), std::string("toi toán "));
        Settings st;
        st.reEditWord = false;
        s.applySettings(st);
        m.doc = "toan";
        type(s, m, ">s");
        CHECK_EQ(m.screen(), std::string("toans"));
    }
}

void testFinishCommitsPreedit() {
    Session s;
    Mock m;
    type(s, m, "vieej");
    s.finish(m);                 // focus out / click
    CHECK_EQ(m.doc, std::string("việ"));
    CHECK_EQ(m.pre, std::string(""));
    type(s, m, "a");
    CHECK_EQ(m.screen(), std::string("việa"));
    Mock m2;
    type(s, m2, "vieej");
    s.finish(m2, false);         // IBus: framework commits the preedit itself
    CHECK_EQ(m2.doc, std::string(""));
    CHECK(!s.composing());
}

void testOverflowNeverLosesText() {
    std::string word(40, 'b');
    bothModes(word + " ", word + " ");
}

void testVniAndLiveSettings() {
    Settings st;
    st.vni = true;
    bothModes("vie65t nam ", "việt nam ", st);
    // settings applied mid-session take effect on the next word
    Session s;
    Mock m;
    type(s, m, "vieejt ");
    s.applySettings(st);
    type(s, m, "vie65t ");
    CHECK_EQ(m.doc, std::string("việt việt "));
}

void testModesAgreeOnRandomScripts() {
    std::mt19937 rng(12345);
    const std::string alphabet = "aeoudwsfrxjzntghiycqAEO  <<.";
    for (int i = 0; i < 3000; ++i) {
        std::string keys;
        int n = 1 + int(rng() % 14);
        for (int k = 0; k < n; ++k) keys += alphabet[rng() % alphabet.size()];
        std::string p = run(keys, DisplayMode::Preedit);
        std::string q = run(keys, DisplayMode::Surrounding);
        if (p != q) {
            std::fprintf(stderr, "mode mismatch for [%s]: preedit=[%s] surrounding=[%s]\n", keys.c_str(),
                         p.c_str(), q.c_str());
            ++g_fail;
            return;
        }
    }
    ++g_pass;
}

// MARK: - Settings

void testConfigParse() {
    Settings d;
    std::string round = serializeConfig(d);
    Settings r = parseConfig(round);
    CHECK_EQ(serializeConfig(r), round);
    Settings s = parseConfig(
        "# comment\n[typing]\ninput_method = \"vni\"  # trailing\nfree_marking = false\n"
        "teencode = true\nspell_check = maybe\n\n[general]\ndisplay_mode = \"surrounding\"\n"
        "toggle_hotkey = \"Alt+Shift+z\"\nper_app_state = false\n[app_modes]\n\"Org.Gnome.TextEditor\" = \"surrounding\"\n"
        "\"kitty\" = \"off\"\n\"bad\" = \"weird\"\n");
    CHECK(s.vni);
    CHECK(!s.freeMarking);
    CHECK(s.teencode);
    CHECK(s.spellCheck);  // bad value → default
    CHECK(s.displayMode == DisplayMode::Surrounding);
    CHECK_EQ(s.toggleHotkey, std::string("Alt+Shift+z"));
    CHECK(!s.perAppState);
    CHECK_EQ(s.appModes.size(), size_t(2));
    CHECK_EQ(s.appModes["org.gnome.texteditor"], std::string("surrounding"));
    Settings e = parseConfig("");
    CHECK(e.freeMarking && e.spellCheck && e.autoRestore && !e.teencode && e.contextualEnglish &&
          e.collisionPrefersVietnamese && !e.vni && e.displayMode == DisplayMode::Preedit);
}

void testSetConfigValue() {
    std::string t = "# mine\n[typing]\nfree_marking = true # c\nfuture_key = 3\n\n[general]\nper_app_state = true\n";
    std::string u = setConfigValue(t, "typing", "free_marking", "false");
    CHECK(u.find("# mine") != std::string::npos);
    CHECK(u.find("future_key = 3") != std::string::npos);
    CHECK(!parseConfig(u).freeMarking);
    u = setConfigValue(u, "typing", "input_method", "\"vni\"");
    CHECK(parseConfig(u).vni);
    CHECK(u.find("input_method") < u.find("[general]"));
    u = setConfigValue(u, "app_modes", "org.gnome.gedit", "\"off\"");
    CHECK_EQ(parseConfig(u).appModes["org.gnome.gedit"], std::string("off"));
    CHECK(parseConfig(u).perAppState);
    CHECK_EQ(setConfigValue("", "general", "display_mode", "\"surrounding\""),
             std::string("[general]\ndisplay_mode = \"surrounding\"\n"));
}

void testShortcutFile() {
    std::string text;
    // sample-shortcuts.yml from the repo root must parse (same format as macOS)
    if (readFile(std::string(VT_SOURCE_ROOT) + "/sample-shortcuts.yml", text)) {
        ShortcutTable t = parseShortcuts(text);
        CHECK_EQ(t["ko"], std::string("không"));
        CHECK_EQ(t["đc"], std::string("được"));
        CHECK_EQ(parseShortcuts(exportShortcuts(t)), t);
    } else {
        ++g_fail;
        std::fprintf(stderr, "sample-shortcuts.yml not found\n");
    }
    ShortcutTable t = parseShortcuts("; c\n// c\na: \"  spaced \"\nb:'q'\nwith space: x\nempty:\nurl: http://x\n");
    CHECK_EQ(t["a"], std::string("  spaced "));
    CHECK_EQ(t["b"], std::string("q"));
    CHECK_EQ(t.count("with space"), size_t(0));
    CHECK_EQ(t.count("empty"), size_t(0));
    CHECK_EQ(t["url"], std::string("http://x"));
    CHECK_EQ(parseShortcuts(exportShortcuts(t)), t);
}

void testHotkeyParse() {
    Hotkey h;
    CHECK(parseHotkey("Ctrl+space", h));
    CHECK_EQ(h.keysym, uint32_t(0x20));
    CHECK_EQ(h.mods, uint32_t(VT_MOD_CTRL));
    CHECK(parseHotkey("ctrl+shift+Z", h));
    CHECK_EQ(h.keysym, uint32_t('z'));
    CHECK_EQ(h.mods, uint32_t(VT_MOD_CTRL | VT_MOD_SHIFT));
    CHECK(parseHotkey("F12", h));
    CHECK_EQ(h.keysym, uint32_t(0xffc9));
    CHECK(!parseHotkey("Super+space", h));   // GNOME's
    CHECK(!parseHotkey("", h));
    CHECK(!parseHotkey("a", h));
    CHECK(!parseHotkey("Hyper+x", h));
}

// MARK: - Surrounding safety (terminals, generic app ids, selections)

// Like a terminal / conhost behind IBus: advertises surrounding text but only ever reports
// an empty one, and cannot delete before the caret (a delete request is simply dropped).
struct TerminalStore : Mock {
    bool textBeforeCursor(std::string &out) override { out.clear(); return true; }
    void deleteBeforeCursor(int) override { ++deletes; }
};

// What a frontend does on focus: resolve the policy, push it into the Session.
void applyPolicy(Session &s, InputContext &ic, const std::string &app, const Settings &st, bool proven) {
    AppPolicy p = resolveAppPolicy(app, st, proven);
    s.applySettings(st);
    s.setPassthrough(p.off, ic);
    s.setDisplayMode(p.mode, ic);
    s.setSurroundingEdits(p.allowSurroundingEdits);
}

void testUnknownAppIdsArePreeditWithoutEdits() {
    Settings s;
    s.displayMode = DisplayMode::Surrounding;
    for (const char *id : {"", "default", "gnome-shell", "GNOME-Shell", "QIBusInputContext", "xim", "XIM"}) {
        CHECK(isUnknownAppId(id));
        AppPolicy p = resolveAppPolicy(id, s, false);
        CHECK(p.mode == DisplayMode::Preedit);
        CHECK(!p.allowSurroundingEdits);
    }
    CHECK(!isUnknownAppId("gedit"));
    // a "surrounding" pin on a generic id covers every app behind it: ignored
    s.appModes["default"] = "surrounding";
    CHECK(resolveAppPolicy("default", s, false).mode == DisplayMode::Preedit);
    // gnome-shell (GNOME Wayland shared context) stays preedit even with text proven
    AppPolicy gs = resolveAppPolicy("gnome-shell", s, true);
    CHECK(gs.mode == DisplayMode::Preedit);
    CHECK(!gs.allowSurroundingEdits);
    // user picked Preedit: an unproven unknown app still may not read back text
    s.displayMode = DisplayMode::Preedit;
    CHECK(!resolveAppPolicy("default", s, false).allowSurroundingEdits);
    // and the Session honours it: no re-edit, no ⌫ reopen, no delete
    Session ss;
    Mock m;
    applyPolicy(ss, m, "default", s, false);
    m.doc = "toan";
    type(ss, m, ">s");
    CHECK_EQ(m.screen(), std::string("toans"));
    ss.finish(m);
    m.doc.clear();
    type(ss, m, "thays <a");
    CHECK_EQ(m.screen(), std::string("tháya"));
    CHECK_EQ(m.deletes, 0);
}

void testProvenUnknownAppAllowed() {
    Settings s;
    s.displayMode = DisplayMode::Surrounding;
    for (const char *id : {"default", "", "xim", "qibusinputcontext"}) {
        AppPolicy p = resolveAppPolicy(id, s, true);
        CHECK(p.mode == DisplayMode::Surrounding);
        CHECK(p.allowSurroundingEdits);
    }
    s.displayMode = DisplayMode::Preedit;
    CHECK(resolveAppPolicy("default", s, true).allowSurroundingEdits);
    Session ss;
    Mock m;
    applyPolicy(ss, m, "default", s, true);
    m.doc = "toi toan";
    type(ss, m, ">s ");
    CHECK_EQ(m.screen(), std::string("toi toán "));
}

void testTerminalStoreTypesVietnamese() {
    const std::string want = "thử gõ tiếng việt";
    for (auto user : {DisplayMode::Preedit, DisplayMode::Surrounding}) {
        for (const char *app : {"default", "gnome-terminal-server", "org.kde.konsole", "kitty", "xim", "vte-2.91"}) {
            Settings st;
            st.displayMode = user;
            Session s;
            TerminalStore t;
            applyPolicy(s, t, app, st, false);  // nothing proven: the client never sent text
            CHECK(s.displayMode() == DisplayMode::Preedit);
            type(s, t, "thuwr gox tieengs vieetj");
            s.finish(t);
            if (t.doc == want && t.deletes == 0) { ++g_pass; continue; }
            ++g_fail;
            std::fprintf(stderr, "terminal [%s] %s: got [%s] deletes=%d\n", app,
                         user == DisplayMode::Preedit ? "preedit" : "surrounding", t.doc.c_str(), t.deletes);
        }
        // even a terminal claiming proven text is forced to preedit without edits
        Settings st;
        st.displayMode = user;
        AppPolicy p = resolveAppPolicy("kitty", st, true);
        CHECK(p.mode == DisplayMode::Preedit);
        CHECK(!p.allowSurroundingEdits);
    }
}

void testSelectionBlocksDeleteAndReEdit() {
    for (auto mode : {DisplayMode::Preedit, DisplayMode::Surrounding}) {
        // re-edit: caret after "toan", but "toan" is selected (Ctrl+L / autocomplete)
        Session s;
        Mock m;
        s.setDisplayMode(mode, m);
        m.doc = "toan";
        m.selection = true;
        type(s, m, ">s");
        CHECK_EQ(m.deletes, 0);
        CHECK(m.screen() != std::string("toán"));
        // reopen: "tháy" ␣ then a selection appears → ⌫ must go to the app
        Session r;
        Mock n;
        r.setDisplayMode(mode, n);
        type(r, n, "thays ");
        n.selection = true;
        int before = n.deletes;
        type(r, n, "<");
        CHECK_EQ(n.deletes, before);
    }
    // Surrounding mid-word: a key needing a delete while a selection exists is typed
    // literally instead (the delete would eat the selection)
    Session s;
    Mock m;
    s.setDisplayMode(DisplayMode::Surrounding, m);
    type(s, m, "vie");
    m.selection = true;
    int before = m.deletes;
    type(s, m, "e");
    CHECK_EQ(m.deletes, before);
    CHECK_EQ(m.doc, std::string("viee"));
    // ⌫ with a selection: no delete of ours, the app's own ⌫ handles it
    m.selection = false;
    type(s, m, "s");
    m.selection = true;
    before = m.deletes;
    type(s, m, "<");
    CHECK_EQ(m.deletes, before);
}

void testModeSwitchWaitsForWordEnd() {
    // IBus: the first surrounding update (→ Surrounding allowed) lands after key 1 of a word
    for (auto from : {DisplayMode::Preedit, DisplayMode::Surrounding}) {
        auto to = from == DisplayMode::Preedit ? DisplayMode::Surrounding : DisplayMode::Preedit;
        Session s;
        Mock m;
        s.setDisplayMode(from, m);
        type(s, m, "t");
        s.setDisplayMode(to, m);
        CHECK(s.displayMode() == from);   // deferred, word not split
        type(s, m, "huwr ");
        CHECK_EQ(m.screen(), std::string("thử "));
        type(s, m, "gox ");
        CHECK(s.displayMode() == to);
        CHECK_EQ(m.screen(), std::string("thử gõ "));
    }
}

void testForcedPreeditList() {
    for (const char *id : {"firefox", "firefox-esr", "librewolf", "zen", "thunderbird", "gnome-shell",
                           "org.mozilla.firefox", "gnome-terminal-server", "kgx", "ptyxis", "org.gnome.Ptyxis",
                           "konsole", "kitty", "alacritty", "wezterm", "foot", "xterm", "tilix", "code",
                           "codium", "chromium", "chromium-browser", "google-chrome", "brave-browser",
                           "vte-2.91", "/usr/bin/xfce4-terminal"}) {
        if (isForcedPreeditApp(id)) { ++g_pass; continue; }
        ++g_fail;
        std::fprintf(stderr, "not forced preedit: %s\n", id);
    }
    CHECK(!isForcedPreeditApp("gedit"));
    CHECK(!isForcedPreeditApp("org.gnome.texteditor"));
}

void testMoreGenericIdsAndSnap() {
    for (const char *id : {"wayland", "sdl2_application", "SDL3_Application", "gtk-im", "(12345)",
                           "gtk3-im:(4242)", "4242"}) {
        if (isUnknownAppId(id)) { ++g_pass; continue; }
        ++g_fail;
        std::fprintf(stderr, "not unknown: %s\n", id);
    }
    CHECK_EQ(normalizeAppId("gtk3-im:gnome-text-editor"), std::string("gnome-text-editor"));
    CHECK_EQ(normalizeAppId("firefox_firefox"), std::string("firefox"));
    CHECK_EQ(normalizeAppId("code_code"), std::string("code"));
    CHECK_EQ(normalizeAppId("libreoffice_writer"), std::string("libreoffice_writer"));
    CHECK_EQ(normalizeAppId("sdl2_application"), std::string("sdl2_application"));
    CHECK(isForcedPreeditApp("firefox_firefox"));
    CHECK(isForcedPreeditApp("gnome-shell-overview"));
    Settings s;
    s.displayMode = DisplayMode::Surrounding;
    CHECK(resolveAppPolicy("gnome-shell-overview", s, true).mode == DisplayMode::Preedit);
    CHECK(!resolveAppPolicy("wayland", s, false).allowSurroundingEdits);
}

void testFieldHints() {
    Settings s;
    s.displayMode = DisplayMode::Surrounding;
    FieldHints f;
    f.terminal = true;
    AppPolicy p = resolveAppPolicy("gedit", s, true, f);
    CHECK(p.mode == DisplayMode::Preedit);
    CHECK(!p.allowSurroundingEdits);
    CHECK(!p.passthrough);
    s.appModes["gedit"] = "surrounding";  // a pin does not beat the field type
    CHECK(resolveAppPolicy("gedit", s, true, f).mode == DisplayMode::Preedit);
    s.appModes.clear();
    f = FieldHints();
    f.urlOrEmail = true;
    CHECK(resolveAppPolicy("gedit", s, true, f).mode == DisplayMode::Preedit);
    CHECK(!resolveAppPolicy("gedit", s, true, f).passthrough);
    f = FieldHints();
    f.numeric = true;
    p = resolveAppPolicy("gedit", s, true, f);
    CHECK(p.passthrough);
    CHECK(p.rememberState);
    f = FieldHints();
    f.sensitive = true;
    p = resolveAppPolicy("gedit", s, true, f);
    CHECK(p.passthrough);
    CHECK(!p.rememberState);
    p = resolveAppPolicy("gedit", s, true);
    CHECK(p.mode == DisplayMode::Surrounding);
    CHECK(!p.passthrough);
    CHECK(p.rememberState);
    // and a passthrough field types literally
    Session ss;
    Mock m;
    ss.setPassthrough(resolveAppPolicy("gedit", s, true, f).passthrough, m);
    type(ss, m, "vieejt 123");
    CHECK_EQ(m.screen(), std::string("vieejt 123"));
}

void testDefaultOffApps() {
    Settings s;
    for (const char *id : {"remmina", "org.remmina.Remmina", "AnyDesk", "rustdesk", "VirtualBoxVM", "vmware",
                           "remote-viewer", "gnome-connections", "org.gnome.Connections", "krdc", "xfreerdp",
                           "wlfreerdp", "moonlight", "parsec", "wine64-preloader", "wine-preloader",
                           "notepad.exe", "C:\\Program Files\\App\\App.EXE"}) {
        if (isDefaultOffApp(id) && resolveAppPolicy(id, s, true).off) { ++g_pass; continue; }
        ++g_fail;
        std::fprintf(stderr, "not default-off: %s\n", id);
    }
    CHECK(!isDefaultOffApp("gedit"));
    CHECK(!isDefaultOffApp("wine"));
    CHECK(!resolveAppPolicy("gedit", s, true).off);
    s.appModes["remmina"] = "preedit";  // [app_modes] overrides the built-in list
    CHECK(!resolveAppPolicy("remmina", s, true).off);
    s.appModes["notepad.exe"] = "surrounding";
    CHECK(!resolveAppPolicy("notepad.exe", s, true).off);
}

void testMoreForcedPreedit() {
    for (const char *id : {"krunner", "org.kde.krunner", "plasmashell", "jetbrains-idea", "jetbrains-pycharm",
                           "idea", "java", "wps", "wpp", "et", "wpsoffice", "desktopeditors", "steam"}) {
        if (isForcedPreeditApp(id)) { ++g_pass; continue; }
        ++g_fail;
        std::fprintf(stderr, "not forced preedit: %s\n", id);
    }
}

size_t indexOf(const std::vector<std::string> &v, const std::string &x) {
    for (size_t i = 0; i < v.size(); ++i)
        if (v[i] == x) return i;
    return v.size();
}

void testCommitBeforeHidingPreedit() {
    // endWord (space)
    {
        Session s;
        Mock m;
        type(s, m, "vieejt ");
        size_t c = indexOf(m.log, "commit:việt"), h = indexOf(m.log, "pre:");
        CHECK(c < m.log.size());
        CHECK(c < h);
    }
    // finish (focus out / click)
    {
        Session s;
        Mock m;
        type(s, m, "vieejt");
        s.finish(m);
        size_t c = indexOf(m.log, "commit:việt"), h = indexOf(m.log, "pre:");
        CHECK(c < m.log.size());
        CHECK(c < h);
    }
    // shortcut expansion
    {
        Settings st;
        auto t = std::make_shared<ShortcutTable>();
        (*t)["ko"] = "không";
        st.shortcuts = t;
        Session s;
        Mock m;
        s.applySettings(st);
        type(s, m, "ko ");
        CHECK_EQ(m.screen(), std::string("không "));
        CHECK(indexOf(m.log, "commit:không") < indexOf(m.log, "pre:"));
    }
    // overflow (> 32 keys in one word)
    {
        Session s;
        Mock m;
        type(s, m, std::string(40, 'b'));
        size_t c = m.log.size(), h = m.log.size();
        for (size_t i = 0; i < m.log.size(); ++i) {
            if (c == m.log.size() && m.log[i].rfind("commit:", 0) == 0) c = i;
            if (c != m.log.size() && m.log[i] == "pre:") { h = i; break; }
        }
        CHECK(c < m.log.size());
        CHECK(c < h);
        CHECK(m.screen().size() >= 40);
    }
}

void testDeleteOnlyEditSendsEmptyCommit() {
    // Surrounding ⌫ reopen: delete the space, insert nothing → empty commit follows
    Session s;
    Mock m;
    s.setDisplayMode(DisplayMode::Surrounding, m);
    type(s, m, "thays ");
    m.log.clear();
    type(s, m, "<");
    CHECK(m.log.size() >= 2);
    if (m.log.size() >= 2) {
        CHECK_EQ(m.log[0], std::string("del:1"));
        CHECK_EQ(m.log[1], std::string("commit:"));
    }
    type(s, m, "a");
    CHECK_EQ(m.screen(), std::string("thấy"));
    // a delete that inserts text needs no extra empty commit
    Session s2;
    Mock m2;
    s2.setDisplayMode(DisplayMode::Surrounding, m2);
    type(s2, m2, "vie");
    m2.log.clear();
    type(s2, m2, "e");
    CHECK(indexOf(m2.log, "commit:") == m2.log.size());
}

// MARK: - App policy / state

void testAppPolicy() {
    Settings s;
    CHECK_EQ(normalizeAppId("/usr/bin/Konsole"), std::string("konsole"));
    CHECK_EQ(normalizeAppId("gtk3-im:gedit"), std::string("gedit"));
    CHECK_EQ(normalizeAppId("org.gnome.TextEditor.desktop"), std::string("org.gnome.texteditor"));
    CHECK(resolveAppPolicy("gedit", s, true).mode == DisplayMode::Preedit);   // default preedit
    s.displayMode = DisplayMode::Surrounding;
    CHECK(resolveAppPolicy("gedit", s, true).mode == DisplayMode::Surrounding);
    CHECK(resolveAppPolicy("gedit", s, false).mode == DisplayMode::Preedit);  // no surrounding
    CHECK(resolveAppPolicy("org.kde.konsole", s, true).mode == DisplayMode::Preedit);
    CHECK(resolveAppPolicy("kitty", s, true).mode == DisplayMode::Preedit);
    CHECK(resolveAppPolicy("libreoffice-writer", s, true).mode == DisplayMode::Preedit);
    s.appModes["kitty"] = "surrounding";
    CHECK(resolveAppPolicy("kitty", s, true).mode == DisplayMode::Surrounding);  // user pin wins
    s.displayMode = DisplayMode::Preedit;
    s.appModes["gedit"] = "surrounding";
    CHECK(resolveAppPolicy("gedit", s, true).mode == DisplayMode::Surrounding);
    s.appModes["steam"] = "off";
    CHECK(resolveAppPolicy("Steam", s, true).off);
}

// GetRunningApplications reply bodies, as gnome-shell 42 (Ubuntu 22.04) and 46 (24.04) send
// them (js/misc/introspect.js: key = ShellApp id, "active-on-seats" only on the focused app,
// "sandboxed-app-id" for Flatpak/Snap windows; the format is the same in both versions).
std::vector<gnome::RunningApp> parseFixture(const char *text, bool *ok = nullptr) {
    GError *err = nullptr;
    GVariant *v = g_variant_parse(nullptr, text, nullptr, nullptr, &err);
    std::vector<gnome::RunningApp> apps;
    bool r = false;
    if (v) {
        r = gnome::parseRunningApplications(v, apps);
        g_variant_unref(v);
    } else {
        std::fprintf(stderr, "fixture parse error: %s\n", err->message);
        g_clear_error(&err);
        ++g_fail;
    }
    if (ok) *ok = r;
    return apps;
}

const char *kGnome42Gedit =
    "({'org.gnome.Nautilus.desktop': @a{sv} {}, "
    "'org.gnome.gedit.desktop': {'active-on-seats': <['seat0']>}, "
    "'firefox_firefox.desktop': {'sandboxed-app-id': <'firefox'>}, "
    "'org.gnome.Terminal.desktop': @a{sv} {}},)";
const char *kGnome42Terminal =
    "({'org.gnome.gedit.desktop': @a{sv} {}, "
    "'org.gnome.Terminal.desktop': {'active-on-seats': <['seat0']>}},)";
const char *kGnome46Flatpak =
    "({'org.gnome.TextEditor.desktop': @a{sv} {}, 'window:7': @a{sv} {}, "
    "'org.mozilla.firefox.desktop': {'active-on-seats': <['seat0']>, 'sandboxed-app-id': <'org.mozilla.firefox'>}},)";
const char *kGnome46TextEditor =
    "({'org.gnome.TextEditor.desktop': {'active-on-seats': <['seat0']>}, "
    "'org.gnome.Ptyxis.desktop': @a{sv} {}},)";

void testGnomePayloads() {
    bool ok = false;
    auto a = parseFixture(kGnome42Gedit, &ok);
    CHECK(ok);
    CHECK_EQ(a.size(), size_t(4));
    CHECK_EQ(gnome::focusedAppId(a), std::string("org.gnome.gedit"));
    CHECK_EQ(gnome::focusedAppId(parseFixture(kGnome42Terminal)), std::string("org.gnome.terminal"));
    a = parseFixture(kGnome46Flatpak);
    CHECK_EQ(gnome::focusedAppId(a), std::string("org.mozilla.firefox"));
    bool sandboxSeen = false;
    for (auto &x : a) sandboxSeen = sandboxSeen || x.sandboxedAppId == "org.mozilla.firefox";
    CHECK(sandboxSeen);
    CHECK_EQ(gnome::focusedAppId(parseFixture(kGnome46TextEditor)), std::string("org.gnome.texteditor"));
    // bare a{sa{sv}} (no tuple) is accepted too
    CHECK_EQ(gnome::focusedAppId(parseFixture("{'code_code.desktop': {'active-on-seats': <['seat0']>}}")),
             std::string("code"));
    // window-backed app (no .desktop): no id — unless the sandbox names it
    CHECK_EQ(gnome::focusedAppId(parseFixture("({'window:12': {'active-on-seats': <['seat0']>}},)")), std::string());
    CHECK_EQ(gnome::focusedAppId(parseFixture(
                 "({'window:3': {'active-on-seats': <['seat0']>, 'sandboxed-app-id': <'com.example.Notes'>}},)")),
             std::string("com.example.notes"));
    // nothing focused (desktop / shell popup), empty seat list, two "focused" apps
    CHECK_EQ(gnome::focusedAppId(parseFixture("({'org.gnome.Nautilus.desktop': @a{sv} {}},)")), std::string());
    CHECK_EQ(gnome::focusedAppId(parseFixture("({'org.gnome.gedit.desktop': {'active-on-seats': <@as []>}},)")),
             std::string());
    CHECK_EQ(gnome::focusedAppId(parseFixture("({'a.desktop': {'active-on-seats': <['seat0']>}, "
                                              "'b.desktop': {'active-on-seats': <['seat1']>}},)")),
             std::string());
    // foreign payloads: other gnome-shell replies seen by the monitor
    parseFixture("('ok',)", &ok);
    CHECK(!ok);
    parseFixture("({uint64 1: {'app-id': <'x'>}},)", &ok);  // GetWindows (a{ta{sv}})
    CHECK(!ok);
    CHECK(!gnome::parseRunningApplications(nullptr, a));
}

void testGnomeFocusTracker() {
    gnome::FocusTracker t;
    auto gedit = parseFixture(kGnome42Gedit), term = parseFixture(kGnome42Terminal);
    CHECK_EQ(t.resolve("gnome-shell"), std::string("gnome-shell"));  // nothing known yet
    CHECK_EQ(t.resolve("gtk3-im:gedit"), std::string("gtk3-im:gedit"));
    // focus change: signal → portal calls → reply to the portal
    CHECK(!t.onAppsChanged());
    t.onCall(":1.40", 7);
    CHECK_EQ(t.resolve("default"), std::string("default"));  // pending
    CHECK(!t.onReply(":1.41", 7, gedit));                     // not the caller
    CHECK(!t.onReply(":1.40", 8, gedit));                     // not that call
    CHECK(t.onReply(":1.40", 7, gedit));
    CHECK_EQ(t.resolve("gnome-shell"), std::string("org.gnome.gedit"));
    CHECK_EQ(t.resolve("default"), std::string("org.gnome.gedit"));  // IBus 1.5.26
    CHECK_EQ(t.resolve("wayland"), std::string("org.gnome.gedit"));
    CHECK_EQ(t.resolve(""), std::string("org.gnome.gedit"));
    CHECK_EQ(t.resolve("kitty"), std::string("kitty"));  // a real id is never replaced
    CHECK(!t.onReply(":1.40", 7, term));                  // answered already
    // next switch: generic again until the new answer (no guessing from the old app)
    CHECK(t.onAppsChanged());
    CHECK_EQ(t.resolve("gnome-shell"), std::string("gnome-shell"));
    t.onCall(":1.40", 9);
    CHECK(t.onReply(":1.40", 9, term));
    CHECK_EQ(t.resolve("gnome-shell"), std::string("org.gnome.terminal"));
    // a call made BEFORE the latest signal: its answer is stale → still pending
    t.onCall(":1.40", 10);
    CHECK(t.onAppsChanged());
    t.onReply(":1.40", 10, gedit);
    CHECK(t.pending());
    CHECK_EQ(t.resolve("gnome-shell"), std::string("gnome-shell"));
    t.onCall(":1.40", 11);
    t.onReply(":1.40", 11, gedit);
    CHECK_EQ(t.resolve("gnome-shell"), std::string("org.gnome.gedit"));
    // overview beats the focused app
    CHECK(t.onOverview(true));
    CHECK(!t.onOverview(true));
    CHECK_EQ(t.resolve("gnome-shell"), std::string("gnome-shell-overview"));
    CHECK_EQ(t.resolve("gtk3-im:gedit"), std::string("gtk3-im:gedit"));
    CHECK(t.onOverview(false));
    CHECK_EQ(t.resolve("gnome-shell"), std::string("org.gnome.gedit"));
    // desktop focused (no active app) → generic
    t.onAppsChanged();
    t.onCall(":1.40", 12);
    t.onReply(":1.40", 12, parseFixture("({'org.gnome.gedit.desktop': @a{sv} {}},)"));
    CHECK_EQ(t.resolve("gnome-shell"), std::string("gnome-shell"));
    // many unanswered calls never grow without bound, and the newest still counts
    for (uint32_t i = 100; i < 200; ++i) t.onCall(":1.40", i);
    CHECK(t.onReply(":1.40", 199, term));
}

void testGnomeResolvedPolicy() {
    // The resolved id goes through the normal policy: no-underline where proven and safe.
    Settings s;
    s.displayMode = DisplayMode::Surrounding;
    gnome::FocusTracker t;
    auto answer = [&t](const char *fixture, uint32_t serial) {
        t.onAppsChanged();
        t.onCall(":1.9", serial);
        t.onReply(":1.9", serial, parseFixture(fixture));
    };
    // unknown: generic → preedit, no edits even with proven surrounding
    CHECK(resolveAppPolicy(t.resolve("gnome-shell"), s, true).mode == DisplayMode::Preedit);
    CHECK(!resolveAppPolicy(t.resolve("gnome-shell"), s, true).allowSurroundingEdits);
    answer(kGnome46TextEditor, 1);
    auto p = resolveAppPolicy(t.resolve("gnome-shell"), s, true);
    CHECK(p.mode == DisplayMode::Surrounding);
    CHECK(p.allowSurroundingEdits);
    CHECK(resolveAppPolicy(t.resolve("gnome-shell"), s, false).mode == DisplayMode::Preedit);  // unproven
    answer(kGnome42Terminal, 2);
    CHECK(resolveAppPolicy(t.resolve("default"), s, true).mode == DisplayMode::Preedit);  // terminal
    answer(kGnome46Flatpak, 3);
    CHECK(resolveAppPolicy(t.resolve("gnome-shell"), s, true).mode == DisplayMode::Preedit);  // Firefox
    answer(kGnome42Gedit, 4);
    t.onOverview(true);
    CHECK(resolveAppPolicy(t.resolve("gnome-shell"), s, true).mode == DisplayMode::Preedit);  // overview
    // per-app pins apply to the resolved id ("gedit" matches org.gnome.gedit's short name)
    t.onOverview(false);
    s.appModes["gedit"] = "off";
    CHECK(resolveAppPolicy(t.resolve("gnome-shell"), s, true).off);
}

void testGnomeSessionDetection() {
    CHECK(gnome::isGnomeWayland("ubuntu:GNOME", "wayland", nullptr));
    CHECK(gnome::isGnomeWayland("GNOME", "wayland", ""));
    CHECK(gnome::isGnomeWayland("GNOME-Classic:GNOME", nullptr, "wayland-0"));
    CHECK(!gnome::isGnomeWayland("ubuntu:GNOME", "x11", "wayland-0"));  // X11 session
    CHECK(!gnome::isGnomeWayland("KDE", "wayland", "wayland-0"));
    CHECK(!gnome::isGnomeWayland("GNOME-Flashback", "wayland", nullptr));
    CHECK(!gnome::isGnomeWayland(nullptr, "wayland", "wayland-0"));
    CHECK(!gnome::isGnomeWayland("GNOME", nullptr, nullptr));
    CHECK(gnome::isSharedShellClientId("gnome-shell"));
    CHECK(gnome::isSharedShellClientId("default"));
    CHECK(gnome::isSharedShellClientId("Wayland"));
    CHECK(gnome::isSharedShellClientId(""));
    CHECK(!gnome::isSharedShellClientId("gtk3-im:gedit"));
    CHECK(!gnome::isSharedShellClientId("gnome-shell-overview"));
    CHECK(!gnome::isSharedShellClientId("xim"));
}

void testAppStateStoreAndWatcher() {
    char tmpl[] = "/tmp/vt-test-XXXXXX";
    std::string dir = mkdtemp(tmpl);
    std::string path = dir + "/state/app-state";
    {
        AppStateStore st(path);
        st.load();
        CHECK(st.vietnamese("gedit", true));
        CHECK(!st.vietnamese("gedit", false));
        st.set("gedit", false);
        st.set("kitty", true);
    }
    AppStateStore st2(path);
    st2.load();
    CHECK(!st2.vietnamese("gedit", true));
    CHECK(st2.vietnamese("kitty", false));

    // live reload through inotify (atomic tmp + rename, as the settings app writes)
    std::string cdir = dir + "/cfg";
    SettingsWatcher w(cdir);
    CHECK(w.fd() >= 0);
    CHECK(!w.settings().vni);
    CHECK(writeFileAtomic(cdir + "/config.toml", "[typing]\ninput_method = \"vni\"\n"));
    CHECK(w.drain());
    CHECK(w.changedOnDisk());
    CHECK(w.reload().vni);
    CHECK(!w.changedOnDisk());
    CHECK(writeFileAtomic(cdir + "/shortcuts.yml", "ko: không\n"));
    CHECK(w.drain());
    CHECK_EQ(w.reload().shortcuts->at("ko"), std::string("không"));
    std::string cmd = "rm -rf '" + dir + "'";
    CHECK_EQ(std::system(cmd.c_str()), 0);
}

}  // namespace

int main() {
    testBasicTyping();
    testPreeditIsUnderlinedComposition();
    testSurroundingHasNoPreedit();
    testShortcuts();
    testCtrlChordCommits();
    testToggleHotkey();
    testPasswordLiteral();
    testReopenAfterBoundary();
    testReEditAfterCaretMove();
    testFinishCommitsPreedit();
    testOverflowNeverLosesText();
    testVniAndLiveSettings();
    testModesAgreeOnRandomScripts();
    testConfigParse();
    testSetConfigValue();
    testShortcutFile();
    testHotkeyParse();
    testAppPolicy();
    testUnknownAppIdsArePreeditWithoutEdits();
    testProvenUnknownAppAllowed();
    testTerminalStoreTypesVietnamese();
    testSelectionBlocksDeleteAndReEdit();
    testForcedPreeditList();
    testModeSwitchWaitsForWordEnd();
    testMoreGenericIdsAndSnap();
    testFieldHints();
    testDefaultOffApps();
    testMoreForcedPreedit();
    testCommitBeforeHidingPreedit();
    testDeleteOnlyEditSendsEmptyCommit();
    testAppStateStoreAndWatcher();
    testGnomePayloads();
    testGnomeFocusTracker();
    testGnomeResolvedPolicy();
    testGnomeSessionDetection();
    std::printf("common tests: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
