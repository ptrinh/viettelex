#include "registration.h"

#include <cstdio>

namespace vtx::reg {

const Category kCategories[] = {
    {"{34745C63-B2F0-4784-8B67-5E12C8701A31}", "GUID_TFCAT_TIP_KEYBOARD"},
    {"{046B8C80-1647-40F7-9B21-B93B81AABC1B}", "GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER"},
    {"{49D2F9CF-1F5E-11D7-A6D3-00065B84435C}", "GUID_TFCAT_TIPCAP_UIELEMENTENABLED"},
    {"{13A016DF-560B-46CD-947A-4C3AF1E0E35D}", "GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT"},
    {"{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}", "GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT"},
    {"{49D2F9CE-1F5E-11D7-A6D3-00065B84435C}", "GUID_TFCAT_TIPCAP_SECUREMODE"},
    {"{364215D9-75BC-11D7-A6EF-00065B84435C}", "GUID_TFCAT_TIPCAP_COMLESS"},
};
const size_t kCategoryCount = sizeof(kCategories) / sizeof(kCategories[0]);

namespace {
std::string tipKey() { return std::string("SOFTWARE\\Microsoft\\CTF\\TIP\\") + kClsid; }
Entry key(const std::string& k) { return Entry{k, "", ValueType::Key, "", 0}; }
Entry sz(const std::string& k, const std::string& n, const std::string& v) { return Entry{k, n, ValueType::Sz, v, 0}; }
Entry dw(const std::string& k, const std::string& n, uint32_t v) { return Entry{k, n, ValueType::Dword, "", v}; }
}  // namespace

std::string languageProfileKey() {
    char lang[16];
    std::snprintf(lang, sizeof lang, "0x%08x", static_cast<unsigned>(kLangId));
    return tipKey() + "\\LanguageProfile\\" + lang + "\\" + kProfile;
}

std::vector<Entry> tipRegistryEntries(const std::string& dllPath, const std::string& iconPath) {
    std::vector<Entry> e;
    const std::string clsidKey = std::string("SOFTWARE\\Classes\\CLSID\\") + kClsid;
    e.push_back(sz(clsidKey, "", kComDescription));
    e.push_back(sz(clsidKey + "\\InprocServer32", "", dllPath));
    e.push_back(sz(clsidKey + "\\InprocServer32", "ThreadingModel", "Apartment"));
    e.push_back(dw(tipKey(), "Enable", 1));
    const std::string lp = languageProfileKey();
    e.push_back(sz(lp, "Description", kProfileDescription));
    e.push_back(sz(lp, "IconFile", iconPath));
    e.push_back(dw(lp, "IconIndex", kIconIndex));
    e.push_back(dw(lp, "Enable", 1));
    e.push_back(dw(lp, "SubstituteLayout", kSubstituteLayout));
    for (size_t i = 0; i < kCategoryCount; ++i) {
        const std::string cat = kCategories[i].guid;
        e.push_back(key(tipKey() + "\\Category\\Category\\" + cat + "\\" + kClsid));
        e.push_back(key(tipKey() + "\\Category\\Item\\" + kClsid + "\\" + cat));
    }
    return e;
}

}  // namespace vtx::reg
