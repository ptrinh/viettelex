#include "conflicts.h"

#include <commctrl.h>
#include <msctf.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <cwchar>

#include "foreground.h"
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

}  // namespace

std::vector<FoundConflict> detectConflicts() {
    std::vector<FoundConflict> v;
    findProcesses(v);
    findMicrosoftKeyboards(v);
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

void resolveConflicts(HWND owner, const std::vector<FoundConflict>& list) {
    if (list.empty()) {
        MessageBoxW(owner, tr(S::ConflictNone), tr(S::AppName), MB_OK | MB_ICONINFORMATION);
        return;
    }
    // Buttons: 100+i open folder, 200+i how to quit, 300+i remove keyboard, 400 settings.
    std::vector<std::wstring> labels;
    std::vector<int> ids;
    for (size_t i = 0; i < list.size(); ++i) {
        const FoundConflict& c = list[i];
        if (isThirdPartyIme(c.kind)) {
            if (!c.path.empty()) {
                labels.push_back(fmt(tr(S::ConflictOpenLocation), c.name));
                ids.push_back(100 + static_cast<int>(i));
            }
            labels.push_back(fmt(tr(S::ConflictHowToQuit), c.name));
            ids.push_back(200 + static_cast<int>(i));
        } else {
            labels.push_back(fmt(tr(S::ConflictRemoveMs), c.name) + L"\n" + tr(S::ConflictRemoveMsNote));
            ids.push_back(300 + static_cast<int>(i));
        }
    }
    labels.push_back(tr(S::ConflictOpenLangSettings));
    ids.push_back(400);
    std::vector<TASKDIALOG_BUTTON> buttons(labels.size());
    for (size_t i = 0; i < labels.size(); ++i) buttons[i] = {ids[i], labels[i].c_str()};
    const std::wstring content = std::wstring(tr(S::ConflictDesc)) + L"\n\n" + conflictNames(list);
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
    } else if (pressed >= 300 && pressed < 300 + static_cast<int>(list.size())) {
        const FoundConflict& c = list[static_cast<size_t>(pressed - 300)];
        const std::string spec = layoutOrTipSpec(c.profile);
        const bool ok = removeLayoutOrTipForUser(widenAscii(spec.c_str()));
        appLog("app", std::string("remove Microsoft Vietnamese keyboard ") + spec + (ok ? ": done" : ": failed"));
        if (ok) {
            MessageBoxW(owner, tr(S::ConflictRemoved), tr(S::AppName), MB_OK | MB_ICONINFORMATION);
        } else {
            MessageBoxW(owner, tr(S::ConflictRemoveFailed), tr(S::AppName), MB_OK | MB_ICONWARNING);
            ShellExecuteW(owner, L"open", kLanguageSettingsUri, nullptr, nullptr, SW_SHOWNORMAL);
        }
    } else if (pressed == 400) {
        ShellExecuteW(owner, L"open", kLanguageSettingsUri, nullptr, nullptr, SW_SHOWNORMAL);
    }
}

}  // namespace vtx::app
