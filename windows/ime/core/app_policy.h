// app_policy.h — per-application typing mode (spec §5.1), equivalent of macOS
// manualAppModes + the shipped typing-modes table.
//
//   InPlace      (default since 1.0.9) no composition; verified edits of the text
//                before the caret. Per field it falls back to composition when that text
//                cannot be read or does not verify.
//   Composition  TSF composition with an invisible display attribute (per-app choice).
//   HookFallback the TIP stays out of the way; VietTelex.exe's low-level keyboard
//                hook types for this app while it is in the foreground.
//   Off          always English (games, remote-desktop clients).
#pragma once
#include <cstdint>
#include <map>
#include <string>

namespace vtx {

enum class AppMode : uint8_t { Composition = 0, InPlace = 1, HookFallback = 2, Off = 3 };

const char* appModeName(AppMode m);
bool parseAppMode(const std::string& s, AppMode& out);

// "C:\\Program Files\\App\\Foo.EXE" -> "foo.exe" (ASCII lowercase; non-ASCII kept).
std::string normalizeExeName(const std::string& pathOrName);

// Built-in default for `exe` (normalized), or false when the table has no entry.
bool builtInAppMode(const std::string& exe, AppMode& out);

// User override first, then built-in table, then InPlace (explicit per-app choices —
// including "composition" picked before 1.0.9 — are kept as they are).
AppMode resolveAppMode(const std::string& exe, const std::map<std::string, AppMode>& overrides);

// Input-scope policy (spec §4.2). Values are InputScope enum numbers from InputScope.h.
enum class FieldPolicy : uint8_t { Normal, Literal };
FieldPolicy classifyInputScopes(const int* scopes, size_t count);

}  // namespace vtx
