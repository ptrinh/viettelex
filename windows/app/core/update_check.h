// update_check.h — parse stable.json and decide whether an update is offered.
//
// Same file the macOS updater reads (docs/stable.json), plus a "windows" object:
//   { "version": "1.7.12", "url": "...", "build": 108,
//     "windows": { "version": "0.2.0", "x64": "https://…/VietTelex-0.2.0-x64.msi",
//                  "arm64": "https://…/VietTelex-0.2.0-arm64.msi",
//                  "notes": "https://github.com/…/releases/tag/win-v0.2.0" } }
// The MSI is only ever run after its Authenticode signature verifies (updater.cpp).
#pragma once
#include <string>

namespace vtx {

struct WindowsRelease {
    std::string version;
    std::string x64;
    std::string arm64;
    std::string notes;
};

// False when there is no usable "windows" object (missing, malformed, no version).
bool parseStableJson(const std::string& json, WindowsRelease& out);

// Dotted numeric compare ("0.10.0" > "0.9.3"); non-numeric parts compare as 0.
int compareVersions(const std::string& a, const std::string& b);
inline bool isNewer(const std::string& candidate, const std::string& current) {
    return compareVersions(candidate, current) > 0;
}

// Only https:// URLs on hosts we publish from are accepted for the download.
bool isTrustedDownloadUrl(const std::string& url);

}  // namespace vtx
