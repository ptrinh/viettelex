#include "direct_policy.h"

namespace vtx {

bool directUsable(bool known, unsigned long target, unsigned long hook) { return known && target <= hook; }

SendOutcome classifySend(unsigned sent, unsigned total) {
    if (sent >= total) return SendOutcome::Ok;
    return sent == 0 ? SendOutcome::NothingSent : SendOutcome::Partial;
}

bool injectionAllowed(uintptr_t now, uintptr_t word, bool secureDesktop) {
    return !secureDesktop && now != 0 && now == word;
}

bool echoMatches(const std::u16string& before, const std::u16string& expected) {
    if (expected.empty()) return true;
    return before.size() >= expected.size() && before.compare(before.size() - expected.size(), expected.size(), expected) == 0;
}

bool echoInValue(const std::u16string& value, const std::u16string& expected) {
    return expected.empty() || value.find(expected) != std::u16string::npos;
}

std::string hostIdentity(const std::string& windowClass, const std::string& ownerExe) {
    if (isConsoleWindowClass(windowClass)) return "conhost.exe";
    return ownerExe;
}

bool foregroundLanguage(int tipProp, bool console, bool hklIsVietTelex, bool storedVietnamese) {
    if (tipProp == 1) return true;
    if (tipProp == 2) return false;
    if (console) return false;
    return hklIsVietTelex && storedVietnamese;
}

bool EchoPolicy::record(uintptr_t w, int c, Echo e) {
    const auto key = std::make_pair(w, c);
    if (fallen_[key]) return false;
    if (e == Echo::Match) {
        mismatches_[key] = 0;
        return false;
    }
    if (e == Echo::Unverifiable) return false;
    if (++mismatches_[key] >= kMismatchesToFallBack) {
        fallen_[key] = true;
        return true;
    }
    return false;
}

bool EchoPolicy::fellBack(uintptr_t w, int c) const {
    auto it = fallen_.find(std::make_pair(w, c));
    return it != fallen_.end() && it->second;
}

void EchoPolicy::focusChanged() {
    mismatches_.clear();
    fallen_.clear();
}

}  // namespace vtx
