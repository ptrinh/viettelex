// test_common — unit tests for linux/common: Session (with a mock InputContext),
// settings/shortcuts/hotkey parsing, app policy, app-state store.
// Links the real libtelexcore, so these are end-to-end through the C ABI.

#include "viettelex/app.h"
#include "viettelex/keys.h"
#include "viettelex/session.h"
#include "viettelex/settings.h"
#include "viettelex/watcher.h"

#include <cstdio>
#include <cstdlib>
#include <random>
#include <string>
#include <unistd.h>

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
    int deletes = 0, preeditUpdates = 0;
    void setPreedit(const std::string &s) override { pre = s; ++preeditUpdates; }
    void commit(const std::string &s) override { doc += s; }
    void deleteBeforeCursor(int n) override { ++deletes; popChars(doc, n); }
    bool textBeforeCursor(std::string &out) override {
        if (!surrounding) return false;
        out = doc;
        return true;
    }
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
    testAppStateStoreAndWatcher();
    std::printf("common tests: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
