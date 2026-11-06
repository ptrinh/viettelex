// settings_pages.h — what each page of the Settings window shows, and in which order
// (docs/SETTINGS-CLEANUP-SPEC.md §1, §3, §4). Portable and unit-tested; the Win32 side
// (app/src/settings_window.cpp) turns every row into a card, a section header or an
// expander. Only WHERE a setting is shown lives here: registry keys, defaults and what a
// switch does are unchanged (settings.h).
//
//   Gõ phím          Kiểu gõ + › Nâng cao · Gõ lẫn tiếng Anh (hồ sơ + › Nâng cao) ·
//                    Chuyển Việt/Anh (phím chuyển + › Nâng cao) · Chính tả
//   Gợi ý & công cụ  Gợi ý cạnh con trỏ (+ dòng link tới cài đặt gợi ý của Windows) ·
//                    › Công cụ văn bản
//   Gõ tắt           bảng gõ tắt
//   Ứng dụng         bảng chế độ theo ứng dụng · › Chơi game / toàn màn hình
//   Chung            giới thiệu · ngôn ngữ · › Giao diện · cập nhật · gỡ lỗi · gỡ cài đặt
//
// "›" = an expander (collapsed by default, one level: an expander never holds another).
// VNI hides the whole "Gõ lẫn tiếng Anh" group (profile rows + its › Nâng cao): VNI puts
// tones on digit keys so English words come out as typed and none of those switches does
// anything. One line (MixedVniNote) stands in for it; the keys keep their values (§1).
// A row that depends on a switch right above it in the same group is HIDDEN while that
// parent makes it do nothing, and comes back in place as soon as the parent changes (§0.4,
// table §6). The one cross-page case — "Hiện công cụ văn bản trong menu" (tray menu) under
// the tray switch on Chung — is hidden too; the Công cụ văn bản expander's summary then
// says to turn the tray icon on in Chung (S::TextToolsNoTray). Display only: no key changes.
#pragma once
#include <vector>

#include "settings.h"

namespace vtx::app {

enum class SettingsPage : int { Typing = 0, Suggestions, Shortcuts, Apps, General, Count };

enum class Expander : int {
    TypingAdvanced,  // Kiểu gõ → Nâng cao
    MixedAdvanced,   // Gõ lẫn tiếng Anh → Nâng cao
    SwitchAdvanced,  // Chuyển Việt/Anh → Nâng cao
    TextTools,       // Công cụ văn bản
    Games,           // Chơi game / toàn màn hình
    Appearance,      // Giao diện
    Count
};

enum class PageSection : int { InputStyle, Mixed, Switch, Spelling, Hints, Updates, Diagnostics, Uninstall };

// Everything that is not a plain switch.
enum class PageControl : int {
    ConflictCard,        // another Vietnamese input method is running (only when detected)
    MixedCard,           // one-time card for upgraded users (only while pending)
    InputMethod,         // Telex / VNI
    ProfileRows,         // the 3 profile rows (+ "Tuỳ chỉnh" while custom)
    SwitchHotkey,        // the main control of "Chuyển Việt/Anh"
    PerAppWin,           // Windows' "input method per app window"
    DefaultInput,        // make VietTelex Windows' default input method (only when advised)
    SwitchIndicator,     // V/E indicator when switching
    TextPredictionLink,  // word prediction is a Windows setting: one link row, no switch
    ClearLearned,
    AddTonesHotkey,
    ShortcutTable,
    AppTable,
    GameHotkey,
    About,
    UiLanguage,
    IconPicker,
    TrayStyle,
    CheckNow,
    Uninstall,
    Links,
    MixedVniNote,        // VNI: the one line shown instead of the "Gõ lẫn tiếng Anh" group
};

enum class RowKind { Section, Expander, Toggle, Control };

struct PageRow {
    RowKind kind = RowKind::Toggle;
    int id = 0;                          // PageSection / Expander / PageControl value
    bool Settings::*field = nullptr;     // Toggle
    int indent = 0;                      // 0 page level, 1 inside an expander, 2 under its parent switch
};

struct PageContext {
    bool conflicts = false;          // detectConflicts() found something
    bool mixedCardPending = false;   // HKCU mixedCardPending
    bool offerDefaultInput = false;  // defaultInputAdvice(...) == MakeVietTelexDefault
    // Portable build (core/portable.h): no Windows keyboard to manage — no per-app input
    // method card, no default-keyboard card, no keyboard icon (an HKLM profile value), no
    // uninstaller (delete the folder).
    bool portable = false;
    bool expanded[static_cast<int>(Expander::Count)] = {};
    bool isExpanded(Expander e) const { return expanded[static_cast<int>(e)]; }
};

// The rows of one page; children of a collapsed expander are left out.
std::vector<PageRow> settingsPageRows(SettingsPage page, const Settings& s, const PageContext& ctx);

// Telex-only switches (simple Telex, free tone placement, quick Telex): VNI never reads
// them. Teencode and bracket vowels are NOT here — both work in VNI too.
bool isTelexOnly(bool Settings::*field);
// VNI: the "Gõ lẫn tiếng Anh" group is replaced by one line (SETTINGS-CLEANUP-SPEC §1).
bool hidesMixedGroup(const Settings& s);
// §6: the switch is left out because the parent right above it makes it do nothing.
bool hiddenByParent(const Settings& s, bool Settings::*field);
// "Kiểu biểu tượng khay": only with the tray icon on.
bool showsTrayStyle(const Settings& s);
// The one-time "Bạn hay gõ trộn Anh/Việt?" card: hidden under VNI (its "Xem" points at the
// hidden group); the HKCU flag is kept, so it shows again after switching back to Telex.
bool showsMixedCard(const Settings& s, const PageContext& ctx);
// Changing this switch shows/hides other rows: the window rebuilds the page at once.
bool affectsLayout(bool Settings::*field);

// Where a switch lives: its page and expander (-1 = page level). False if no page shows it.
bool findToggle(bool Settings::*field, SettingsPage& page, int& expander);

}  // namespace vtx::app
