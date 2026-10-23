#include "viettelex/retro_english.h"

namespace viettelex::retro {

namespace {
bool endsWith(const std::string &s, const std::string &t) {
    return s.size() >= t.size() && s.compare(s.size() - t.size(), t.size(), t) == 0;
}
bool isContinuation(char c) { return (static_cast<unsigned char>(c) & 0xc0) == 0x80; }
}  // namespace

Mode modeFor(bool contextualEnglish, bool fixEarlierWords) {
    if (!contextualEnglish) return Mode::Off;
    return fixEarlierWords ? Mode::Auto : Mode::Offer;
}

namespace {
// How many bytes of `expected` the end of `before` shows (all of it, or all but a tail of at
// most `inflightBytes` the host has not shown yet); 0 = it does not.
size_t shownPrefix(const std::string &before, const std::string &expected, size_t inflightBytes) {
    if (expected.empty()) return 0;
    if (endsWith(before, expected)) return expected.size();
    // The host may not show the word this key event committed yet: drop at most that many
    // bytes from the end of `expected`, on a character boundary, never down to nothing.
    const size_t limit = inflightBytes < expected.size() ? inflightBytes : expected.size() - 1;
    for (size_t drop = 1; drop <= limit; ++drop) {
        const size_t keep = expected.size() - drop;
        if (isContinuation(expected[keep])) continue;
        if (before.size() >= keep && before.compare(before.size() - keep, keep, expected, 0, keep) == 0)
            return keep;
    }
    return 0;
}
bool isSpace(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
constexpr size_t kDisplayMaxBytes = 120;
}  // namespace

Apply decideApply(bool editsAllowed, bool haveText, bool selection, const std::string &before,
                  const std::string &expected, size_t inflightBytes) {
    if (!editsAllowed || !haveText || selection) return Apply::Unverifiable;
    if (expected.empty()) return Apply::Mismatch;
    if (endsWith(before, expected)) return Apply::Apply;
    if (before.empty()) return Apply::Unverifiable;  // the client reports nothing usable
    return shownPrefix(before, expected, inflightBytes) ? Apply::Apply : Apply::Mismatch;
}

std::string offerDisplay(const std::string &before, const std::string &expected, const std::string &insert,
                         size_t inflightBytes) {
    size_t p = 0;
    while (p < expected.size() && p < insert.size() && expected[p] == insert[p]) ++p;
    if (p == expected.size() && p == insert.size()) return std::string();  // nothing differs
    size_t s = 0;
    while (s < expected.size() - p && s < insert.size() - p &&
           expected[expected.size() - 1 - s] == insert[insert.size() - 1 - s])
        ++s;
    size_t start = p, end = insert.size() - s;
    while (start > 0 && !isSpace(insert[start - 1])) --start;  // spaces are ASCII: never mid-character
    while (end < insert.size() && !isSpace(insert[end])) ++end;
    std::string head;
    const size_t shown = start == 0 ? shownPrefix(before, expected, inflightBytes) : 0;
    if (shown) {
        // The engine dropped an unchanged prefix of the first word ("H" of "Hí").
        const size_t stop = before.size() - shown;
        size_t i = stop;
        while (i > 0 && !isSpace(before[i - 1]) && stop - i < 32) --i;
        while (i < stop && isContinuation(before[i])) ++i;
        head = before.substr(i, stop - i);
    }
    std::string d = head + insert.substr(start, end - start);
    if (d.size() > kDisplayMaxBytes) {
        size_t cut = kDisplayMaxBytes;
        while (cut > 0 && isContinuation(d[cut])) --cut;
        d = d.substr(0, cut) + "\u2026";
    }
    return d;
}

Offer makeOffer(const std::string &before, const std::string &expected, const std::string &insert, char boundary,
                int words, size_t inflightBytes) {
    Offer o;
    if (boundary < 0x20 || boundary > 0x7e || insert.empty() || expected.empty() || insert == expected) return o;
    o.display = offerDisplay(before, expected, insert, inflightBytes);
    if (o.display.empty()) return o;
    o.replace = expected + boundary;
    o.insert = insert + boundary;
    o.words = words;
    return o;
}

Undo makeUndo(const std::string &expected, const std::string &insert, char boundary) {
    Undo u;
    if (boundary < 0x20 || boundary > 0x7e || insert.empty()) return u;
    u.applied = insert + boundary;
    u.original = expected + boundary;
    return u;
}

bool undoApplies(const Undo &u, bool editsAllowed, bool haveText, bool selection, const std::string &before) {
    return u.armed() && editsAllowed && haveText && !selection && endsWith(before, u.applied);
}

}  // namespace viettelex::retro
