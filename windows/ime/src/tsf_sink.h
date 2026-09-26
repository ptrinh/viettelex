// tsf_sink.h — vtx::TextSink over a live ITfContext inside an edit session.
#pragma once
#include "globals.h"
#include "session.h"

namespace vtx::tip {

class TextService;

class TsfTextSink final : public TextSink {
public:
    // `ec` must be a read/write cookie for mutations; read-only works for queries.
    TsfTextSink(TextService* svc, ITfContext* ctx, TfEditCookie ec) : svc_(svc), ctx_(ctx), ec_(ec) {}

    std::u16string textBeforeCaret(int max) override;
    char16_t charAfterCaret() override;
    bool hasSelection() override;
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) override;
    bool compositionActive() override;
    bool setComposition(const std::u16string& text, int absorb) override;
    void endComposition(const std::u16string& finalText) override;
    void endCompositionAsIs() override;
    bool canReadContext() override;

    // True when the selection lies inside the active composition (OnEndEdit check).
    bool selectionInsideComposition();

private:
    ITfRange* selectionRange();  // caller releases; nullptr on failure
    void setCaretAfter(ITfRange* r);
    void applyAttribute(ITfRange* r, bool set);

    TextService* svc_;
    ITfContext* ctx_;
    TfEditCookie ec_;
};

}  // namespace vtx::tip
