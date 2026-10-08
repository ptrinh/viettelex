#include "app_policy.h"
#include "game_ipc.h"
#include "ipc.h"
#include "hotkey.h"
#include "keymap.h"
#include "settings.h"
#include "shortcuts.h"
#include "text_tool_ipc.h"
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
    CHECK(!s.showTrayIcon);  // tray icon hidden by default (1.0.5)
    CHECK(!s.underlineMisspelled);  // red squiggle is opt-in
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
    s.showTrayIcon = true;
    s.underlineMisspelled = true;
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
    CHECK(resolveAppMode("notepad.exe", o) == AppMode::InPlace);  // default since 1.0.9
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

#include "com_path.h"

TEST(arm64x_com_server_path) {
    const std::wstring a = L"C:\\Program Files\\VietTelex\\VietTelexTIP_arm64.dll";
    const std::wstring x = L"C:\\Program Files\\VietTelex\\viettelextip_X64.DLL";
    const std::wstring f = L"C:\\Program Files\\VietTelex\\VietTelexTIP.dll";
    CHECK(comServerPath(a, true) == f);
    CHECK(comServerPath(x, true) == f);
    CHECK(comServerPath(a, false) == a);  // no forwarder installed: register self
    CHECK(comServerPath(f, true) == f);   // plain x64/x86 DLL
    CHECK(forwarderCandidate(L"C:\\x\\VietTelexTIP.dll").empty());
    CHECK(forwarderCandidate(L"VietTelexTIP_arm64.dll") == L"VietTelexTIP.dll");
    // version-named release DLLs (1.0.6+)
    CHECK(forwarderCandidate(L"C:\\VT\\VietTelexTIP_arm64_1_0_6.dll") == L"C:\\VT\\VietTelexTIP_1_0_6.dll");
    CHECK(forwarderCandidate(L"VietTelexTIP_x64_1_0_6.dll") == L"VietTelexTIP_1_0_6.dll");
    CHECK(forwarderCandidate(L"VietTelexTIP_1_0_6.dll").empty());
    CHECK(forwarderCandidate(L"VietTelexTIP_arm64_x.dll").empty());
}

#include "registration.h"

TEST(registration_data_shape) {
    auto e = vtx::reg::tipRegistryEntries("C:\\VT\\VietTelexTIP.dll", "C:\\VT\\icon.dll");
    CHECK_EQ(e.size(), size_t(9 + 2 * vtx::reg::kCategoryCount));
    bool apartment = false, inproc = false, subst = false, enable = false;
    size_t catKeys = 0, itemKeys = 0;
    const std::string clsid = vtx::reg::kClsid;
    for (const auto& r : e) {
        if (r.name == "ThreadingModel") apartment = r.sz == "Apartment";
        if (r.key == "SOFTWARE\\Classes\\CLSID\\" + clsid + "\\InprocServer32" && r.name.empty())
            inproc = r.sz == "C:\\VT\\VietTelexTIP.dll";
        if (r.name == "SubstituteLayout") subst = r.dword == 0x04090409;
        if (r.name == "Enable" && r.key == vtx::reg::languageProfileKey()) enable = r.dword == 1;
        if (r.type == vtx::reg::ValueType::Key) {
            if (r.key.find("\\Category\\Category\\") != std::string::npos) ++catKeys;
            if (r.key.find("\\Category\\Item\\" + clsid + "\\") != std::string::npos) ++itemKeys;
        }
    }
    CHECK(apartment && inproc && subst && enable);
    CHECK_EQ(catKeys, vtx::reg::kCategoryCount);
    CHECK_EQ(itemKeys, vtx::reg::kCategoryCount);
    CHECK_EQ(vtx::reg::languageProfileKey(), std::string("SOFTWARE\\Microsoft\\CTF\\TIP\\") + clsid +
                                                 "\\LanguageProfile\\0x0000042a\\" + vtx::reg::kProfile);
}

#include "res/icon_ids.h"

TEST(icon_choice_mapping) {
    CHECK(parseIconChoice("vt") == IconChoice::Vt);
    CHECK(parseIconChoice("star") == IconChoice::Star);
    CHECK(parseIconChoice("flag") == IconChoice::Flag);
    CHECK(parseIconChoice("logo") == IconChoice::Logo);
    CHECK(parseIconChoice("vi") == IconChoice::Vi);
    CHECK(parseIconChoice("letter") == IconChoice::Vt);  // retired "V / E" migrates to Vᴛ
    CHECK(parseIconChoice("") == IconChoice::Vt);
    for (int i = 0; i < kIconChoiceCount; ++i) {
        IconChoice c = static_cast<IconChoice>(i);
        CHECK(parseIconChoice(iconChoiceName(c)) == c);
    }
    // dynamic indicator icon
    CHECK_EQ(indicatorIcon(IconChoice::Vt, true, false).resourceId, IDI_GLYPH_VT_V_DARK);
    CHECK_EQ(indicatorIcon(IconChoice::Vt, false, true).resourceId, IDI_GLYPH_VT_E_LIGHT);
    CHECK_EQ(indicatorIcon(IconChoice::Star, true, true).resourceId, IDI_GLYPH_STAR_V_LIGHT);
    CHECK_EQ(indicatorIcon(IconChoice::Flag, false, false).resourceId, IDI_GLYPH_FLAG_E_DARK);
    CHECK_EQ(indicatorIcon(IconChoice::Logo, true, false).resourceId, IDI_APP);
    CHECK(!indicatorIcon(IconChoice::Logo, true, false).dim);
    CHECK(indicatorIcon(IconChoice::Logo, false, false).dim);  // English = dimmed logo
    CHECK_EQ(indicatorIcon(IconChoice::Vi, true, true).resourceId, 0);
    CHECK_EQ(std::string(indicatorIcon(IconChoice::Vi, true, true).text), std::string("VI"));
    CHECK_EQ(std::string(indicatorIcon(IconChoice::Vi, false, true).text), std::string("EN"));
    // static profile icon: resource id and index in the DLL
    CHECK_EQ(profileIconId(IconChoice::Vt), IDI_PROFILE_VT);
    CHECK_EQ(profileIconId(IconChoice::Vi), IDI_PROFILE_VI);
    CHECK_EQ(profileIconIndex(IconChoice::Vt), 13);
    CHECK_EQ(profileIconIndex(IconChoice::Vi), 17);
    CHECK_EQ(static_cast<int>(vtx::reg::kIconIndex), profileIconIndex(IconChoice::Vt));
    // kAllIconIds must be ascending (Windows' icon-group index order)
    for (size_t i = 1; i < sizeof(kAllIconIds) / sizeof(kAllIconIds[0]); ++i) CHECK(kAllIconIds[i - 1] < kAllIconIds[i]);
}

TEST(glyph_icon_ids) {
    CHECK_EQ(glyphIconId("vt", true, false), IDI_GLYPH_VT_V_DARK);
    CHECK_EQ(glyphIconId("vt", true, true), IDI_GLYPH_VT_V_LIGHT);
    CHECK_EQ(glyphIconId("vt", false, false), IDI_GLYPH_VT_E_DARK);
    CHECK_EQ(glyphIconId("star", false, true), IDI_GLYPH_STAR_E_LIGHT);
    CHECK_EQ(glyphIconId("flag", true, false), IDI_GLYPH_FLAG_V_DARK);
    CHECK_EQ(glyphIconId("garbage", true, true), IDI_GLYPH_VT_V_LIGHT);  // unknown -> default
    CHECK_EQ(glyphIconId("letter", true, true), IDI_GLYPH_VT_V_LIGHT);   // retired -> Vᴛ
    CHECK_EQ(glyphIconId("logo", true, true), IDI_APP);
    CHECK_EQ(glyphIconId("vi", true, true), 0);
}

TEST(display_attribute_provider_is_registered) {
    // No-underline composition depends on TSF finding our ITfDisplayAttributeProvider,
    // which it does ONLY through this category (Chrome underlines otherwise).
    bool found = false;
    for (size_t i = 0; i < vtx::reg::kCategoryCount; ++i)
        if (std::string(vtx::reg::kCategories[i].guid) == "{046B8C80-1647-40F7-9B21-B93B81AABC1B}") found = true;
    CHECK(found);
    bool rows = false;
    for (const auto& e : vtx::reg::tipRegistryEntries("x", "y"))
        if (e.key.find("\\Category\\Category\\{046B8C80-1647-40F7-9B21-B93B81AABC1B}\\") != std::string::npos) rows = true;
    CHECK(rows);  // ...and the MSI writes it (release.sh diffs the built MSI against these rows)
}

TEST(ipc_state_changed_is_internal) {
    // TIP -> app Việt/Anh notification (tray icon is the only state indicator since 1.0.8);
    // accepted on the window message, never from the command line.
    CHECK(isValidAppCommand(static_cast<unsigned>(AppCommand::StateChanged)));
    CHECK(!isUserCommand(static_cast<unsigned>(AppCommand::StateChanged)));
    CHECK(isUserCommand(static_cast<unsigned>(AppCommand::OpenSettings)));
    CHECK(isValidAppCommand(static_cast<unsigned>(AppCommand::DirectMode)));
    CHECK(!isUserCommand(static_cast<unsigned>(AppCommand::DirectMode)));
    CHECK(isValidAppCommand(static_cast<unsigned>(AppCommand::SetAppLanguage)));
    CHECK(!isUserCommand(static_cast<unsigned>(AppCommand::SetAppLanguage)));
    CHECK(isValidAppCommand(static_cast<unsigned>(AppCommand::TextToolReply)));
    CHECK(!isUserCommand(static_cast<unsigned>(AppCommand::TextToolReply)));
    CHECK(isValidAppCommand(static_cast<unsigned>(AppCommand::UserSwitched)));
    CHECK(!isUserCommand(static_cast<unsigned>(AppCommand::UserSwitched)));
    CHECK(!isValidAppCommand(0) && !isValidAppCommand(11));
}

TEST(text_tool_ipc_roundtrip) {
    // Công cụ văn bản: TIP <-> app payloads (text_tool_ipc.h)
    const std::u16string t = u"toi di hoc \U0001F600 Việt";
    std::vector<uint8_t> b = packTextToolData(0x0ABCDEF1u, 3, t);
    uint32_t req = 0, tool = 0;
    std::u16string out;
    CHECK(unpackTextToolData(b.data(), b.size(), req, tool, out));
    CHECK_EQ(req, 0x0ABCDEF1u);
    CHECK_EQ(tool, 3u);
    CHECK(out == t);
    CHECK(unpackTextToolData(b.data(), 8, req, tool, out) && out.empty());
    CHECK(!unpackTextToolData(b.data(), 7, req, tool, out));
    CHECK(!unpackTextToolData(b.data(), b.size() - 1, req, tool, out));  // odd size
    CHECK(!unpackTextToolData(nullptr, 0, req, tool, out));
    std::vector<uint8_t> big = packTextToolData(1, 0, std::u16string(kTextToolMaxLength + 1, u'a'));
    CHECK(!unpackTextToolData(big.data(), big.size(), req, tool, out));  // over the cap
    const uint32_t lp = textToolReplyParam(0x1234567u, TextToolStatus::Refused);
    CHECK_EQ(textToolReplyRequest(lp), 0x1234567u);
    CHECK(textToolReplyStatus(lp) == TextToolStatus::Refused);
    CHECK_EQ(textToolReplyRequest(textToolReplyParam(0xFFFFFFFFu, TextToolStatus::Replaced)), kTextToolRequestMask);
    CHECK(isSecretInputScope(31) && isSecretInputScope(64) && !isSecretInputScope(5) && !isSecretInputScope(1));
}

TEST(text_tools_settings_defaults) {
    Settings s;
    CHECK(s.textToolsInMenu);                              // macOS textToolsInMenu default ON
    CHECK_EQ(s.addTonesHotkey, std::string("off"));        // hotkey default OFF
    CHECK_EQ(s.uiLanguage, std::string("vi"));             // Vietnamese UI regardless of locale
    s.textToolsInMenu = false;
    std::vector<uint8_t> b = serialize(s);
    Settings r;
    CHECK(deserialize(b.data(), b.size(), r));
    CHECK(!r.textToolsInMenu);
}

TEST(settings_underline_misspelled_snapshot_bit) {
    size_t n = 0;
    const BoolKey* keys = boolKeys(&n);
    CHECK(n <= 32);                      // snapshot bits fit the u32
    // Appended, never reordered: bit 21, then the game bits (game_ipc.h) after it.
    CHECK(n >= 24);
    CHECK_EQ(std::string(keys[21].name), std::string("underlineMisspelled"));
    CHECK_EQ(std::string(keys[22].name), std::string("autoOffFullscreen"));
    CHECK_EQ(std::string(keys[23].name), std::string("gameMode"));
    Settings on;
    on.underlineMisspelled = true;
    std::vector<uint8_t> b = serialize(on);
    Settings r;
    CHECK(deserialize(b.data(), b.size(), r));
    CHECK(r.underlineMisspelled);
    CHECK(!(r == Settings{}));
}

TEST(settings_snapshot_game_bits) {
    // Games / fullscreen: appended snapshot bits (game_ipc.h). The TIP reads gameMode from
    // the snapshot; autoOffFullscreen defaults ON.
    Settings d;
    CHECK(d.autoOffFullscreen);
    CHECK(!d.gameMode);
    Settings s;
    s.gameMode = true;
    s.autoOffFullscreen = false;
    std::vector<uint8_t> b = serialize(s);
    Settings r;
    CHECK(deserialize(b.data(), b.size(), r));
    CHECK(r.gameMode && !r.autoOffFullscreen);
    // A snapshot from before these bits (22 of them) leaves both at their defaults.
    CHECK(b.size() > 8);
    b[6] = 22;
    b[7] = 0;
    CHECK(deserialize(b.data(), b.size(), r));
    CHECK(!r.gameMode && r.autoOffFullscreen);
    // Registry-only strings are not in the snapshot.
    s.gameModeHotkey = "ctrl-alt-g";
    s.switchIndicator = "off";
    b = serialize(s);
    CHECK(deserialize(b.data(), b.size(), r));
    CHECK_EQ(r.gameModeHotkey, std::string("off"));
    CHECK_EQ(r.switchIndicator, std::string("auto"));
}

TEST(tip_suspension_reasons) {
    CHECK(!tipSuspended(0, false));
    CHECK(tipSuspended(kSuspendFullscreen, false));
    CHECK(tipSuspended(0, true));  // Chế độ game reaches every TIP through the snapshot
    CHECK(tipSuspended(kSuspendFullscreen | kSuspendGameMode, false));
    CHECK(!tipSuspended(0x100, false));  // unknown bits are ignored
    // The suspend message must not collide with the TIP window's other messages
    // (kTipTextToolMsg; text_service.cpp uses WM_APP + 0x59..0x5C internally).
    CHECK(kTipSuspendMsg != kTipTextToolMsg);
    CHECK(kTipSuspendMsg > 0x8000u + 0x5Cu && kTipSuspendMsg < 0xC000u);
}
