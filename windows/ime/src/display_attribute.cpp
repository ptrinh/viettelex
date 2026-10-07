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

// Same input attribute with a red squiggly underline (spell-checker convention). How much
// of it shows is up to the app's text store (line style and colour are hints it may drop).
TF_DISPLAYATTRIBUTE MisspelledAttribute() {
    TF_DISPLAYATTRIBUTE a = InputAttribute();
    a.lsStyle = TF_LS_SQUIGGLE;
    a.crLine.type = TF_CT_COLORREF;
    a.crLine.cr = RGB(0xE8, 0x11, 0x23);
    return a;
}
constexpr ULONG kAttributeCount = 2;  // [0] input, [1] misspelled

class DisplayAttributeInfo final : public ITfDisplayAttributeInfo {
public:
    explicit DisplayAttributeInfo(bool misspelled) : misspelled_(misspelled) { DllAddRef(); }
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
        *pguid = misspelled_ ? GUID_DisplayAttributeMisspelled : GUID_DisplayAttributeInput;
        return S_OK;
    }
    STDMETHODIMP GetDescription(BSTR* pbstr) override {
        if (!pbstr) return E_INVALIDARG;
        *pbstr = SysAllocString(misspelled_ ? L"VietTelex misspelled syllable" : L"VietTelex input");
        return *pbstr ? S_OK : E_OUTOFMEMORY;
    }
    STDMETHODIMP GetAttributeInfo(TF_DISPLAYATTRIBUTE* pda) override {
        if (!pda) return E_INVALIDARG;
        *pda = misspelled_ ? MisspelledAttribute() : InputAttribute();
        return S_OK;
    }
    STDMETHODIMP SetAttributeInfo(const TF_DISPLAYATTRIBUTE*) override { return E_NOTIMPL; }
    STDMETHODIMP Reset() override { return S_OK; }

private:
    ~DisplayAttributeInfo() { DllRelease(); }
    LONG ref_ = 1;
    bool misspelled_;
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
        while (fetched < ulCount && pos_ < kAttributeCount) {
            rgInfo[fetched] = new (std::nothrow) DisplayAttributeInfo(pos_ == 1);
            if (!rgInfo[fetched]) {
                while (fetched > 0) rgInfo[--fetched]->Release();
                return E_OUTOFMEMORY;
            }
            ++fetched;
            ++pos_;
        }
        if (pcFetched) *pcFetched = fetched;
        return fetched == ulCount ? S_OK : S_FALSE;
    }
    STDMETHODIMP Reset() override {
        pos_ = 0;
        return S_OK;
    }
    STDMETHODIMP Skip(ULONG ulCount) override {
        const ULONG left = kAttributeCount - pos_;
        const ULONG n = ulCount < left ? ulCount : left;
        pos_ += n;
        return n == ulCount ? S_OK : S_FALSE;
    }

private:
    ~EnumDisplayAttributeInfo() { DllRelease(); }
    LONG ref_ = 1;
    ULONG pos_;
};

}  // namespace

HRESULT CreateDisplayAttributeInfo(ITfDisplayAttributeInfo** out, bool misspelled) {
    if (!out) return E_INVALIDARG;
    *out = new (std::nothrow) DisplayAttributeInfo(misspelled);
    return *out ? S_OK : E_OUTOFMEMORY;
}

HRESULT CreateEnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** out) {
    if (!out) return E_INVALIDARG;
    *out = new (std::nothrow) EnumDisplayAttributeInfo();
    return *out ? S_OK : E_OUTOFMEMORY;
}

}  // namespace vtx::tip
