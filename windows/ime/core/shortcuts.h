// shortcuts.h — bảng gõ tắt: import/export like macOS ShortcutImporter, plus the
// expansion lookup used at word boundaries.
#pragma once
#include <map>
#include <string>

namespace vtx {

using StringMap = std::map<std::string, std::string>;  // UTF-8

// Flat JSON object of strings <-> map. parseFlatJson returns false on malformed input.
bool parseFlatJson(const std::string& text, StringMap& out);
std::string toFlatJson(const StringMap& m);

// Universal importer (JSON object, flat YAML "key: value", plain "key:value" with
// ; # // comments). Same key filter as macOS: non-empty, <= 64 chars, no whitespace.
// Returns false when nothing parseable was found.
bool parseShortcutFile(const std::string& text, StringMap& out);
std::string exportShortcutsYaml(const StringMap& m);

// Boundary lookup (macOS TelexInputController.boundary): composed word first, then
// the raw keystrokes (a key containing Telex triggers never survives composition).
// `charBeforeWord` = the character right before the word (0 if none): a word glued
// to a digit or / # @ is part of a token ("5h", "/h3", "#tag") and never expands.
const std::u16string* findShortcut(const std::map<std::u16string, std::u16string>& table,
                                   const std::u16string& composed, const std::u16string& raw,
                                   char16_t charBeforeWord);

inline bool gluesShortcutToken(char16_t c) {
    return (c >= u'0' && c <= u'9') || c == u'/' || c == u'#' || c == u'@';
}

// ---- Symbol / digit keys ("=>", "<>", "->", ":D", "k2") ----------------------------
// A key that is not made of letters only never comes out of the engine as one word: in
// Telex = < > - : and digits END a word (they are not word keys), so "=>" reaches the
// session as two boundary characters and no word at all. Such keys are matched against the
// whole run of non-whitespace text right before the caret (macOS ShortcutTable
// .tokenExpansion), and only at a whitespace boundary (space, Enter, Tab) — "a->b" or
// "x=>y" never expand. Letter keys keep the word lookup above (findShortcut).

// Letters as far as shortcut keys go: ASCII, Latin-1 / Latin Extended-A/B letters,
// combining marks, the Vietnamese block. Everything else (digits, punctuation, symbols such
// as an arrow) makes a key a token key.
bool isShortcutLetter(char16_t c);
// Non-empty and not letters only.
bool isTokenShortcutKey(const std::u16string& key);
// Whitespace that ends a token run and triggers a token key.
inline bool isShortcutSpace(char32_t c) {
    return c == U' ' || c == U'\t' || c == U'\r' || c == U'\n' || c == 0x00A0 || c == 0x3000;
}
// Expansion of a token key equal to `token` (the run before the caret, word in progress
// included), or nullptr. Letter-only tokens never match here (the word lookup owns them).
const std::u16string* findTokenShortcut(const std::map<std::u16string, std::u16string>& table,
                                        const std::u16string& token);

}  // namespace vtx
