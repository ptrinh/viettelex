#include "word_adopt.h"

#include "session.h"
#include "typed_word.h"

namespace vtx::app {

namespace {

// The session types into a text model only: nothing is sent while a word is adopted.
class ModelSink final : public TextSink {
public:
    std::u16string text;
    bool blind() override { return true; }
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) override {
        if (expect.size() > text.size() || text.compare(text.size() - expect.size(), expect.size(), expect) != 0)
            return false;
        text.erase(text.size() - expect.size());
        text += insert;
        return true;
    }
    bool compositionActive() override { return false; }
    bool setComposition(const std::u16string&, int, bool) override { return false; }
    void endComposition(const std::u16string&) override {}
    void endCompositionAsIs() override {}
};

}  // namespace

bool WordAdoption::adopt(TypingSession& s) {
    s.reset();
    owed_ = false;
    believed_.clear();
    if (raw_.empty()) return true;
    ModelSink m;
    for (char16_t c : raw_) {
        KeyInput k;
        k.kind = KeyKind::Char;
        k.ch = c;
        if (!s.wantsKey(k)) {
            s.noteKeyPassedBy(k);
            m.text.push_back(c);  // the app types it
        } else if (!s.handleKey(k, m)) {
            m.text.push_back(c);  // passed through (plain append) or replayed after the edit
        }
    }
    // The whole record must be ONE word in progress the session now shows (a Telex digit ends
    // the word, an overflow types the rest raw): else nothing is adopted.
    if (!s.wordActive() || m.text != s.shown()) {
        s.reset();
        raw_.clear();
        return false;
    }
    believed_ = m.text;
    owed_ = believed_ != raw_;
    return true;
}

WordAdoption::Start WordAdoption::begin(uint32_t typedWord, const KeyInput& k, TypingSession& s) {
    pending_ = false;
    const DecodedTypedWord d = decodeTypedWord(typedWord);
    if (d.unknown) return Start::Unknown;
    // A key that does not type (arrows, chords, Enter / Tab / Esc): the word ends as it is.
    if (d.raw.empty() || (k.kind != KeyKind::Char && k.kind != KeyKind::Backspace)) return Start::Nothing;
    raw_ = d.raw;
    if (!adopt(s)) return Start::Unknown;
    return Start::Adopted;
}

void WordAdoption::backspace(TypingSession& s) {
    if (!owed_) return;
    if (!raw_.empty()) raw_.pop_back();
    if (!adopt(s)) drop();
}

WordAdoption::Fix WordAdoption::takeFix() {
    Fix f;
    if (!owed_) return f;
    size_t p = 0;
    while (p < raw_.size() && p < believed_.size() && raw_[p] == believed_[p]) ++p;
    f.expect = raw_.substr(p);
    f.insert = believed_.substr(p);
    owed_ = false;
    raw_.clear();
    believed_.clear();
    return f;
}

}  // namespace vtx::app
