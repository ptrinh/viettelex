#include "settings_store.h"

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>

#include <vector>

#include "shortcuts.h"
#include "utf.h"

namespace vtx::app {

namespace {
constexpr wchar_t kRoot[] = L"Software\\VietTelex";

HKEY openRoot(bool write) {
    HKEY k = nullptr;
    if (write) {
        if (RegCreateKeyExW(HKEY_CURRENT_USER, kRoot, 0, nullptr, 0, KEY_READ | KEY_WRITE, nullptr, &k, nullptr) !=
            ERROR_SUCCESS)
            return nullptr;
    } else if (RegOpenKeyExW(HKEY_CURRENT_USER, kRoot, 0, KEY_READ, &k) != ERROR_SUCCESS) {
        return nullptr;
    }
    return k;
}

bool getDword(HKEY k, const wchar_t* name, DWORD& v) {
    DWORD sz = sizeof v, type = 0;
    return RegQueryValueExW(k, name, nullptr, &type, reinterpret_cast<BYTE*>(&v), &sz) == ERROR_SUCCESS &&
           type == REG_DWORD;
}

bool getString(HKEY k, const wchar_t* name, std::wstring& out) {
    DWORD type = 0, sz = 0;
    if (RegQueryValueExW(k, name, nullptr, &type, nullptr, &sz) != ERROR_SUCCESS || type != REG_SZ) return false;
    std::wstring buf(sz / sizeof(wchar_t) + 1, L'\0');
    if (RegQueryValueExW(k, name, nullptr, &type, reinterpret_cast<BYTE*>(&buf[0]), &sz) != ERROR_SUCCESS)
        return false;
    buf.resize(wcsnlen(buf.c_str(), buf.size()));
    out = buf;
    return true;
}

bool getBinary(HKEY k, const wchar_t* name, std::string& out) {
    DWORD type = 0, sz = 0;
    if (RegQueryValueExW(k, name, nullptr, &type, nullptr, &sz) != ERROR_SUCCESS || type != REG_BINARY) return false;
    out.assign(sz, '\0');
    return sz == 0 ||
           RegQueryValueExW(k, name, nullptr, &type, reinterpret_cast<BYTE*>(&out[0]), &sz) == ERROR_SUCCESS;
}

void setDword(HKEY k, const wchar_t* name, DWORD v) {
    RegSetValueExW(k, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&v), sizeof v);
}
void setString(HKEY k, const wchar_t* name, const std::wstring& v) {
    RegSetValueExW(k, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(v.c_str()),
                   static_cast<DWORD>((v.size() + 1) * sizeof(wchar_t)));
}
void setBinary(HKEY k, const wchar_t* name, const void* data, size_t len) {
    RegSetValueExW(k, name, 0, REG_BINARY, static_cast<const BYTE*>(data), static_cast<DWORD>(len));
}

std::wstring localAppDataDir() {
    wchar_t buf[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return L"";
    return std::wstring(buf) + L"\\VietTelex";
}

// Grant ALL APPLICATION PACKAGES (S-1-15-2-1) and ALL RESTRICTED APPLICATION PACKAGES
// (S-1-15-2-2) read access, inherited by files created inside.
void grantAppContainerRead(const std::wstring& dir) {
    PACL oldDacl = nullptr;
    PSECURITY_DESCRIPTOR sd = nullptr;
    if (GetNamedSecurityInfoW(dir.c_str(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, nullptr, nullptr, &oldDacl,
                              nullptr, &sd) != ERROR_SUCCESS)
        return;
    PSID sids[2] = {nullptr, nullptr};
    ConvertStringSidToSidW(L"S-1-15-2-1", &sids[0]);
    ConvertStringSidToSidW(L"S-1-15-2-2", &sids[1]);
    EXPLICIT_ACCESSW ea[2] = {};
    int n = 0;
    for (PSID sid : sids) {
        if (!sid) continue;
        ea[n].grfAccessPermissions = GENERIC_READ | GENERIC_EXECUTE;
        ea[n].grfAccessMode = GRANT_ACCESS;
        ea[n].grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
        ea[n].Trustee.TrusteeForm = TRUSTEE_IS_SID;
        ea[n].Trustee.TrusteeType = TRUSTEE_IS_WELL_KNOWN_GROUP;
        ea[n].Trustee.ptstrName = static_cast<LPWSTR>(sid);
        ++n;
    }
    PACL newDacl = nullptr;
    if (n > 0 && SetEntriesInAclW(static_cast<ULONG>(n), ea, oldDacl, &newDacl) == ERROR_SUCCESS) {
        SetNamedSecurityInfoW(const_cast<LPWSTR>(dir.c_str()), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, nullptr,
                              nullptr, newDacl, nullptr);
        LocalFree(newDacl);
    }
    for (PSID sid : sids)
        if (sid) LocalFree(sid);
    LocalFree(sd);
}

bool writeSnapshotFile(const std::vector<uint8_t>& bytes) {
    std::wstring dir = localAppDataDir();
    if (dir.empty()) return false;
    if (CreateDirectoryW(dir.c_str(), nullptr) || GetLastError() == ERROR_ALREADY_EXISTS) grantAppContainerRead(dir);
    const std::wstring tmp = dir + L"\\settings.bin.tmp";
    const std::wstring dst = dir + L"\\settings.bin";
    HANDLE f = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    DWORD wrote = 0;
    BOOL ok = WriteFile(f, bytes.data(), static_cast<DWORD>(bytes.size()), &wrote, nullptr) && wrote == bytes.size();
    ok = FlushFileBuffers(f) && ok;
    CloseHandle(f);
    // Atomic replace: the TIP never sees a half-written file.
    return ok && MoveFileExW(tmp.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
}

}  // namespace

std::wstring widen(const std::string& s) {
    if (s.empty()) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), &w[0], n);
    return w;
}

std::string narrow(const std::wstring& w) {
    if (w.empty()) return "";
    int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
    std::string s(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), &s[0], n, nullptr, nullptr);
    return s;
}

Settings loadSettings() {
    Settings s;
    HKEY k = openRoot(false);
    if (!k) return s;
    size_t count = 0;
    const BoolKey* keys = boolKeys(&count);
    for (size_t i = 0; i < count; ++i) {
        DWORD v;
        if (getDword(k, widen(keys[i].name).c_str(), v)) s.*keys[i].field = v != 0;
    }
    std::wstring str;
    if (getString(k, L"switchHotkey", str)) s.switchHotkey = narrow(str);
    if (getString(k, L"menuIcon", str)) s.menuIcon = narrow(str);
    if (getString(k, L"uiLanguage", str)) s.uiLanguage = narrow(str);
    std::string json;
    StringMap m;
    if (getBinary(k, L"shortcuts", json) && parseFlatJson(json, m))
        for (const auto& kv : m) s.shortcuts[utf8ToUtf16(kv.first)] = utf8ToUtf16(kv.second);
    if (getBinary(k, L"appModes", json) && parseFlatJson(json, m)) {
        for (const auto& kv : m) {
            AppMode mode;
            if (parseAppMode(kv.second, mode)) s.appModes[normalizeExeName(kv.first)] = mode;
        }
    }
    RegCloseKey(k);
    return s;
}

bool saveSettings(const Settings& s) {
    HKEY k = openRoot(true);
    if (!k) return false;
    size_t count = 0;
    const BoolKey* keys = boolKeys(&count);
    for (size_t i = 0; i < count; ++i) setDword(k, widen(keys[i].name).c_str(), (s.*keys[i].field) ? 1 : 0);
    setString(k, L"switchHotkey", widen(s.switchHotkey));
    setString(k, L"menuIcon", widen(s.menuIcon));
    setString(k, L"uiLanguage", widen(s.uiLanguage));
    StringMap sc;
    for (const auto& kv : s.shortcuts) sc[utf16ToUtf8(kv.first)] = utf16ToUtf8(kv.second);
    std::string j = toFlatJson(sc);
    setBinary(k, L"shortcuts", j.data(), j.size());
    StringMap am;
    for (const auto& kv : s.appModes) am[kv.first] = appModeName(kv.second);
    j = toFlatJson(am);
    setBinary(k, L"appModes", j.data(), j.size());
    std::vector<uint8_t> snap = serialize(s);
    setBinary(k, L"snapshot", snap.data(), snap.size());
    RegCloseKey(k);
    return writeSnapshotFile(snap);
}

unsigned long long readQword(const wchar_t* name, unsigned long long def) {
    unsigned long long v = def;
    DWORD sz = sizeof v;
    if (RegGetValueW(HKEY_CURRENT_USER, kRoot, name, RRF_RT_REG_QWORD, nullptr, &v, &sz) != ERROR_SUCCESS) v = def;
    return v;
}

void writeQword(const wchar_t* name, unsigned long long v) {
    if (HKEY k = openRoot(true)) {
        RegSetValueExW(k, name, 0, REG_QWORD, reinterpret_cast<const BYTE*>(&v), sizeof v);
        RegCloseKey(k);
    }
}

std::wstring readString(const wchar_t* name) {
    std::wstring out;
    if (HKEY k = openRoot(false)) {
        getString(k, name, out);
        RegCloseKey(k);
    }
    return out;
}

void writeString(const wchar_t* name, const std::wstring& v) {
    if (HKEY k = openRoot(true)) {
        setString(k, name, v);
        RegCloseKey(k);
    }
}

bool readFlag(const wchar_t* name) {
    DWORD v = 0, sz = sizeof v;
    return RegGetValueW(HKEY_CURRENT_USER, kRoot, name, RRF_RT_REG_DWORD, nullptr, &v, &sz) == ERROR_SUCCESS && v;
}

void writeFlag(const wchar_t* name, bool v) {
    if (HKEY k = openRoot(true)) {
        setDword(k, name, v ? 1 : 0);
        RegCloseKey(k);
    }
}

void eraseUserData() {
    RegDeleteTreeW(HKEY_CURRENT_USER, kRoot);
    std::wstring dir = localAppDataDir();
    if (dir.empty()) return;
    DeleteFileW((dir + L"\\settings.bin").c_str());
    DeleteFileW((dir + L"\\settings.bin.tmp").c_str());
    RemoveDirectoryW(dir.c_str());
}

}  // namespace vtx::app
