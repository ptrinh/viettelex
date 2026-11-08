// debug_header.h — the context block at the top of each process's part of debug.log
// (debug_log.h), mirroring the macOS DebugHeader (App/Sources/SettingsWindow.swift):
// what a developer needs to read the lines that follow, nothing personal.
//
//   * Every process (the TIP in a host, VietTelex.exe) writes one `# context:` line when
//     it first logs, when it starts a new file and on its first line of a new day:
//     version, module, process/OS architecture, Windows build, integrity, AppContainer.
//   * VietTelex.exe adds the full header (formatDebugHeader): install kind, TIP DLL
//     version (it can differ from the app: an upgrade with a host still holding the old
//     DLL, or a stale registration), Windows edition + display version, UI language,
//     keyboard layouts, other text services, DPI, settings summary, update check.
//
// PRIVACY: no user or machine name, no typed text or shortcut contents (counts only),
// paths under %USERPROFILE% become "~" (redactUserPath). Portable: unit-tested on the host.
#pragma once
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "settings.h"

namespace vtx {

struct ProcessContext {
    std::string version;       // VTX_VER_STRING of the binary that writes
    std::string module;        // lowercase base name: "viettelex.exe", "viettelextip_1_3_17.dll"
    uint16_t processMachine = 0;  // IMAGE_FILE_MACHINE_* this code was built for
    uint16_t osMachine = 0;       // native machine (IsWow64Process2), 0 = unknown
    unsigned osMajor = 0, osMinor = 0, osBuild = 0;
    uint32_t integrityRid = 0;    // SECURITY_MANDATORY_*_RID, 0 = unknown
    bool elevated = false;
    bool appContainer = false;
};

// IMAGE_FILE_MACHINE_* -> "x64" / "arm64" / "arm64ec" / "x86" / "arm"; "?" otherwise.
const char* machineName(uint16_t imageFileMachine);
// SECURITY_MANDATORY_*_RID -> "untrusted" / "low" / "medium" / "medium+" / "high" / "system".
const char* integrityName(uint32_t rid);
// The `# context:` message (no line prefix):
// "# context: VietTelex 1.3.17.0 viettelex.exe, x64 on arm64 (emulated), Windows 10.0.26100,
//  integrity medium, not elevated"  (+ ", AppContainer").
std::string formatProcessContext(const ProcessContext& c);

// "Windows 11 Professional 24H2 (10.0.26100.2314)". Windows 11 reports major 10: build
// 22000+ is 11. Empty edition / display version are left out.
std::string formatWindowsVersion(unsigned major, unsigned minor, unsigned build, unsigned ubr,
                                 const std::string& displayVersion, const std::string& edition);

// Every occurrence of `userProfile` (ASCII case-insensitive, followed by a separator or
// the end) -> "~". "C:\Users\An\AppData\Local\x" + "C:\Users\An" -> "~\AppData\Local\x".
std::string redactUserPath(const std::string& path, const std::string& userProfile);

enum class InstallKind { Portable, Store, MsiPerMachine, MsiPerUser, Other };
const char* installKindName(InstallKind k);
// Where VietTelex.exe runs from: a portable copy and an MSIX package win; else the folder
// decides (a Program Files root = per-machine MSI, %LOCALAPPDATA% = per-user MSI).
// Paths compare ASCII case-insensitively, as prefixes ending at a separator.
InstallKind classifyInstall(bool portable, bool packaged, const std::string& exePath,
                            const std::vector<std::string>& machineRoots, const std::string& userRoot);

// App version "1.3.17.0" vs TIP DLL version "1.3.15" (from its file name): same x.y.z?
// An empty / "0" TIP version (unversioned or not found) never matches.
bool sameRelease(const std::string& appVersion, const std::string& tipVersion);

// "Telex | on: freeMarking autoRestore … | switch ctrl-shift | ui vi | per-app 3 (off 1,
//  direct 2) | shortcuts 12". Counts only for the user's data.
std::string formatSettingsSummary(const Settings& s);

// key/value pairs -> "# key: value" messages, led by a one-line legend.
std::vector<std::string> formatDebugHeader(const std::vector<std::pair<std::string, std::string>>& fields);

}  // namespace vtx
