#include "debug_header.h"

#include <cstdio>

namespace vtx {

namespace {

char lowerAscii(char c) { return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c; }

bool isSep(char c) { return c == '\\' || c == '/'; }

// `root` is a prefix of `path` (ASCII case-insensitive) ending at a separator or the end.
bool underRoot(const std::string& path, const std::string& root) {
    std::string r = root;
    while (!r.empty() && isSep(r.back())) r.pop_back();
    if (r.empty() || path.size() < r.size()) return false;
    for (size_t i = 0; i < r.size(); ++i)
        if (lowerAscii(path[i]) != lowerAscii(r[i])) return false;
    return path.size() == r.size() || isSep(path[r.size()]);
}

}  // namespace

const char* machineName(uint16_t m) {
    switch (m) {
        case 0x8664: return "x64";
        case 0xAA64: return "arm64";
        case 0x014C: return "x86";
        case 0x01C4: return "arm";
        case 0xA641: return "arm64ec";
        default: return "?";
    }
}

const char* integrityName(uint32_t rid) {
    if (rid == 0) return "?";
    if (rid < 0x1000) return "untrusted";
    if (rid < 0x2000) return "low";
    if (rid == 0x2000) return "medium";
    if (rid < 0x3000) return "medium+";
    if (rid < 0x4000) return "high";
    return "system";
}

std::string formatProcessContext(const ProcessContext& c) {
    std::string s = "# context: VietTelex " + (c.version.empty() ? std::string("?") : c.version) + " " +
                    (c.module.empty() ? std::string("?") : c.module) + ", " + machineName(c.processMachine);
    if (c.osMachine && c.osMachine != c.processMachine) {
        s += " on ";
        s += machineName(c.osMachine);
        // x86 on x64 is WOW64, not emulation; x64 / x86 / arm64ec code on arm64 is.
        if (c.osMachine == 0xAA64) s += " (emulated)";
    }
    char os[48];
    std::snprintf(os, sizeof os, ", Windows %u.%u.%u", c.osMajor, c.osMinor, c.osBuild);
    s += os;
    s += ", integrity ";
    s += integrityName(c.integrityRid);
    s += c.elevated ? ", elevated" : ", not elevated";
    if (c.appContainer) s += ", AppContainer";
    return s;
}

std::string formatWindowsVersion(unsigned major, unsigned minor, unsigned build, unsigned ubr,
                                 const std::string& displayVersion, const std::string& edition) {
    char name[32];
    if (major == 10 && minor == 0)
        std::snprintf(name, sizeof name, "Windows %d", build >= 22000 ? 11 : 10);
    else
        std::snprintf(name, sizeof name, "Windows %u.%u", major, minor);
    std::string s = name;
    if (!edition.empty()) s += " " + edition;
    if (!displayVersion.empty()) s += " " + displayVersion;
    char num[64];
    std::snprintf(num, sizeof num, " (%u.%u.%u.%u)", major, minor, build, ubr);
    return s + num;
}

std::string redactUserPath(const std::string& path, const std::string& userProfile) {
    std::string root = userProfile;
    while (!root.empty() && isSep(root.back())) root.pop_back();
    if (root.empty()) return path;
    std::string out;
    size_t i = 0;
    while (i < path.size()) {
        bool hit = path.size() - i >= root.size();
        for (size_t k = 0; hit && k < root.size(); ++k) hit = lowerAscii(path[i + k]) == lowerAscii(root[k]);
        if (hit) {
            const size_t end = i + root.size();
            hit = end == path.size() || isSep(path[end]) || path[end] == ';' || path[end] == '"';
        }
        if (hit) {
            out += '~';
            i += root.size();
        } else {
            out += path[i++];
        }
    }
    return out;
}

const char* installKindName(InstallKind k) {
    switch (k) {
        case InstallKind::Portable: return "portable";
        case InstallKind::Store: return "Store (MSIX)";
        case InstallKind::MsiPerMachine: return "MSI per-machine";
        case InstallKind::MsiPerUser: return "MSI per-user";
        case InstallKind::Other: return "other folder";
    }
    return "?";
}

InstallKind classifyInstall(bool portable, bool packaged, const std::string& exePath,
                            const std::vector<std::string>& machineRoots, const std::string& userRoot) {
    if (portable) return InstallKind::Portable;
    if (packaged) return InstallKind::Store;
    for (const std::string& r : machineRoots)
        if (underRoot(exePath, r)) return InstallKind::MsiPerMachine;
    if (underRoot(exePath, userRoot)) return InstallKind::MsiPerUser;
    return InstallKind::Other;
}

bool sameRelease(const std::string& appVersion, const std::string& tipVersion) {
    if (tipVersion.empty() || tipVersion == "0") return false;
    // x.y.z of each: the app's is x.y.z.0.
    auto xyz = [](const std::string& v) {
        size_t dots = 0, i = 0;
        for (; i < v.size(); ++i)
            if (v[i] == '.' && ++dots == 3) break;
        return v.substr(0, i);
    };
    return xyz(appVersion) == xyz(tipVersion);
}

std::string formatSettingsSummary(const Settings& s) {
    std::string out = s.vniMode ? "VNI" : s.simpleTelex ? "Telex (simple)" : "Telex";
    out += " | on:";
    size_t n = 0;
    const BoolKey* keys = boolKeys(&n);
    for (size_t i = 0; i < n; ++i) {
        const BoolKey& k = keys[i];
        if (!(s.*k.field)) continue;
        if (k.field == &Settings::vniMode || k.field == &Settings::simpleTelex || k.field == &Settings::debugLogging)
            continue;
        out += ' ';
        out += k.name;
    }
    out += " | switch " + s.switchHotkey + " | ui " + s.uiLanguage + " | game hotkey " + s.gameModeHotkey +
           " | add-tones hotkey " + s.addTonesHotkey + " | indicator " + s.switchIndicator;
    out += " | per-app " + std::to_string(s.appModes.size());
    if (!s.appModes.empty()) {
        // Count per mode (Composition .. Direct), never the app names.
        unsigned counts[5] = {};
        for (const auto& kv : s.appModes) {
            const unsigned m = static_cast<unsigned>(kv.second);
            if (m < 5) ++counts[m];
        }
        std::string parts;
        for (unsigned m = 0; m < 5; ++m) {
            if (!counts[m]) continue;
            if (!parts.empty()) parts += ", ";
            parts += appModeName(static_cast<AppMode>(m));
            parts += ' ';
            parts += std::to_string(counts[m]);
        }
        out += " (" + parts + ")";
    }
    out += " | shortcuts " + std::to_string(s.shortcuts.size());
    return out;
}

std::vector<std::string> formatDebugHeader(const std::vector<std::pair<std::string, std::string>>& fields) {
    std::vector<std::string> out;
    out.push_back("# VietTelex debug log: time pid exe [component] message; decisions only, never typed text");
    for (const auto& f : fields) out.push_back("# " + f.first + ": " + (f.second.empty() ? "?" : f.second));
    return out;
}

}  // namespace vtx
