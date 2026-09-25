#include "langbar.h"

#include <olectl.h>

#include <string>

#include "config.h"
#include "icons.h"
#include "text_service.h"

namespace vtx::tip {

namespace {
constexpr DWORD kSinkCookie = 0x56545842;  // one sink only
enum MenuId : UINT { kMenuVi = 1, kMenuEn, kMenuTelex, kMenuVni, kMenuSettings, kMenuUpdate, kMenuAbout };

std::wstring appExePath() {
    wchar_t buf[MAX_PATH];
    DWORD sz = sizeof buf;
    // Written by the installer (64-bit view so the x86 DLL finds the x64/ARM64 app).
    if (RegGetValueW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\VietTelex", L"AppPath", RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
                     nullptr, buf, &sz) == ERROR_SUCCESS)
        return buf;
    DWORD n = GetModuleFileNameW(g_hInst, buf, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return L"";
    std::wstring p(buf, n);
    size_t slash = p.find_last_of(L'\\');
    return slash == std::wstring::npos ? L"" : p.substr(0, slash + 1) + L"VietTelex.exe";
}
}  // namespace

void SendAppCommand(AppCommand cmd) {
    if (HWND h = FindWindowW(kAppWindowClass, nullptr)) {
        PostMessageW(h, kAppCommandMsg, static_cast<WPARAM>(cmd), 0);
        return;
    }
    if (config::secureMode() || config::inAppContainer()) return;  // cannot launch from there
    std::wstring exe = appExePath();
    if (exe.empty()) return;
    std::wstring cmdLine = L"\"" + exe + L"\" --command " + std::to_wstring(static_cast<unsigned>(cmd));
    STARTUPINFOW si = {};
    si.cb = sizeof si;
    PROCESS_INFORMATION pi = {};
    if (CreateProcessW(exe.c_str(), &cmdLine[0], nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi)) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
}

LangBarButton::LangBarButton(TextService* svc) : svc_(svc) { DllAddRef(); }
LangBarButton::~LangBarButton() {
    if (sink_) sink_->Release();
    DllRelease();
}

STDMETHODIMP LangBarButton::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfLangBarItem) ||
        IsEqualIID(riid, IID_ITfLangBarItemButton))
        *ppv = static_cast<ITfLangBarItemButton*>(this);
    else if (IsEqualIID(riid, IID_ITfSource))
        *ppv = static_cast<ITfSource*>(this);
    if (!*ppv) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}
STDMETHODIMP_(ULONG) LangBarButton::AddRef() { return static_cast<ULONG>(InterlockedIncrement(&ref_)); }
STDMETHODIMP_(ULONG) LangBarButton::Release() {
    LONG r = InterlockedDecrement(&ref_);
    if (r == 0) delete this;
    return static_cast<ULONG>(r);
}

bool LangBarButton::vietnamese() const { return svc_ && svc_->vietnamese(); }
bool LangBarButton::english() const { return svc_ && svc_->settings().uiLanguage == "en"; }

STDMETHODIMP LangBarButton::GetInfo(TF_LANGBARITEMINFO* info) {
    if (!info) return E_INVALIDARG;
    info->clsidService = CLSID_VietTelexTIP;
    info->guidItem = GUID_LBI_INPUTMODE_VTX;
    info->dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_SHOWNINTRAY | TF_LBI_STYLE_TEXTCOLORICON;
    info->ulSort = 0;
    lstrcpynW(info->szDescription, L"VietTelex", TF_LBI_DESC_MAXLEN);
    return S_OK;
}

STDMETHODIMP LangBarButton::GetStatus(DWORD* status) {
    if (!status) return E_INVALIDARG;
    *status = 0;
    return S_OK;
}

STDMETHODIMP LangBarButton::Show(BOOL) { return E_NOTIMPL; }

STDMETHODIMP LangBarButton::GetTooltipString(BSTR* tip) {
    if (!tip) return E_INVALIDARG;
    const wchar_t* s = vietnamese() ? (english() ? L"VietTelex — Vietnamese" : L"VietTelex — Tiếng Việt")
                                    : (english() ? L"VietTelex — English" : L"VietTelex — Tiếng Anh");
    *tip = SysAllocString(s);
    return *tip ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LangBarButton::OnClick(TfLBIClick click, POINT, const RECT*) {
    if (click == TF_LBI_CLK_LEFT && svc_) svc_->toggleVietnamese();
    return S_OK;
}

STDMETHODIMP LangBarButton::InitMenu(ITfMenu* menu) {
    if (!menu || !svc_) return E_INVALIDARG;
    const bool en = english();
    const bool vi = vietnamese();
    const bool vni = svc_->settings().vniMode;
    auto add = [&](UINT id, DWORD flags, const wchar_t* text) {
        menu->AddMenuItem(id, flags, nullptr, nullptr, text, static_cast<ULONG>(lstrlenW(text)), nullptr);
    };
    add(kMenuVi, vi ? TF_LBMENUF_RADIOCHECKED : 0, en ? L"Vietnamese" : L"Tiếng Việt");
    add(kMenuEn, vi ? 0 : TF_LBMENUF_RADIOCHECKED, en ? L"English" : L"Tiếng Anh");
    add(0, TF_LBMENUF_SEPARATOR, L"");
    add(kMenuTelex, vni ? 0 : TF_LBMENUF_RADIOCHECKED, L"Telex");
    add(kMenuVni, vni ? TF_LBMENUF_RADIOCHECKED : 0, L"VNI");
    add(0, TF_LBMENUF_SEPARATOR, L"");
    add(kMenuSettings, 0, en ? L"Settings…" : L"Cài đặt…");
    add(kMenuUpdate, 0, en ? L"Check for updates" : L"Kiểm tra cập nhật");
    add(kMenuAbout, 0, en ? L"About VietTelex" : L"Giới thiệu VietTelex");
    return S_OK;
}

STDMETHODIMP LangBarButton::OnMenuSelect(UINT id) {
    if (!svc_) return S_OK;
    switch (id) {
        case kMenuVi: svc_->setVietnameseFromUi(true); break;
        case kMenuEn: svc_->setVietnameseFromUi(false); break;
        case kMenuTelex: SendAppCommand(AppCommand::SetTelex); svc_->requestConfigRecheck(); break;
        case kMenuVni: SendAppCommand(AppCommand::SetVni); svc_->requestConfigRecheck(); break;
        case kMenuSettings: SendAppCommand(AppCommand::OpenSettings); break;
        case kMenuUpdate: SendAppCommand(AppCommand::CheckUpdate); break;
        case kMenuAbout: SendAppCommand(AppCommand::OpenAbout); break;
        default: break;
    }
    return S_OK;
}

STDMETHODIMP LangBarButton::GetIcon(HICON* icon) {
    if (!icon) return E_INVALIDARG;
    bool vt = !svc_ || svc_->settings().menuIcon != "letter";
    *icon = CreateModeIcon(vietnamese(), vt, 0);
    return *icon ? S_OK : E_FAIL;
}

STDMETHODIMP LangBarButton::GetText(BSTR* text) {
    if (!text) return E_INVALIDARG;
    *text = SysAllocString(vietnamese() ? L"V" : L"E");
    return *text ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LangBarButton::AdviseSink(REFIID riid, IUnknown* punk, DWORD* cookie) {
    if (!punk || !cookie) return E_INVALIDARG;
    if (!IsEqualIID(riid, IID_ITfLangBarItemSink)) return CONNECT_E_CANNOTCONNECT;
    if (sink_) return CONNECT_E_ADVISELIMIT;
    if (FAILED(punk->QueryInterface(IID_ITfLangBarItemSink, reinterpret_cast<void**>(&sink_)))) {
        sink_ = nullptr;
        return E_NOINTERFACE;
    }
    *cookie = kSinkCookie;
    return S_OK;
}

STDMETHODIMP LangBarButton::UnadviseSink(DWORD cookie) {
    if (cookie != kSinkCookie || !sink_) return CONNECT_E_NOCONNECTION;
    sink_->Release();
    sink_ = nullptr;
    return S_OK;
}

void LangBarButton::update() {
    if (sink_) sink_->OnUpdate(TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP);
}

}  // namespace vtx::tip
