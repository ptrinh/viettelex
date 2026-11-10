#include "store_files.h"

namespace vtx {

namespace {
std::wstring lower(const std::wstring& s) {
    std::wstring out = s;
    for (wchar_t& c : out)
        if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
    return out;
}

bool endsWith(const std::wstring& s, const std::wstring& tail) {
    return s.size() >= tail.size() && s.compare(s.size() - tail.size(), tail.size(), tail) == 0;
}
}  // namespace

bool isUserDataFileName(const std::wstring& name) {
    if (name.empty() || name.find_first_of(L"\\/:") != std::wstring::npos) return false;
    const std::wstring n = lower(name);
    static const wchar_t* const kExact[] = {
        L"settings.bin",      L"settings.bin.tmp", L"learned-words.bin", L"learned-words.bin.tmp",
        L"applang.txt",       L"applang.txt.tmp",  L"debug.log",         L"debug.1.log",
    };
    for (const wchar_t* e : kExact)
        if (n == e) return true;
    // update-<version>.log and update-watcher.log
    const std::wstring pre = L"update-";
    return n.size() > pre.size() + 4 && n.compare(0, pre.size(), pre) == 0 && endsWith(n, L".log");
}

}  // namespace vtx
