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

//   Direct       (1.1.3) no underline where TSF cannot edit in place (consoles, IMM/CUAS
//                apps, xterm.js): like UniKey/OpenKey, VietTelex.exe's low-level hook
//                eats the key and sends N backspaces + Unicode text in one SendInput
//                batch; the engine tracks the word itself. Needs VietTelex.exe running —
//                otherwise the TIP composes.
enum class AppMode : uint8_t { Composition = 0, InPlace = 1, HookFallback = 2, Off = 3, Direct = 4 };
// Keys typed by the hook itself carry this in dwExtraInfo; nobody (hook, TIP) may
// process them again.
constexpr uintptr_t kInjectedMagic = 0x56545831;  // "VTX1"
inline bool isOwnInjected(uintptr_t extraInfo) { return extraInfo == kInjectedMagic; }
// The hook (not the TIP) types for this mode.
inline bool hookTypes(AppMode m) { return m == AppMode::HookFallback || m == AppMode::Direct; }

const char* appModeName(AppMode m);
bool parseAppMode(const std::string& s, AppMode& out);

// "C:\\Program Files\\App\\Foo.EXE" -> "foo.exe" (ASCII lowercase; non-ASCII kept).
std::string normalizeExeName(const std::string& pathOrName);

// Which app a TSF context belongs to. Inside msedgewebview2.exe (new Teams, new Outlook,
// many WebView2 apps) the process says nothing: use the exe owning the root window.
// Both arguments normalized; `rootOwnerExe` may be empty (unknown).
std::string appIdentity(const std::string& processExe, const std::string& rootOwnerExe);

// Built-in default for `exe` (normalized), or false when the table has no entry.
bool builtInAppMode(const std::string& exe, AppMode& out);

// User override first, then built-in table, then InPlace (explicit per-app choices —
// including "composition" picked before 1.0.9 — are kept as they are).
AppMode resolveAppMode(const std::string& exe, const std::map<std::string, AppMode>& overrides);

// What a text CONTEXT allows, decided per focused field at each word start.
//   TF_SS_TRANSITORY alone means NOTHING about readability: Chromium's TSF store
//   (Chrome, Edge, Brave, Electron, WebView2) always reports TRANSITORY|NOHIDDENTEXT and
//   is fully readable (1.1.1 regression). Mozc's rule (tip_transitory_extension.cc):
//     not transitory                      -> full context
//     transitory + TRANSITORYEXTENSION    -> use the PARENT context if it is not transitory
//       parent (classic Edit / RichEdit)     (full), else none
//     transitory + CUAS-emulated          -> legacy IMM32 app: no surrounding text
//       (compartment {A94C5FD2-...} & 1)
//     transitory, otherwise               -> TSF app that says transitory: full (Chromium)
struct ContextInfo {
    bool hasContext = true;       // a focused document/context exists
    bool keyboardDisabled = false;// GUID_COMPARTMENT_KEYBOARD_DISABLED / EMPTYCONTEXT set
    bool readOnly = false;        // TF_SD_READONLY
    bool console = false;         // TIP activated with TF_TMAE_CONSOLE
    bool transitory = false;      // TF_SS_TRANSITORY on this context
    bool cuasEmulated = false;    // IMM32 app through CUAS (focused field not Edit/RichEdit)
    bool hasParent = false;       // GUID_COMPARTMENT_TRANSITORYEXTENSION_PARENT document
    bool parentTransitory = true; // that parent's context status
    bool unicodeWindow = true;    // IsWindowUnicode(focus); ANSI windows mangle Unicode
};

enum class HostText : uint8_t {
    Normal,           // app policy decides (in-place by default, verified)
    NormalViaParent,  // read / edit through the transitory-extension parent context
    CompositionOnly,  // no usable surrounding text: compose, never read back
    Literal,          // keys pass through untouched (read-only, disabled, ANSI window)
    Ignore,           // no context at all: do not eat keys
};
HostText classifyContext(const ContextInfo& c);

// Input-scope policy (spec §4.2). Values are InputScope enum numbers from InputScope.h.
enum class FieldPolicy : uint8_t { Normal, Literal };
FieldPolicy classifyInputScopes(const int* scopes, size_t count);

}  // namespace vtx
