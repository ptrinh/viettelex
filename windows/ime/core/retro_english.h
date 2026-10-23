// retro_english.h — "Tự sửa từ phía trước" (Fix earlier words, EXPERIMENTAL, default OFF):
// the frontend half of the engine's retroactive English correction (docs/DESIGN.md
// "Sửa ngược tiếng Anh"). Pure decisions, unit-tested on any OS; TypingSession applies them.
//
// Windows/Linux behaviour (owner spec 23/10/2026):
//   * "Quyết định theo ngữ cảnh" (contextualEnglish) off = nothing (engine flag off).
//   * contextualEnglish on = the engine flag is on; the switch picks what a correction does:
//       - switch ON  (Mode::Auto): at a typed word boundary (space / punctuation; Enter / Tab
//         only end the phrase) the correction is applied, only when the text before the caret
//         reads back exactly as the engine's `expected` (never blind, never in a context that
//         cannot be read, never in a terminal / remote viewer / game). ⌫ as the very next key
//         reverts it to the exact previous text (again only when it verifies).
//       - switch OFF (Mode::Offer): the same verified correction is OFFERED as a caret hint
//         ("His car is", caret_hints.h Kind::Retro); Tab applies it (text re-read first), any
//         other key dismisses it. It wins over every other caret hint of that key.
#pragma once
#include <cstdint>
#include <string>

namespace vtx::retro {

// Settings gate. The engine flag (VTX_RETRO_ENGLISH, Settings::engineFlags()) is on for
// Offer and Auto.
enum class Mode : uint8_t { Off, Offer, Auto };
Mode modeFor(bool contextualEnglish, bool fixEarlierWords);
inline bool flagWanted(bool contextualEnglish, bool fixEarlierWords) {
    return modeFor(contextualEnglish, fixEarlierWords) != Mode::Off;
}

// Per-app gate: never where the built-in table types through the hook or not at all
// (terminals, remote desktop / VM viewers, games). `exe` normalized ("notepad.exe").
bool allowedForApp(const std::string& exe);

// What the session knows about the field when a correction arrives.
struct Field {
    bool blind = false;             // hook sink: nothing can be read back
    bool compositionOnly = false;   // console / transitory document: never reach back
    bool canRead = true;            // TextSink::canReadContext()
    bool hasSelection = false;
    bool compositionActive = false; // a composition is still open (should not be)
};

enum class Apply : uint8_t {
    Apply,          // `before` ends with `expected`: delete it, insert `insert`
    Unverifiable,   // the field cannot be read / is not ours to touch: skip
    Mismatch,       // the text before the caret is not `expected`: skip
};

// `before` = text immediately before the caret (at least expected.size() units when
// available). `backspaces` must equal expected.size() (the engine's contract).
Apply decideApply(const Field& f, const std::u16string& before, const std::u16string& expected,
                  int backspaces);

// The rewrite just applied, armed for one key: ⌫ next restores `original`.
// Both strings include the boundary character that ended the word (it reaches the
// document after the rewrite), so the revert keeps it: "His car is very fast " -> ⌫ ->
// "Hí cả í very fast ".
struct Undo {
    std::u16string applied;   // what is on screen now, ending at the caret
    std::u16string original;  // what was there before the rewrite
    bool armed() const { return !applied.empty(); }
    void clear() { applied.clear(); original.clear(); }
};

// Arm after a rewrite + its boundary char. `boundary` 0 = none (Enter / Tab / Esc: the key
// may leave the field or send the message — no undo then).
Undo makeUndo(const std::u16string& expected, const std::u16string& insert, char16_t boundary);

// ⌫ right after the rewrite: revert only when the text before the caret still ends with
// what we put there and nothing else is going on in the field.
bool undoApplies(const Undo& u, const Field& f, const std::u16string& before);

// Offer mode: the verified correction as a caret hint. `replace` / `insert` include the
// boundary character (the app inserts it after the key that produced the correction, before
// the hint can be accepted). `display` = the rewritten words, whole ("His car is"): the part
// of `insert` that differs from `expected`, widened to word edges, with the start of the
// first word taken from `before` when the engine dropped an unchanged prefix ("H" of "Hí").
struct Offer {
    std::u16string display, replace, insert;
    int words = 0;
    bool empty() const { return replace.empty(); }
    void clear() { display.clear(); replace.clear(); insert.clear(); words = 0; }
};
// `before` = text before the caret (must end with `expected`; the boundary is not typed
// yet). Empty Offer when `boundary` is 0 (Enter / Tab: never), nothing differs, or `before`
// does not end with `expected`.
Offer makeOffer(const std::u16string& before, const std::u16string& expected, const std::u16string& insert,
                char16_t boundary, int words);
std::u16string offerDisplay(const std::u16string& before, const std::u16string& expected,
                            const std::u16string& insert);

}  // namespace vtx::retro
