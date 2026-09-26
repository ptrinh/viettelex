#include "text_service.h"

#include <new>

#include "config.h"
#include "ipc.h"
#include "display_attribute.h"
#include "edit_session.h"
#include "tsf_sink.h"

namespace vtx::tip {

namespace {

// Keeps a COM object alive inside an async edit-session lambda.
template <class T>
class Ref {
public:
    explicit Ref(T* p) : p_(p) { if (p_) p_->AddRef(); }
    Ref(const Ref& o) : p_(o.p_) { if (p_) p_->AddRef(); }
    Ref& operator=(const Ref&) = delete;
    ~Ref() { if (p_) p_->Release(); }
    T* get() const { return p_; }
    T* operator->() const { return p_; }

private:
    T* p_;
};

template <class T>
void SafeRelease(T*& p) {
    if (p) {
        p->Release();
        p = nullptr;
    }
}

uint8_t modBit(uint32_t v) {
    switch (v) {
        case vk::Control: case vk::LControl: case vk::RControl: return kModCtrl;
        case vk::Shift: case vk::LShift: case vk::RShift: return kModShift;
        case vk::Menu: case vk::LMenu: case vk::RMenu: return kModAlt;
        case vk::LWin: case vk::RWin: return kModWin;
        default: return 0;
    }
}

bool keyDown(int vkey) { return (GetKeyState(vkey) & 0x8000) != 0; }

}  // namespace

// ---------------------------------------------------------------- lifetime

HRESULT TextService::CreateInstance(IUnknown* outer, REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    auto* s = new (std::nothrow) TextService();
    if (!s) return E_OUTOFMEMORY;
    if (!s->session_.ok()) {
        s->Release();
        return E_OUTOFMEMORY;
    }
    HRESULT hr = s->QueryInterface(riid, ppv);
    s->Release();
    return hr;
}

TextService::TextService() { DllAddRef(); }
TextService::~TextService() { DllRelease(); }

STDMETHODIMP TextService::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfTextInputProcessor) ||
        IsEqualIID(riid, IID_ITfTextInputProcessorEx))
        *ppv = static_cast<ITfTextInputProcessorEx*>(this);
    else if (IsEqualIID(riid, IID_ITfThreadMgrEventSink))
        *ppv = static_cast<ITfThreadMgrEventSink*>(this);
    else if (IsEqualIID(riid, IID_ITfTextEditSink))
        *ppv = static_cast<ITfTextEditSink*>(this);
    else if (IsEqualIID(riid, IID_ITfKeyEventSink))
        *ppv = static_cast<ITfKeyEventSink*>(this);
    else if (IsEqualIID(riid, IID_ITfCompositionSink))
        *ppv = static_cast<ITfCompositionSink*>(this);
    else if (IsEqualIID(riid, IID_ITfDisplayAttributeProvider))
        *ppv = static_cast<ITfDisplayAttributeProvider*>(this);
    if (!*ppv) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) TextService::AddRef() { return static_cast<ULONG>(InterlockedIncrement(&ref_)); }
STDMETHODIMP_(ULONG) TextService::Release() {
    LONG r = InterlockedDecrement(&ref_);
    if (r == 0) delete this;
    return static_cast<ULONG>(r);
}

// ---------------------------------------------------------------- activation

STDMETHODIMP TextService::Activate(ITfThreadMgr* ptim, TfClientId tid) { return ActivateEx(ptim, tid, 0); }

STDMETHODIMP TextService::ActivateEx(ITfThreadMgr* ptim, TfClientId tid, DWORD flags) {
    if (!ptim) return E_INVALIDARG;
    threadMgr_ = ptim;
    threadMgr_->AddRef();
    clientId_ = tid;
    // Console hosts (conhost / OpenConsole / Windows Terminal) activate TSF with
    // TF_TMAE_CONSOLE: their document is only the composition (see app_policy.h HostText).
    consoleHost_ = (flags & TF_TMAE_CONSOLE) != 0;

    config::init((flags & TF_TMAE_SECUREMODE) != 0);
    applyConfig(true);

    if (!initThreadMgrSink() || !initKeySink()) {
        Deactivate();
        return E_FAIL;
    }
    registerDisplayAtom();
    updatePreservedKey();

    // No language-bar item: the taskbar already shows the keyboard-profile icon (the one
    // chosen in Settings); a second, input-mode icon next to it was redundant (1.0.8).
    // Việt/Anh state is shown by the optional tray icon in VietTelex.exe.

    ITfDocumentMgr* dm = nullptr;
    if (SUCCEEDED(threadMgr_->GetFocus(&dm)) && dm) {
        hookTextEditSink(dm);
        dm->Release();
    }
    config::log("activated");
    return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
    if (composition_ && compositionContext_) {
        // Best effort: close our composition so the app keeps plain text.
        ITfContext* ctx = compositionContext_;
        RunEditSession(ctx, clientId_, TF_ES_SYNC | TF_ES_READWRITE, [this, ctx](TfEditCookie ec) -> HRESULT {
            TsfTextSink sink(this, ctx, ec);
            session_.flush(sink);
            return S_OK;
        });
    }
    clearComposition();
    session_.resetContext();
    SafeRelease(targetCtx_);
    unhookTextEditSink();

    if (altZPreserved_ && threadMgr_) {
        ITfKeystrokeMgr* km = nullptr;
        if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&km))) && km) {
            TF_PRESERVEDKEY pk = {'Z', TF_MOD_ALT};
            km->UnpreserveKey(GUID_PreservedKeyToggle, &pk);
            km->Release();
        }
        altZPreserved_ = false;
    }
    uninitKeySink();
    uninitThreadMgrSink();
    SafeRelease(threadMgr_);
    clientId_ = TF_CLIENTID_NULL;
    return S_OK;
}

bool TextService::initThreadMgrSink() {
    ITfSource* src = nullptr;
    if (FAILED(threadMgr_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&src))) || !src) return false;
    HRESULT hr = src->AdviseSink(IID_ITfThreadMgrEventSink, static_cast<ITfThreadMgrEventSink*>(this),
                                 &threadMgrCookie_);
    src->Release();
    if (FAILED(hr)) threadMgrCookie_ = TF_INVALID_COOKIE;
    return SUCCEEDED(hr);
}

void TextService::uninitThreadMgrSink() {
    if (threadMgrCookie_ == TF_INVALID_COOKIE || !threadMgr_) return;
    ITfSource* src = nullptr;
    if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&src))) && src) {
        src->UnadviseSink(threadMgrCookie_);
        src->Release();
    }
    threadMgrCookie_ = TF_INVALID_COOKIE;
}

bool TextService::initKeySink() {
    ITfKeystrokeMgr* km = nullptr;
    if (FAILED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&km))) || !km) return false;
    HRESULT hr = km->AdviseKeyEventSink(clientId_, static_cast<ITfKeyEventSink*>(this), TRUE);
    km->Release();
    keySinkAdvised_ = SUCCEEDED(hr);
    return keySinkAdvised_;
}

void TextService::uninitKeySink() {
    if (!keySinkAdvised_ || !threadMgr_) return;
    ITfKeystrokeMgr* km = nullptr;
    if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&km))) && km) {
        km->UnadviseKeyEventSink(clientId_);
        km->Release();
    }
    keySinkAdvised_ = false;
}

void TextService::updatePreservedKey() {
    if (!threadMgr_) return;
    const bool want = hotkey_ == SwitchHotkey::AltZ;
    if (want == altZPreserved_) return;
    ITfKeystrokeMgr* km = nullptr;
    if (FAILED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&km))) || !km) return;
    TF_PRESERVEDKEY pk = {'Z', TF_MOD_ALT};
    if (want) {
        static const wchar_t kDesc[] = L"VietTelex: Việt/Anh";
        altZPreserved_ = SUCCEEDED(km->PreserveKey(clientId_, GUID_PreservedKeyToggle, &pk, kDesc,
                                                   static_cast<ULONG>(lstrlenW(kDesc))));
    } else {
        km->UnpreserveKey(GUID_PreservedKeyToggle, &pk);
        altZPreserved_ = false;
    }
    km->Release();
}

void TextService::registerDisplayAtom() {
    // TF_CreateCategoryMgr works in COM-less hosts (TIPCAP_COMLESS); msctf.dll is
    // necessarily loaded already when TSF activates us.
    ITfCategoryMgr* cm = nullptr;
    using CreateFn = HRESULT(WINAPI*)(ITfCategoryMgr**);
    if (HMODULE msctf = GetModuleHandleW(L"msctf.dll")) {
        auto fn = reinterpret_cast<CreateFn>(reinterpret_cast<void*>(GetProcAddress(msctf, "TF_CreateCategoryMgr")));
        if (fn && FAILED(fn(&cm))) cm = nullptr;
    }
    if (!cm && FAILED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                       reinterpret_cast<void**>(&cm))))
        cm = nullptr;
    if (cm) {
        if (FAILED(cm->RegisterGUID(GUID_DisplayAttributeInput, &displayAtom_))) displayAtom_ = TF_INVALID_GUIDATOM;
        cm->Release();
    }
}

void TextService::hookTextEditSink(ITfDocumentMgr* dm) {
    unhookTextEditSink();
    if (!dm) return;
    ITfContext* ctx = nullptr;
    if (FAILED(dm->GetTop(&ctx)) || !ctx) return;
    ITfSource* src = nullptr;
    if (SUCCEEDED(ctx->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&src))) && src) {
        if (SUCCEEDED(src->AdviseSink(IID_ITfTextEditSink, static_cast<ITfTextEditSink*>(this), &editSinkCookie_))) {
            editSinkContext_ = ctx;
            ctx = nullptr;
        } else {
            editSinkCookie_ = TF_INVALID_COOKIE;
        }
        src->Release();
    }
    SafeRelease(ctx);
}

void TextService::unhookTextEditSink() {
    if (editSinkContext_ && editSinkCookie_ != TF_INVALID_COOKIE) {
        ITfSource* src = nullptr;
        if (SUCCEEDED(editSinkContext_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&src))) && src) {
            src->UnadviseSink(editSinkCookie_);
            src->Release();
        }
    }
    editSinkCookie_ = TF_INVALID_COOKIE;
    SafeRelease(editSinkContext_);
}

// ---------------------------------------------------------------- configuration

void TextService::applyConfig(bool force) {
    unsigned long gen = config::refresh();
    if (!force && gen == settingsGen_) return;
    settingsGen_ = gen;
    settings_ = config::copySettings();

    SessionOptions o;
    o.engineFlags = settings_.engineFlags();
    o.autoRestore = settings_.autoRestore;
    o.reEditWord = settings_.reEditWord && !config::secureMode();
    o.shortcuts = config::secureMode() ? nullptr : &settings_.shortcuts;
    o.log = config::log;
    session_.configure(o);

    const OutputMode want = config::appMode() == AppMode::InPlace ? OutputMode::InPlace : OutputMode::Composition;
    // (AppMode::Direct maps to Composition only for the case the app is not running.)
    if (want != session_.outputMode()) {
        if (composition_) endCompositionAsync();
        session_.setOutputMode(want);
    }

    hotkey_ = parseSwitchHotkey(settings_.switchHotkey);
    chord_.disarm();
    updatePreservedKey();
}

bool TextService::vietnamese() const { return config::vietnamese(); }

bool TextService::appRunning() const { return FindWindowW(kAppWindowClass, nullptr) != nullptr; }

bool TextService::typingEnabled() const {
    if (!config::vietnamese() || directActive_) return false;
    AppMode m = config::appMode();
    if (m == AppMode::Direct) return !appRunning();  // the hook types; without the app, compose
    return m == AppMode::Composition || m == AppMode::InPlace;
}

// Hand this field to VietTelex.exe's hook (Direct mode: backspaces + Unicode, no
// underline) instead of composing. Only when the app runs; else composition stays.
bool TextService::requestDirect(const char* why) {
    if (directActive_) return true;
    if (!appRunning()) return false;
    directActive_ = true;
    session_.reset();
    if (HWND h = FindWindowW(kAppWindowClass, nullptr))
        PostMessageW(h, kAppCommandMsg, static_cast<WPARAM>(AppCommand::DirectMode), 1);
    config::log(why);
    return true;
}

void TextService::toggleVietnamese() { setVietnamese(!vietnamese()); }

void TextService::setVietnamese(bool on) {
    if (on != vietnamese()) {
        if (!on) {
            flushAsync(composition_ ? compositionContext_ : nullptr);
        } else {
            session_.resetContext();
        }
        config::setVietnamese(on);
        config::log(on ? "mode: vietnamese" : "mode: english");
        notifyAppState(on);
    }
}

// The optional tray icon in VietTelex.exe is the only Việt/Anh indicator (1.0.8): tell it.
void TextService::notifyAppState(bool on) {
    if (HWND h = FindWindowW(kAppWindowClass, nullptr))
        PostMessageW(h, kAppCommandMsg, static_cast<WPARAM>(AppCommand::StateChanged), on ? 1 : 0);
}

void TextService::flushAsync(ITfContext* ctx) {
    if (!ctx || !composition_) {
        session_.reset();
        return;
    }
    Ref<TextService> self(this);
    Ref<ITfContext> c(ctx);
    HRESULT hr = RunEditSession(ctx, clientId_, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
                                [self, c](TfEditCookie ec) -> HRESULT {
                                    TsfTextSink sink(self.get(), c.get(), ec);
                                    self->session_.flush(sink);
                                    return S_OK;
                                });
    if (FAILED(hr)) session_.reset();
}

void TextService::endCompositionAsync() {
    if (!composition_ || !compositionContext_) return;
    Ref<TextService> self(this);
    Ref<ITfContext> c(compositionContext_);
    HRESULT hr = RunEditSession(compositionContext_, clientId_, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
                                [self, c](TfEditCookie ec) -> HRESULT {
                                    TsfTextSink sink(self.get(), c.get(), ec);
                                    sink.endCompositionAsIs();
                                    return S_OK;
                                });
    if (FAILED(hr)) clearComposition();
}

void TextService::setComposition(ITfComposition* c, ITfContext* ctx) {
    clearComposition();
    composition_ = c;
    if (composition_) composition_->AddRef();
    compositionContext_ = ctx;
    if (compositionContext_) compositionContext_->AddRef();
}

void TextService::clearComposition() {
    SafeRelease(composition_);
    SafeRelease(compositionContext_);
}

namespace {
// {A94C5FD2-C471-4031-9546-709C17300CB9}: set by CUAS on the document manager of an
// IMM32 app whose focused field is not an Edit/RichEdit (Mozc IsTsfEmulatedDocumentMgr).
const GUID kCompartmentTsfEmulated = {0xa94c5fd2, 0xc471, 0x4031, {0x95, 0x46, 0x70, 0x9c, 0x17, 0x30, 0x0c, 0xb9}};
// GUID_COMPARTMENT_TRANSITORYEXTENSION_PARENT {8BE347F8-C7A0-11D7-B408-00065B84435C}
// (defined locally: not every SDK/mingw header set declares it).
const GUID kCompartmentTransitoryParent = {0x8be347f8, 0xc7a0, 0x11d7, {0xb4, 0x08, 0x00, 0x06, 0x5b, 0x84, 0x43, 0x5c}};

bool compartmentVariant(IUnknown* owner, REFGUID guid, VARIANT& out) {
    VariantInit(&out);
    if (!owner) return false;
    ITfCompartmentMgr* mgr = nullptr;
    if (FAILED(owner->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&mgr))) || !mgr) return false;
    ITfCompartment* c = nullptr;
    bool ok = SUCCEEDED(mgr->GetCompartment(guid, &c)) && c && SUCCEEDED(c->GetValue(&out));
    if (c) c->Release();
    mgr->Release();
    return ok;
}

bool compartmentFlag(IUnknown* owner, REFGUID guid, LONG mask) {
    VARIANT v;
    const bool set = compartmentVariant(owner, guid, v) && v.vt == VT_I4 && (v.lVal & mask) != 0;
    VariantClear(&v);
    return set;
}

bool isTransitory(ITfContext* ctx) {
    TF_STATUS st = {};
    return ctx && SUCCEEDED(ctx->GetStatus(&st)) && (st.dwStaticFlags & TF_SS_TRANSITORY) != 0;
}
}  // namespace

// Classifies the context a word is about to start in (see app_policy.h ContextInfo) and,
// for classic Edit/RichEdit, finds the full transitory-extension PARENT context.
void TextService::evaluateHost(ITfContext* ctx) {
    SafeRelease(targetCtx_);
    ContextInfo c;
    c.console = consoleHost_;
    c.hasContext = ctx != nullptr;
    ITfDocumentMgr* dm = nullptr;
    if (ctx && (FAILED(ctx->GetDocumentMgr(&dm)) || !dm)) c.hasContext = false;
    if (c.hasContext) {
        c.keyboardDisabled = compartmentFlag(ctx, GUID_COMPARTMENT_KEYBOARD_DISABLED, ~0) ||
                             compartmentFlag(ctx, GUID_COMPARTMENT_EMPTYCONTEXT, ~0);
        TF_STATUS st = {};
        if (SUCCEEDED(ctx->GetStatus(&st))) {
            c.transitory = (st.dwStaticFlags & TF_SS_TRANSITORY) != 0;
            c.readOnly = (st.dwDynamicFlags & TF_SD_READONLY) != 0;
        }
        if (c.transitory) {
            c.cuasEmulated = compartmentFlag(dm, kCompartmentTsfEmulated, 0x1);
            VARIANT v;
            if (!parentFailed_ && compartmentVariant(dm, kCompartmentTransitoryParent, v) &&
                v.vt == VT_UNKNOWN && v.punkVal) {
                ITfDocumentMgr* parent = nullptr;
                if (SUCCEEDED(v.punkVal->QueryInterface(IID_ITfDocumentMgr, reinterpret_cast<void**>(&parent))) &&
                    parent && parent != dm) {
                    c.hasParent = true;
                    ITfContext* top = nullptr;
                    if (SUCCEEDED(parent->GetTop(&top)) && top) {
                        c.parentTransitory = isTransitory(top);
                        if (!c.parentTransitory) targetCtx_ = top;  // keep the reference
                        else top->Release();
                    }
                }
                if (parent) parent->Release();
            }
            VariantClear(&v);
        }
        HWND focus = GetFocus();
        c.unicodeWindow = !focus || IsWindowUnicode(focus);
    }
    if (dm) dm->Release();
    host_ = classifyContext(c);
    if (host_ != HostText::NormalViaParent) SafeRelease(targetCtx_);
    // No usable text store: prefer Direct (the hook types, no underline) over composition.
    if (host_ == HostText::CompositionOnly && requestDirect("context without surrounding text -> direct (hook)")) return;
    session_.setCompositionOnlyContext(host_ == HostText::CompositionOnly);
}

bool TextService::fieldIsLiteral(ITfContext* ctx, TfEditCookie ec) {
    // Input scope is a text-store attribute (app property); some stores expose it as a
    // regular property instead.
    ITfReadOnlyProperty* prop = nullptr;
    if (FAILED(ctx->GetAppProperty(GUID_PROP_INPUTSCOPE, &prop)) || !prop) {
        prop = nullptr;
        ITfProperty* p = nullptr;
        if (FAILED(ctx->GetProperty(GUID_PROP_INPUTSCOPE, &p)) || !p) return false;
        prop = p;
    }
    bool literal = false;
    TF_SELECTION sel;
    ULONG fetched = 0;
    if (SUCCEEDED(ctx->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &fetched)) && fetched == 1) {
        VARIANT v;
        VariantInit(&v);
        if (SUCCEEDED(prop->GetValue(ec, sel.range, &v)) && v.vt == VT_UNKNOWN && v.punkVal) {
            ITfInputScope* is = nullptr;
            if (SUCCEEDED(v.punkVal->QueryInterface(IID_ITfInputScope, reinterpret_cast<void**>(&is))) && is) {
                InputScope* scopes = nullptr;
                UINT count = 0;
                if (SUCCEEDED(is->GetInputScopes(&scopes, &count)) && scopes) {
                    int buf[32];
                    UINT n = count < 32 ? count : 32;
                    for (UINT i = 0; i < n; ++i) buf[i] = static_cast<int>(scopes[i]);
                    literal = classifyInputScopes(buf, n) == FieldPolicy::Literal;
                    CoTaskMemFree(scopes);
                }
                is->Release();
            }
        }
        VariantClear(&v);
        sel.range->Release();
    }
    prop->Release();
    return literal;
}

// ---------------------------------------------------------------- thread manager events

STDMETHODIMP TextService::OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr*) {
    if (composition_) endCompositionAsync();
    session_.resetContext();
    chord_.disarm();
    parentFailed_ = false;
    SafeRelease(targetCtx_);
    host_ = HostText::Normal;
    if (directActive_) {  // the new field is evaluated afresh
        directActive_ = false;
        if (HWND h = FindWindowW(kAppWindowClass, nullptr))
            PostMessageW(h, kAppCommandMsg, static_cast<WPARAM>(AppCommand::DirectMode), 0);
    }
    resolveActiveApp();
    config::reloadVietnamese();
    applyConfig(true);
    if (focus) notifyAppState(vietnamese());
    hookTextEditSink(focus);
    return S_OK;
}

// WebView2 (new Teams, new Outlook…): the TIP runs in msedgewebview2.exe; per-app rules
// and Việt/Anh memory must follow the app that owns the root window.
void TextService::resolveActiveApp() {
    if (config::exeName() != "msedgewebview2.exe") return;
    HWND w = GetFocus();
    if (!w) w = GetForegroundWindow();
    HWND root = w ? GetAncestor(w, GA_ROOTOWNER) : nullptr;
    DWORD pid = 0;
    if (root) GetWindowThreadProcessId(root, &pid);
    std::wstring name;
    if (pid && pid != GetCurrentProcessId()) {
        if (HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
            wchar_t buf[MAX_PATH];
            DWORD n = MAX_PATH;
            if (QueryFullProcessImageNameW(p, 0, buf, &n)) {
                std::wstring path(buf, n);
                name = path.substr(path.find_last_of(L"\\/") + 1);
            }
            CloseHandle(p);
        }
    }
    config::setActiveApp(name);
}

STDMETHODIMP TextService::OnPushContext(ITfContext*) {
    ITfDocumentMgr* dm = nullptr;
    if (threadMgr_ && SUCCEEDED(threadMgr_->GetFocus(&dm)) && dm) {
        hookTextEditSink(dm);
        dm->Release();
    }
    session_.reset();
    return S_OK;
}

STDMETHODIMP TextService::OnPopContext(ITfContext* ctx) { return OnPushContext(ctx); }

// ---------------------------------------------------------------- text edit sink

STDMETHODIMP TextService::OnEndEdit(ITfContext* ctx, TfEditCookie ecReadOnly, ITfEditRecord* record) {
    if (!ctx || !record) return S_OK;
    if (composition_) {
        // The app emptied our composition (Excel cell autocomplete, app-side clear):
        // drop the word and end the composition (Mozc tip_edit_session_impl ~L565).
        ITfRange* cr = nullptr;
        if (SUCCEEDED(composition_->GetRange(&cr)) && cr) {
            BOOL empty = FALSE;
            cr->IsEmpty(ecReadOnly, &empty);
            cr->Release();
            if (empty && session_.wordActive()) {
                session_.reset();
                endCompositionAsync();
                return S_OK;
            }
        }
    }
    BOOL selChanged = FALSE;
    if (FAILED(record->GetSelectionStatus(&selChanged)) || !selChanged) return S_OK;
    chord_.disarm();  // a click between Ctrl+Shift press and release is not a toggle
    TsfTextSink ro(this, ctx, ecReadOnly);
    if (composition_) {
        // Caret left our composition (click, app-side move): the word is done as is.
        if (!ro.selectionInsideComposition()) {
            session_.reset();
            endCompositionAsync();
        }
        return S_OK;
    }
    // (Via the transitory-extension parent, this context is not the one holding our word;
    // the session re-verifies against the parent at every key instead.)
    if (session_.wordActive() && session_.wordMode() == OutputMode::InPlace && host_ != HostText::NormalViaParent) {
        const std::u16string& shown = session_.shown();
        // Our own edits and the app inserting a key we passed keep the word right
        // before the caret; anything else (click, arrow, app rewrite) does not.
        // A forward selection (omnibox autocomplete suffix) is the app's, not a change.
        if (ro.textBeforeCaret(static_cast<int>(shown.size())) != shown) session_.reset();
    }
    return S_OK;
}

// ---------------------------------------------------------------- keys

uint8_t TextService::heldModifiers(uint32_t vkey, bool down) const {
    uint8_t h = 0;
    if (keyDown(VK_CONTROL)) h |= kModCtrl;
    if (keyDown(VK_SHIFT)) h |= kModShift;
    if (keyDown(VK_MENU)) h |= kModAlt;
    if (keyDown(VK_LWIN) || keyDown(VK_RWIN)) h |= kModWin;
    uint8_t b = modBit(vkey);
    if (down) h |= b;
    else h &= static_cast<uint8_t>(~b);
    return h;
}

void TextService::onModifierEvent(uint32_t vkey, bool down) {
    if (hotkey_ != SwitchHotkey::CtrlShift) return;
    if (chord_.note(heldModifiers(vkey, down)) && !down) toggleVietnamese();
}

bool TextService::prepareKey(WPARAM wp, bool down, KeyInput& out) {
    const uint32_t vkey = static_cast<uint32_t>(wp);
    if (isModifierVk(vkey)) {
        onModifierEvent(vkey, down);
        return false;
    }
    if (down) chord_.disarm();
    if (!typingEnabled()) return false;
    Modifiers m;
    m.shift = keyDown(VK_SHIFT);
    m.ctrl = keyDown(VK_CONTROL);
    m.alt = keyDown(VK_MENU);
    m.win = keyDown(VK_LWIN) || keyDown(VK_RWIN);
    m.capsLock = (GetKeyState(VK_CAPITAL) & 1) != 0;
    out = classifyKey(vkey, m);
    return true;
}

STDMETHODIMP TextService::OnSetFocus(BOOL) { return S_OK; }

STDMETHODIMP TextService::OnTestKeyDown(ITfContext* ctx, WPARAM wp, LPARAM, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    if (isOwnInjected(static_cast<uintptr_t>(GetMessageExtraInfo()))) return S_OK;  // typed by our hook
    KeyInput k;
    if (!prepareKey(wp, true, k)) return S_OK;
    if (!session_.wordActive()) evaluateHost(ctx);
    if (directActive_) return S_OK;  // the hook types in this field
    // No focused context, keyboard disabled (games, canvases), read-only, ANSI window:
    // never eat a key there (SampleIME _IsKeyboardDisabled).
    if (host_ == HostText::Ignore || host_ == HostText::Literal) return S_OK;
    *eaten = session_.wantsKey(k) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnKeyDown(ITfContext* ctx, WPARAM wp, LPARAM, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    if (isOwnInjected(static_cast<uintptr_t>(GetMessageExtraInfo()))) return S_OK;
    KeyInput k;
    if (!ctx || !prepareKey(wp, true, k)) return S_OK;
    if (!session_.wordActive()) evaluateHost(ctx);
    if (directActive_) return S_OK;  // the hook types in this field
    if (host_ == HostText::Ignore || host_ == HostText::Literal || !session_.wantsKey(k)) return S_OK;
    // Classic Edit/RichEdit: read and edit through the full transitory-extension parent.
    ITfContext* target = (host_ == HostText::NormalViaParent && targetCtx_) ? targetCtx_ : ctx;
    BOOL result = FALSE;
    auto run = [&](ITfContext* tc) {
        return RunEditSession(tc, clientId_, TF_ES_SYNC | TF_ES_READWRITE, [&, tc](TfEditCookie ec) -> HRESULT {
            TsfTextSink sink(this, tc, ec);
            // Literal fields (password, PIN, number, e-mail): checked where a word would
            // start, so a field switch inside one context is caught too.
            if (!session_.wordActive() && k.kind == KeyKind::Char && fieldIsLiteral(tc, ec)) return S_OK;
            result = session_.handleKey(k, sink) ? TRUE : FALSE;
            return S_OK;
        });
    };
    HRESULT hr = run(target);
    if (hr != S_OK && target != ctx && !session_.wordActive()) {
        // Guard: the parent context refused a synchronous edit session. Stop using it
        // for this focus and compose in the keystroke context instead.
        config::log("transitory extension parent refused an edit session -> composition");
        parentFailed_ = true;
        SafeRelease(targetCtx_);
        host_ = HostText::CompositionOnly;
        session_.setCompositionOnlyContext(true);
        hr = run(ctx);
    }
    if (hr != S_OK) {
        // The app refused a synchronous edit session: type literally, never guess.
        session_.reset();
        result = FALSE;
    }
    // In-place just proved impossible in this field (nothing readable, e.g. xterm.js):
    // hand it to the hook rather than composing with an underline.
    if (session_.contextFellBack() && !result) requestDirect("in-place failed in this field -> direct (hook)");
    *eaten = result;
    return S_OK;
}

STDMETHODIMP TextService::OnTestKeyUp(ITfContext*, WPARAM wp, LPARAM, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    const uint32_t vkey = static_cast<uint32_t>(wp);
    if (isModifierVk(vkey)) onModifierEvent(vkey, false);
    return S_OK;
}

STDMETHODIMP TextService::OnKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnPreservedKey(ITfContext*, REFGUID guid, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    if (IsEqualGUID(guid, GUID_PreservedKeyToggle)) {
        toggleVietnamese();
        *eaten = TRUE;
    }
    return S_OK;
}

// ---------------------------------------------------------------- composition sink

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie, ITfComposition* comp) {
    if (comp && comp == composition_) {
        clearComposition();
        session_.reset();
    }
    return S_OK;
}

// ---------------------------------------------------------------- display attributes

STDMETHODIMP TextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) {
    return CreateEnumDisplayAttributeInfo(ppEnum);
}

STDMETHODIMP TextService::GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** ppInfo) {
    if (!ppInfo) return E_INVALIDARG;
    *ppInfo = nullptr;
    if (!IsEqualGUID(guid, GUID_DisplayAttributeInput)) return E_INVALIDARG;
    return CreateDisplayAttributeInfo(ppInfo);
}

}  // namespace vtx::tip
