// fake_document.h — a text field + "app" that behaves like a TSF document for the
// TypingSession: composition range, caret, selection, and the app's default handling
// of keys the TIP did not eat.
#pragma once
#include <set>
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

    // Insertion point = selection START (a selection after it, e.g. an omnibox
    // autocomplete suffix, belongs to the app).
    size_t lo() const { return anchor < caret ? anchor : caret; }
    size_t hi() const { return anchor < caret ? caret : anchor; }
    bool unreadable = false;     // simulate a control whose text cannot be read
    bool refuseReplace = false;  // in-place edits refused (verification-style failure)
    bool canReadContext() override { return !unreadable; }
    std::set<int> undoReplaces;  // these replaces (1-based, in order) are undone by the app
    int replaces = 0;            // replaceBeforeCaret calls that verified
    bool undidReplace = false;   // a replace was undone since the last appRewrite

    // How a TSF text service SEES the app putting its own text back after an undone replace
    // (1.3.19: Word's Navigation search box through the TIP — the TSF store reports the
    // app's "set text" as several edits, one OnEndEdit each). The final text is the same in
    // every style (the atomic model above, which is also all the hook ever sees).
    enum class Rewrite {
        Atomic,                // one edit: the word as before the replace
        ClearThenSet,          // the field emptied, then its text set
        SelectAllThenCollapse, // the text set with all of it selected, then the caret to the end
        Piecewise,             // the last word's last two units (never its first) deleted, then put back
    };
    Rewrite rewrite = Rewrite::Atomic;
    // Plays the app's rewrite after the key (if a replace was undone), calling `endEdit`
    // (the TIP's OnEndEdit) at every intermediate state and at the final one.
    template <class F>
    void appRewrite(F endEdit) {
        if (!undidReplace) return;
        undidReplace = false;
        const std::u16string t = text;
        const size_t end = t.size();
        switch (rewrite) {
            case Rewrite::Atomic: break;
            case Rewrite::ClearThenSet:
                text.clear();
                caret = anchor = 0;
                endEdit();
                break;
            case Rewrite::SelectAllThenCollapse:
                caret = 0;
                anchor = end;
                endEdit();
                break;
            case Rewrite::Piecewise: {
                size_t from = end >= 2 ? end - 2 : 0;
                // Within the last word, its first unit kept: a state with the word wholly gone
                // and other text before it is indistinguishable from a click (word dropped).
                const size_t sp = t.find_last_of(u" \n");
                const size_t first = sp == std::u16string::npos ? 1 : sp + 2;
                if (first > from) from = first;
                for (size_t cut = from; cut < end; ++cut) {
                    text = t.substr(0, cut);
                    caret = anchor = cut;
                    endEdit();
                }
                break;
            }
        }
        text = t;
        caret = anchor = end;
        endEdit();
    }

    int blankReads = 0;          // the next N reads see nothing (a store one update behind)
    std::u16string textBeforeCaret(int max) override {
        if (unreadable) return {};
        if (blankReads > 0) {
            --blankReads;
            return {};
        }
        size_t end = comp ? compStart : lo();
        size_t n = static_cast<size_t>(max) < end ? static_cast<size_t>(max) : end;
        return text.substr(end - n, n);
    }
    char16_t charAfterCaret() override {
        size_t at = comp ? compEnd : hi();
        return at < text.size() ? text[at] : 0;
    }
    bool hasSelection() override { return anchor != caret; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& ins) override {
        const size_t at = lo(), selLen = hi() - lo();
        if (refuseEdits || refuseReplace || unreadable || comp || expect.size() > at) return false;
        if (text.compare(at - expect.size(), expect.size(), expect) != 0) return false;
        // A field that takes the edit and then puts its own text back (Word's Navigation
        // search box, 2026-11): the edit "succeeds", the text is as before.
        if (undoReplaces.count(++replaces)) {
            undidReplace = true;  // appRewrite: how TSF shows the app putting its text back
            return true;
        }
        text.replace(at - expect.size(), expect.size(), ins);
        caret = at - expect.size() + ins.size();
        anchor = caret + selLen;  // the app's selected suffix stays selected, untouched
        ++edits;
        return true;
    }
    bool compositionActive() override { return comp; }
    bool compositionText(std::u16string& out) override {
        if (!comp) return false;
        out = text.substr(compStart, compEnd - compStart);
        return true;
    }
    bool misspelled = false;     // attribute of the last setComposition (red squiggle)
    int misspelledSets = 0;      // setComposition calls that asked for the red squiggle
    bool setComposition(const std::u16string& t, int absorb, bool bad) override {
        if (refuseEdits) return false;
        misspelled = bad;
        if (bad) ++misspelledSets;
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
        misspelled = false;  // committed text carries no attribute
        ++edits;
    }

    void endCompositionAsIs() override {
        if (!comp) return;
        caret = anchor = compEnd;
        comp = false;
        misspelled = false;  // committed text carries no attribute
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
