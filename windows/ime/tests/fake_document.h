// fake_document.h — a text field + "app" that behaves like a TSF document for the
// TypingSession: composition range, caret, selection, and the app's default handling
// of keys the TIP did not eat.
#pragma once
#include <string>

#include "session.h"

namespace vtx::test {

class FakeDocument : public TextSink {
public:
    std::u16string text;
    size_t caret = 0;
    size_t anchor = 0;           // selection = [min(anchor,caret), max)
    bool comp = false;
    size_t compStart = 0, compEnd = 0;
    int edits = 0;               // number of TextSink mutations (for "no-op" checks)
    bool refuseEdits = false;    // simulate an app that rejects edit sessions

    std::u16string textBeforeCaret(int max) override {
        size_t end = comp ? compStart : caret;
        size_t n = static_cast<size_t>(max) < end ? static_cast<size_t>(max) : end;
        return text.substr(end - n, n);
    }
    char16_t charAfterCaret() override {
        size_t at = comp ? compEnd : caret;
        return at < text.size() ? text[at] : 0;
    }
    bool hasSelection() override { return anchor != caret; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& ins) override {
        if (refuseEdits || comp || expect.size() > caret) return false;
        if (text.compare(caret - expect.size(), expect.size(), expect) != 0) return false;
        text.replace(caret - expect.size(), expect.size(), ins);
        caret = caret - expect.size() + ins.size();
        anchor = caret;
        ++edits;
        return true;
    }
    bool compositionActive() override { return comp; }
    bool setComposition(const std::u16string& t, int absorb) override {
        if (refuseEdits) return false;
        if (!comp) {
            if (static_cast<size_t>(absorb) > caret) return false;
            // typing over a selection replaces it
            size_t lo = anchor < caret ? anchor : caret, hi = anchor < caret ? caret : anchor;
            text.erase(lo, hi - lo);
            caret = lo;
            compStart = caret - static_cast<size_t>(absorb);
            compEnd = caret;
            comp = true;
        }
        text.replace(compStart, compEnd - compStart, t);
        compEnd = compStart + t.size();
        caret = anchor = compEnd;
        ++edits;
        return true;
    }
    void endComposition(const std::u16string& t) override {
        if (!comp) return;
        text.replace(compStart, compEnd - compStart, t);
        compEnd = compStart + t.size();
        caret = anchor = compEnd;
        comp = false;
        ++edits;
    }

    void endCompositionAsIs() override {
        if (!comp) return;
        caret = anchor = compEnd;
        comp = false;
        ++edits;
    }

    // --- the app's default behaviour for a key the TIP let through ---
    void appInsert(char16_t c) {
        size_t lo = anchor < caret ? anchor : caret, hi = anchor < caret ? caret : anchor;
        text.replace(lo, hi - lo, 1, c);
        caret = anchor = lo + 1;
    }
    void appBackspace() {
        if (anchor != caret) {
            size_t lo = anchor < caret ? anchor : caret, hi = anchor < caret ? caret : anchor;
            text.erase(lo, hi - lo);
            caret = anchor = lo;
        } else if (caret > 0) {
            text.erase(caret - 1, 1);
            caret = anchor = caret - 1;
        }
    }
    void setText(const std::u16string& t) {
        text = t;
        caret = anchor = t.size();
        comp = false;
    }
};

}  // namespace vtx::test
