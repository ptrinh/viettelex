#include "foreground.h"

#include <atomic>
#include <vector>

#include "app_language.h"
#include "app_policy.h"
#include "debug_file.h"
#include "direct_policy.h"

namespace vtx::app {

namespace {
constexpr wchar_t kRegAppLang[] = L"Software\\VietTelex\\AppLanguage";
constexpr unsigned kViVN = 0x042A;
std::atomic<bool> g_logging{false};
}  // namespace

std::string narrowAscii(const std::wstring& w) {
    std::string s;
    for (wchar_t c : w) {
        if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
        s.push_back(c < 0x80 ? static_cast<char>(c) : '_');
    }
    return s;
}

FgApp describeWindow(HWND hwnd) {
    FgApp a;
    if (!hwnd) return a;
    a.tid = GetWindowThreadProcessId(hwnd, &a.pid);
    wchar_t cls[128] = {};
    GetClassNameW(hwnd, cls, 128);
    for (const wchar_t* p = cls; *p; ++p) a.windowClass.push_back(*p < 0x80 ? static_cast<char>(*p) : '_');
    std::wstring exe;
    if (HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, a.pid)) {
        wchar_t buf[MAX_PATH];
        DWORD n = MAX_PATH;
        if (QueryFullProcessImageNameW(p, 0, buf, &n)) {
            exe.assign(buf, n);
            exe = exe.substr(exe.find_last_of(L"\\/") + 1);
        }
        CloseHandle(p);
    }
    a.console = isConsoleWindowClass(a.windowClass);
    const std::string id = hostIdentity(a.windowClass, narrowAscii(exe));
    a.identity.assign(id.begin(), id.end());
    return a;
}

bool fgVietnamese(HWND fg, const FgApp& app) {
    HWND root = fg ? GetAncestor(fg, GA_ROOT) : nullptr;
    const int prop = root ? static_cast<int>(reinterpret_cast<INT_PTR>(GetPropW(root, kTipLangProp))) : 0;
    const bool hkl = LOWORD(reinterpret_cast<ULONG_PTR>(GetKeyboardLayout(app.tid))) == kViVN;
    return foregroundLanguage(prop, app.console, hkl, storedVietnamese(app.identity));
}

bool storedVietnamese(const std::wstring& identity) {
    DWORD v = 1, sz = sizeof v;
    if (!identity.empty())
        RegGetValueW(HKEY_CURRENT_USER, kRegAppLang, identity.c_str(), RRF_RT_REG_DWORD, nullptr, &v, &sz);
    return v != 0;
}

void storeVietnamese(const std::wstring& identity, bool on) {
    if (identity.empty()) return;
    HKEY k;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegAppLang, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) !=
        ERROR_SUCCESS)
        return;
    DWORD v = on ? 1 : 0;
    RegSetValueExW(k, identity.c_str(), 0, REG_DWORD, reinterpret_cast<const BYTE*>(&v), sizeof v);
    RegCloseKey(k);
}

void mirrorAppLanguage() {
    AppLanguageStore store;
    HKEY k;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegAppLang, 0, KEY_QUERY_VALUE, &k) == ERROR_SUCCESS) {
        for (DWORD i = 0;; ++i) {
            wchar_t name[260];
            DWORD nameLen = 260, type = 0, v = 0, sz = sizeof v;
            if (RegEnumValueW(k, i, name, &nameLen, nullptr, &type, reinterpret_cast<BYTE*>(&v), &sz) != ERROR_SUCCESS)
                break;
            if (type == REG_DWORD) store.set(narrowAscii(std::wstring(name, nameLen)), v != 0);
        }
        RegCloseKey(k);
    }
    wchar_t buf[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return;
    const std::wstring dir = std::wstring(buf) + L"\\VietTelex";
    CreateDirectoryW(dir.c_str(), nullptr);  // ACL (AppContainer read) set by settings_store
    const std::wstring tmp = dir + L"\\applang.txt.tmp", dst = dir + L"\\applang.txt";
    const std::string text = store.serialize();
    HANDLE f = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    DWORD wrote = 0;
    const bool ok = WriteFile(f, text.data(), static_cast<DWORD>(text.size()), &wrote, nullptr) && wrote == text.size();
    CloseHandle(f);
    if (ok) MoveFileExW(tmp.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING);
    else DeleteFileW(tmp.c_str());
}

void appSetLogging(bool on) { g_logging.store(on); }
bool appLogging() { return g_logging.load(); }
void appLog(const char* component, const std::string& msg) {
    if (g_logging.load()) debugFileWrite(component, msg);
}

}  // namespace vtx::app
