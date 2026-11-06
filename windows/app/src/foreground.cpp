#include "foreground.h"

#include <atomic>
#include <vector>

#include "app_language.h"
#include "app_policy.h"
#include "debug_file.h"
#include "direct_policy.h"
#include "input_switch.h"
#include "portable.h"
#include "settings_store.h"

namespace vtx::app {

namespace {
constexpr wchar_t kRegAppLang[] = L"Software\\VietTelex\\AppLanguage";
constexpr unsigned kViVN = 0x042A;
std::atomic<bool> g_logging{false};
std::atomic<bool> g_portableDefaultVi{true};  // portable: !Settings::startEnglish
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

int fgTipProp(HWND fg) {
    HWND root = fg ? GetAncestor(fg, GA_ROOT) : nullptr;
    return root ? static_cast<int>(reinterpret_cast<INT_PTR>(GetPropW(root, kTipLangProp))) : 0;
}

unsigned fgLangId(const FgApp& app) {
    return app.tid ? LOWORD(reinterpret_cast<ULONG_PTR>(GetKeyboardLayout(app.tid))) : 0;
}

bool fgVietnamese(HWND fg, const FgApp& app) {
    const int prop = fgTipProp(fg);
    const unsigned lang = fgLangId(app);
    // Portable: no TIP of its own. Vietnamese = not yielding to a Vietnamese keyboard there
    // (core/portable.h yields) + this app's remembered state.
    if (portableMode())
        return !portable::yields(prop, lang) && !focusedPasswordField(app.tid) && storedVietnamese(app.identity);
    return foregroundLanguage(prop, app.console, lang == kViVN, storedVietnamese(app.identity));
}

void setPortableDefaultVietnamese(bool on) { g_portableDefaultVi.store(on); }

bool focusedPasswordField(DWORD tid) {
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    if (!tid || !GetGUIThreadInfo(tid, &gi) || !gi.hwndFocus) return false;
    char cls[64] = {};
    GetClassNameA(gi.hwndFocus, cls, sizeof cls);
    return portable::isPasswordField(cls, static_cast<uint32_t>(GetWindowLongW(gi.hwndFocus, GWL_STYLE)));
}

bool storedVietnamese(const std::wstring& identity) {
    if (portableMode()) {
        bool on = g_portableDefaultVi.load();
        portableAppLanguage(identity, on);
        return on;
    }
    DWORD v = 1, sz = sizeof v;
    if (!identity.empty())
        RegGetValueW(HKEY_CURRENT_USER, kRegAppLang, identity.c_str(), RRF_RT_REG_DWORD, nullptr, &v, &sz);
    return v != 0;
}

void storeVietnamese(const std::wstring& identity, bool on) {
    if (identity.empty()) return;
    if (portableMode()) return setPortableAppLanguage(identity, on);
    HKEY k;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegAppLang, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr) !=
        ERROR_SUCCESS)
        return;
    DWORD v = on ? 1 : 0;
    RegSetValueExW(k, identity.c_str(), 0, REG_DWORD, reinterpret_cast<const BYTE*>(&v), sizeof v);
    RegCloseKey(k);
}

void mirrorAppLanguage() {
    if (portableMode()) return;  // no TIP reads it; never overwrite the installed build's mirror
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

bool activateVietTelexForChord(SwitchHotkey hotkey, bool suspended) {
    HWND fg = GetForegroundWindow();
    if (!fg) return false;
    HWND root = GetAncestor(fg, GA_ROOT);
    const int prop = root ? static_cast<int>(reinterpret_cast<INT_PTR>(GetPropW(root, kTipLangProp))) : 0;
    const FgApp app = describeWindow(fg);
    const unsigned lang = LOWORD(reinterpret_cast<ULONG_PTR>(GetKeyboardLayout(app.tid)));
    if (foreignChordAction(hotkey, prop, lang, suspended) != ForeignChord::ActivateVietTelex) return false;
    HKL list[64];
    const int n = GetKeyboardLayoutList(64, list);
    uintptr_t raw[64];
    for (int i = 0; i < n; ++i) raw[i] = reinterpret_cast<uintptr_t>(list[i]);
    const uintptr_t vi = pickVietnameseHkl(raw, n > 0 ? static_cast<size_t>(n) : 0);
    if (!vi) {
        appLog("app", "Ctrl+Shift on another keyboard: no Vietnamese input language in the list");
        return false;
    }
    // The TIP reads the per-app Việt/Anh memory when it activates: the user pressed the
    // switch key to TYPE VIETNAMESE, so land in Việt (not a stale "Anh" for this app).
    storeVietnamese(app.identity, true);
    mirrorAppLanguage();
    // What the taskbar language indicator does: ask the focused window to change its input
    // language; DefWindowProc activates it (WM_INPUTLANGCHANGEREQUEST, learn.microsoft.com
    // winmsg/wm-inputlangchangerequest). Per thread, so "different input method for each
    // app window" keeps working. UIPI drops it for an elevated app (nothing happens).
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    HWND target = (app.tid && GetGUIThreadInfo(app.tid, &gi) && gi.hwndFocus) ? gi.hwndFocus : fg;
    const bool posted = PostMessageW(target, WM_INPUTLANGCHANGEREQUEST, 0, static_cast<LPARAM>(vi)) != FALSE;
    if (appLogging())
        appLog("app", "Ctrl+Shift on another keyboard (lang " + std::to_string(lang) + ") in " +
                          narrowAscii(app.identity) + ": requested the Vietnamese input language" +
                          (posted ? "" : " (post failed)"));
    return posted;
}

void appSetLogging(bool on) { g_logging.store(on); }
bool appLogging() { return g_logging.load(); }
void appLog(const char* component, const std::string& msg) {
    if (g_logging.load()) debugFileWrite(component, msg);
}

}  // namespace vtx::app
