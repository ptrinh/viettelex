// uninstall.h — pure parts of "Gỡ cài đặt VietTelex" (About page), unit-tested.
//
// The installed product is found through its UpgradeCode (MsiEnumRelatedProducts), never
// by a hard-coded ProductCode: every release has a new ProductCode (major upgrade) and
// repair packages keep old ones.
#pragma once
#include <functional>
#include <string>
#include <vector>

namespace vtx {

// UpgradeCodes of the per-architecture MSIs (windows/scripts/release.sh). Never change.
constexpr const char* kUpgradeCodeX64 = "{C7AF803E-D7DC-4371-9318-04EA3B66BF59}";
constexpr const char* kUpgradeCodeArm64 = "{5E0A7C41-9B3D-4F62-A8E1-7D2C4B9F3A06}";

// "{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}" (hex, braces) — anything else is refused so no
// odd string ever reaches a command line.
bool isGuidString(const std::string& s);

// Enumerates ProductCodes installed for one UpgradeCode (MsiEnumRelatedProducts on
// Windows; a fake in tests).
using RelatedProducts = std::function<std::vector<std::string>(const std::string& upgradeCode)>;

// The installed VietTelex ProductCode, or "" when none (dev build / not installed).
// `preferArm64`: look under the ARM64 package first.
std::string findInstalledProductCode(const RelatedProducts& enumerate, bool preferArm64);

// Parameters for msiexec.exe: "/x {GUID}". Empty when the code is not a GUID.
std::string uninstallParameters(const std::string& productCode);

// "1.0.4.0" -> "1.0.4", "1.0.0.0" -> "1.0.0", "1.2.3.4" -> "1.2.3.4": trailing ".0"
// fields beyond major.minor.patch are not shown.
std::string versionForDisplay(const std::string& v);

}  // namespace vtx
