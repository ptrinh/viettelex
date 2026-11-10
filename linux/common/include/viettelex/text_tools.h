// text_tools.h — "Công cụ văn bản" for the selection (Thêm dấu, HOA, thường, Hoa Đầu Từ,
// Hoa đầu câu, Xoá dấu), shared by the Fcitx5 addon and the IBus engine. Same feature as
// macOS App/Sources/TextActions.swift.
//
// The transforms are NOT reimplemented here: they run in the child process
// viettelex-text-tool (linux/engine-capi, the shared iOS/Keyboard Swift sources), so the
// add-tones lexicon/LM never lives in the IM process. This file only:
//   • names/labels the tools (vi / en, following Settings::uiLanguage),
//   • finds the selection (surrounding text → PRIMARY selection through wl-paste / xclip /
//     xsel when one is installed — never a hard dependency),
//   • runs the helper off the main thread (TextToolRunner) with a timeout.
// Replacing is the frontend's job: commit the result while the selection is still there
// (typing over a selection replaces it in GTK, Qt, Chromium, LibreOffice…). The clipboard is
// never written, so there is nothing to restore.
#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <string>

namespace viettelex {

enum class TextTool { AddTones, Upper, Lower, Title, Sentence, StripDiacritics };
constexpr int kTextToolCount = 6;
TextTool textToolAt(int i);  // menu order (AddTones first)

// CLI argument of viettelex-text-tool, also the suffix of action / property names.
const char *textToolId(TextTool t);
bool textToolFromId(const std::string &id, TextTool &out);
std::string textToolLabel(TextTool t, bool english);

// IM menu / tooltip strings. Vietnamese source text is the key (like iOS L10n); unknown
// strings come back unchanged.
std::string uiText(const std::string &vi, bool english);
// Settings::toggleHotkey for display, as the settings app shows it (hotkey_label):
// "Ctrl+space" → "Ctrl+Space"; "" for none / an invalid one.
std::string hotkeyLabel(const std::string &value);
// Tooltip of the Vi/En toggle: "Chuyển Việt/Anh (Ctrl+Space)" with the configured hotkey,
// without the parenthesis when there is none.
std::string toggleTooltip(const std::string &toggleHotkey, bool english);
inline bool isEnglishUi(const std::string &uiLanguage) { return uiLanguage == "en"; }

// Longest selection handled (UTF-16 units on macOS; here Unicode scalars — the helper
// re-checks the exact macOS rule).
constexpr size_t kTextToolMaxChars = 20000;

// $VIETTELEX_TEXT_TOOL, else the installed helper (VT_TEXT_TOOL_PATH at build time).
std::string textToolHelperPath();
bool textToolAvailable();

// Runs the helper synchronously — NEVER on the IM main thread. True (and `out`) only when
// the tool changed the text; false for "unchanged", timeout or a missing helper.
bool runTextTool(TextTool t, const std::string &in, std::string &out, int timeoutMs = 5000);

// Selected text inside a surrounding-text snapshot (`cursor` / `anchor` in characters).
// False when there is no selection or the offsets are out of range.
bool selectionFromSurrounding(const std::string &text, unsigned cursor, unsigned anchor, std::string &out);

// GTK3 clients (Firefox, Chromium, GTK3 apps — gtk_im_context_set_surrounding has no anchor)
// report surrounding text with anchor == cursor even while text is selected. The PRIMARY
// selection is then taken as the selection only when it sits right against the caret (a
// selection always ends at the caret): text before the caret ends with it, or text after
// the caret starts with it. A stale PRIMARY from elsewhere is ignored.
bool primaryAdjacentToCursor(const std::string &text, unsigned cursor, const std::string &primary);

// Is text selected at the caret? The decision behind InputContext::selectionAtCaret (asked
// before re-edit / ⌫ reopen / shortcut or auto-restore deletes): anchor != cursor, else —
// GTK3 reports no anchor — a PRIMARY selection against the caret. `readPrimary` is called
// only in that second case (it may block briefly); false from it = no PRIMARY.
bool selectionAtCaret(const std::string &text, unsigned cursor, unsigned anchor,
                      const std::function<bool(std::string &)> &readPrimary);

// Key-path form used by the frontends — the external PRIMARY read spawns a process (150 ms
// budget per tool) on the IM thread, so the cheapest answer wins:
// - anchor != cursor ⇒ true, and `anchorSeen` is set: this host reports real anchors (GTK4,
//   Qt, text-input-v3), so from then on (until the frontend clears it at focus-in)
//   anchor == cursor really means "no selection" ⇒ false without any probe;
// - `cachedPrimary` (Fcitx5 clipboard addon, in process; null = no cache): not against the
//   caret ⇒ false without spawning; against it ⇒ confirmed by `readLive` when `liveTool`
//   (the cache keeps the text after the app drops the selection);
// - no cache ⇒ `readLive`.
bool selectionAtCaretProbe(const std::string &text, unsigned cursor, unsigned anchor, bool &anchorSeen,
                           const std::string *cachedPrimary, bool liveTool,
                           const std::function<bool(std::string &)> &readLive);

// PRIMARY selection (the highlighted text) through wl-paste --primary (Wayland) or
// xclip / xsel (X11) — only when such a tool is on PATH. Blocking: worker thread only.
bool readPrimarySelection(std::string &out, int timeoutMs = 700);
// A tool readPrimarySelection can use is installed for this session (an empty read then
// really means "nothing selected").
bool primarySelectionToolAvailable();

// Runs one job at a time on a worker thread and hands the result back on the IM's main
// thread through `post` (Fcitx5 EventDispatcher / g_main_context_invoke).
class TextToolRunner {
public:
    using Post = std::function<void(std::function<void()>)>;
    // source: produces the input on the worker thread (e.g. readPrimarySelection); false = none.
    using Source = std::function<bool(std::string &)>;
    // done(changed, input, result) on the main thread.
    using Done = std::function<void(bool changed, const std::string &input, const std::string &result)>;

    explicit TextToolRunner(Post post);
    ~TextToolRunner();
    TextToolRunner(const TextToolRunner &) = delete;
    TextToolRunner &operator=(const TextToolRunner &) = delete;

    // Main thread. False when a job is already running (hotkey held down).
    bool start(TextTool tool, Source source, Done done);
    bool busy() const { return busy_->load(); }

private:
    Post post_;
    std::shared_ptr<std::atomic<bool>> busy_;
    std::shared_ptr<std::atomic<bool>> alive_;
};

}  // namespace viettelex
