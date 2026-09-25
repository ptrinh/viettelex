// langbar.h — the V/E button in the taskbar input indicator (GUID_LBI_INPUTMODE):
// left click toggles Vietnamese/English, right click opens the menu.
#pragma once
#include "globals.h"
#include "ipc.h"
#include "tsf_compat.h"

namespace vtx::tip {

class TextService;

class LangBarButton final : public ITfLangBarItemButton, public ITfSource {
public:
    explicit LangBarButton(TextService* svc);
    void detach() { svc_ = nullptr; }
    void update();  // mode or settings changed

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    // ITfLangBarItem
    STDMETHODIMP GetInfo(TF_LANGBARITEMINFO* info) override;
    STDMETHODIMP GetStatus(DWORD* status) override;
    STDMETHODIMP Show(BOOL show) override;
    STDMETHODIMP GetTooltipString(BSTR* tip) override;
    // ITfLangBarItemButton
    STDMETHODIMP OnClick(TfLBIClick click, POINT pt, const RECT* area) override;
    STDMETHODIMP InitMenu(ITfMenu* menu) override;
    STDMETHODIMP OnMenuSelect(UINT id) override;
    STDMETHODIMP GetIcon(HICON* icon) override;
    STDMETHODIMP GetText(BSTR* text) override;
    // ITfSource
    STDMETHODIMP AdviseSink(REFIID riid, IUnknown* punk, DWORD* cookie) override;
    STDMETHODIMP UnadviseSink(DWORD cookie) override;

private:
    ~LangBarButton();
    bool vietnamese() const;
    bool english() const;  // UI language

    LONG ref_ = 1;
    TextService* svc_;
    ITfLangBarItemSink* sink_ = nullptr;
};

// Deliver a command to VietTelex.exe (running instance or a fresh launch).
void SendAppCommand(AppCommand cmd);

}  // namespace vtx::tip
