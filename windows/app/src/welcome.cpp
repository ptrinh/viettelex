// welcome.cpp — first-run window (app/core/onboarding.h decideWelcome): typing method,
// switch key, tray icon, other Vietnamese input methods, "Chuyển từ UniKey". Plain native
// controls; every choice applies at once like the Settings window. Shown once per user.
//
// Onboarding (docs/ONBOARDING-SPEC.md, onboarding.h decideOnboarding): for a new user the
// same window goes on with two pages — "Bạn thường gõ thế nào?" (three command links, the
// chosen profile is written into the settings at once) and "Gõ thử" (sample sentences, an
// edit box typed through VietTelex itself, a checkbox per switch the profile turned on).
// "Bỏ qua" / closing on any page: the profile page keeps the defaults, the try page keeps
// the chosen profile. Either way onboardingDone = 1.
#include <windows.h>
#include <commctrl.h>

#include <string>
#include <vector>

#include "app.h"
#include "conflicts.h"
#include "onboarding.h"
#include "foreground.h"
#include "input_switch.h"
#include "res/icon_ids.h"
#include "settings_store.h"
#include "strings.h"
#include "tip_control.h"

namespace vtx::app {

namespace {

constexpr wchar_t kWelcomeClass[] = L"VietTelexWelcome";
enum : int {
    IdTelex = 100,
    IdVni,
    IdSwitch,
    IdTray,
    IdDefaultInput,
    IdResolve,
    IdImport,
    IdSettings,
    IdNext,
    IdSkip,
    IdProfileVi,
    IdProfileMixed,
    IdProfileEn,
    IdTryEdit,
    IdTryToggle = 200,  // + index into g_tryFields
};

enum class Step { Setup, Profile, Try };

const char* const kSwitchIds[] = {"ctrl-shift", "win-space", "alt-z", "off"};
const S kSwitchLabels[] = {S::HotkeyCtrlShift, S::HotkeyWinSpace, S::HotkeyAltZ, S::HotkeyOff};

HWND g_wnd = nullptr;
HFONT g_font = nullptr, g_title = nullptr;
UINT g_dpi = 96;
std::vector<FoundConflict> g_found;
Step g_step = Step::Setup;
bool g_profilePages = false;  // this run includes the onboarding pages
vtx::TypingProfile g_profile = vtx::TypingProfile::Vi;
std::vector<bool Settings::*> g_tryFields;  // the "Gõ thử" checkboxes, in order

int px(int v) { return MulDiv(v, static_cast<int>(g_dpi), 96); }

HWND add(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id = 0,
         HFONT font = nullptr) {
    HWND c = CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, px(x), px(y), px(w), px(h), g_wnd,
                             reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), g_inst, nullptr);
    SendMessageW(c, WM_SETFONT, reinterpret_cast<WPARAM>(font ? font : g_font), TRUE);
    return c;
}

// The setup page's checkboxes take effect when the page is left (Tiếp) or the window closes.
void applySetupChoices() {
    const bool tray = IsDlgButtonChecked(g_wnd, IdTray) == BST_CHECKED;
    if (tray != g_settings.showTrayIcon) {
        g_settings.showTrayIcon = tray;
        settingsChanged();
        refreshSettingsWindow();
    }
    // "Make VietTelex the default keyboard" (shown only when Windows' default is another
    // one): SetDefaultLayoutOrTip, applied to this session too. The ticked box is consent.
    if (GetDlgItem(g_wnd, IdDefaultInput) && IsDlgButtonChecked(g_wnd, IdDefaultInput) == BST_CHECKED) {
        const bool ok = setDefaultKeyboardForUser();
        appLog("app", std::string("welcome: make VietTelex the default keyboard: ") + (ok ? "done" : "failed"));
    }
}

void finish() {
    if (g_step == Step::Setup) applySetupChoices();
    if (g_profilePages) writeFlag(L"onboardingDone", true);
    DestroyWindow(g_wnd);
}

void clearPage() {
    HWND child = GetWindow(g_wnd, GW_CHILD);
    while (child) {
        HWND next = GetWindow(child, GW_HWNDNEXT);
        DestroyWindow(child);
        child = next;
    }
}

// Client size (DIP) -> window size, centred on the work area.
void fitWindow(int W, int H) {
    RECT r = {0, 0, px(W), px(H)};
    const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(g_wnd, GWL_STYLE));
    AdjustWindowRectExForDpi(&r, style, FALSE, WS_EX_CONTROLPARENT, g_dpi);
    RECT wa;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0);
    const int w = r.right - r.left, h = r.bottom - r.top;
    SetWindowPos(g_wnd, nullptr, wa.left + (wa.right - wa.left - w) / 2, wa.top + (wa.bottom - wa.top - h) / 2, w, h,
                 SWP_NOZORDER);
}

S toggleTitle(bool Settings::*f) {
    if (f == &Settings::autoRestore) return S::AutoRestore;
    if (f == &Settings::contextualEnglish) return S::ContextualEnglish;
    if (f == &Settings::retroactiveEnglish) return S::RetroEnglish;
    if (f == &Settings::englishByFrequency) return S::EnglishByFrequency;
    if (f == &Settings::collisionPrefersVietnamese) return S::CollisionPrefersVi;
    return S::StartEnglish;
}

void buildProfile() {
    const int W = 480;
    int y = 20;
    add(L"STATIC", tr(S::ProfileTitle), SS_LEFT, 24, y, W - 48, 30, 0, g_title);
    y += 38;
    add(L"STATIC", tr(S::ProfileIntro), SS_LEFT, 24, y, W - 48, 52);
    y += 60;
    const struct {
        int id;
        S title, example;
    } cards[] = {{IdProfileVi, S::ProfileVi, S::ProfileViEx},
                 {IdProfileMixed, S::ProfileMixed, S::ProfileMixedEx},
                 {IdProfileEn, S::ProfileEn, S::ProfileEnEx}};
    for (const auto& c : cards) {
        HWND b = add(L"BUTTON", tr(c.title),
                     static_cast<DWORD>(BS_COMMANDLINK | WS_TABSTOP | (c.id == IdProfileVi ? WS_GROUP : 0)), 24, y,
                     W - 48, 60, c.id);
        SendMessageW(b, BCM_SETNOTE, 0, reinterpret_cast<LPARAM>(tr(c.example)));
        y += 68;
    }
    y += 8;
    add(L"BUTTON", tr(S::WelcomeSkip), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 140, y, 140, 32, IdSkip);
    y += 32 + 20;
    fitWindow(W, y);
    SetFocus(GetDlgItem(g_wnd, IdProfileVi));
}

void buildTry() {
    const int W = 480;
    int y = 20;
    add(L"STATIC", tr(S::TryTitle), SS_LEFT, 24, y, W - 48, 30, 0, g_title);
    y += 38;
    add(L"STATIC", tr(S::TryIntro), SS_LEFT, 24, y, W - 48, 40);
    y += 44;
    const S samples = g_profile == vtx::TypingProfile::Vi      ? S::TrySamplesVi
                      : g_profile == vtx::TypingProfile::Mixed ? S::TrySamplesMixed
                                                               : S::TrySamplesEn;
    add(L"STATIC", tr(samples), SS_LEFT, 24, y, W - 48, 60);
    y += 64;
    // ES_WANTRETURN: Enter types a new line instead of pressing a button.
    add(L"EDIT", L"", ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_BORDER | WS_TABSTOP | WS_GROUP | WS_VSCROLL,
        24, y, W - 48, 64, IdTryEdit);
    y += 70;
    add(L"STATIC", tr(S::TryHint), SS_LEFT, 24, y, W - 48, 36);
    y += 44;
    add(L"STATIC", tr(S::TryTurnedOn), SS_LEFT, 24, y, W - 48, 20);
    y += 26;
    g_tryFields = vtx::profileTurnedOn(g_profile);
    for (size_t i = 0; i < g_tryFields.size(); ++i) {
        const int id = IdTryToggle + static_cast<int>(i);
        add(L"BUTTON", tr(toggleTitle(g_tryFields[i])),
            static_cast<DWORD>(BS_AUTOCHECKBOX | WS_TABSTOP | (i == 0 ? WS_GROUP : 0)), 24, y, W - 48, 24, id);
        CheckDlgButton(g_wnd, id, (g_settings.*g_tryFields[i]) ? BST_CHECKED : BST_UNCHECKED);
        y += 28;
    }
    y += 16;
    add(L"BUTTON", tr(S::WelcomeSkip), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 140 - 8 - 140, y, 140, 32,
        IdSkip);
    add(L"BUTTON", tr(S::WelcomeDone), BS_PUSHBUTTON | WS_TABSTOP, W - 24 - 140, y, 140, 32, IDOK);
    y += 32 + 20;
    fitWindow(W, y);
    SetFocus(GetDlgItem(g_wnd, IdTryEdit));
}

void goTo(Step step) {
    if (g_step == Step::Setup && step != Step::Setup) applySetupChoices();
    g_step = step;
    clearPage();
    if (step == Step::Profile) buildProfile();
    else if (step == Step::Try) buildTry();
    InvalidateRect(g_wnd, nullptr, TRUE);
}

void chooseProfile(vtx::TypingProfile p) {
    g_profile = p;
    vtx::applyProfile(g_settings, p);
    writeString(L"onboardingProfile", widen(vtx::profileName(p)));
    settingsChanged();
    refreshSettingsWindow();
    appLog("app", std::string("onboarding: profile ") + vtx::profileName(p));
    goTo(Step::Try);
}

void makeFonts() {
    NONCLIENTMETRICSW ncm = {};
    ncm.cbSize = sizeof ncm;
    SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, g_dpi);
    g_font = CreateFontIndirectW(&ncm.lfMessageFont);
    LOGFONTW lf = ncm.lfMessageFont;
    lf.lfHeight = -px(20);
    lf.lfWeight = FW_SEMIBOLD;
    g_title = CreateFontIndirectW(&lf);
}

void build() {
    const int W = 480;  // client width (DIP)
    int y = 20;
    add(L"STATIC", tr(S::WelcomeTitle), SS_LEFT, 24, y, W - 48, 30, 0, g_title);
    y += 38;
    add(L"STATIC", tr(S::WelcomeIntro), SS_LEFT, 24, y, W - 48, 40);
    y += 48;
    // How to start: a UniKey user has never picked a keyboard in Windows (field report
    // 2026-10: "không gõ được tiếng Việt" right after installing).
    add(L"STATIC", tr(S::WelcomeHowTo), SS_LEFT, 24, y, W - 48, 60);
    y += 70;

    add(L"STATIC", tr(S::WelcomeMethod), SS_LEFT, 24, y + 3, 170, 20);
    add(L"BUTTON", tr(S::Telex), BS_AUTORADIOBUTTON | WS_GROUP | WS_TABSTOP, 200, y, 90, 24, IdTelex);
    add(L"BUTTON", tr(S::Vni), BS_AUTORADIOBUTTON, 300, y, 90, 24, IdVni);
    CheckRadioButton(g_wnd, IdTelex, IdVni, g_settings.vniMode ? IdVni : IdTelex);
    y += 36;

    add(L"STATIC", tr(S::WelcomeSwitch), SS_LEFT, 24, y + 4, 170, 20);
    HWND combo = add(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL | WS_GROUP, 200, y, 256, 200,
                     IdSwitch);
    int sel = 0;
    for (int i = 0; i < 4; ++i) {
        SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(tr(kSwitchLabels[i])));
        if (g_settings.switchHotkey == kSwitchIds[i]) sel = i;
    }
    SendMessageW(combo, CB_SETCURSEL, static_cast<WPARAM>(sel), 0);
    y += 40;

    // Windows still opens apps with the old keyboard (ENG): offer to make VietTelex the
    // default, pre-ticked (input_switch.h welcomeOffersDefaultInput).
    if (welcomeOffersDefaultInput(parseSwitchHotkey(g_settings.switchHotkey), defaultInputLangId())) {
        add(L"BUTTON", tr(S::WelcomeDefaultInput), BS_AUTOCHECKBOX | WS_TABSTOP | WS_GROUP, 24, y, W - 48, 24,
            IdDefaultInput);
        CheckDlgButton(g_wnd, IdDefaultInput, BST_CHECKED);
        y += 32;
    }

    // Tray icon: the setting stays OFF by default, but the box is pre-ticked: it is the only
    // lasting Việt/Anh indicator (the taskbar shows the static keyboard icon since 1.0.8).
    add(L"BUTTON", tr(S::WelcomeTray), BS_AUTOCHECKBOX | WS_TABSTOP | WS_GROUP, 24, y, W - 48, 24, IdTray);
    CheckDlgButton(g_wnd, IdTray, BST_CHECKED);
    y += 26;
    add(L"STATIC", tr(S::WelcomeTrayNote), SS_LEFT, 44, y, W - 68, 52);
    y += 62;

    if (!g_found.empty()) {
        const std::wstring msg = std::wstring(tr(S::ConflictTitle)) + L": " + conflictNames(g_found) + L". " +
                                 conflictDescription(g_found);
        add(L"STATIC", msg.c_str(), SS_LEFT, 24, y, W - 48 - 120, 96);
        add(L"BUTTON", tr(S::ConflictButton), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 110, y, 110, 30,
            IdResolve);
        y += 106;
    }

    add(L"BUTTON", tr(S::WelcomeImport), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, 24, y, 300, 30, IdImport);
    y += 52;

    add(L"BUTTON", tr(S::WelcomeOpenSettings), BS_PUSHBUTTON | WS_TABSTOP | WS_GROUP, W - 24 - 140 - 8 - 140, y,
        140, 32, IdSettings);
    // New user: "Tiếp" goes on to the onboarding pages instead of closing.
    const int next = g_profilePages ? IdNext : IDOK;
    add(L"BUTTON", tr(g_profilePages ? S::WelcomeNext : S::WelcomeDone), BS_DEFPUSHBUTTON | WS_TABSTOP,
        W - 24 - 140, y, 140, 32, next);
    y += 32 + 20;

    fitWindow(W, y);
    SetFocus(GetDlgItem(g_wnd, next));
}

LRESULT CALLBACK welcomeProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CTLCOLORSTATIC: {
            HDC dc = reinterpret_cast<HDC>(wp);
            SetBkColor(dc, GetSysColor(COLOR_WINDOW));
            SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
            return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
        }
        case WM_COMMAND: {
            const int id = LOWORD(wp), code = HIWORD(wp);
            switch (id) {
                case IdTelex:
                case IdVni:
                    if (code == BN_CLICKED) {
                        g_settings.vniMode = id == IdVni;
                        settingsChanged();
                        refreshSettingsWindow();
                    }
                    return 0;
                case IdSwitch:
                    if (code == CBN_SELCHANGE) {
                        const int i = static_cast<int>(SendMessageW(reinterpret_cast<HWND>(lp), CB_GETCURSEL, 0, 0));
                        if (i >= 0 && i < 4) {
                            g_settings.switchHotkey = kSwitchIds[i];
                            settingsChanged();
                            refreshSettingsWindow();
                        }
                    }
                    return 0;
                case IdResolve: resolveConflicts(h, g_found); return 0;
                case IdNext: goTo(Step::Profile); return 0;
                case IdSkip: finish(); return 0;  // profile page: defaults kept; try page: profile kept
                case IdProfileVi:
                case IdProfileMixed:
                case IdProfileEn:
                    if (code == BN_CLICKED)
                        chooseProfile(id == IdProfileVi      ? vtx::TypingProfile::Vi
                                      : id == IdProfileMixed ? vtx::TypingProfile::Mixed
                                                             : vtx::TypingProfile::En);
                    return 0;
                case IdImport: importShortcutsDialog(h); return 0;
                case IdSettings:
                    finish();
                    showSettings(Tab::Typing);
                    return 0;
                case IDOK:
                case IDCANCEL: finish(); return 0;
                default:
                    if (id >= IdTryToggle && id < IdTryToggle + static_cast<int>(g_tryFields.size()) &&
                        code == BN_CLICKED) {
                        g_settings.*g_tryFields[static_cast<size_t>(id - IdTryToggle)] =
                            IsDlgButtonChecked(h, id) == BST_CHECKED;
                        settingsChanged();
                        refreshSettingsWindow();
                        return 0;
                    }
                    break;
            }
            break;
        }
        case WM_CLOSE: finish(); return 0;
        case WM_DESTROY:
            g_wnd = nullptr;
            if (g_font) DeleteObject(g_font);
            if (g_title) DeleteObject(g_title);
            g_font = g_title = nullptr;
            return 0;
        default: break;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

}  // namespace

void showWelcome(bool setupPage, bool profilePages) {
    if (g_wnd) {
        SetForegroundWindow(g_wnd);
        return;
    }
    if (!setupPage && !profilePages) return;
    // Shown once per user, even if it is closed at once or the app is killed.
    writeFlag(L"welcomeShown", true);
    writeFlag(L"welcomePending", false);
    // Onboarding is not finished until Xong / Bỏ qua / close: a run cut short (killed,
    // sign-out) shows the profile pages again at the next start (decideOnboarding).
    g_profilePages = profilePages;
    if (profilePages) writeFlag(L"onboardingDone", false);
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW wc = {};
        wc.cbSize = sizeof wc;
        wc.lpfnWndProc = welcomeProc;
        wc.hInstance = g_inst;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
        wc.hIcon = LoadIconW(g_inst, MAKEINTRESOURCEW(IDI_APP));
        wc.lpszClassName = kWelcomeClass;
        registered = RegisterClassExW(&wc) != 0;
    }
    g_found = detectConflicts();
    g_dpi = GetDpiForSystem();
    g_wnd = CreateWindowExW(WS_EX_CONTROLPARENT, kWelcomeClass, tr(S::WelcomeTitle),
                            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT,
                            100, 100, nullptr, nullptr, g_inst, nullptr);
    if (!g_wnd) return;
    g_dpi = GetDpiForWindow(g_wnd);
    makeFonts();
    g_step = setupPage ? Step::Setup : Step::Profile;
    if (setupPage) build();
    else buildProfile();
    ShowWindow(g_wnd, SW_SHOWNORMAL);
    SetForegroundWindow(g_wnd);
}

bool welcomeDialogMessage(MSG* msg) { return g_wnd && IsDialogMessageW(g_wnd, msg); }

}  // namespace vtx::app
