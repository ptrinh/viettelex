#include "uninstall.h"

namespace vtx {

bool isGuidString(const std::string& s) {
    if (s.size() != 38 || s.front() != '{' || s.back() != '}') return false;
    for (size_t i = 1; i < 37; ++i) {
        const char c = s[i];
        if (i == 9 || i == 14 || i == 19 || i == 24) {
            if (c != '-') return false;
        } else if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))) {
            return false;
        }
    }
    return true;
}

std::string findInstalledProductCode(const RelatedProducts& enumerate, bool preferArm64) {
    const char* order[2] = {preferArm64 ? kUpgradeCodeArm64 : kUpgradeCodeX64,
                            preferArm64 ? kUpgradeCodeX64 : kUpgradeCodeArm64};
    for (const char* up : order)
        for (const std::string& code : enumerate(up))
            if (isGuidString(code)) return code;
    return std::string();
}

std::string uninstallParameters(const std::string& productCode) {
    return isGuidString(productCode) ? "/x " + productCode : std::string();
}

std::string versionForDisplay(const std::string& v) {
    std::string out = v;
    int dots = 0;
    for (char c : out)
        if (c == '.') ++dots;
    while (dots > 2 && out.size() >= 2 && out.compare(out.size() - 2, 2, ".0") == 0) {
        out.erase(out.size() - 2);
        --dots;
    }
    return out;
}

}  // namespace vtx
