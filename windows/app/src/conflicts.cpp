#include "conflicts.h"

#include <commctrl.h>
#include <msctf.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <cwchar>

#include "app.h"
#include "app_feel.h"
#include "foreground.h"
#include "hotkey.h"
#include "input_switch.h"
#include "registration.h"
#include "strings.h"
#include "tip_control.h"

// Windows SDK msctf.h values (older mingw-w64 headers lack them).
#ifndef TF_IPP_FLAG_ENABLED
#define TF_IPP_FLAG_ENABLED 0x00000002
#endif
#ifndef TF_PROFILETYPE_INPUTPROCESSOR
#define TF_PROFILETYPE_INPUTPROCESSOR 0x0001
#endif

namespace vtx::app {

namespace {

std::wstring fmt(const wchar_t* f, const std::wstring& a, const std::wstring& b = L"") {
    wchar_t buf[1024];
    swprintf(buf, 1024, f, a.c_str(), b.c_str());
    return buf;
}

std::string guidString(const GUID& g) {
    wchar_t w[64] = {};
    StringFromGUID2(g, w, 64);
    std::string s;
    for (const wchar_t* p = w; *p; ++p) s.push_back(static_cast<char>(*p));
    return s;
}

std::wstring widenAscii(const char* s) {
    std::wstring w;
    for (; s && *s; ++s) w.push_back(static_cast<wchar_t>(static_cast<unsigned char>(*s)));
    return w;
}

void findProcesses(std::vector<FoundConflict>& out) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return;
    PROCESSENTRY32W pe = {};
    pe.dwSize = sizeof pe;
    for (BOOL ok = Process32FirstW(snap, &pe); ok; ok = Process32NextW(snap, &pe)) {
        ConflictKind k;
        if (!classifyImeProcess(narrowAscii(pe.szExeFile), k)) continue;
        bool dup = false;
        for (const FoundConflict& c : out) dup = dup || c.kind == k;
        if (dup) continue;
        FoundConflict c;
        c.kind = k;
        c.name = widenAscii(conflictName(k));
        if (HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe.th32ProcessID)) {
            wchar_t buf[MAX_PATH];
            DWORD n = MAX_PATH;
            if (QueryFullProcessImageNameW(p, 0, buf, &n)) c.path.assign(buf, n);
            CloseHandle(p);
        }
        out.push_back(c);
    }
    CloseHandle(snap);
}

void findMicrosoftKeyboards(std::vector<FoundConflict>& out) {
    const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ITfInputProcessorProfileMgr* mgr = nullptr;
    ITfInputProcessorProfiles* profiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&mgr))) &&
        mgr) {
        mgr->QueryInterface(IID_ITfInputProcessorProfiles, reinterpret_cast<void**>(&profiles));
        IEnumTfInputProcessorProfiles* en = nullptr;
        if (SUCCEEDED(mgr->EnumProfiles(0x042A, &en)) && en) {
            TF_INPUTPROCESSORPROFILE pr;
            ULONG got = 0;
            while (en->Next(1, &pr, &got) == S_OK && got == 1) {
                ViProfile v;
                v.langId = pr.langid;
                v.isTip = pr.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR;
                v.enabled = (pr.dwFlags & TF_IPP_FLAG_ENABLED) != 0;
                if (v.isTip) {
                    v.clsid = guidString(pr.clsid);
                    v.profile = guidString(pr.guidProfile);
                } else {
                    v.hkl = static_cast<unsigned long>(reinterpret_cast<ULONG_PTR>(pr.hkl));
                }
                if (!isOtherVietnameseProfile(v, reg::kClsid)) continue;
                FoundConflict c;
                c.kind = ConflictKind::MicrosoftVietnamese;
                c.profile = v;
                BSTR desc = nullptr;
                if (v.isTip && profiles &&
                    SUCCEEDED(profiles->GetLanguageProfileDescription(pr.clsid, pr.langid, pr.guidProfile, &desc)) &&
                    desc) {
                    c.name = desc;
                    SysFreeString(desc);
                }
                if (c.name.empty()) c.name = L"Vietnamese";
                out.push_back(c);
            }
            en->Release();
        }
    }
    if (profiles) profiles->Release();
    if (mgr) mgr->Release();
    if (SUCCEEDED(init)) CoUninitialize();
}

constexpr wchar_t kToggleKey[] = L"Keyboard Layout\\Toggle";

bool readToggleValue(const wchar_t* name, std::string& out) {
    wchar_t buf[16] = {};
    DWORD sz = sizeof buf;
    if (RegGetValueW(HKEY_CURRENT_USER, kToggleKey, name, RRF_RT_REG_SZ, nullptr, buf, &sz) != ERROR_SUCCESS)
        return false;
    out = narrowAscii(buf);
    return true;
}

WinToggles readWindowsToggles() {
    std::string lang, legacy, layout;
    const bool hasLang = readToggleValue(L"Language Hotkey", lang);
    const bool hasLegacy = readToggleValue(L"Hotkey", legacy);
    const bool hasLayout = readToggleValue(L"Layout Hotkey", layout);
    return readWinToggles(hasLang, lang, hasLegacy, legacy, hasLayout, layout);
}

// Windows' own Ctrl+Shift (input_switch.h winHotkeyClash): one registry read, only when
// the warning is built (welcome window / Kiểu gõ page).
void findWindowsHotkey(std::vector<FoundConflict>& out) {
    bool otherVi = false;
    for (const FoundConflict& c : out) otherVi = otherVi || c.kind == ConflictKind::MicrosoftVietnamese;
    const WinToggles w = readWindowsToggles();
    const WinHotkeyClash clash = winHotkeyClash(parseSwitchHotkey(g_settings.switchHotkey), w, otherVi);
    if (appLogging())
        appLog("app", std::string("Windows input hotkeys: language ") + winToggleValue(w.language) + ", layout " +
                          winToggleValue(w.layout) +
                          (clash == WinHotkeyClash::None ? "" : " -> clashes with Ctrl+Shift"));
    if (clash == WinHotkeyClash::None) return;
    FoundConflict c;
    c.kind = ConflictKind::WindowsHotkey;
    c.name = tr(S::WinHotkeyName);
    out.push_back(c);
}

// Move Windows' hotkeys off Ctrl+Shift (winToggleFix), then SPI_SETLANGTOGGLE: Windows
// re-reads HKCU\Keyboard Layout\Toggle (documented for exactly this). User's click only.
bool fixWindowsHotkey() {
    const WinToggles before = readWindowsToggles();
    const WinToggleFix f = winToggleFix(before);
    HKEY k;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kToggleKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) !=
        ERROR_SUCCESS)
        return false;
    auto set = [k](const wchar_t* name, WinToggle t) {
        const wchar_t v[2] = {static_cast<wchar_t>(winToggleValue(t)[0]), 0};
        return RegSetValueExW(k, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(v), sizeof v) == ERROR_SUCCESS;
    };
    bool ok = true;
    if (f.changeLanguage) ok = set(L"Language Hotkey", f.language) && set(L"Hotkey", f.language) && ok;
    if (f.changeLayout) ok = set(L"Layout Hotkey", f.layout) && ok;
    RegCloseKey(k);
    SystemParametersInfoW(SPI_SETLANGTOGGLE, 0, nullptr, SPIF_SENDCHANGE);
    const WinToggles after = readWindowsToggles();
    ok = ok && after.language != WinToggle::CtrlShift && after.layout != WinToggle::CtrlShift;
    appLog("app", std::string("Windows input hotkeys -> language ") + winToggleValue(after.language) + ", layout " +
                      winToggleValue(after.layout) + (ok ? "" : " (failed)"));
    return ok;
}

}  // namespace

std::vector<FoundConflict> detectConflicts() {
    std::vector<FoundConflict> v;
    findProcesses(v);
    findMicrosoftKeyboards(v);
    findWindowsHotkey(v);  // after the keyboards: the layout clash needs them
    if (appLogging()) appLog("app", "other Vietnamese input methods found: " + std::to_string(v.size()));
    return v;
}

std::wstring conflictNames(const std::vector<FoundConflict>& list) {
    std::wstring s;
    for (const FoundConflict& c : list) {
        if (!s.empty()) s += L", ";
        s += c.name;
    }
    return s;
}

std::wstring conflictDescription(const std::vector<FoundConflict>& list) {
    bool other = false, windows = false;
    for (const FoundConflict& c : list) (c.kind == ConflictKind::WindowsHotkey ? windows : other) = true;
    std::wstring s;
    if (other || !windows) s = tr(S::ConflictDesc);
    if (windows) s += (s.empty() ? L"" : L" ") + std::wstring(tr(S::WinHotkeyDesc));
    return s;
}

bool removeBuiltInVietnameseKeyboards(const std::vector<FoundConflict>& list) {
    std::vector<ViProfile> profiles;
    for (const FoundConflict& c : list)
        if (c.kind == ConflictKind::MicrosoftVietnamese) profiles.push_back(c.profile);
    const std::vector<std::string> specs = builtInKeyboardRemovals(profiles, reg::kClsid);
    bool ok = !specs.empty();
    for (const std::string& spec : specs) {
        const bool removed = removeLayoutOrTipForUser(widenAscii(spec.c_str()));
        appLog("app", std::string("remove Windows Vietnamese keyboard ") + spec + (removed ? ": done" : ": failed"));
        ok = ok && removed;
    }
    // Look again (app_feel.h afterBuiltInRemoval): Windows may say "done" and keep the
    // keyboard (log 1.3.23), and the removal may take VietTelex out of the list with it
    // (report 12/11/2026) — VietTelex is then added back before anything else.
    std::vector<FoundConflict> left;
    findMicrosoftKeyboards(left);
    std::vector<ViProfile> leftProfiles;
    for (const FoundConflict& c : left) leftProfiles.push_back(c.profile);
    const bool stillListed = !builtInKeyboardRemovals(leftProfiles, reg::kClsid).empty();
    bool registered = false;
    const bool inList = vietTelexInUserList(registered);
    const vtx::BuiltInRemovalOutcome out = vtx::afterBuiltInRemoval(ok, stillListed, inList, registered);
    if (out.readd) {
        const bool added = addKeyboardForUser();
        appLog("app", std::string("VietTelex left the list with the removal: ") + (added ? "added back" : "add failed"));
    }
    if (stillListed) appLog("app", "Windows Vietnamese keyboard still listed after the removal");
    ok = out.ok;
    // What the user wanted: VietTelex is what Windows types Vietnamese with, from now on.
    const bool made = setDefaultKeyboardForUser();
    const bool selected = selectVietTelexForSession();
    appLog("app", std::string("after removal: ") + (made ? "default" : "default failed") +
                      (selected ? ", selected" : ", select failed"));
    return ok;
}

void resolveConflicts(HWND owner, const std::vector<FoundConflict>& list) {
    if (list.empty()) {
        MessageBoxW(owner, tr(S::ConflictNone), tr(S::AppName), MB_OK | MB_ICONINFORMATION);
        return;
    }
    // Buttons: 100+i open folder, 200+i how to quit, 300 remove Windows' built-in
    // Vietnamese keyboard(s) — one button for all of them, 400 settings.
    std::vector<std::wstring> labels;
    std::vector<int> ids;
    bool removeOffered = false;
    for (size_t i = 0; i < list.size(); ++i) {
        const FoundConflict& c = list[i];
        if (c.kind == ConflictKind::WindowsHotkey) {
            labels.push_back(std::wstring(tr(S::WinHotkeyFix)) + L"\n" + tr(S::WinHotkeyFixNote));
            ids.push_back(500);
        } else if (isThirdPartyIme(c.kind)) {
            if (!c.path.empty()) {
                labels.push_back(fmt(tr(S::ConflictOpenLocation), c.name));
                ids.push_back(100 + static_cast<int>(i));
            }
            labels.push_back(fmt(tr(S::ConflictHowToQuit), c.name));
            ids.push_back(200 + static_cast<int>(i));
        } else if (!removeOffered) {
            removeOffered = true;
            labels.push_back(std::wstring(tr(S::ConflictRemoveMs)) + L"\n" + tr(S::ConflictRemoveMsNote));
            ids.push_back(300);
        }
    }
    labels.push_back(tr(S::ConflictOpenLangSettings));
    ids.push_back(400);
    std::vector<TASKDIALOG_BUTTON> buttons(labels.size());
    for (size_t i = 0; i < labels.size(); ++i) buttons[i] = {ids[i], labels[i].c_str()};
    const std::wstring content = conflictDescription(list) + L"\n\n" + conflictNames(list);
    TASKDIALOGCONFIG tc = {};
    tc.cbSize = sizeof tc;
    tc.hwndParent = owner;
    tc.dwFlags = TDF_USE_COMMAND_LINKS | TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW;
    tc.dwCommonButtons = TDCBF_CLOSE_BUTTON;
    tc.pszWindowTitle = tr(S::AppName);
    tc.pszMainIcon = TD_WARNING_ICON;
    tc.pszMainInstruction = tr(S::ConflictTitle);
    tc.pszContent = content.c_str();
    tc.pszFooter = tr(S::ConflictDlgIntro);
    tc.cButtons = static_cast<UINT>(buttons.size());
    tc.pButtons = buttons.data();
    int pressed = 0;
    if (FAILED(TaskDialogIndirect(&tc, &pressed, nullptr, nullptr))) return;
    if (pressed >= 100 && pressed < 100 + static_cast<int>(list.size())) {
        const std::wstring args = L"/select,\"" + list[static_cast<size_t>(pressed - 100)].path + L"\"";
        ShellExecuteW(owner, L"open", L"explorer.exe", args.c_str(), nullptr, SW_SHOWNORMAL);
    } else if (pressed >= 200 && pressed < 200 + static_cast<int>(list.size())) {
        const std::wstring& n = list[static_cast<size_t>(pressed - 200)].name;
        MessageBoxW(owner, fmt(tr(S::ConflictQuitHelp), n, n).c_str(), tr(S::AppName), MB_OK | MB_ICONINFORMATION);
    } else if (pressed == 300) {
        if (removeBuiltInVietnameseKeyboards(list)) {
            MessageBoxW(owner, tr(S::ConflictRemoved), tr(S::AppName), MB_OK | MB_ICONINFORMATION);
        } else {
            MessageBoxW(owner, tr(S::ConflictRemoveFailed), tr(S::AppName), MB_OK | MB_ICONWARNING);
            ShellExecuteW(owner, L"open", kLanguageSettingsUri, nullptr, nullptr, SW_SHOWNORMAL);
        }
    } else if (pressed == 500) {
        if (fixWindowsHotkey()) {
            MessageBoxW(owner, tr(S::WinHotkeyFixed), tr(S::AppName), MB_OK | MB_ICONINFORMATION);
        } else {
            MessageBoxW(owner, tr(S::WinHotkeyFixFailed), tr(S::AppName), MB_OK | MB_ICONWARNING);
            ShellExecuteW(owner, L"open", kTypingSettingsUri, nullptr, nullptr, SW_SHOWNORMAL);
        }
    } else if (pressed == 400) {
        ShellExecuteW(owner, L"open", kLanguageSettingsUri, nullptr, nullptr, SW_SHOWNORMAL);
    }
}

}  // namespace vtx::app
