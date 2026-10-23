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

bool flagWanted(bool contextualEnglish, bool fixEarlierWords) { return contextualEnglish && fixEarlierWords; }

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

}  // namespace vtx::retro
