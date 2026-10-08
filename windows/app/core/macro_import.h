// macro_import.h — "Chuyển từ UniKey": read another IME's gõ tắt (macro) file into
// VietTelex's shortcut table. Portable; unit-tested with fixtures in app/tests/fixtures.
//
// Formats, verified against the public source code:
//   UniKey  (ukengine/mactab.cpp, CMacroTable::writeToFile / loadFromFile — the engine the
//           Windows UniKey 4.x and x-unikey/ibus-unikey share). Header line
//             <UTF-8 BOM>;DO NOT DELETE THIS LINE*** version=1 ***      (Windows build)
//             DO NOT DELETE THIS LINE*** version=1 ***                  (other builds)
//           read as: after an optional BOM, "***", optional spaces, "version=<n>". Then one
//           macro per line, "key:text" split at the FIRST colon, nothing trimmed (only the
//           line's \n / \r\n). version 1 = UTF-8. A file without that header is version 0,
//           whose lines UniKey decodes as VIQR ("Vie^.t") — not converted here: such
//           lines are imported as they are and the result says so (`viqr`).
//   OpenKey (Sources/OpenKey/engine/Macro.cpp saveToFile / readFromFile). Header
//             ;Compatible OpenKey Macro Data file for UniKey*** version=1 ***
//           (UTF-8, no BOM); OpenKey ALWAYS skips the first line; then "key:text" at the
//           first colon, except that a key starting with ':' takes the next field too
//           (":D:smile" -> key ":D", text "smile").
//   EVKey   closed source: its export format could not be verified from public samples.
//           EVKey files are read by the generic path below (it accepts the UniKey layout).
//   Generic everything else: VietTelex/macOS JSON, flat YAML, "key: value" and
//           "key<TAB>value" text (parseShortcutFile + tab-separated lines).
// Encodings: UTF-8 (with or without BOM), UTF-16LE (with BOM, or without: detected by the
// NUL high bytes of ASCII text, as Notepad's "Unicode" files), UTF-16BE with BOM.
// Keys VietTelex cannot use (empty, whitespace inside, > 64 chars) are skipped and counted.
#pragma once
#include <cstddef>
#include <string>

#include "shortcuts.h"

namespace vtx {

enum class TextEncoding { Utf8, Utf8Bom, Utf16Le, Utf16Be, Unknown };
// Bytes of a file -> UTF-8 (no BOM). False when it is not text in any supported encoding.
bool decodeTextFile(const std::string& bytes, std::string& utf8, TextEncoding* enc = nullptr);

enum class MacroFormat { None, UniKey, OpenKey, Generic };
struct MacroImport {
    MacroFormat format = MacroFormat::None;
    TextEncoding encoding = TextEncoding::Unknown;
    StringMap entries;     // UTF-8 key -> text
    size_t skipped = 0;    // lines with a key VietTelex cannot use
    bool viqr = false;     // UniKey file without the UTF-8 header (old VIQR encoding)
};
// False when nothing usable was found.
bool parseMacroFile(const std::string& bytes, MacroImport& out);

}  // namespace vtx
