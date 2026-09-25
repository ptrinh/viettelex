// app_policy.h — per-application typing mode (spec §5.1), equivalent of macOS
// manualAppModes + the shipped typing-modes table.
//
//   Composition  (default) TSF composition with an invisible display attribute.
//   InPlace      no composition; edit the text before the caret directly.
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

// User override first, then built-in table, then Composition.
AppMode resolveAppMode(const std::string& exe, const std::map<std::string, AppMode>& overrides);

// Input-scope policy (spec §4.2). Values are InputScope enum numbers from InputScope.h.
enum class FieldPolicy : uint8_t { Normal, Literal };
FieldPolicy classifyInputScopes(const int* scopes, size_t count);

}  // namespace vtx
