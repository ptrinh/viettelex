#include "hook_fallback.h"

#include <windows.h>

#include <memory>
#include <set>
#include <string>
#include <vector>

#include "app_policy.h"
#include "breaker.h"
#include "hook_watchdog.h"
#include "keymap.h"
#include "session.h"
#include "settings_store.h"
#include "setup_helper_logic.h"

// Hook threading (1.1.3). The low-level hooks live on their OWN high-priority thread with
// its own message loop, so a busy UI thread (Settings window, dialogs) can never push the
// hook past LowLevelHooksTimeout — after which Windows silently removes it. A watchdog on
// the same thread compares raw input against the hook and reinstalls it if it died
// (hook_watchdog.h). The UI thread only posts commands (install/uninstall, settings,
// foreground app) to the hook thread; all typing state is owned by the hook thread.

namespace vtx::app {

namespace {

constexpr LANGID kViVN = 0x042A;
enum : UINT {
    kCmdConfig = WM_APP + 1,   // lParam: Settings* (hook thread owns it)
    kCmdForeground,            // wParam: install (0/1), lParam: std::wstring* exe; tid in hookTid
    kCmdQuit,
};

// ---------------------------------------------------------------- hook-thread state
struct HookState {
    Settings settings;
    TypingSession session;
    RateBreaker breaker;
    HookWatchdog watchdog;
    HHOOK kbHook = nullptr;
    HHOOK mouseHook = nullptr;
    HWND sink = nullptr;       // message-only window: raw input for the watchdog
    DWORD fgThread = 0;
    std::wstring fgExe;        // lowercase
    bool wanted = false;       // hooks should be installed
};
HookState* h = nullptr;        // hook thread only
DWORD g_hookTid = 0;
HANDLE g_hookThread = nullptr;
HANDLE g_hookReady = nullptr;

// ---------------------------------------------------------------- UI-thread state
struct UiState {
    Settings settings;
    HWINEVENTHOOK fgHook = nullptr;
    bool directFromTip = false;  // TIP asked for direct mode for the current field
    std::wstring fgExe;
    DWORD fgThread = 0;
};
UiState* u = nullptr;
void (*g_elevationNotify)(const std::wstring&) = nullptr;
std::set<std::wstring> g_warnedExes;

// Collects the edits a TypingSession wants and turns them into ONE SendInput batch:
// backspaces first, then the text — SendInput inserts the whole array atomically, so a
// user key can never land between them (OpenKey batches the same way).
class HookSink final : public TextSink {
public:
    std::vector<INPUT> inputs;
    bool blind() override { return true; }  // nothing can be read back from here
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) override {
        for (size_t i = 0; i < expect.size(); ++i) addVk(VK_BACK);
        for (char16_t c : insert) addUnicode(c);
        return true;
    }
    bool compositionActive() override { return false; }
    bool setComposition(const std::u16string&, int) override { return false; }
    void endComposition(const std::u16string&) override {}
    void endCompositionAsIs() override {}

    void addVk(WORD vkey) {
        INPUT in[2] = {};
        for (int i = 0; i < 2; ++i) {
            in[i].type = INPUT_KEYBOARD;
            in[i].ki.wVk = vkey;
            in[i].ki.dwFlags = i ? KEYEVENTF_KEYUP : 0;
            in[i].ki.dwExtraInfo = kInjectedMagic;
            inputs.push_back(in[i]);
        }
    }
    void addUnicode(char16_t c) {
        INPUT in[2] = {};
        for (int i = 0; i < 2; ++i) {
            in[i].type = INPUT_KEYBOARD;
            in[i].ki.wScan = static_cast<WORD>(c);
            in[i].ki.dwFlags = KEYEVENTF_UNICODE | (i ? KEYEVENTF_KEYUP : 0);
            in[i].ki.dwExtraInfo = kInjectedMagic;
            inputs.push_back(in[i]);
        }
    }
};

std::wstring exeOfWindow(HWND hwnd, DWORD* tid) {
    DWORD pid = 0;
    *tid = GetWindowThreadProcessId(hwnd, &pid);
    std::wstring out;
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return out;
    wchar_t buf[MAX_PATH];
    DWORD n = MAX_PATH;
    if (QueryFullProcessImageNameW(p, 0, buf, &n)) {
        std::wstring path(buf, n);
        size_t slash = path.find_last_of(L"\\/");
        out = slash == std::wstring::npos ? path : path.substr(slash + 1);
        for (wchar_t& c : out)
            if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
    }
    CloseHandle(p);
    return out;
}

bool foregroundVietnamese() {
    // Our TIP (vi-VN profile) must be the active input method of that thread…
    HKL hkl = GetKeyboardLayout(h->fgThread);
    if (LOWORD(reinterpret_cast<ULONG_PTR>(hkl)) != kViVN) return false;
    // …and the app in Vietnamese mode (per-app memory the TIP maintains).
    DWORD v = 1, sz = sizeof v;
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\VietTelex\\AppLanguage", h->fgExe.c_str(), RRF_RT_REG_DWORD,
                 nullptr, &v, &sz);
    return v != 0;
}

LRESULT CALLBACK keyboardProc(int code, WPARAM wp, LPARAM lp) {
    if (code != HC_ACTION || !h) return CallNextHookEx(nullptr, code, wp, lp);
    const auto* kb = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lp);
    if (isOwnInjected(kb->dwExtraInfo)) return CallNextHookEx(nullptr, code, wp, lp);  // never re-process ours
    h->watchdog.lowLevelKey(GetTickCount64());
    const bool down = wp == WM_KEYDOWN || wp == WM_SYSKEYDOWN;
    if (!down) return CallNextHookEx(nullptr, code, wp, lp);
    if (kb->flags & LLKHF_INJECTED) {  // someone else's synthetic input: do not compose over it
        h->session.reset();
        return CallNextHookEx(nullptr, code, wp, lp);
    }
    Modifiers m;
    m.shift = GetAsyncKeyState(VK_SHIFT) < 0;
    m.ctrl = GetAsyncKeyState(VK_CONTROL) < 0;
    m.alt = GetAsyncKeyState(VK_MENU) < 0;
    m.win = GetAsyncKeyState(VK_LWIN) < 0 || GetAsyncKeyState(VK_RWIN) < 0;
    m.capsLock = (GetKeyState(VK_CAPITAL) & 1) != 0;
    KeyInput k = classifyKey(kb->vkCode, m);
    if (k.kind == KeyKind::Modifier || k.kind == KeyKind::Other) return CallNextHookEx(nullptr, code, wp, lp);
    if (!h->session.wordActive() && !foregroundVietnamese()) return CallNextHookEx(nullptr, code, wp, lp);
    if (!h->session.wantsKey(k)) return CallNextHookEx(nullptr, code, wp, lp);

    HookSink sink;
    bool eaten = h->session.handleKey(k, sink);
    if (sink.inputs.empty()) return eaten ? 1 : CallNextHookEx(nullptr, code, wp, lp);
    // Edits + a key that should still reach the app: the key must come AFTER our
    // edits, so swallow it and replay it at the end of the batch.
    if (!eaten) {
        if (k.kind == KeyKind::Char) sink.addUnicode(static_cast<char16_t>(k.ch));
        else sink.addVk(static_cast<WORD>(kb->vkCode));
    }
    if (!h->breaker.allow(GetTickCount64(), static_cast<uint32_t>(sink.inputs.size()))) {
        h->session.reset();
        return CallNextHookEx(nullptr, code, wp, lp);
    }
    SendInput(static_cast<UINT>(sink.inputs.size()), sink.inputs.data(), sizeof(INPUT));
    return 1;
}

LRESULT CALLBACK mouseProc(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION && h && (wp == WM_LBUTTONDOWN || wp == WM_RBUTTONDOWN || wp == WM_MBUTTONDOWN))
        h->session.reset();  // caret probably moved
    return CallNextHookEx(nullptr, code, wp, lp);
}

void removeHooks() {
    if (h->kbHook) UnhookWindowsHookEx(h->kbHook);
    if (h->mouseHook) UnhookWindowsHookEx(h->mouseHook);
    h->kbHook = h->mouseHook = nullptr;
}

void installHooks() {
    removeHooks();
    HINSTANCE inst = GetModuleHandleW(nullptr);
    h->kbHook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardProc, inst, 0);
    h->mouseHook = SetWindowsHookExW(WH_MOUSE_LL, mouseProc, inst, 0);
    h->watchdog.hookInstalled(GetTickCount64());
}

void applyWanted(bool on) {
    if (on == h->wanted && (!on || h->kbHook)) return;
    h->wanted = on;
    if (on) installHooks();
    else removeHooks();
    h->watchdog.setActive(on, GetTickCount64());
    h->session.resetContext();
}

void configureSession(const Settings& s) {
    h->settings = s;
    SessionOptions o;
    o.engineFlags = s.engineFlags();
    o.autoRestore = s.autoRestore;
    o.reEditWord = false;  // cannot read the app's text from here
    o.shortcuts = &h->settings.shortcuts;
    h->session.configure(o);
    h->session.setOutputMode(OutputMode::InPlace);
}

LRESULT CALLBACK sinkProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_INPUT && h && h->wanted) {
        RAWINPUT ri;
        UINT sz = sizeof ri;
        if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lp), RID_INPUT, &ri, &sz, sizeof(RAWINPUTHEADER)) != UINT(-1) &&
            ri.header.dwType == RIM_TYPEKEYBOARD && !(ri.data.keyboard.Flags & RI_KEY_BREAK)) {
            // Raw input sees every key; if the LL hook has not for a while, Windows removed it.
            if (h->watchdog.rawKey(GetTickCount64())) installHooks();
        }
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

DWORD WINAPI hookThreadMain(void*) {
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
    h = new HookState();
    WNDCLASSW wc = {};
    wc.lpfnWndProc = sinkProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"VietTelexHookSink";
    RegisterClassW(&wc);
    h->sink = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
    if (h->sink) {
        RAWINPUTDEVICE rid = {};
        rid.usUsagePage = 0x01;  // generic desktop
        rid.usUsage = 0x06;      // keyboard
        rid.dwFlags = RIDEV_INPUTSINK;
        rid.hwndTarget = h->sink;
        RegisterRawInputDevices(&rid, 1, sizeof rid);
    }
    MSG msg;
    PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);  // create the queue
    SetEvent(g_hookReady);
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (msg.hwnd == nullptr) {
            switch (msg.message) {
                case kCmdConfig: {
                    std::unique_ptr<Settings> s(reinterpret_cast<Settings*>(msg.lParam));
                    configureSession(*s);
                    break;
                }
                case kCmdForeground: {
                    std::unique_ptr<std::wstring> exe(reinterpret_cast<std::wstring*>(msg.lParam));
                    h->fgExe = *exe;
                    h->fgThread = static_cast<DWORD>(msg.wParam >> 1);
                    applyWanted((msg.wParam & 1) != 0);
                    break;
                }
                case kCmdQuit: PostQuitMessage(0); break;
                default: break;
            }
            continue;
        }
        DispatchMessageW(&msg);
    }
    removeHooks();
    if (h->sink) DestroyWindow(h->sink);
    delete h;
    h = nullptr;
    return 0;
}

void ensureHookThread() {
    if (g_hookThread) return;
    g_hookReady = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    g_hookThread = CreateThread(nullptr, 0, hookThreadMain, nullptr, 0, &g_hookTid);
    if (g_hookThread && g_hookReady) WaitForSingleObject(g_hookReady, 2000);
}

// ---------------------------------------------------------------- UI thread
// Mandatory integrity RID of a process (0x2000 medium, 0x3000 high). False = unreadable.
bool integrityOf(HANDLE process, DWORD& rid) {
    HANDLE tok = nullptr;
    if (!OpenProcessToken(process, TOKEN_QUERY, &tok)) return false;
    BYTE buf[128];
    DWORD len = 0;
    bool ok = GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof buf, &len);
    if (ok) {
        auto* til = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf);
        rid = *GetSidSubAuthority(til->Label.Sid, *GetSidSubAuthorityCount(til->Label.Sid) - 1);
    }
    CloseHandle(tok);
    return ok;
}

void publishForeground() {
    const AppMode mode = resolveAppMode(narrow(u->fgExe), u->settings.appModes);
    const bool hookOn = hookTypes(mode) || u->directFromTip;
    ensureHookThread();
    // wParam = (tid << 1) | install
    PostThreadMessageW(g_hookTid, kCmdForeground, (static_cast<WPARAM>(u->fgThread) << 1) | (hookOn ? 1 : 0),
                       reinterpret_cast<LPARAM>(new std::wstring(u->fgExe)));
    if (hookOn && g_elevationNotify && !u->fgExe.empty()) {
        HWND fg = GetForegroundWindow();
        DWORD pid = 0, fgRid = 0, ourRid = 0x2000;
        if (fg) GetWindowThreadProcessId(fg, &pid);
        bool known = false;
        if (HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
            known = integrityOf(p, fgRid);
            CloseHandle(p);
        }
        integrityOf(GetCurrentProcess(), ourRid);
        if (hookNeedsElevationWarning(true, known, fgRid, ourRid, g_warnedExes.count(u->fgExe) != 0)) {
            g_warnedExes.insert(u->fgExe);
            g_elevationNotify(u->fgExe);
        }
    }
}

void onForeground(HWND hwnd) {
    if (!u || !hwnd) return;
    DWORD tid = 0;
    u->fgExe = exeOfWindow(hwnd, &tid);
    u->fgThread = tid;
    u->directFromTip = false;  // a new window: the TIP re-evaluates its field
    publishForeground();
}

void CALLBACK winEventProc(HWINEVENTHOOK, DWORD event, HWND hwnd, LONG idObject, LONG, DWORD, DWORD) {
    if (event == EVENT_SYSTEM_FOREGROUND && idObject == OBJID_WINDOW) onForeground(hwnd);
}

}  // namespace

void hookConfigure(const Settings& s) {
    if (!u) u = new UiState();
    u->settings = s;
    ensureHookThread();
    PostThreadMessageW(g_hookTid, kCmdConfig, 0, reinterpret_cast<LPARAM>(new Settings(s)));
    // Always watch the foreground: built-in Direct rules (consoles, terminals) exist.
    if (!u->fgHook)
        u->fgHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, winEventProc, 0, 0,
                                    WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    onForeground(GetForegroundWindow());
}

void hookSetDirectFromTip(bool on) {
    if (!u || u->directFromTip == on) return;
    u->directFromTip = on;
    publishForeground();
}

void hookSetElevationNotifier(void (*notify)(const std::wstring& exe)) { g_elevationNotify = notify; }

void hookShutdown() {
    if (u && u->fgHook) UnhookWinEvent(u->fgHook);
    if (g_hookThread) {
        PostThreadMessageW(g_hookTid, kCmdQuit, 0, 0);
        WaitForSingleObject(g_hookThread, 2000);
        CloseHandle(g_hookThread);
        g_hookThread = nullptr;
    }
    if (g_hookReady) CloseHandle(g_hookReady);
    g_hookReady = nullptr;
    delete u;
    u = nullptr;
}

}  // namespace vtx::app
