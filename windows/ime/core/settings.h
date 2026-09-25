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
    // Chuyển / giao diện / hệ thống
    std::string switchHotkey = "ctrl-shift";
    std::string menuIcon = "vt";      // "vt" (Vᴛ) | "letter" (V / E)
    std::string uiLanguage = "vi";    // "vi" | "en"
    bool autoUpdateCheck = false;
    bool debugLogging = false;
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

// Snapshot (binary, versioned, little-endian). deserialize() never throws; on any
// malformed input it returns false and leaves `out` = defaults.
std::vector<uint8_t> serialize(const Settings& s);
bool deserialize(const uint8_t* data, size_t len, Settings& out);

}  // namespace vtx
