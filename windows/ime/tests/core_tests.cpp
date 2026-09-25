#include "app_policy.h"
#include "hotkey.h"
#include "keymap.h"
#include "settings.h"
#include "shortcuts.h"
#include "test.h"

#include <viettelex/vtx_engine.h>

using namespace vtx;

TEST(keymap_letters_shift_caps) {
    Modifiers m;
    CHECK_EQ(classifyKey('A', m).ch, U'a');
    m.shift = true;
    CHECK_EQ(classifyKey('A', m).ch, U'A');
    m.capsLock = true;
    CHECK_EQ(classifyKey('A', m).ch, U'a');  // Shift XOR Caps
    m.shift = false;
    CHECK_EQ(classifyKey('A', m).ch, U'A');
    CHECK_EQ(classifyKey('1', m).ch, U'1');  // Caps never shifts digits
}

TEST(keymap_us_punctuation_not_vietnamese_layout) {
    Modifiers m;
    CHECK_EQ(classifyKey('1', m).ch, U'1');
    CHECK_EQ(classifyKey(vk::Oem4, m).ch, U'[');
    CHECK_EQ(classifyKey(vk::Oem6, m).ch, U']');
    m.shift = true;
    CHECK_EQ(classifyKey('2', m).ch, U'@');
    CHECK_EQ(classifyKey(vk::Oem7, m).ch, U'"');
    CHECK_EQ(classifyKey(vk::Oem4, m).ch, U'{');
}

TEST(keymap_kinds) {
    Modifiers m;
    CHECK(classifyKey(vk::Back, m).kind == KeyKind::Backspace);
    CHECK(classifyKey(vk::Return, m).kind == KeyKind::Boundary);
    CHECK(classifyKey(vk::Tab, m).kind == KeyKind::Boundary);
    CHECK(classifyKey(vk::Left, m).kind == KeyKind::Navigation);
    CHECK(classifyKey(vk::Delete, m).kind == KeyKind::Navigation);
    CHECK(classifyKey(vk::Shift, m).kind == KeyKind::Modifier);
    CHECK(classifyKey(vk::LWin, m).kind == KeyKind::Modifier);
    CHECK(classifyKey(0x70 /*F1*/, m).kind == KeyKind::Other);
    CHECK(classifyKey(vk::Space, m).kind == KeyKind::Char);
    CHECK(classifyKey(vk::Numpad0 + 5, m).ch == U'5');
    m.ctrl = true;
    CHECK(classifyKey('C', m).kind == KeyKind::Chord);
    m.ctrl = false;
    m.alt = true;
    CHECK(classifyKey('Z', m).kind == KeyKind::Chord);
}

TEST(hotkey_parse_and_default) {
    CHECK(parseSwitchHotkey("ctrl-shift") == SwitchHotkey::CtrlShift);
    CHECK(parseSwitchHotkey("win-space") == SwitchHotkey::WinSpace);
    CHECK(parseSwitchHotkey("alt-z") == SwitchHotkey::AltZ);
    CHECK(parseSwitchHotkey("off") == SwitchHotkey::Off);
    CHECK(parseSwitchHotkey("") == SwitchHotkey::CtrlShift);
    CHECK(parseSwitchHotkey("garbage") == SwitchHotkey::CtrlShift);
    CHECK_EQ(std::string(switchHotkeyName(SwitchHotkey::WinSpace)), std::string("win-space"));
}

TEST(hotkey_chord_clean_press_release) {
    ModifierChord c;
    CHECK(!c.note(kModCtrl));
    CHECK(!c.note(kModCtrl | kModShift));  // armed
    CHECK(c.note(kModCtrl));               // release shift -> fire
    CHECK(!c.note(0));                     // already fired
}

TEST(hotkey_chord_other_key_disarms) {
    ModifierChord c;
    c.note(kModCtrl | kModShift);
    c.disarm();  // Ctrl+Shift+C
    CHECK(!c.note(0));
}

TEST(hotkey_chord_extra_modifier_disarms) {
    ModifierChord c;
    c.note(kModCtrl | kModShift);
    CHECK(!c.note(kModCtrl | kModShift | kModAlt));
    CHECK(!c.note(0));
}

TEST(hotkey_chord_shift_first_order_irrelevant) {
    ModifierChord c;
    c.note(kModShift);
    c.note(kModShift | kModCtrl);
    CHECK(c.note(0));
}

TEST(settings_defaults_match_macos) {
    Settings s;
    CHECK(s.freeMarking);
    CHECK(s.autoRestore);
    CHECK(s.liveSpellCheck);
    CHECK(s.contextualEnglish);
    CHECK(s.collisionPrefersVietnamese);
    CHECK(s.reEditWord);
    CHECK(!s.vniMode);
    CHECK(!s.simpleTelex);
    CHECK(!s.quickTelex);
    CHECK(!s.modernOrthography);
    CHECK(!s.bracketVowels);
    CHECK(!s.teencode);
    CHECK(!s.autoUpdateCheck);
    CHECK(!s.debugLogging);
    CHECK_EQ(s.switchHotkey, std::string("ctrl-shift"));
    CHECK_EQ(s.uiLanguage, std::string("vi"));
    uint32_t f = s.engineFlags();
    CHECK(f & VTX_FREE_MARKING);
    CHECK(f & VTX_LIVE_SPELL_CHECK);
    CHECK(f & VTX_CONTEXTUAL_ENGLISH);
    CHECK(f & VTX_COLLISION_PREFERS_VI);
    CHECK(f & VTX_ENGLISH_WORD_RESTORE);
    CHECK(!(f & VTX_TEENCODE));  // app default OFF even though the engine default is ON
    CHECK(!(f & VTX_VNI));
}

TEST(settings_snapshot_roundtrip) {
    Settings s;
    s.vniMode = true;
    s.autoRestore = false;
    s.debugLogging = true;
    s.switchHotkey = "win-space";
    s.uiLanguage = "en";
    s.shortcuts[u"vn"] = u"Việt Nam";
    s.shortcuts[u"ko"] = u"không";
    s.appModes["code.exe"] = AppMode::InPlace;
    s.appModes["game.exe"] = AppMode::Off;
    std::vector<uint8_t> b = serialize(s);
    Settings r;
    CHECK(deserialize(b.data(), b.size(), r));
    CHECK(r == s);
}

TEST(settings_snapshot_rejects_garbage) {
    Settings r;
    r.vniMode = true;
    uint8_t junk[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
    CHECK(!deserialize(junk, sizeof junk, r));
    CHECK(r == Settings{});
    Settings s;
    s.shortcuts[u"a"] = u"b";
    std::vector<uint8_t> b = serialize(s);
    for (size_t cut = 0; cut < b.size(); ++cut) CHECK(!deserialize(b.data(), cut, r));
    CHECK(!deserialize(nullptr, 0, r));
}

TEST(json_flat_roundtrip) {
    StringMap m{{"vn", "Việt Nam"}, {"q\"x", "a\\b\nc"}, {"e", ""}};
    StringMap r;
    CHECK(parseFlatJson(toFlatJson(m), r));
    CHECK(r == m);
    CHECK(parseFlatJson("  { }  ", r) && r.empty());
    CHECK(parseFlatJson("{\"a\":\"\\u1ec7\"}", r));
    CHECK_EQ(r["a"], std::string("ệ"));
    CHECK(!parseFlatJson("{\"a\":1}", r));
    CHECK(!parseFlatJson("{\"a\":\"b\"", r));
    CHECK(!parseFlatJson("[]", r));
}

TEST(shortcut_import_formats) {
    StringMap r;
    CHECK(parseShortcutFile("{\"vn\":\"Việt Nam\"}", r));
    CHECK_EQ(r["vn"], std::string("Việt Nam"));
    CHECK(parseShortcutFile("# c\n; c\n// c\nvn: Việt Nam\nko:không\nq: \"  spaced \"\nbad key: x\n", r));
    CHECK_EQ(r.size(), size_t(3));
    CHECK_EQ(r["ko"], std::string("không"));
    CHECK_EQ(r["q"], std::string("  spaced "));
    CHECK(!parseShortcutFile("<?xml version=\"1.0\"?>\n<!DOCTYPE plist PUBLIC>\n", r));
    StringMap back;
    StringMap m{{"vn", "Việt Nam"}, {"sp", " x"}};
    CHECK(parseShortcutFile(exportShortcutsYaml(m), back));
    CHECK(back == m);
}

TEST(shortcut_lookup_rules) {
    std::map<std::u16string, std::u16string> t{{u"vn", u"Việt Nam"}, {u"cf", u"cà phê"}};
    CHECK(findShortcut(t, u"vn", u"vn", 0) != nullptr);
    CHECK(findShortcut(t, u"c", u"cf", u' ') != nullptr);  // raw fallback ("cf" composes away)
    CHECK(findShortcut(t, u"vn", u"vn", u'5') == nullptr);
    CHECK(findShortcut(t, u"vn", u"vn", u'#') == nullptr);
    CHECK(findShortcut(t, u"xx", u"xx", 0) == nullptr);
}

TEST(app_policy_resolution) {
    CHECK_EQ(normalizeExeName("C:\\Program Files\\Foo\\Code.EXE"), std::string("code.exe"));
    CHECK_EQ(normalizeExeName("notepad.exe"), std::string("notepad.exe"));
    std::map<std::string, AppMode> o;
    CHECK(resolveAppMode("notepad.exe", o) == AppMode::Composition);
    CHECK(resolveAppMode("mstsc.exe", o) == AppMode::Off);
    o["mstsc.exe"] = AppMode::Composition;  // user override beats built-in
    CHECK(resolveAppMode("mstsc.exe", o) == AppMode::Composition);
    o["code.exe"] = AppMode::InPlace;
    CHECK(resolveAppMode("code.exe", o) == AppMode::InPlace);
    AppMode m;
    CHECK(parseAppMode("hookFallback", m) && m == AppMode::HookFallback);
    CHECK(!parseAppMode("bogus", m));
    for (AppMode x : {AppMode::Composition, AppMode::InPlace, AppMode::HookFallback, AppMode::Off})
        CHECK(parseAppMode(appModeName(x), m) && m == x);
}

TEST(input_scope_policy) {
    int pw[] = {31};
    int def[] = {0};
    int url[] = {1};
    int priv[] = {61, 0};
    int mixed[] = {0, 29};
    int email[] = {5};
    CHECK(classifyInputScopes(pw, 1) == FieldPolicy::Literal);
    CHECK(classifyInputScopes(def, 1) == FieldPolicy::Normal);
    CHECK(classifyInputScopes(url, 1) == FieldPolicy::Normal);   // Chrome omnibox
    CHECK(classifyInputScopes(priv, 2) == FieldPolicy::Normal);  // InPrivate windows
    CHECK(classifyInputScopes(mixed, 2) == FieldPolicy::Literal);
    CHECK(classifyInputScopes(email, 1) == FieldPolicy::Literal);
    CHECK(classifyInputScopes(nullptr, 0) == FieldPolicy::Normal);
}

TEST(utf_roundtrip) {
    std::string s = "Tiếng Việt 😀";
    CHECK_EQ(utf16ToUtf8(utf8ToUtf16(s)), s);
    CHECK_EQ(utf8ToUtf16("ệ").size(), size_t(1));
}
