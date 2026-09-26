#include "display_attribute.h"

#include <new>

namespace vtx::tip {

namespace {

// Regression guard (Chrome showed an underline): the attribute must say "no line, no
// colours, input". Chrome's TSF text store maps lsStyle TF_LS_NONE to no underline.
static_assert(TF_LS_NONE == 0 && TF_CT_NONE == 0 && TF_ATTR_INPUT == 0, "TSF enum values");

TF_DISPLAYATTRIBUTE InputAttribute() {
    TF_DISPLAYATTRIBUTE a;
    a.crText.type = TF_CT_NONE;
    a.crText.cr = 0;
    a.crBk.type = TF_CT_NONE;
    a.crBk.cr = 0;
    a.lsStyle = TF_LS_NONE;
    a.fBoldLine = FALSE;
    a.crLine.type = TF_CT_NONE;
    a.crLine.cr = 0;
    a.bAttr = TF_ATTR_INPUT;
    return a;
}

class DisplayAttributeInfo final : public ITfDisplayAttributeInfo {
public:
    DisplayAttributeInfo() { DllAddRef(); }
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfDisplayAttributeInfo)) {
            *ppv = static_cast<ITfDisplayAttributeInfo*>(this);
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
    STDMETHODIMP GetGUID(GUID* pguid) override {
        if (!pguid) return E_INVALIDARG;
        *pguid = GUID_DisplayAttributeInput;
        return S_OK;
    }
    STDMETHODIMP GetDescription(BSTR* pbstr) override {
        if (!pbstr) return E_INVALIDARG;
        *pbstr = SysAllocString(L"VietTelex input");
        return *pbstr ? S_OK : E_OUTOFMEMORY;
    }
    STDMETHODIMP GetAttributeInfo(TF_DISPLAYATTRIBUTE* pda) override {
        if (!pda) return E_INVALIDARG;
        *pda = InputAttribute();
        return S_OK;
    }
    STDMETHODIMP SetAttributeInfo(const TF_DISPLAYATTRIBUTE*) override { return E_NOTIMPL; }
    STDMETHODIMP Reset() override { return S_OK; }

private:
    ~DisplayAttributeInfo() { DllRelease(); }
    LONG ref_ = 1;
};

class EnumDisplayAttributeInfo final : public IEnumTfDisplayAttributeInfo {
public:
    explicit EnumDisplayAttributeInfo(ULONG pos = 0) : pos_(pos) { DllAddRef(); }
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IEnumTfDisplayAttributeInfo)) {
            *ppv = static_cast<IEnumTfDisplayAttributeInfo*>(this);
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
    STDMETHODIMP Clone(IEnumTfDisplayAttributeInfo** ppEnum) override {
        if (!ppEnum) return E_INVALIDARG;
        *ppEnum = new (std::nothrow) EnumDisplayAttributeInfo(pos_);
        return *ppEnum ? S_OK : E_OUTOFMEMORY;
    }
    STDMETHODIMP Next(ULONG ulCount, ITfDisplayAttributeInfo** rgInfo, ULONG* pcFetched) override {
        if (!rgInfo) return E_INVALIDARG;
        ULONG fetched = 0;
        if (ulCount > 0 && pos_ == 0) {
            rgInfo[0] = new (std::nothrow) DisplayAttributeInfo();
            if (!rgInfo[0]) return E_OUTOFMEMORY;
            fetched = 1;
            pos_ = 1;
        }
        if (pcFetched) *pcFetched = fetched;
        return fetched == ulCount ? S_OK : S_FALSE;
    }
    STDMETHODIMP Reset() override {
        pos_ = 0;
        return S_OK;
    }
    STDMETHODIMP Skip(ULONG ulCount) override {
        if (ulCount > 0 && pos_ == 0) {
            pos_ = 1;
            return ulCount == 1 ? S_OK : S_FALSE;
        }
        return ulCount == 0 ? S_OK : S_FALSE;
    }

private:
    ~EnumDisplayAttributeInfo() { DllRelease(); }
    LONG ref_ = 1;
    ULONG pos_;
};

}  // namespace

HRESULT CreateDisplayAttributeInfo(ITfDisplayAttributeInfo** out) {
    if (!out) return E_INVALIDARG;
    *out = new (std::nothrow) DisplayAttributeInfo();
    return *out ? S_OK : E_OUTOFMEMORY;
}

HRESULT CreateEnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** out) {
    if (!out) return E_INVALIDARG;
    *out = new (std::nothrow) EnumDisplayAttributeInfo();
    return *out ? S_OK : E_OUTOFMEMORY;
}

}  // namespace vtx::tip
