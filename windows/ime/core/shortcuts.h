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

}  // namespace vtx
