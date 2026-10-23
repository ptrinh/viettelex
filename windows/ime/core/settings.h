// settings.h — one settings model shared by the TIP and VietTelex.exe (spec §7, §9).
//
// Keys and defaults mirror macOS App/Sources/AppState.swift (1.7.12). Storage:
//   * VietTelex.exe owns HKCU\Software\VietTelex: one DWORD/String value per key
//     (names below), shortcuts as REG_BINARY JSON (value "shortcuts"), per-app
//     typing modes as REG_BINARY JSON (value "appModes").
//   * After every save the app also writes a compact binary SNAPSHOT (this file's
//     serialize()) to value "snapshot" and to %LOCALAPPDATA%\VietTelex\settings.bin
//     (ACL: ALL APPLICATION PACKAGES read) — the TIP only ever parses the snapshot,
//     so it has one tiny parser whether it runs in a normal or an AppContainer process.
#pragma once
#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "app_policy.h"

namespace vtx {

struct Settings {
    // Kiểu gõ
    bool vniMode = false;
    bool simpleTelex = false;
    bool freeMarking = true;
    bool quickTelex = false;
    bool modernOrthography = false;
    bool bracketVowels = false;
    // Chính tả
    bool autoRestore = true;
    bool liveSpellCheck = true;
    bool contextualEnglish = true;
    bool collisionPrefersVietnamese = true;
    bool teencode = false;
    bool reEditWord = true;
    // "Tự sửa từ phía trước" (Fix earlier words, EXPERIMENTAL, default OFF; macOS/iOS/Android
    // retroactiveEnglish): only shown and only effective while contextualEnglish is on. On =
    // the TIP rewrites "Hí cả í very fast" -> "His car is very fast" at the boundary (verified
    // against the text before the caret), ⌫ next reverts it (core/retro_english.h).
    bool retroactiveEnglish = false;
    // "Gạch đỏ âm tiết sai chính tả khi gõ" (Windows/Linux only, default OFF): the word in
    // a composition gets a red squiggle when it cannot become a Vietnamese syllable.
    // Composition mode only; in-place has no composition to decorate.
    bool underlineMisspelled = false;
    // Chuyển / giao diện / hệ thống
    std::string switchHotkey = "ctrl-shift";
    std::string menuIcon = "vt";      // keyboard icon: vt | star | flag | logo | vi (res/icon_ids.h)
    std::string uiLanguage = "vi";    // "vi" | "en"
    bool autoUpdateCheck = false;
    bool debugLogging = false;
    bool showTrayIcon = false;        // the ONLY lasting Việt/Anh indicator (the taskbar shows
                                      // the static keyboard icon since 1.0.8); the welcome
                                      // window pre-ticks it. Start menu -> VietTelex = Settings
    // Công cụ văn bản (macOS textToolsInMenu / addTonesHotkey): the tray menu's "Công cụ
    // văn bản" submenu, and the global Thêm dấu hotkey (app/core/text_action_logic.h
    // choices, default "off"). VietTelex.exe only: addTonesHotkey is registry-only (not in
    // the TIP snapshot, not compared by operator==).
    bool textToolsInMenu = true;
    std::string addTonesHotkey = "off";
    // Gợi ý cạnh con trỏ (macOS 1.8.2 mathResults / numberChips / typoHints / toneHints /
    // dateHints; caret_hints.h). All off = the TIP does one flag read per key, nothing else.
    bool mathResults = true;
    bool numberChips = true;
    bool typoHints = true;
    bool toneHints = false;
    bool dateHints = true;
    // "Lọc từ nhạy cảm" (iOS/macOS filterSensitive, default ON): word prediction + typo fixes
    // never offer SensitiveWords.set. Read by VietTelex.exe (HintJobs) — the TIP only shows.
    bool filterSensitive = true;
    // "Học từ bạn gõ" (iOS/macOS, default ON; only with word prediction on): the TIP sends the
    // words it composed and committed (caret_hint_ipc.h HintJob::Learn) to VietTelex.exe, which
    // keeps the counts in %LOCALAPPDATA%\VietTelex\learned-words.bin (app/core/learned_words.h).
    bool learnWords = true;
    // Games / fullscreen (app/core/game_logic.h, ime/core/game_ipc.h).
    //   autoOffFullscreen: VietTelex stands aside (eats no key) while an exclusive-fullscreen
    //     Direct3D app/game (or a slideshow) is in the foreground. Default ON — borderless
    //     fullscreen browsers / video players are not affected.
    //   gameMode: "Chế độ game" — every key passes through, in every app. Runtime state:
    //     toggled by gameModeHotkey (or Settings), in the snapshot so every TIP sees it,
    //     and cleared whenever VietTelex.exe starts (never left on across a reboot).
    bool autoOffFullscreen = true;
    bool gameMode = false;
    // Gợi ý từ (word prediction, app/core/word_prediction.h): a MIRROR of the Windows
    // setting "Show text suggestions when typing on the physical keyboard" (HKCU\Software\
    // Microsoft\Input\Settings EnableHwkbTextPrediction; absent = OFF). No VietTelex
    // toggle: VietTelex.exe reads the Windows value at load and when it changes, and only
    // puts it in the snapshot — never into HKCU\Software\VietTelex (isSystemMirror()).
    bool systemTextPrediction = false;
    // VietTelex.exe only, registry-only like addTonesHotkey (not in the snapshot, not
    // compared by operator==): the Chế độ game hotkey (game_logic.h kGameModeHotkeys,
    // default "off") and the floating V/E indicator ("auto" | "on" | "off").
    std::string gameModeHotkey = "off";
    std::string switchIndicator = "auto";
    // Tray icon style (res/icon_ids.h TrayStyle): "letter" = V/E badge, "keyboard".
    std::string trayIconStyle = "letter";
    // Data
    std::map<std::u16string, std::u16string> shortcuts;   // gõ tắt
    std::map<std::string, AppMode> appModes;              // user override, key = lowercase exe

    // vtx_engine flag bitmask (VTX_* in windows/engine/API.md).
    uint32_t engineFlags() const;

    bool operator==(const Settings& o) const;
};

// Registry value names for the bool settings, in snapshot bit order. Never reorder:
// the bit index is the on-disk format.
struct BoolKey {
    const char* name;
    bool Settings::*field;
};
const BoolKey* boolKeys(size_t* count);
// Bool keys that mirror a Windows setting (snapshot only, not stored by VietTelex).
bool isSystemMirror(const BoolKey& k);

// Snapshot (binary, versioned, little-endian). deserialize() never throws; on any
// malformed input it returns false and leaves `out` = defaults.
std::vector<uint8_t> serialize(const Settings& s);
bool deserialize(const uint8_t* data, size_t len, Settings& out);

}  // namespace vtx
