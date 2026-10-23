#include "retro_english.h"

#include "app_policy.h"

namespace vtx::retro {

namespace {
bool endsWith(const std::u16string& s, const std::u16string& t) {
    return s.size() >= t.size() && s.compare(s.size() - t.size(), t.size(), t) == 0;
}
bool readable(const Field& f) {
    return !f.blind && !f.compositionOnly && f.canRead && !f.hasSelection && !f.compositionActive;
}
}  // namespace

Mode modeFor(bool contextualEnglish, bool fixEarlierWords) {
    if (!contextualEnglish) return Mode::Off;
    return fixEarlierWords ? Mode::Auto : Mode::Offer;
}

bool allowedForApp(const std::string& exe) {
    AppMode m;
    if (builtInAppMode(exe, m) && m != AppMode::InPlace && m != AppMode::Composition) return false;
    return true;
}

Apply decideApply(const Field& f, const std::u16string& before, const std::u16string& expected, int backspaces) {
    if (!readable(f)) return Apply::Unverifiable;
    if (expected.empty() || backspaces != static_cast<int>(expected.size())) return Apply::Mismatch;
    return endsWith(before, expected) ? Apply::Apply : Apply::Mismatch;
}

Undo makeUndo(const std::u16string& expected, const std::u16string& insert, char16_t boundary) {
    Undo u;
    if (boundary == 0 || insert.empty()) return u;
    u.applied = insert + boundary;
    u.original = expected + boundary;
    return u;
}

bool undoApplies(const Undo& u, const Field& f, const std::u16string& before) {
    return u.armed() && readable(f) && endsWith(before, u.applied);
}

namespace {
bool isSpace(char16_t c) { return c == u' ' || c == u'\t' || c == u'\n' || c == u'\r' || c == 0xA0; }
constexpr size_t kDisplayMax = 64;
}  // namespace

std::u16string offerDisplay(const std::u16string& before, const std::u16string& expected,
                            const std::u16string& insert) {
    size_t p = 0;
    while (p < expected.size() && p < insert.size() && expected[p] == insert[p]) ++p;
    if (p == expected.size() && p == insert.size()) return {};  // nothing differs
    size_t s = 0;
    while (s < expected.size() - p && s < insert.size() - p &&
           expected[expected.size() - 1 - s] == insert[insert.size() - 1 - s])
        ++s;
    size_t start = p, end = insert.size() - s;
    while (start > 0 && !isSpace(insert[start - 1])) --start;
    while (end < insert.size() && !isSpace(insert[end])) ++end;
    std::u16string head;
    if (start == 0 && endsWith(before, expected)) {
        // The engine dropped an unchanged prefix of the first word ("H" of "Hí").
        const size_t stop = before.size() - expected.size();
        size_t i = stop;
        while (i > 0 && !isSpace(before[i - 1]) && stop - i < kDisplayMax) --i;
        head = before.substr(i, stop - i);
    }
    std::u16string d = head + insert.substr(start, end - start);
    if (d.size() > kDisplayMax) d = d.substr(0, kDisplayMax - 1) + u'\u2026';
    return d;
}

Offer makeOffer(const std::u16string& before, const std::u16string& expected, const std::u16string& insert,
                char16_t boundary, int words) {
    Offer o;
    if (boundary == 0 || insert.empty() || expected.empty() || insert == expected || !endsWith(before, expected))
        return o;
    o.display = offerDisplay(before, expected, insert);
    if (o.display.empty()) return o;
    o.replace = expected + boundary;
    o.insert = insert + boundary;
    o.words = words;
    return o;
}

}  // namespace vtx::retro
