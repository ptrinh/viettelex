// docs/WINDOWS-APP-FEEL-SPEC.md — the portable decisions behind "cài xong là gõ được, dùng
// như một app" (core/app_feel.h) and the portable build (core/portable.h), plus the two
// guide pages it rewrites (no other input method named there).
#include <cstdio>
#include <fstream>
#include <iterator>
#include <set>
#include <string>
#include <vector>

#include "app_feel.h"
#include "idle_trim.h"
#include "onboarding.h"
#include "portable.h"
#include "switch_sound.h"
#include "settings.h"
#include "settings_pages.h"
#include "strings.h"
#include "test.h"

using namespace vtx;

namespace {
constexpr unsigned kVi = 0x042A;
constexpr uintptr_t kUs = 0x04090409, kUk = 0x08090809, kFr = 0x040C040C, kViHkl = 0x042A042A;

std::string readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
}
}  // namespace

// ---------------------------------------------------------------- §1 keyboard at start

TEST(feel_keyboard_nothing_for_portable_system_or_unregistered) {
    KeyboardStatus s;
    s.inUserList = false;
    s.firstRun = true;
    s.reselectPending = true;
    for (int i = 0; i < 3; ++i) {
        KeyboardStatus t = s;
        if (i == 0) t.portable = true;
        if (i == 1) t.systemAccount = true;
        if (i == 2) t.tipRegistered = false;
        const KeyboardPlan p = planKeyboardAtStart(t);
        CHECK(!p.add && !p.makeDefault && !p.select && !p.rememberPrevious);
    }
}

TEST(feel_keyboard_missing_is_added_made_default_and_selected) {
    KeyboardStatus s;
    s.inUserList = false;  // removed by hand, or never reached this user
    const KeyboardPlan p = planKeyboardAtStart(s);
    CHECK(p.add && p.makeDefault && p.select && p.rememberPrevious);
}

TEST(feel_keyboard_first_run_selects_even_when_listed) {
    KeyboardStatus s;
    s.inUserList = true;  // the MSI's SetupUser already added it
    s.firstRun = true;
    const KeyboardPlan p = planKeyboardAtStart(s);
    CHECK(p.add && p.makeDefault && p.select);
}

TEST(feel_keyboard_existing_user_untouched) {
    KeyboardStatus s;
    s.inUserList = true;
    const KeyboardPlan p = planKeyboardAtStart(s);
    CHECK(!p.add && !p.makeDefault && !p.select && !p.rememberPrevious);
}

TEST(feel_keyboard_reopen_after_tray_exit_selects_again) {
    KeyboardStatus s;
    s.inUserList = true;
    s.reselectPending = true;
    const KeyboardPlan p = planKeyboardAtStart(s);
    CHECK(p.select && p.rememberPrevious);
    CHECK(!p.add && !p.makeDefault);  // the default stays whatever the user has
}

// ---------------------------------------------------------------- §2 new vs existing users

TEST(feel_new_user_gets_tray_existing_keeps_choice) {
    CHECK(isNewUser(false, false, false));
    CHECK(!isNewUser(true, false, false));   // settings stored by an older version
    CHECK(!isNewUser(false, true, false));   // set up before
    CHECK(!isNewUser(false, false, true));   // saw the welcome before
    Settings s;
    CHECK(!s.showTrayIcon);  // the shared default (TIP snapshot) is unchanged
    applyNewUserDefaults(s);
    CHECK(s.showTrayIcon);
    CHECK(s.trayIconStyle == "letter");  // V/E letter by default
    // Nothing else moves.
    Settings d, n;
    applyNewUserDefaults(n);
    n.showTrayIcon = d.showTrayIcon;
    CHECK(n == d);
}

// ---------------------------------------------------------------- switch sound

TEST(feel_switch_sound_is_off_by_default_and_never_in_a_game) {
    CHECK(!Settings().switchSound);
    CHECK(!playsSwitchSound(false, false));
    CHECK(playsSwitchSound(true, false));
    CHECK(!playsSwitchSound(true, true));  // keys pass through: stay silent
    Settings s;
    s.switchSound = true;
    const std::vector<uint8_t> blob = serialize(s);
    Settings r;
    CHECK(deserialize(blob.data(), blob.size(), r) && r.switchSound);  // bit 31 round-trips
}

TEST(feel_switch_sound_is_a_valid_short_wav_rising_for_viet) {
    const std::vector<uint8_t> vi = switchSoundWav(true), en = switchSoundWav(false);
    CHECK(vi.size() == en.size() && vi != en);
    CHECK(std::string(vi.begin(), vi.begin() + 4) == "RIFF" && std::string(vi.begin() + 8, vi.begin() + 12) == "WAVE");
    auto u32 = [](const std::vector<uint8_t>& w, size_t at) {
        return static_cast<uint32_t>(w[at]) | (w[at + 1] << 8) | (w[at + 2] << 16) | (static_cast<uint32_t>(w[at + 3]) << 24);
    };
    CHECK_EQ(u32(vi, 4), static_cast<uint32_t>(vi.size() - 8));
    CHECK_EQ(u32(vi, 40), static_cast<uint32_t>(vi.size() - 44));
    CHECK_EQ(u32(vi, 24), static_cast<uint32_t>(kSwitchSoundRate));
    const size_t frames = (vi.size() - 44) / 2;
    CHECK(frames * 1000 / kSwitchSoundRate <= 300);  // short: never in the way of typing
    // Zero crossings per half: Việt goes low -> high, Anh high -> low; quiet (well under full scale).
    auto crossings = [&](const std::vector<uint8_t>& w, size_t from, size_t to) {
        int n = 0, peak = 0;
        int16_t prev = 0;
        for (size_t i = from; i < to; ++i) {
            const int16_t v = static_cast<int16_t>(w[44 + i * 2] | (w[45 + i * 2] << 8));
            if ((prev < 0) != (v < 0)) ++n;
            if (v > peak) peak = v;
            prev = v;
        }
        CHECK(peak < 32767 / 3);
        return n;
    };
    CHECK(crossings(vi, 0, frames / 2) < crossings(vi, frames / 2, frames));
    CHECK(crossings(en, 0, frames / 2) > crossings(en, frames / 2, frames));
}

// ---------------------------------------------------------------- #159 start hidden

TEST(feel_start_hidden_keeps_settings_closed_on_plain_start) {
    CHECK(!Settings().startHidden);                    // off by default: a plain start opens Settings
    CHECK(opensSettingsAtStart(false, false, false));
    CHECK(!opensSettingsAtStart(false, false, true));  // the option: tray only
    CHECK(!opensSettingsAtStart(true, false, false));  // autostart: never a window
    CHECK(!opensSettingsAtStart(true, false, true));
    CHECK(opensSettingsAtStart(false, true, true));    // --settings (installer) always opens it
    // Round trip through the stored snapshot.
    Settings s;
    s.startHidden = true;
    const std::vector<uint8_t> blob = serialize(s);
    Settings r;
    CHECK(deserialize(blob.data(), blob.size(), r) && r.startHidden);
}

// ---------------------------------------------------------------- §2/§3 tray state

TEST(feel_tray_state_installed) {
    // The TIP's own word wins.
    CHECK(trayStateFor(false, 1, false, 0x0409, false, false) == TrayState::Vietnamese);
    CHECK(trayStateFor(false, 2, false, kVi, true, false) == TrayState::English);
    // VietTelex selected, per-app memory.
    CHECK(trayStateFor(false, 0, false, kVi, true, false) == TrayState::Vietnamese);
    CHECK(trayStateFor(false, 0, false, kVi, false, false) == TrayState::English);
    CHECK(trayStateFor(false, 0, false, kVi, true, true) == TrayState::English);  // Luôn tiếng Anh
    // Another keyboard selected (Win+Space by mistake): off.
    CHECK(trayStateFor(false, 0, false, 0x0409, true, false) == TrayState::Off);
    CHECK(trayStateFor(false, 0, false, 0x0411, false, false) == TrayState::Off);
    // Unknown layout: no claim of "off".
    CHECK(trayStateFor(false, 0, false, 0, true, false) == TrayState::Vietnamese);
    // Console without the prop: its thread layout is cmd's — English, never "off".
    CHECK(trayStateFor(false, 0, true, 0x0409, true, false) == TrayState::English);
}

TEST(feel_tray_state_portable) {
    CHECK(trayStateFor(true, 0, false, 0x0409, true, false) == TrayState::Vietnamese);
    CHECK(trayStateFor(true, 0, false, 0x0409, false, false) == TrayState::English);
    CHECK(trayStateFor(true, 0, false, 0x0409, true, true) == TrayState::English);
    // The installed TIP or another Vietnamese keyboard there: portable yields -> off.
    CHECK(trayStateFor(true, 1, false, kVi, true, false) == TrayState::Off);
    CHECK(trayStateFor(true, 2, false, 0x0409, true, false) == TrayState::Off);
    CHECK(trayStateFor(true, 0, false, kVi, true, false) == TrayState::Off);
    // Consoles are typed by the portable hook like any app.
    CHECK(trayStateFor(true, 0, true, 0x0409, true, false) == TrayState::Vietnamese);
}

TEST(feel_tray_left_click) {
    CHECK(trayClickAction(TrayState::Vietnamese, false) == TrayClick::ToggleLanguage);
    CHECK(trayClickAction(TrayState::English, false) == TrayClick::ToggleLanguage);
    CHECK(trayClickAction(TrayState::Off, false) == TrayClick::SelectVietTelex);
    CHECK(trayClickAction(TrayState::English, true) == TrayClick::ToggleLanguage);
    CHECK(trayClickAction(TrayState::Off, true) == TrayClick::SwitchToEnglishKeys);
}

// ---------------------------------------------------------------- §4 welcome "Xử lý" row

TEST(feel_welcome_resolve_row) {
    // Third-party kinds by property, not by name (this file names no other input method).
    std::vector<ConflictKind> others;
    for (int i = 0; i <= static_cast<int>(ConflictKind::WindowsHotkey); ++i)
        if (isThirdPartyIme(static_cast<ConflictKind>(i))) others.push_back(static_cast<ConflictKind>(i));
    CHECK(others.size() >= 2);
    CHECK(welcomeResolveRow({}) == ResolveRow::None);
    CHECK(welcomeResolveRow({ConflictKind::WindowsHotkey}) == ResolveRow::None);  // Kiểu gõ card covers it
    CHECK(welcomeResolveRow({ConflictKind::MicrosoftVietnamese}) == ResolveRow::WindowsKeyboard);
    for (ConflictKind k : others) {
        CHECK(welcomeResolveRow({k}) == ResolveRow::OtherInputMethod);
        CHECK(welcomeResolveRow({k, ConflictKind::WindowsHotkey}) == ResolveRow::OtherInputMethod);
        CHECK(welcomeResolveRow({ConflictKind::MicrosoftVietnamese, k}) == ResolveRow::Both);
    }
}

// ---------------------------------------------------------------- §5 tray Thoát

TEST(feel_exit_layout) {
    const uintptr_t list[] = {kViHkl, kFr, kUk, kUs};
    CHECK(pickExitLayout(list, 4, kUk) == kUk);      // the one used before VietTelex
    CHECK(pickExitLayout(list, 4, 0) == kUs);        // nothing saved: US English
    CHECK(pickExitLayout(list, 4, 0x04070407) == kUs);  // saved one no longer installed
    CHECK(pickExitLayout(list, 4, kViHkl) == kUs);   // never "back" to a Vietnamese one
    const uintptr_t noUs[] = {kViHkl, kFr};
    CHECK(pickExitLayout(noUs, 2, 0) == kFr);        // first non-Vietnamese
    const uintptr_t onlyVi[] = {kViHkl};
    CHECK(pickExitLayout(onlyVi, 1, kUs) == 0);      // nothing to switch to
    CHECK(pickExitLayout(nullptr, 0, kUs) == 0);
    CHECK(rememberableLayout(kUs) && !rememberableLayout(kViHkl) && !rememberableLayout(0));
}

// ---------------------------------------------------------------- portable: mode + paths

TEST(portable_marker_detection) {
    std::set<std::wstring> files;
    auto exists = [&files](const std::wstring& p) { return files.count(p) != 0; };
    CHECK(!portable::detectPortable(L"D:\\Tools\\VietTelex", exists));
    files.insert(L"D:\\Tools\\VietTelex\\portable.ini");
    CHECK(portable::detectPortable(L"D:\\Tools\\VietTelex", exists));
    CHECK(portable::detectPortable(L"D:\\Tools\\VietTelex\\", exists));  // trailing separator
    files = {L"E:\\VietTelex.portable"};
    CHECK(portable::detectPortable(L"E:\\", exists));
    CHECK(!portable::detectPortable(L"", exists));
    CHECK(portable::exeDirOf(L"C:\\Program Files\\VietTelex\\VietTelex.exe") == L"C:\\Program Files\\VietTelex");
    CHECK(portable::exeDirOf(L"VietTelex.exe") == L"");
}

TEST(portable_settings_path) {
    CHECK(portable::settingsPath(L"D:\\VT", true, L"C:\\Users\\a\\AppData\\Roaming") == L"D:\\VT\\settings.ini");
    CHECK(portable::settingsPath(L"D:\\VT", false, L"C:\\Users\\a\\AppData\\Roaming") ==
          L"C:\\Users\\a\\AppData\\Roaming\\VietTelex\\settings.ini");  // read-only folder / CD / share
    CHECK(portable::settingsPath(L"D:\\VT", false, L"") == L"");
    CHECK(portable::settingsPath(L"", true, L"C:\\R\\") == L"C:\\R\\VietTelex\\settings.ini");
}

TEST(portable_start_and_yield) {
    CHECK(portable::decideStart(false) == portable::StartAction::Run);
    CHECK(portable::decideStart(true) == portable::StartAction::ExitInstalledRunning);
    CHECK(!portable::yields(0, 0x0409));
    CHECK(!portable::yields(0, 0));
    CHECK(portable::yields(1, 0x0409));   // installed TIP active, Vietnamese
    CHECK(portable::yields(2, 0x0409));   // installed TIP active, English: still its window
    CHECK(portable::yields(0, kVi));      // a Vietnamese keyboard selected
    // Names that keep the installed TIP from ever talking to a portable copy.
    CHECK(std::wstring(portable::kWindowClass) != L"VietTelexAppWindow");
    CHECK(std::wstring(portable::kMutexName) != L"Local\\VietTelex.App");
}

// Báo lỗi 1.3.17 ("bản portable không hoạt động"): Explorer's "Run" inside the zip copies
// only the exe to a temp folder — no portable.ini, so it started as the installed build.
TEST(portable_launched_from_archive) {
    const std::wstring tmp = L"C:\\Users\\a\\AppData\\Local\\Temp\\";
    CHECK(portable::launchedFromArchive(
        tmp + L"Temp1_VietTelex-1.3.17-portable-x64.zip\\VietTelex-1.3.17-portable-x64\\VietTelex.exe"));
    CHECK(portable::launchedFromArchive(tmp + L"Temp2_vt.ZIP\\VietTelex.exe"));  // case, Temp2_
    CHECK(portable::launchedFromArchive(tmp + L"7zO4A1B2C3D\\VietTelex.exe"));
    CHECK(portable::launchedFromArchive(tmp + L"Rar$EXa1234.5678\\VietTelex-1.3.17-portable-x64\\VietTelex.exe"));
    CHECK(portable::launchedFromArchive(L"C:/Users/a/AppData/Local/Temp/Temp1_x.zip/VietTelex.exe"));
    // Unzipped folders, installed builds, the update watcher's copy: not from an archive.
    CHECK(!portable::launchedFromArchive(L"D:\\Tools\\VietTelex-1.3.17-portable-x64\\VietTelex.exe"));
    CHECK(!portable::launchedFromArchive(L"C:\\Program Files\\VietTelex\\VietTelex.exe"));
    CHECK(!portable::launchedFromArchive(L"C:\\Users\\a\\AppData\\Local\\VietTelex\\VietTelex.exe"));
    CHECK(!portable::launchedFromArchive(tmp + L"VietTelex-update-1234.exe"));
    CHECK(!portable::launchedFromArchive(L"D:\\zip\\VietTelex.exe"));         // a folder just named "zip"
    CHECK(!portable::launchedFromArchive(L"D:\\VietTelex.zip.exe"));          // the file name never counts
    CHECK(!portable::launchedFromArchive(L"D:\\.zip"));
    CHECK(!portable::launchedFromArchive(L""));
}

// Portable tray click while it yields: with only Vietnamese keyboards in the list there is
// nothing to switch to — explain instead of a silent no-op.
TEST(portable_yield_click) {
    const uintptr_t onlyVi[] = {0x042A042A};
    CHECK(portable::yieldClick(pickExitLayout(onlyVi, 1, 0)) == portable::YieldClick::ExplainNoOtherKeyboard);
    const uintptr_t withUs[] = {0x042A042A, 0x04090409};
    CHECK(portable::yieldClick(pickExitLayout(withUs, 2, 0)) == portable::YieldClick::SwitchLayout);
}

TEST(portable_hook_plan) {
    for (AppMode m : {AppMode::InPlace, AppMode::Composition, AppMode::HookFallback, AppMode::Direct}) {
        const portable::HookPlan p = portable::hookPlan(m, false, false);
        CHECK(p.install && !p.direct);  // no TIP to fall back to: plain hook typing everywhere
        CHECK(!portable::hookPlan(m, true, false).install);   // password box
        CHECK(!portable::hookPlan(m, false, true).install);   // yields
    }
    CHECK(!portable::hookPlan(AppMode::Off, false, false).install);  // Luôn tiếng Anh
    CHECK(portable::isPasswordField("Edit", 0x20));
    CHECK(portable::isPasswordField("RichEdit20W", 0x50010020));
    CHECK(!portable::isPasswordField("Edit", 0x50010000));
    CHECK(!portable::isPasswordField("Chrome_RenderWidgetHostHWND", 0x20));
}

TEST(portable_autostart_points_at_this_copy) {
    const std::wstring exe = L"D:\\Tools\\VietTelex\\VietTelex.exe";
    CHECK(portable::autostartCommand(exe) == L"\"D:\\Tools\\VietTelex\\VietTelex.exe\" --background");
    CHECK(portable::autostartPointsHere(L"\"d:\\tools\\viettelex\\VIETTELEX.EXE\" --background", exe));
    CHECK(!portable::autostartPointsHere(L"\"C:\\Program Files\\VietTelex\\VietTelex.exe\" --background", exe));
    CHECK(!portable::autostartPointsHere(L"", exe));
}

// ---------------------------------------------------------------- portable: settings.ini

TEST(portable_kv_round_trip) {
    portable::KeyValueFile f;
    f.setDword("vniMode", 1);
    f.setDword("showTrayIcon", 0);
    f.setQword("lastUpdateCheck", 13412345678901234567ull);
    f.setString("switchHotkey", "ctrl-shift");
    f.setString("note", "dòng 1\nline\t2 \\ end\r");
    static const char kBin[] = "{\"ko\":\"kh\xC3\xB4ng\"}\0\xFF";
    const std::string bin(kBin, sizeof kBin - 1);
    f.setBinary("shortcuts", bin);
    f.setDword("AppLanguage\\notepad.exe", 0);
    f.setDword("AppLanguage\\chrome.exe", 1);
    const std::string text = f.serialize();
    portable::KeyValueFile g;
    g.parse(text);
    uint32_t d = 9;
    uint64_t q = 0;
    std::string s;
    CHECK(g.getDword("vniMode", d) && d == 1);
    CHECK(g.getDword("showTrayIcon", d) && d == 0);
    CHECK(g.getQword("lastUpdateCheck", q) && q == 13412345678901234567ull);
    CHECK(g.getString("switchHotkey", s) && s == "ctrl-shift");
    CHECK(g.getString("note", s) && s == "dòng 1\nline\t2 \\ end\r");
    CHECK(g.getBinary("shortcuts", s) && s == bin);
    CHECK(!g.getString("vniMode", s));  // typed: a DWORD is not a string
    const auto langs = g.dwordsWithPrefix("AppLanguage\\");
    CHECK(langs.size() == 2 && langs.at("notepad.exe") == 0 && langs.at("chrome.exe") == 1);
    CHECK(g.serialize() == text);
    CHECK(text.find('\n') != std::string::npos && text.find("[VietTelex]") != std::string::npos);
}

TEST(portable_kv_tolerates_hand_edits_and_garbage) {
    portable::KeyValueFile f;
    f.parse("\xEF\xBB\xBF; comment\r\n# other\r\n[VietTelex]\r\n\r\nvniMode=dword:1\nbad line\n=dword:1\n"
            "x=dword:-1\ny=dword:99999999999\nz=hex:abc\nw=sz:a\\q\nv=what:1\nok=sz:yes\nhx=hex:00FF\n");
    uint32_t d = 0;
    std::string s;
    CHECK(f.getDword("vniMode", d) && d == 1);
    CHECK(!f.getDword("x", d) && !f.getDword("y", d));
    CHECK(!f.getBinary("z", s) && !f.getString("w", s));
    CHECK(f.getString("ok", s) && s == "yes");
    CHECK(f.getBinary("hx", s) && s == std::string("\0\xFF", 2));
    CHECK(f.entries().size() == 3);
    // Invalid names are never written.
    portable::KeyValueFile g;
    g.setDword("", 1);
    g.setDword("a=b", 1);
    g.setDword("a\nb", 1);
    g.setDword(";x", 1);
    CHECK(g.entries().empty());
}

// ---------------------------------------------------------------- portable: Settings pages

TEST(portable_settings_pages_hide_keyboard_rows) {
    Settings s;
    s.showTrayIcon = true;
    app::PageContext c;
    for (bool& e : c.expanded) e = true;
    c.offerDefaultInput = true;
    auto has = [](const std::vector<app::PageRow>& rows, app::PageControl pc) {
        for (const app::PageRow& r : rows)
            if (r.kind == app::RowKind::Control && r.id == static_cast<int>(pc)) return true;
        return false;
    };
    auto all = [&](const app::PageContext& ctx) {
        std::vector<app::PageRow> out;
        for (int p = 0; p < static_cast<int>(app::SettingsPage::Count); ++p)
            for (const app::PageRow& r : app::settingsPageRows(static_cast<app::SettingsPage>(p), s, ctx))
                out.push_back(r);
        return out;
    };
    const auto installed = all(c);
    c.portable = true;
    const auto port = all(c);
    for (app::PageControl pc : {app::PageControl::PerAppWin, app::PageControl::DefaultInput,
                                app::PageControl::IconPicker, app::PageControl::Uninstall}) {
        CHECK(has(installed, pc));
        CHECK(!has(port, pc));
    }
    // Everything else stays: the switch key, tray, updates check, links.
    for (app::PageControl pc : {app::PageControl::SwitchHotkey, app::PageControl::CheckNow,
                                app::PageControl::Links, app::PageControl::TrayStyle})
        CHECK(has(port, pc));
}

// ---------------------------------------------------------------- strings + guide pages

TEST(feel_new_strings) {
    app::setEnglish(false);
    CHECK(std::wstring(app::tr(app::S::ReadyTitle)).find(L"Đã sẵn sàng") == 0);
    CHECK(std::wstring(app::tr(app::S::ReadySwitchLine)).find(L"Ctrl+Shift") != std::wstring::npos);
    CHECK(std::wstring(app::tr(app::S::MenuExit)).find(L"Thoát") == 0);
    app::setEnglish(true);
    CHECK(std::wstring(app::tr(app::S::ReadySwitchLine)).find(L"Ctrl+Shift") != std::wstring::npos);
    app::setEnglish(false);
}

// The rewritten Windows guide pages (spec item 6) never name another Vietnamese input
// method: behaviour is described instead. Names stored ROT13 (as settings_pages_tests).
TEST(feel_guide_pages_name_no_other_input_method) {
    const char* const kRot13[] = {"havxrl", "bcraxrl", "rixrl", "ivrgxrl", "tbgvrativrg", "ynonaxrl", "onzobb", "kxrl"};
    std::vector<std::string> names;
    for (const char* r : kRot13) {
        std::string n;
        for (const char* c = r; *c; ++c) n.push_back(static_cast<char>((*c - 'a' + 13) % 26 + 'a'));
        names.push_back(n);
    }
    for (const char* page : {"/hdsd/index.html", "/en/guide/index.html", "/download/index.html",
                             "/en/download/index.html"}) {
        std::string text = readFile(std::string(VTX_DOCS_DIR) + page);
        CHECK(!text.empty());
        for (char& c : text)
            if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
        for (const std::string& n : names)
            if (text.find(n) != std::string::npos) {
                std::printf("  %s names another input method\n", page);
                CHECK(false);
            }
    }
}

// ---- idle working-set trim (core/idle_trim.h, GitHub #153) ---------------------------------
TEST(idle_trim_only_when_nothing_is_on_screen_and_the_user_is_quiet) {
    using namespace vtx::idletrim;
    State s;
    s.idleMs = kQuietMs;
    CHECK(decide(s) == Decision::Trim);
    s.idleMs = 60000;
    CHECK(decide(s) == Decision::Trim);
    // a window on screen: never (its closing asks again), whatever the idle time
    s.windowOpen = true;
    CHECK(decide(s) == Decision::Drop);
    s.windowOpen = false;
    // typing / clicking just now, or a text tool mid-job: wait, then try again
    s.idleMs = kQuietMs - 1;
    CHECK(decide(s) == Decision::Wait);
    s.idleMs = 0;
    CHECK(decide(s) == Decision::Wait);
    s.idleMs = 60000;
    s.textJobBusy = true;
    CHECK(decide(s) == Decision::Wait);
    // non-stop typing: give up after kMaxRetries waits (no timer forever)
    s.retries = kMaxRetries - 1;
    CHECK(decide(s) == Decision::Wait);
    s.retries = kMaxRetries;
    CHECK(decide(s) == Decision::Drop);
    s.textJobBusy = false;
    CHECK(decide(s) == Decision::Trim);
    // the quiet gap is shorter than the first delay: a trim right after a window closes is
    // never the reason a keystroke stalls (the user had stopped typing for ≥ kQuietMs)
    CHECK(kQuietMs < kDelayMs && kRetryMs >= kQuietMs);
}

// ---------------------------------------------------------------- one-click built-in removal

TEST(feel_built_in_keyboard_removals) {
    const std::string ours = "{12345678-1234-1234-1234-123456789ABC}";
    ViProfile us;  // VietTelex itself: never removed
    us.langId = 0x042A;
    us.isTip = true;
    us.enabled = true;
    us.clsid = ours;
    us.profile = "{87654321-4321-4321-4321-CBA987654321}";
    ViProfile telex = us;  // Windows' built-in Vietnamese TIP
    telex.clsid = "{11111111-2222-3333-4444-555555555555}";
    telex.profile = "{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}";
    ViProfile legacy;  // the legacy "Vietnamese" layout
    legacy.langId = 0x042A;
    legacy.enabled = true;
    legacy.hkl = 0x042A042A;
    ViProfile disabled = telex;  // installed, not in the user's list
    disabled.enabled = false;
    disabled.profile = "{BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE}";
    ViProfile variant = legacy;  // a variant layout id: left to Windows Settings
    variant.hkl = 0xF0C1042A;
    const std::vector<std::string> r = builtInKeyboardRemovals({us, telex, legacy, telex, disabled, variant}, ours);
    CHECK_EQ(r.size(), static_cast<size_t>(2));
    CHECK_EQ(r[0], std::string("042A:{11111111-2222-3333-4444-555555555555}{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}"));
    CHECK_EQ(r[1], std::string("042A:0000042A"));
    CHECK(builtInKeyboardRemovals({us}, ours).empty());
    CHECK(builtInKeyboardRemovals({}, ours).empty());
}
