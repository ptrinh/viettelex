// retro_english.h — "Tự sửa từ phía trước" (Fix earlier words, EXPERIMENTAL, default OFF):
// the frontend half of the engine's retroactive English correction (docs/DESIGN.md
// "Sửa ngược tiếng Anh"; VT_FLAG_RETRO_ENGLISH, vt_note_boundary, vt_take_retro).
// Pure decisions, unit-tested; Session applies them.
//
// Desktop behaviour (owner spec 23/10/2026 — no suggestion chip on Windows / Linux):
//   * The engine flag is on only when [typing] contextual_english AND retroactive_english
//     are on. Off = nothing happens.
//   * On: at a word boundary the correction is applied (delete-surrounding + commit) only
//     where the Session may reach back into committed text (AppPolicy surrounding edits:
//     never terminals / Direct / passthrough / a distrusted field) and the client's
//     surrounding text proves the words being rewritten are on screen exactly.
//   * ⌫ as the very next key reverts it to the exact previous text, again only when the
//     surrounding text still ends with what was inserted; otherwise ⌫ is an ordinary ⌫.
#pragma once

#include <cstddef>
#include <string>

namespace viettelex::retro {

// Settings gate: VT_FLAG_RETRO_ENGLISH wanted.
bool flagWanted(bool contextualEnglish, bool fixEarlierWords);

enum class Apply {
    Apply,         // the text before the caret verifies: delete `expected`, commit `insert`
    Unverifiable,  // no surrounding text / edits not allowed here / selection: skip
    Mismatch,      // the surrounding text is not `expected`: skip
};

// `before` = the client's text before the caret (UTF-8, at least `expected`'s characters
// when available). IBus / Fcitx5 surrounding text follows our commits asynchronously: the
// word committed by THIS key event (`inflightBytes` = its UTF-8 size, 0 = none) may not be
// shown yet. Accepted then: `before` ends with `expected` minus a tail of at most
// `inflightBytes` (the IM channel is ordered, so the delete lands after that commit) — the
// rewritten words and the boundaries between them must all be there.
Apply decideApply(bool editsAllowed, bool haveText, bool selection, const std::string &before,
                  const std::string &expected, size_t inflightBytes);

// The rewrite just applied, armed for one key. Both strings include the boundary
// character the app inserted after it, so the revert keeps it.
struct Undo {
    std::string applied;   // on screen now, ending at the caret
    std::string original;  // what was there before the rewrite
    bool armed() const { return !applied.empty(); }
    void clear() { applied.clear(); original.clear(); }
};
// `boundary` = the printable ASCII key that ended the word; 0 (Enter / Tab / non-ASCII) = no undo.
Undo makeUndo(const std::string &expected, const std::string &insert, char boundary);
// ⌫ right after the rewrite reverts only when the surrounding text ends with `applied`.
bool undoApplies(const Undo &u, bool editsAllowed, bool haveText, bool selection, const std::string &before);

}  // namespace viettelex::retro
