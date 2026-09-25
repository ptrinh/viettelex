#include "hook_fallback.h"

#include <windows.h>

#include <string>
#include <vector>

#include "app_policy.h"
#include "breaker.h"
#include "keymap.h"
#include "session.h"
#include "settings_store.h"

namespace vtx::app {

namespace {

constexpr ULONG_PTR kInjectedMagic = 0x56545831;  // "VTX1"
constexpr LANGID kViVN = 0x042A;

struct State {
    Settings settings;
    TypingSession session;
    RateBreaker breaker;
    HWINEVENTHOOK fgHook = nullptr;
    HHOOK kbHook = nullptr;
    HHOOK mouseHook = nullptr;
    DWORD fgThread = 0;
    std::wstring fgExe;  // lowercase
    bool anyHookApps = false;
};

State* g = nullptr;

// Collects the edits a TypingSession wants and turns them into one SendInput batch.
class HookSink final : public TextSink {
public:
    std::vector<INPUT> inputs;
    std::u16string textBeforeCaret(int) override { return {}; }  // unreadable from here
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
    HKL hkl = GetKeyboardLayout(g->fgThread);
    if (LOWORD(reinterpret_cast<ULONG_PTR>(hkl)) != kViVN) return false;
    // …and the app in Vietnamese mode (per-app memory the TIP maintains).
    DWORD v = 1, sz = sizeof v;
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\VietTelex\\AppLanguage", g->fgExe.c_str(), RRF_RT_REG_DWORD, nullptr,
                 &v, &sz);
    return v != 0;
}

bool isInjectedByUs(ULONG_PTR extra) { return extra == kInjectedMagic; }

LRESULT CALLBACK keyboardProc(int code, WPARAM wp, LPARAM lp) {
    if (code != HC_ACTION || !g) return CallNextHookEx(nullptr, code, wp, lp);
    const auto* kb = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lp);
    if (isInjectedByUs(kb->dwExtraInfo)) return CallNextHookEx(nullptr, code, wp, lp);
    const bool down = wp == WM_KEYDOWN || wp == WM_SYSKEYDOWN;
    if (!down) return CallNextHookEx(nullptr, code, wp, lp);
    if (kb->flags & LLKHF_INJECTED) {  // someone else's synthetic input: do not compose over it
        g->session.reset();
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
    if (!g->session.wordActive() && !foregroundVietnamese()) return CallNextHookEx(nullptr, code, wp, lp);
    if (!g->session.wantsKey(k)) return CallNextHookEx(nullptr, code, wp, lp);

    HookSink sink;
    bool eaten = g->session.handleKey(k, sink);
    if (sink.inputs.empty()) return eaten ? 1 : CallNextHookEx(nullptr, code, wp, lp);
    // Edits + a key that should still reach the app: the key must come AFTER our
    // edits, so swallow it and replay it at the end of the batch.
    if (!eaten) {
        if (k.kind == KeyKind::Char) sink.addUnicode(static_cast<char16_t>(k.ch));
        else sink.addVk(static_cast<WORD>(kb->vkCode));
    }
    if (!g->breaker.allow(GetTickCount64(), static_cast<uint32_t>(sink.inputs.size()))) {
        g->session.reset();
        return CallNextHookEx(nullptr, code, wp, lp);
    }
    SendInput(static_cast<UINT>(sink.inputs.size()), sink.inputs.data(), sizeof(INPUT));
    return 1;
}

LRESULT CALLBACK mouseProc(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION && g && (wp == WM_LBUTTONDOWN || wp == WM_RBUTTONDOWN || wp == WM_MBUTTONDOWN))
        g->session.reset();  // caret probably moved
    return CallNextHookEx(nullptr, code, wp, lp);
}

void installInputHooks(bool on) {
    if (on && !g->kbHook) {
        HINSTANCE inst = GetModuleHandleW(nullptr);
        g->kbHook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardProc, inst, 0);
        g->mouseHook = SetWindowsHookExW(WH_MOUSE_LL, mouseProc, inst, 0);
    } else if (!on && g->kbHook) {
        UnhookWindowsHookEx(g->kbHook);
        if (g->mouseHook) UnhookWindowsHookEx(g->mouseHook);
        g->kbHook = g->mouseHook = nullptr;
    }
    g->session.resetContext();
}

void onForeground(HWND hwnd) {
    if (!g || !hwnd) return;
    DWORD tid = 0;
    g->fgExe = exeOfWindow(hwnd, &tid);
    g->fgThread = tid;
    const AppMode mode = resolveAppMode(narrow(g->fgExe), g->settings.appModes);
    installInputHooks(mode == AppMode::HookFallback);
}

void CALLBACK winEventProc(HWINEVENTHOOK, DWORD event, HWND hwnd, LONG idObject, LONG, DWORD, DWORD) {
    if (event == EVENT_SYSTEM_FOREGROUND && idObject == OBJID_WINDOW) onForeground(hwnd);
}

}  // namespace

void hookConfigure(const Settings& s) {
    if (!g) g = new State();
    g->settings = s;
    SessionOptions o;
    o.engineFlags = s.engineFlags();
    o.autoRestore = s.autoRestore;
    o.reEditWord = false;  // cannot read the app's text from here
    o.shortcuts = &g->settings.shortcuts;
    g->session.configure(o);
    g->session.setOutputMode(OutputMode::InPlace);

    g->anyHookApps = false;
    for (const auto& kv : s.appModes)
        if (kv.second == AppMode::HookFallback) g->anyHookApps = true;

    if (g->anyHookApps && !g->fgHook) {
        g->fgHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, winEventProc, 0, 0,
                                    WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    } else if (!g->anyHookApps && g->fgHook) {
        UnhookWinEvent(g->fgHook);
        g->fgHook = nullptr;
    }
    if (g->anyHookApps) onForeground(GetForegroundWindow());
    else installInputHooks(false);
}

void hookShutdown() {
    if (!g) return;
    installInputHooks(false);
    if (g->fgHook) UnhookWinEvent(g->fgHook);
    delete g;
    g = nullptr;
}

}  // namespace vtx::app
