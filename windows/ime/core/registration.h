// registration.h — the ONE description of what registering VietTelexTIP.dll writes.
//
// Two consumers must agree byte for byte:
//   * DllRegisterServer (ime/src/register.cpp) — COM keys + TSF profile/categories
//     through the TSF APIs; it refuses to register if the SDK GUIDs it passes to those
//     APIs differ from the strings here.
//   * The MSI (windows/scripts/release.sh) — no regsvr32: the same data goes in as
//     Registry-table rows, generated from tipRegistryEntries() by tools/regtable.cpp,
//     and release.sh re-reads the built MSI and diffs it against this list.
//
// Layout mirrored (what ITfInputProcessorProfileMgr::RegisterProfile and
// ITfCategoryMgr::RegisterCategory store, relative to HKLM):
//   SOFTWARE\Classes\CLSID\{CLSID}                      (default) = description
//   SOFTWARE\Classes\CLSID\{CLSID}\InprocServer32       (default) = dll, ThreadingModel = Apartment
//   SOFTWARE\Microsoft\CTF\TIP\{CLSID}                   Enable = 1
//   ...\TIP\{CLSID}\LanguageProfile\0x0000042a\{PROFILE} Description, IconFile, IconIndex,
//                                                        Enable = 1, SubstituteLayout = 0x04090409
//   ...\TIP\{CLSID}\Category\Category\{CAT}\{CLSID}      (key)
//   ...\TIP\{CLSID}\Category\Item\{CLSID}\{CAT}          (key)
// A 32-bit (x86) registration writes the same rows into the 32-bit registry view.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace vtx::reg {

constexpr const char* kClsid = "{A93425B6-980D-4BB2-83C4-2DA555A30D85}";
constexpr const char* kProfile = "{A4D93021-292F-4C97-97A1-45F50D970649}";
constexpr uint32_t kLangId = 0x042A;                 // vi-VN
constexpr uint32_t kSubstituteLayout = 0x04090409;   // US keyboard
constexpr const char* kComDescription = "VietTelex Text Service";
// ASCII on purpose: wixl writes MSI strings in codepage 1252 only, and the MSI carries
// this value verbatim. Windows lists it under the "Tiếng Việt" language anyway.
constexpr const char* kProfileDescription = "VietTelex";
// Index of the default profile icon (monochrome Vᴛ, IDI_PROFILE_VT) in the TIP DLL's icon
// resources — vtx::profileIconIndex(IconChoice::Vt); a unit test keeps them equal.
// VietTelex.exe --set-profile-icon rewrites it when the user picks another icon.
constexpr uint32_t kIconIndex = 13;

struct Category {
    const char* guid;
    const char* sdkName;
};
// Index-aligned with the SDK constants in ime/src/register.cpp (checked at registration).
extern const Category kCategories[];
extern const size_t kCategoryCount;

enum class ValueType { Key, Sz, Dword };

struct Entry {
    std::string key;    // relative to HKLM
    std::string name;   // empty = default value (or key-only row)
    ValueType type;
    std::string sz;     // Sz
    uint32_t dword;     // Dword
};

// `dllPath` / `iconPath`: literal paths or MSI formatted strings
// ("[INSTALLFOLDER]VietTelexTIP.dll").
std::vector<Entry> tipRegistryEntries(const std::string& dllPath, const std::string& iconPath);

std::string languageProfileKey();  // SOFTWARE\Microsoft\CTF\TIP\{CLSID}\LanguageProfile\0x0000042a\{PROFILE}

}  // namespace vtx::reg
