#include "viettelex/retro_english.h"

namespace viettelex::retro {

namespace {
bool endsWith(const std::string &s, const std::string &t) {
    return s.size() >= t.size() && s.compare(s.size() - t.size(), t.size(), t) == 0;
}
bool isContinuation(char c) { return (static_cast<unsigned char>(c) & 0xc0) == 0x80; }
}  // namespace

bool flagWanted(bool contextualEnglish, bool fixEarlierWords) { return contextualEnglish && fixEarlierWords; }

Apply decideApply(bool editsAllowed, bool haveText, bool selection, const std::string &before,
                  const std::string &expected, size_t inflightBytes) {
    if (!editsAllowed || !haveText || selection) return Apply::Unverifiable;
    if (expected.empty()) return Apply::Mismatch;
    if (endsWith(before, expected)) return Apply::Apply;
    if (before.empty()) return Apply::Unverifiable;  // the client reports nothing usable
    // The host may not show the word this key event committed yet: drop at most that many
    // bytes from the end of `expected`, on a character boundary, never down to nothing.
    const size_t limit = inflightBytes < expected.size() ? inflightBytes : expected.size() - 1;
    for (size_t drop = 1; drop <= limit; ++drop) {
        const size_t keep = expected.size() - drop;
        if (isContinuation(expected[keep])) continue;
        if (before.size() >= keep && before.compare(before.size() - keep, keep, expected, 0, keep) == 0)
            return Apply::Apply;
    }
    return Apply::Mismatch;
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
