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
    if (name == L"viettelextip_arm64.dll" || name == L"viettelextip_x64.dll") return dir + L"VietTelexTIP.dll";
    return std::wstring();
}

std::wstring comServerPath(const std::wstring& modulePath, bool forwarderExists) {
    std::wstring fwd = forwarderCandidate(modulePath);
    return (!fwd.empty() && forwarderExists) ? fwd : modulePath;
}

}  // namespace vtx
