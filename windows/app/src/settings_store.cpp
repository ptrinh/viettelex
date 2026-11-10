#include "settings_store.h"

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>

#include <vector>

#include "portable.h"
#include "shortcuts.h"
#include "store_files.h"
#include "word_prediction.h"
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

bool regDword(HKEY k, const wchar_t* name, DWORD& v) {
    DWORD sz = sizeof v, type = 0;
    return RegQueryValueExW(k, name, nullptr, &type, reinterpret_cast<BYTE*>(&v), &sz) == ERROR_SUCCESS &&
           type == REG_DWORD;
}

bool regString(HKEY k, const wchar_t* name, std::wstring& out) {
    DWORD type = 0, sz = 0;
    if (RegQueryValueExW(k, name, nullptr, &type, nullptr, &sz) != ERROR_SUCCESS || type != REG_SZ) return false;
    std::wstring buf(sz / sizeof(wchar_t) + 1, L'\0');
    if (RegQueryValueExW(k, name, nullptr, &type, reinterpret_cast<BYTE*>(&buf[0]), &sz) != ERROR_SUCCESS)
        return false;
    buf.resize(wcsnlen(buf.c_str(), buf.size()));
    out = buf;
    return true;
}

bool regBinary(HKEY k, const wchar_t* name, std::string& out) {
    DWORD type = 0, sz = 0;
    if (RegQueryValueExW(k, name, nullptr, &type, nullptr, &sz) != ERROR_SUCCESS || type != REG_BINARY) return false;
    out.assign(sz, '\0');
    return sz == 0 ||
           RegQueryValueExW(k, name, nullptr, &type, reinterpret_cast<BYTE*>(&out[0]), &sz) == ERROR_SUCCESS;
}

// ---- backend: HKCU (installed) or settings.ini (portable, core/portable.h) --------------
bool g_portable = false;
std::wstring g_iniPath;
portable::KeyValueFile g_kv;
SRWLOCK g_kvLock = SRWLOCK_INIT;

std::string kvName(const wchar_t* name) {
    std::string s;
    for (const wchar_t* p = name; *p; ++p) s.push_back(*p < 0x80 ? static_cast<char>(*p) : '_');
    return s;
}

void kvLoadLocked() {
    g_kv.clear();
    HANDLE f = CreateFileW(g_iniPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    LARGE_INTEGER size = {};
    if (GetFileSizeEx(f, &size) && size.QuadPart > 0 && size.QuadPart < 16 * 1024 * 1024) {
        std::string text(static_cast<size_t>(size.QuadPart), '\0');
        DWORD got = 0;
        if (ReadFile(f, &text[0], static_cast<DWORD>(text.size()), &got, nullptr)) {
            text.resize(got);
            g_kv.parse(text);
        }
    }
    CloseHandle(f);
}

// The disk side of a save, OUTSIDE g_kvLock (portable.h SaveSequencer): the hook thread's
// per-app Việt/Anh read at a word start never waits for a flush. Atomic replace (temp file +
// MoveFileEx), like the installed build's snapshot.
SRWLOCK g_kvFileLock = SRWLOCK_INIT;  // file writes, in order
portable::SaveSequencer g_kvSeq;      // stage(): under g_kvLock; the rest under g_kvFileLock

void kvWriteFile(const std::string& text, uint64_t seq) {
    AcquireSRWLockExclusive(&g_kvFileLock);
    if (g_kvSeq.shouldWrite(seq) && !g_iniPath.empty()) {
        const size_t slash = g_iniPath.find_last_of(L'\\');
        if (slash != std::wstring::npos) CreateDirectoryW(g_iniPath.substr(0, slash).c_str(), nullptr);
        const std::wstring tmp = g_iniPath + L".tmp";
        HANDLE f = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (f != INVALID_HANDLE_VALUE) {
            DWORD wrote = 0;
            const bool ok =
                WriteFile(f, text.data(), static_cast<DWORD>(text.size()), &wrote, nullptr) && wrote == text.size();
            CloseHandle(f);
            if (ok) MoveFileExW(tmp.c_str(), g_iniPath.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
            else DeleteFileW(tmp.c_str());
        }
    }
    g_kvSeq.done(seq);
    ReleaseSRWLockExclusive(&g_kvFileLock);
}

// One open of the store: the HKCU key, or the settings.ini map under its lock (written back
// when closed if anything changed).
class Store {
public:
    explicit Store(bool write) : write_(write) {
        if (g_portable) {
            if (write) AcquireSRWLockExclusive(&g_kvLock);
            else AcquireSRWLockShared(&g_kvLock);
            ok_ = true;
        } else {
            k_ = openRoot(write);
            ok_ = k_ != nullptr;
        }
    }
    ~Store() {
        if (g_portable) {
            if (write_) {
                // Serialise under the lock (memory only), write after releasing it.
                std::string text;
                uint64_t seq = 0;
                if (dirty_) {
                    text = g_kv.serialize();
                    seq = g_kvSeq.stage();
                }
                ReleaseSRWLockExclusive(&g_kvLock);
                if (seq) kvWriteFile(text, seq);
            } else {
                ReleaseSRWLockShared(&g_kvLock);
            }
        } else if (k_) {
            RegCloseKey(k_);
        }
    }
    Store(const Store&) = delete;
    Store& operator=(const Store&) = delete;
    bool ok() const { return ok_; }

    bool dword(const wchar_t* n, DWORD& v) const {
        if (!g_portable) return regDword(k_, n, v);
        uint32_t x = 0;
        if (!g_kv.getDword(kvName(n), x)) return false;
        v = x;
        return true;
    }
    bool qword(const wchar_t* n, unsigned long long& v) const {
        if (!g_portable) {
            DWORD type = 0, sz = sizeof v;
            return RegQueryValueExW(k_, n, nullptr, &type, reinterpret_cast<BYTE*>(&v), &sz) == ERROR_SUCCESS &&
                   type == REG_QWORD;
        }
        uint64_t x = 0;
        if (!g_kv.getQword(kvName(n), x)) return false;
        v = x;
        return true;
    }
    bool string(const wchar_t* n, std::wstring& out) const {
        if (!g_portable) return regString(k_, n, out);
        std::string u;
        if (!g_kv.getString(kvName(n), u)) return false;
        out = widen(u);
        return true;
    }
    bool binary(const wchar_t* n, std::string& out) const {
        if (!g_portable) return regBinary(k_, n, out);
        return g_kv.getBinary(kvName(n), out);
    }
    void setDword(const wchar_t* n, DWORD v) {
        if (!g_portable) {
            RegSetValueExW(k_, n, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&v), sizeof v);
            return;
        }
        g_kv.setDword(kvName(n), v);
        dirty_ = true;
    }
    void setQword(const wchar_t* n, unsigned long long v) {
        if (!g_portable) {
            RegSetValueExW(k_, n, 0, REG_QWORD, reinterpret_cast<const BYTE*>(&v), sizeof v);
            return;
        }
        g_kv.setQword(kvName(n), v);
        dirty_ = true;
    }
    void setString(const wchar_t* n, const std::wstring& v) {
        if (!g_portable) {
            RegSetValueExW(k_, n, 0, REG_SZ, reinterpret_cast<const BYTE*>(v.c_str()),
                           static_cast<DWORD>((v.size() + 1) * sizeof(wchar_t)));
            return;
        }
        g_kv.setString(kvName(n), narrow(v));
        dirty_ = true;
    }
    void setBinary(const wchar_t* n, const void* data, size_t len) {
        if (!g_portable) {
            RegSetValueExW(k_, n, 0, REG_BINARY, static_cast<const BYTE*>(data), static_cast<DWORD>(len));
            return;
        }
        g_kv.setBinary(kvName(n), std::string(static_cast<const char*>(data), len));
        dirty_ = true;
    }

private:
    bool write_;
    bool ok_ = false;
    bool dirty_ = false;
    HKEY k_ = nullptr;
};

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

// Both AppContainer SIDs have an inheritable allow ACE on the folder (what
// grantAppContainerRead adds). Unreadable DACL = not present.
bool appContainerReadGranted(const std::wstring& dir) {
    PACL dacl = nullptr;
    PSECURITY_DESCRIPTOR sd = nullptr;
    if (GetNamedSecurityInfoW(dir.c_str(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, nullptr, nullptr, &dacl, nullptr,
                              &sd) != ERROR_SUCCESS)
        return false;
    bool found[2] = {false, false};
    PSID sids[2] = {nullptr, nullptr};
    ConvertStringSidToSidW(L"S-1-15-2-1", &sids[0]);
    ConvertStringSidToSidW(L"S-1-15-2-2", &sids[1]);
    if (dacl) {
        for (DWORD i = 0; i < dacl->AceCount; ++i) {
            void* ace = nullptr;
            if (!GetAce(dacl, i, &ace)) continue;
            auto* a = static_cast<ACCESS_ALLOWED_ACE*>(ace);
            if (a->Header.AceType != ACCESS_ALLOWED_ACE_TYPE) continue;
            if ((a->Header.AceFlags & (OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE)) !=
                (OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE))
                continue;
            if (!(a->Mask & (GENERIC_READ | FILE_READ_DATA))) continue;
            for (int k = 0; k < 2; ++k)
                if (sids[k] && EqualSid(reinterpret_cast<PSID>(&a->SidStart), sids[k])) found[k] = true;
        }
    }
    for (PSID sid : sids)
        if (sid) LocalFree(sid);
    LocalFree(sd);
    return (found[0] || !sids[0]) && (found[1] || !sids[1]);
}

bool g_aclChecked = false;  // UI thread (saves)

bool writeSnapshotFile(const std::vector<uint8_t>& bytes) {
    std::wstring dir = localAppDataDir();
    if (dir.empty()) return false;
    // The DACL is rewritten only for a new folder, or once per process when the grant is
    // missing — not at every save (store_files.h appContainerGrantNeeded).
    const bool created = CreateDirectoryW(dir.c_str(), nullptr) != FALSE;
    if (created || GetLastError() == ERROR_ALREADY_EXISTS) {
        const bool present = !created && !g_aclChecked && appContainerReadGranted(dir);
        if (appContainerGrantNeeded(created, g_aclChecked, present)) grantAppContainerRead(dir);
        g_aclChecked = true;
    }
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

constexpr char kAppLangPrefix[] = "AppLanguage\\";

}  // namespace

void initStorage(bool portableMode, const std::wstring& portableIni) {
    AcquireSRWLockExclusive(&g_kvLock);
    g_portable = portableMode;
    g_iniPath = portableMode ? portableIni : std::wstring();
    if (portableMode) kvLoadLocked();
    ReleaseSRWLockExclusive(&g_kvLock);
}

bool portableMode() { return g_portable; }

bool settingsStored() {
    Store st(false);
    if (!st.ok()) return false;
    std::wstring v;
    return st.string(L"switchHotkey", v);  // every saveSettings() of every version writes it
}

bool portableAppLanguage(const std::wstring& identity, bool& vietnamese) {
    if (!g_portable || identity.empty()) return false;
    Store st(false);
    uint32_t v = 0;
    if (!g_kv.getDword(kAppLangPrefix + narrow(identity), v)) return false;
    vietnamese = v != 0;
    return true;
}

void setPortableAppLanguage(const std::wstring& identity, bool vietnamese) {
    if (!g_portable || identity.empty()) return;
    const std::wstring name = widen(kAppLangPrefix) + identity;
    Store st(true);
    st.setDword(name.c_str(), vietnamese ? 1 : 0);
}

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

bool readSystemTextPrediction() {
    DWORD v = 0, sz = sizeof v;
    const bool present = RegGetValueW(HKEY_CURRENT_USER, predict::kHwkbPredictionKey, predict::kHwkbPredictionValue,
                                      RRF_RT_REG_DWORD, nullptr, &v, &sz) == ERROR_SUCCESS;
    return predict::resolveHwkbPrediction(present, v);
}

Settings loadSettings() {
    Settings s;
    s.systemTextPrediction = readSystemTextPrediction();  // Windows' own setting, not ours
    Store st(false);
    if (!st.ok()) return s;
    size_t count = 0;
    const BoolKey* keys = boolKeys(&count);
    for (size_t i = 0; i < count; ++i) {
        DWORD v;
        if (!isSystemMirror(keys[i]) && st.dword(widen(keys[i].name).c_str(), v)) s.*keys[i].field = v != 0;
    }
    std::wstring str;
    if (st.string(L"switchHotkey", str)) s.switchHotkey = narrow(str);
    if (st.string(L"menuIcon", str)) s.menuIcon = narrow(str);
    if (st.string(L"uiLanguage", str)) s.uiLanguage = narrow(str);
    if (st.string(L"addTonesHotkey", str)) s.addTonesHotkey = narrow(str);
    if (st.string(L"gameModeHotkey", str)) s.gameModeHotkey = narrow(str);
    if (st.string(L"switchIndicator", str)) s.switchIndicator = narrow(str);
    if (st.string(L"trayIconStyle", str)) s.trayIconStyle = narrow(str);
    std::string json;
    StringMap m;
    if (st.binary(L"shortcuts", json) && parseFlatJson(json, m))
        for (const auto& kv : m) s.shortcuts[utf8ToUtf16(kv.first)] = utf8ToUtf16(kv.second);
    if (st.binary(L"appModes", json) && parseFlatJson(json, m)) {
        for (const auto& kv : m) {
            AppMode mode;
            if (parseAppMode(kv.second, mode)) s.appModes[normalizeExeName(kv.first)] = mode;
        }
    }
    return s;
}

bool saveSettings(const Settings& s) {
    std::vector<uint8_t> snap;
    {
        Store st(true);
        if (!st.ok()) return false;
        size_t count = 0;
        const BoolKey* keys = boolKeys(&count);
        for (size_t i = 0; i < count; ++i)
            if (!isSystemMirror(keys[i])) st.setDword(widen(keys[i].name).c_str(), (s.*keys[i].field) ? 1 : 0);
        // Bookkeeping only (not a setting): what the snapshot says about Windows' text
        // suggestions, so a start-up after the Windows toggle changed republishes it.
        st.setDword(L"systemTextPredictionPublished", s.systemTextPrediction ? 1 : 0);
        st.setString(L"switchHotkey", widen(s.switchHotkey));
        st.setString(L"menuIcon", widen(s.menuIcon));
        st.setString(L"uiLanguage", widen(s.uiLanguage));
        st.setString(L"addTonesHotkey", widen(s.addTonesHotkey));
        st.setString(L"gameModeHotkey", widen(s.gameModeHotkey));
        st.setString(L"switchIndicator", widen(s.switchIndicator));
        st.setString(L"trayIconStyle", widen(s.trayIconStyle));
        StringMap sc;
        for (const auto& kv : s.shortcuts) sc[utf16ToUtf8(kv.first)] = utf16ToUtf8(kv.second);
        std::string j = toFlatJson(sc);
        st.setBinary(L"shortcuts", j.data(), j.size());
        StringMap am;
        for (const auto& kv : s.appModes) am[kv.first] = appModeName(kv.second);
        j = toFlatJson(am);
        st.setBinary(L"appModes", j.data(), j.size());
        if (g_portable) return true;  // no TIP to publish to (see settings_store.h)
        snap = serialize(s);
        st.setBinary(L"snapshot", snap.data(), snap.size());
    }
    return writeSnapshotFile(snap);
}

unsigned long long readQword(const wchar_t* name, unsigned long long def) {
    unsigned long long v = def;
    Store st(false);
    if (!st.ok() || !st.qword(name, v)) v = def;
    return v;
}

void writeQword(const wchar_t* name, unsigned long long v) {
    Store st(true);
    if (st.ok()) st.setQword(name, v);
}

std::wstring readString(const wchar_t* name) {
    std::wstring out;
    Store st(false);
    if (st.ok()) st.string(name, out);
    return out;
}

void writeString(const wchar_t* name, const std::wstring& v) {
    Store st(true);
    if (st.ok()) st.setString(name, v);
}

bool readFlag(const wchar_t* name) {
    DWORD v = 0;
    Store st(false);
    return st.ok() && st.dword(name, v) && v;
}

int readFlagState(const wchar_t* name) {
    DWORD v = 0;
    Store st(false);
    if (!st.ok() || !st.dword(name, v)) return -1;
    return v ? 1 : 0;
}

void writeFlag(const wchar_t* name, bool v) {
    Store st(true);
    if (st.ok()) st.setDword(name, v ? 1 : 0);
}

void eraseUserData() {
    if (g_portable) {  // never reached from the UI (no uninstaller in portable); kept total
        AcquireSRWLockExclusive(&g_kvLock);
        g_kv.clear();
        const uint64_t seq = g_kvSeq.stage();  // saves staged before this are not written
        ReleaseSRWLockExclusive(&g_kvLock);
        AcquireSRWLockExclusive(&g_kvFileLock);
        if (!g_iniPath.empty()) DeleteFileW(g_iniPath.c_str());
        g_kvSeq.done(seq);
        ReleaseSRWLockExclusive(&g_kvFileLock);
        return;
    }
    RegDeleteTreeW(HKEY_CURRENT_USER, kRoot);
    std::wstring dir = localAppDataDir();
    if (dir.empty()) return;
    // Every file VietTelex writes there, by name (store_files.h); anything else stays, and
    // so does the folder then.
    WIN32_FIND_DATAW fd;
    HANDLE find = FindFirstFileW((dir + L"\\*").c_str(), &fd);
    if (find != INVALID_HANDLE_VALUE) {
        do {
            if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && isUserDataFileName(fd.cFileName))
                DeleteFileW((dir + L"\\" + fd.cFileName).c_str());
        } while (FindNextFileW(find, &fd));
        FindClose(find);
    }
    RemoveDirectoryW(dir.c_str());
}

}  // namespace vtx::app
