// edit_session.h — ITfEditSession wrapping a callable.
//
// Sync sessions (TF_ES_SYNC, from inside key handlers) may capture by reference;
// async sessions must capture by value (they run after the caller returned).
#pragma once
#include <new>
#include <utility>

#include "globals.h"

namespace vtx::tip {

template <class F>
class EditSession final : public ITfEditSession {
public:
    explicit EditSession(F&& f) : f_(std::move(f)) { DllAddRef(); }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfEditSession)) {
            *ppv = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&ref_)); }
    STDMETHODIMP_(ULONG) Release() override {
        LONG r = InterlockedDecrement(&ref_);
        if (r == 0) delete this;
        return static_cast<ULONG>(r);
    }
    STDMETHODIMP DoEditSession(TfEditCookie ec) override { return f_(ec); }

private:
    ~EditSession() { DllRelease(); }
    LONG ref_ = 1;
    F f_;
};

// Runs `f(ec)` in an edit session on `ctx`. Returns S_OK only if the session ran and
// `f` returned S_OK. `flags` e.g. TF_ES_SYNC | TF_ES_READWRITE.
template <class F>
HRESULT RunEditSession(ITfContext* ctx, TfClientId tid, DWORD flags, F&& f) {
    if (!ctx) return E_INVALIDARG;
    auto* es = new (std::nothrow) EditSession<std::decay_t<F>>(std::forward<F>(f));
    if (!es) return E_OUTOFMEMORY;
    HRESULT hrSession = E_FAIL;
    HRESULT hr = ctx->RequestEditSession(tid, es, flags, &hrSession);
    es->Release();
    if (FAILED(hr)) return hr;
    return hrSession;
}

}  // namespace vtx::tip
