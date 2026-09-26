#include "setup_helper_logic.h"

namespace vtx {

namespace {
std::wstring lower(std::wstring s) {
    for (wchar_t& c : s)
        if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
    return s;
}
std::wstring baseName(const std::wstring& p) {
    size_t s = p.find_last_of(L"\\/");
    return s == std::wstring::npos ? p : p.substr(s + 1);
}
bool endsWith(const std::wstring& s, const std::wstring& suf) {
    return s.size() >= suf.size() && s.compare(s.size() - suf.size(), suf.size(), suf) == 0;
}
bool versionTail(const std::wstring& t) {  // "" or "_1_0_6" (digits and underscores)
    if (t.empty()) return true;
    if (t[0] != L'_') return false;
    for (wchar_t c : t)
        if (!(c == L'_' || (c >= L'0' && c <= L'9'))) return false;
    return t.size() > 1;
}
}  // namespace

bool isAppImage(const std::wstring& p) { return lower(baseName(p)) == L"viettelex.exe"; }

bool isTipDllName(const std::wstring& fileName) {
    const std::wstring n = lower(baseName(fileName));
    if (!endsWith(n, L".dll")) return false;
    std::wstring stem = n.substr(0, n.size() - 4);
    const std::wstring pre = L"viettelextip";
    if (stem.compare(0, pre.size(), pre) != 0) return false;
    stem = stem.substr(pre.size());
    for (const wchar_t* arch : {L"_arm64", L"_x64"}) {
        const std::wstring a = arch;
        if (stem.compare(0, a.size(), a) == 0) return versionTail(stem.substr(a.size()));
    }
    return versionTail(stem);
}

bool isReleasedLeftover(const std::wstring& fileName) {
    const std::wstring n = lower(baseName(fileName));
    return endsWith(n, L".old") && n.find(L"viettelextip") == 0;
}

std::wstring releaseName(const std::wstring& fileName, unsigned long long stamp) {
    return fileName + L"." + std::to_wstring(stamp) + L".old";
}

std::string versionSuffix(const std::string& v) {
    std::string out = "_";
    for (char c : v) out.push_back(c == '.' ? '_' : c);
    return out;
}

HelperArgs parseHelperArgs(const std::vector<std::wstring>& argv) {
    HelperArgs a;
    for (size_t i = 0; i < argv.size(); ++i) {
        if (argv[i] == L"--quit-app") a.quitApp = true;
        else if (argv[i] == L"--release-tip") {
            a.releaseTip = true;
            while (i + 1 < argv.size() && argv[i + 1].compare(0, 2, L"--") != 0) {
                std::wstring d = argv[++i];
                // MSI passes "[INSTALLFOLDER]." -> "C:\dir\." ; tolerate "C:\dir\" and a stray quote.
                if (d.size() >= 2 && d.compare(d.size() - 2, 2, L"\\.") == 0) d.erase(d.size() - 2);
                while (!d.empty() && (d.back() == L'\\' || d.back() == L'"')) d.pop_back();
                if (!d.empty()) a.dirs.push_back(d);
            }
        }
    }
    return a;
}

}  // namespace vtx

#include "update_check.h"

namespace vtx {

std::wstring mainWindowTitle(const std::string& version) {
    std::wstring t = L"VietTelex ";
    for (char c : version) t.push_back(static_cast<wchar_t>(c));
    return t;
}

Handoff decideHandoff(const std::wstring& runningTitle, const std::string& ourVersion) {
    const std::wstring pre = L"VietTelex ";
    if (runningTitle.compare(0, pre.size(), pre) != 0) return Handoff::ReplaceRunning;  // <= 1.0.5
    std::string running;
    for (size_t i = pre.size(); i < runningTitle.size(); ++i) {
        wchar_t c = runningTitle[i];
        if (!((c >= L'0' && c <= L'9') || c == L'.')) return Handoff::ReplaceRunning;
        running.push_back(static_cast<char>(c));
    }
    if (running.empty()) return Handoff::ReplaceRunning;
    return isNewer(ourVersion, running) ? Handoff::ReplaceRunning : Handoff::PassToRunning;
}

}  // namespace vtx

namespace vtx {

std::wstring watcherArgs(unsigned long pid) { return L"--wait-install " + std::to_wstring(pid); }

bool parseWaitInstallArg(const std::vector<std::wstring>& argv, unsigned long& pid) {
    for (size_t i = 0; i + 1 < argv.size(); ++i) {
        if (argv[i] != L"--wait-install") continue;
        const std::wstring& n = argv[i + 1];
        if (n.empty() || n.size() > 10) return false;
        unsigned long long v = 0;
        for (wchar_t c : n) {
            if (c < L'0' || c > L'9') return false;
            v = v * 10 + static_cast<unsigned>(c - L'0');
        }
        if (v == 0 || v > 0xFFFFFFFFull) return false;
        pid = static_cast<unsigned long>(v);
        return true;
    }
    return false;
}

AfterInstall afterInstallAction(bool appAlreadyRunning, bool installedExeExists) {
    // The MSI's LaunchApp normally started the new version already: never start a second.
    if (appAlreadyRunning || !installedExeExists) return AfterInstall::Nothing;
    return AfterInstall::LaunchInstalled;
}

}  // namespace vtx
