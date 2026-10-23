// retro_english.h — "Tự sửa từ phía trước" (Fix earlier words, EXPERIMENTAL, default OFF):
// the frontend half of the engine's retroactive English correction (docs/DESIGN.md
// "Sửa ngược tiếng Anh"). Pure decisions, unit-tested on any OS; TypingSession applies them.
//
// Windows/Linux behaviour (owner spec 23/10/2026 — no suggestion chip on desktop):
//   * The engine flag is on only when "Quyết định theo ngữ cảnh" (contextualEnglish) AND
//     this switch are on. Off = nothing happens.
//   * On: at a typed word boundary (space / punctuation; Enter / Tab only end the phrase)
//     the correction is applied automatically, only when the text
//     before the caret reads back exactly as the engine's `expected` (never blind, never
//     in a context that cannot be read, never in a terminal / remote viewer / game).
//   * ⌫ as the very next key reverts the rewrite to the exact previous text, again only
//     when the text before the caret still verifiably is what we inserted; otherwise ⌫
//     is an ordinary ⌫.
#pragma once
#include <cstdint>
#include <string>

namespace vtx::retro {

// Settings gate: VTX_RETRO_ENGLISH wanted (Settings::engineFlags()).
bool flagWanted(bool contextualEnglish, bool fixEarlierWords);

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

}  // namespace vtx::retro
