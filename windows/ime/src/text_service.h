// text_service.h — the VietTelex TSF text input processor (one instance per thread
// manager, i.e. per UI thread that has text input).
#pragma once
#include "globals.h"
#include "hotkey.h"
#include "session.h"
#include "settings.h"
#include "tsf_compat.h"

namespace vtx::tip {

class LangBarButton;

class TextService final : public ITfTextInputProcessorEx,
                          public ITfThreadMgrEventSink,
                          public ITfTextEditSink,
                          public ITfKeyEventSink,
                          public ITfCompositionSink,
                          public ITfDisplayAttributeProvider {
public:
    static HRESULT CreateInstance(IUnknown* outer, REFIID riid, void** ppv);

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor(Ex)
    STDMETHODIMP Activate(ITfThreadMgr* ptim, TfClientId tid) override;
    STDMETHODIMP ActivateEx(ITfThreadMgr* ptim, TfClientId tid, DWORD flags) override;
    STDMETHODIMP Deactivate() override;

    // ITfThreadMgrEventSink
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    STDMETHODIMP OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr* prev) override;
    STDMETHODIMP OnPushContext(ITfContext* ctx) override;
    STDMETHODIMP OnPopContext(ITfContext* ctx) override;

    // ITfTextEditSink
    STDMETHODIMP OnEndEdit(ITfContext* ctx, TfEditCookie ecReadOnly, ITfEditRecord* record) override;

    // ITfKeyEventSink
    STDMETHODIMP OnSetFocus(BOOL foreground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext* ctx, WPARAM wp, LPARAM lp, BOOL* eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext* ctx, WPARAM wp, LPARAM lp, BOOL* eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext* ctx, WPARAM wp, LPARAM lp, BOOL* eaten) override;
    STDMETHODIMP OnKeyUp(ITfContext* ctx, WPARAM wp, LPARAM lp, BOOL* eaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext* ctx, REFGUID guid, BOOL* eaten) override;

    // ITfCompositionSink
    STDMETHODIMP OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* comp) override;

    // ITfDisplayAttributeProvider
    STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) override;
    STDMETHODIMP GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** ppInfo) override;

    // --- used by TsfTextSink / LangBarButton ---
    ITfComposition* composition() const { return composition_; }
    void setComposition(ITfComposition* c, ITfContext* ctx);  // takes a reference
    void clearComposition();
    TfGuidAtom displayAtom() const { return displayAtom_; }
    TfClientId clientId() const { return clientId_; }
    ITfCompositionSink* compositionSink() { return this; }

    bool vietnamese() const;
    void toggleVietnamese();                 // hotkey / button click
    void setVietnameseFromUi(bool on);
    const Settings& settings() const { return settings_; }
    void requestConfigRecheck() { recheckConfig_ = true; }

private:
    TextService();
    ~TextService();

    bool typingEnabled() const;
    void applyConfig(bool force);
    bool prepareKey(WPARAM wp, bool down, KeyInput& out);
    uint8_t heldModifiers(uint32_t vk, bool down) const;
    void onModifierEvent(uint32_t vk, bool down);
    void flushAsync(ITfContext* ctx);
    void endCompositionAsync();
    bool fieldIsLiteral(ITfContext* ctx, TfEditCookie ec);

    bool initThreadMgrSink();
    void uninitThreadMgrSink();
    bool initKeySink();
    void uninitKeySink();
    void updatePreservedKey();
    void hookTextEditSink(ITfDocumentMgr* dm);
    void unhookTextEditSink();
    void registerDisplayAtom();

    LONG ref_ = 1;
    ITfThreadMgr* threadMgr_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    DWORD threadMgrCookie_ = TF_INVALID_COOKIE;
    ITfContext* editSinkContext_ = nullptr;
    DWORD editSinkCookie_ = TF_INVALID_COOKIE;
    bool keySinkAdvised_ = false;
    bool altZPreserved_ = false;

    ITfComposition* composition_ = nullptr;
    ITfContext* compositionContext_ = nullptr;
    TfGuidAtom displayAtom_ = TF_INVALID_GUIDATOM;

    TypingSession session_;
    Settings settings_;
    unsigned long settingsGen_ = 0;
    SwitchHotkey hotkey_ = SwitchHotkey::CtrlShift;
    ModifierChord chord_;
    bool recheckConfig_ = false;

    LangBarButton* langBar_ = nullptr;
};

}  // namespace vtx::tip
