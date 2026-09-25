#include "tsf_sink.h"

#include "text_service.h"

namespace vtx::tip {

namespace {
constexpr int kMaxRead = 64;
}  // namespace

ITfRange* TsfTextSink::selectionRange() {
    TF_SELECTION sel;
    ULONG fetched = 0;
    if (FAILED(ctx_->GetSelection(ec_, TF_DEFAULT_SELECTION, 1, &sel, &fetched)) || fetched != 1) return nullptr;
    return sel.range;  // already AddRef'd
}

void TsfTextSink::setCaretAfter(ITfRange* r) {
    ITfRange* c = nullptr;
    if (FAILED(r->Clone(&c)) || !c) return;
    c->Collapse(ec_, TF_ANCHOR_END);
    TF_SELECTION sel;
    sel.range = c;
    sel.style.ase = TF_AE_NONE;
    sel.style.fInterimChar = FALSE;
    ctx_->SetSelection(ec_, 1, &sel);
    c->Release();
}

void TsfTextSink::applyAttribute(ITfRange* r, bool set) {
    if (svc_->displayAtom() == TF_INVALID_GUIDATOM) return;
    ITfProperty* prop = nullptr;
    if (FAILED(ctx_->GetProperty(GUID_PROP_ATTRIBUTE, &prop)) || !prop) return;
    if (set) {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_I4;
        v.lVal = static_cast<LONG>(svc_->displayAtom());
        prop->SetValue(ec_, r, &v);
    } else {
        prop->Clear(ec_, r);
    }
    prop->Release();
}

std::u16string TsfTextSink::textBeforeCaret(int max) {
    std::u16string out;
    if (max <= 0) return out;
    if (max > kMaxRead) max = kMaxRead;
    ITfRange* r = nullptr;
    if (ITfComposition* comp = svc_->composition()) {
        ITfRange* cr = nullptr;
        if (SUCCEEDED(comp->GetRange(&cr)) && cr) {
            cr->Clone(&r);
            cr->Release();
        }
    } else {
        r = selectionRange();
    }
    if (!r) return out;
    r->Collapse(ec_, TF_ANCHOR_START);
    LONG shifted = 0;
    if (SUCCEEDED(r->ShiftStart(ec_, -max, &shifted, nullptr)) && shifted < 0) {
        WCHAR buf[kMaxRead + 1];
        ULONG got = 0;
        if (SUCCEEDED(r->GetText(ec_, 0, buf, static_cast<ULONG>(-shifted), &got)))
            out.assign(reinterpret_cast<const char16_t*>(buf), got);
    }
    r->Release();
    return out;
}

char16_t TsfTextSink::charAfterCaret() {
    ITfRange* r = nullptr;
    if (ITfComposition* comp = svc_->composition()) {
        ITfRange* cr = nullptr;
        if (SUCCEEDED(comp->GetRange(&cr)) && cr) {
            cr->Clone(&r);
            cr->Release();
        }
    } else {
        r = selectionRange();
    }
    if (!r) return 0;
    r->Collapse(ec_, TF_ANCHOR_END);
    char16_t c = 0;
    LONG shifted = 0;
    if (SUCCEEDED(r->ShiftEnd(ec_, 1, &shifted, nullptr)) && shifted == 1) {
        WCHAR buf[2];
        ULONG got = 0;
        if (SUCCEEDED(r->GetText(ec_, 0, buf, 1, &got)) && got == 1) c = static_cast<char16_t>(buf[0]);
    }
    r->Release();
    return c;
}

bool TsfTextSink::hasSelection() {
    ITfRange* r = selectionRange();
    if (!r) return false;
    BOOL empty = TRUE;
    r->IsEmpty(ec_, &empty);
    r->Release();
    return !empty;
}

bool TsfTextSink::replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) {
    if (svc_->composition()) return false;
    if (expect.size() > static_cast<size_t>(kMaxRead)) return false;
    ITfRange* r = selectionRange();
    if (!r) return false;
    bool ok = false;
    BOOL empty = FALSE;
    r->IsEmpty(ec_, &empty);
    if (empty) {
        LONG want = static_cast<LONG>(expect.size());
        LONG shifted = 0;
        bool positioned = want == 0 || (SUCCEEDED(r->ShiftStart(ec_, -want, &shifted, nullptr)) && shifted == -want);
        if (positioned && want > 0) {
            WCHAR buf[kMaxRead + 1];
            ULONG got = 0;
            positioned = SUCCEEDED(r->GetText(ec_, 0, buf, static_cast<ULONG>(want), &got)) &&
                         got == static_cast<ULONG>(want) &&
                         expect.compare(0, expect.size(), reinterpret_cast<const char16_t*>(buf), got) == 0;
        }
        if (positioned) {
            ok = SUCCEEDED(r->SetText(ec_, 0, reinterpret_cast<const WCHAR*>(insert.data()),
                                      static_cast<LONG>(insert.size())));
            if (ok) setCaretAfter(r);
        }
    }
    r->Release();
    return ok;
}

bool TsfTextSink::compositionActive() { return svc_->composition() != nullptr; }

bool TsfTextSink::setComposition(const std::u16string& text, int absorb) {
    ITfComposition* comp = svc_->composition();
    ITfRange* r = nullptr;
    if (!comp) {
        r = selectionRange();
        if (!r) return false;
        if (absorb > 0) {
            LONG shifted = 0;
            if (FAILED(r->ShiftStart(ec_, -absorb, &shifted, nullptr)) || shifted != -absorb) {
                r->Release();
                return false;
            }
        }
        ITfContextComposition* cc = nullptr;
        if (FAILED(ctx_->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void**>(&cc))) || !cc) {
            r->Release();
            return false;
        }
        ITfComposition* started = nullptr;
        HRESULT hr = cc->StartComposition(ec_, r, svc_->compositionSink(), &started);
        cc->Release();
        r->Release();
        r = nullptr;
        if (FAILED(hr) || !started) return false;  // app refused (read-only field etc.)
        svc_->setComposition(started, ctx_);
        started->Release();
        comp = svc_->composition();
    }
    if (FAILED(comp->GetRange(&r)) || !r) return false;
    bool ok = SUCCEEDED(r->SetText(ec_, 0, reinterpret_cast<const WCHAR*>(text.data()), static_cast<LONG>(text.size())));
    if (ok) {
        applyAttribute(r, true);
        setCaretAfter(r);
    }
    r->Release();
    return ok;
}

void TsfTextSink::endComposition(const std::u16string& finalText) {
    ITfComposition* comp = svc_->composition();
    if (!comp) return;
    ITfRange* r = nullptr;
    if (SUCCEEDED(comp->GetRange(&r)) && r) {
        r->SetText(ec_, 0, reinterpret_cast<const WCHAR*>(finalText.data()), static_cast<LONG>(finalText.size()));
        applyAttribute(r, false);
        setCaretAfter(r);
        r->Release();
    }
    comp->AddRef();
    svc_->clearComposition();
    comp->EndComposition(ec_);
    comp->Release();
}

void TsfTextSink::endCompositionAsIs() {
    ITfComposition* comp = svc_->composition();
    if (!comp) return;
    ITfRange* r = nullptr;
    if (SUCCEEDED(comp->GetRange(&r)) && r) {
        applyAttribute(r, false);
        r->Release();
    }
    comp->AddRef();
    svc_->clearComposition();
    comp->EndComposition(ec_);
    comp->Release();
}

bool TsfTextSink::selectionInsideComposition() {
    ITfComposition* comp = svc_->composition();
    if (!comp) return false;
    ITfRange* cr = nullptr;
    if (FAILED(comp->GetRange(&cr)) || !cr) return false;
    ITfRange* sr = selectionRange();
    bool inside = false;
    if (sr) {
        LONG startCmp = 0, endCmp = 0;
        // sel.start >= comp.start  and  sel.end <= comp.end
        if (SUCCEEDED(sr->CompareStart(ec_, cr, TF_ANCHOR_START, &startCmp)) &&
            SUCCEEDED(sr->CompareEnd(ec_, cr, TF_ANCHOR_END, &endCmp)))
            inside = startCmp >= 0 && endCmp <= 0;
        sr->Release();
    }
    cr->Release();
    return inside;
}

}  // namespace vtx::tip
