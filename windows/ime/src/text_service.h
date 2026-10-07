// text_service.h — the VietTelex TSF text input processor (one instance per thread
// manager, i.e. per UI thread that has text input).
#pragma once
#include "globals.h"
#include "app_policy.h"
#include "caret_hints.h"
#include "hint_popup.h"
#include "hotkey.h"
#include "session.h"
#include "settings.h"
#include "text_tool_ipc.h"
#include "caret_hint_ipc.h"
#include "tsf_compat.h"

#include <string>

namespace vtx::tip {

// DllCanUnloadNow: unregister the text-tool window class of this module load.
void UnregisterToolWindowClass();

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

    // --- used by TsfTextSink ---
    ITfComposition* composition() const { return composition_; }
    void setComposition(ITfComposition* c, ITfContext* ctx);  // takes a reference
    void clearComposition();
    TfGuidAtom displayAtom() const { return displayAtom_; }
    TfGuidAtom misspelledAtom() const { return misspelledAtom_; }
    TfClientId clientId() const { return clientId_; }
    ITfCompositionSink* compositionSink() { return this; }

    bool vietnamese() const;
    void toggleVietnamese();                 // switch hotkey
    void setVietnamese(bool on);
    const Settings& settings() const { return settings_; }

private:
    TextService();
    ~TextService();

    bool typingEnabled() const;
    bool appRunning() const;
    bool directServesHere() const;
    bool requestDirect(const char* why);
    void publishLangProp();  // kTipLangProp on the focus root (hook / tray read it)
    void clearLangProp();
    void notifyAppState(bool on);
    void applyConfig(bool force);
    bool prepareKey(WPARAM wp, bool down, KeyInput& out);
    uint8_t heldModifiers(uint32_t vk, bool down) const;
    void onModifierEvent(uint32_t vk, bool down);
    void flushAsync(ITfContext* ctx);
    void endCompositionAsync();
    bool fieldIsLiteral(ITfContext* ctx, TfEditCookie ec);
    UINT inputScopesAtSelection(ITfContext* ctx, TfEditCookie ec, int* buf, UINT cap);

    // Công cụ văn bản (text_tool_ipc.h): a message-only window per thread manager that
    // VietTelex.exe asks for the selection; one pending request at a time.
    static LRESULT CALLBACK toolWndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp);
    void createToolWindow();
    void destroyToolWindow();
    void dropTextToolPending();
    ITfContext* textToolContext(TextToolStatus& why);
    void onTextToolRequest(unsigned tool, uint32_t request);
    int readToolSelection(ITfContext* ctx, TfEditCookie ec);
    void sendTextToolSelection();
    void applyTextToolResult();
    void evaluateHost(ITfContext* ctx);
    void resolveActiveApp();

    // Gợi ý cạnh con trỏ (ime/core/caret_hints.h). Keys feed a tracker only while a hint is
    // enabled; a trigger arms a timer on toolWnd_ (the app inserts the key first), then an
    // async READ session takes the text before the caret + the caret rectangle; typo fixes
    // and tones go through VietTelex.exe (caret_hint_ipc.h). Tab applies in OnKeyDown.
    enum class HintStage : uint8_t { None, Show, TypoAsk, TypoShow, TonesRun, TonesShow };
    bool hintsUsable() const;
    ITfContext* keyTarget(ITfContext* ctx) const;  // context holding the text (parent for Edit)
    void noteHintKey(const KeyInput& k, ITfContext* target, bool handled);
    void scheduleHint(const hints::Trigger& t, ITfContext* target);
    void onHintTimer();
    void readForHint(HintStage stage, int window);
    void onHintRead();
    void askApp(HintJob job, const std::u16string& text);
    void onHintReply();
    void presentHint(const hints::Suggestion& s);
    void hideHint();
    void dropHintWork();
    bool applyHint(ITfContext* ctx);
    void declineHint();
    bool hintKeyTest(WPARAM wp, BOOL* eaten);  // true = handled (eaten set)

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
    bool consoleHost_ = false;  // activated with TF_TMAE_CONSOLE
    HostText host_ = HostText::Normal;  // classification of the context of the current word
    ITfContext* targetCtx_ = nullptr;   // full transitory-extension parent (Edit/RichEdit)
    bool parentFailed_ = false;         // parent refused edit sessions for this focus
    bool directActive_ = false;         // this field is typed by the app's hook (Direct)
    bool directWanted_ = false;         // this field asked the app's hook to type (1.1.5)
    HWND langPropWnd_ = nullptr;        // where kTipLangProp is set

    ITfComposition* composition_ = nullptr;
    ITfContext* compositionContext_ = nullptr;
    TfGuidAtom displayAtom_ = TF_INVALID_GUIDATOM;
    TfGuidAtom misspelledAtom_ = TF_INVALID_GUIDATOM;  // red squiggle (underlineMisspelled)

    TypingSession session_;
    Settings settings_;
    unsigned long settingsGen_ = 0;
    SwitchHotkey hotkey_ = SwitchHotkey::CtrlShift;
    ModifierChord chord_;

    HWND toolWnd_ = nullptr;
    struct ToolPending {
        uint32_t request = 0;       // 0 = none
        unsigned tool = 0;
        int status = 0;             // read result: 0 = have text, else TextToolStatus
        ITfContext* ctx = nullptr;  // owned references
        ITfRange* range = nullptr;  // the selection that was read
        std::u16string text, result;
    } tool_;

    // caret hints
    hints::Enabled hintsOn_;
    bool hintsAny_ = false;
    hints::HintTracker hintTracker_;
    uint32_t keyGen_ = 0;               // +1 per key: background hint work shows only if unchanged
    hints::Trigger hintTrig_;           // armed trigger (timer)
    uint32_t hintGen_ = 0;              // keyGen_ when armed
    HintStage hintStage_ = HintStage::None;
    ITfContext* hintCtx_ = nullptr;     // owned: context to read
    struct HintRead {
        bool ok = false;
        std::u16string before;
        RECT caret = {0, 0, 0, 0};
        bool caretOk = false;
    } hintRead_;
    std::u32string hintAnswer_;         // from VietTelex.exe (typo fix / toned run)
    std::u32string hintRun_;            // tones: the run sent to the app
    bool hintAwaitingApp_ = false;
    std::optional<hints::Suggestion> hint_;  // shown
    std::u16string hintShownBefore_;    // tail of the screen when shown (caret moved -> hide)
    RECT hintCaret_ = {0, 0, 0, 0};
    int hintKeyAct_ = -1;               // hints::KeyAction decided in OnTestKeyDown
    hints::Rejected rejectedTypos_;
    std::u32string declinedTones_;
    HintPopup popup_;

};

}  // namespace vtx::tip
