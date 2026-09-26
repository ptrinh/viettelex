#include "com_path.h"

namespace vtx {

namespace {
std::wstring lower(std::wstring s) {
    for (wchar_t& c : s)
        if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
    return s;
}
}  // namespace

std::wstring forwarderCandidate(const std::wstring& modulePath) {
    size_t slash = modulePath.find_last_of(L"\\/");
    std::wstring dir = slash == std::wstring::npos ? std::wstring() : modulePath.substr(0, slash + 1);
    std::wstring name = lower(slash == std::wstring::npos ? modulePath : modulePath.substr(slash + 1));
    // VietTelexTIP_arm64[_1_0_6].dll / VietTelexTIP_x64[_1_0_6].dll -> VietTelexTIP[_1_0_6].dll
    // (release DLLs carry the version so an upgrade never overwrites an in-use file).
    for (const wchar_t* half : {L"viettelextip_arm64", L"viettelextip_x64"}) {
        const std::wstring h = half;
        if (name.compare(0, h.size(), h) != 0 || name.size() < h.size() + 4) continue;
        const std::wstring rest = name.substr(h.size());  // "" + ".dll" or "_1_0_6.dll"
        if (rest.compare(rest.size() - 4, 4, L".dll") != 0) continue;
        const std::wstring ver = rest.substr(0, rest.size() - 4);
        bool ok = ver.empty() || ver[0] == L'_';
        for (wchar_t c : ver) ok = ok && (c == L'_' || (c >= L'0' && c <= L'9'));
        if (ok) return dir + L"VietTelexTIP" + ver + L".dll";
    }
    return std::wstring();
}

std::wstring comServerPath(const std::wstring& modulePath, bool forwarderExists) {
    std::wstring fwd = forwarderCandidate(modulePath);
    return (!fwd.empty() && forwarderExists) ? fwd : modulePath;
}

}  // namespace vtx
