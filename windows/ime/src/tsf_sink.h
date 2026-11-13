// tsf_sink.h — vtx::TextSink over a live ITfContext inside an edit session.
#pragma once
#include "globals.h"
#include "session.h"
#include "tip_caches.h"

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
    bool setComposition(const std::u16string& text, int absorb, bool misspelled) override;
    void endComposition(const std::u16string& finalText) override;
    void endCompositionAsIs() override;
    bool canReadContext() override;
    bool compositionText(std::u16string& out) override;
    AppView appTextEndsWith(const std::u16string& tail) override;

    // The store gives a selection (a caret) at all: false on a page with no editable
    // element focused (tip_caches.h NoEditableContext).
    bool hasCaret();
    // True when the selection lies inside the active composition (OnEndEdit check).
    bool selectionInsideComposition();

private:
    ITfRange* selectionRange();  // caller releases; nullptr on failure
    void setCaretAfter(ITfRange* r);
    // set=false clears the attribute; `misspelled` picks the red-squiggle atom.
    void applyAttribute(ITfRange* r, bool set, bool misspelled = false);

    TextService* svc_;
    ITfContext* ctx_;
    TfEditCookie ec_;
    // The last textBeforeCaret of this edit session (one sink = one session): lets
    // replaceBeforeCaret skip its verification read (tip_caches.h).
    BeforeCaretCache before_;
};

}  // namespace vtx::tip
