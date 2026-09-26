#include "hook_fallback.h"

#include <windows.h>

#include <memory>
#include <set>
#include <string>
#include <vector>

#include "app_policy.h"
#include "breaker.h"
#include "direct_policy.h"
#include "direct_verify.h"
#include "foreground.h"
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

enum : UINT {
    kCmdConfig = WM_APP + 1,   // lParam: Settings* (hook thread owns it)
    kCmdForeground,            // lParam: Foreground* (hook thread owns it)
    kCmdDisableHere,           // Direct proved unusable in the current field: stop hooking
    kCmdQuit,
};

// ---------------------------------------------------------------- hook-thread state
struct Foreground {
    FgApp app;
    std::wstring exe;
    DWORD tid = 0;
    HWND hwnd = nullptr;
    bool install = false;
    bool direct = false;  // Direct mode (verify echo) vs explicit hookFallback
    bool fresh = false;   // a foreground change (not a mid-focus re-publish)
};

struct HookState {
    Settings settings;
    TypingSession session;
    RateBreaker breaker;
    HookWatchdog watchdog;
    HHOOK kbHook = nullptr;
    HHOOK mouseHook = nullptr;
    HWND sink = nullptr;       // message-only window: raw input for the watchdog
    DWORD fgThread = 0;
    HWND fgHwnd = nullptr;     // window the hooked typing belongs to
    std::wstring fgExe;        // lowercase
    bool wanted = false;       // hooks should be installed
    bool direct = false;
    FgApp app;
    HookArming arming;
    HWND ackHwnd = nullptr;    // window carrying kDirectOnProp (the TIP stays out there)
    uint64_t editSeq = 0;      // bumps on every injected edit (echo checks use the latest)
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
    FgApp fgApp;
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
    unsigned backspaces = 0, units = 0;
    bool blind() override { return true; }  // nothing can be read back from here
    std::u16string textBeforeCaret(int) override { return {}; }
    char16_t charAfterCaret() override { return 0; }
    bool hasSelection() override { return false; }
    bool replaceBeforeCaret(const std::u16string& expect, const std::u16string& insert) override {
        for (size_t i = 0; i < expect.size(); ++i) addVk(VK_BACK);
        for (char16_t c : insert) addUnicode(c);
        backspaces += static_cast<unsigned>(expect.size());
        units += static_cast<unsigned>(insert.size());
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
            // A real key event: scan code included (console readers look at it).
            in[i].ki.wScan = static_cast<WORD>(MapVirtualKeyW(vkey, MAPVK_VK_TO_VSC));
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

// The VietTelex keyboard is the foreground app's input method and it is in Vietnamese
// (the TIP's kTipLangProp first — the only truth for consoles; see foreground.h).
bool foregroundVietnamese() { return fgVietnamese(h->fgHwnd, h->app); }

void markNoDirect(DWORD tid, const char* why);

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
    // Engaged mid-focus: the TIP may be composing this word — start at the next boundary.
    const bool boundary = k.kind == KeyKind::Boundary || k.kind == KeyKind::Navigation || k.kind == KeyKind::Chord ||
                          (k.kind == KeyKind::Char && k.ch == U' ');
    if (!h->arming.key(boundary)) return CallNextHookEx(nullptr, code, wp, lp);
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
    // Focus moved between the key and the injection: the edit belongs to another
    // window now — drop it, reset the word, let the key go.
    if (!injectionAllowed(reinterpret_cast<uintptr_t>(GetForegroundWindow()), reinterpret_cast<uintptr_t>(h->fgHwnd),
                          false)) {
        h->session.reset();
        appLog("hook", "foreground changed before injection: edit dropped, word reset");
        return CallNextHookEx(nullptr, code, wp, lp);
    }
    const UINT total = static_cast<UINT>(sink.inputs.size());
    const UINT sent = SendInput(total, sink.inputs.data(), sizeof(INPUT));
    const SendOutcome out = classifySend(sent, total);
    if (appLogging())
        appLog("hook", "SendInput " + std::to_string(sent) + "/" + std::to_string(total) + " events (" +
                           std::to_string(sink.backspaces) + " backspaces, " + std::to_string(sink.units) +
                           " units) key class " + std::to_string(static_cast<int>(k.kind)));
    if (out != SendOutcome::Ok) {
        // Blocked (UIPI, secure input) or cut short: the screen is unknown. This field
        // goes to composition (TIP) for the rest of the focus.
        h->session.reset();
        markNoDirect(h->fgThread, "SendInput refused");
        PostThreadMessageW(g_hookTid, kCmdDisableHere, 0, 0);
        return out == SendOutcome::NothingSent ? CallNextHookEx(nullptr, code, wp, lp) : 1;
    }
    if (h->direct && h->session.wordActive())
        directVerifyAfterEdit(h->fgHwnd, h->fgThread, h->session.shown(), ++h->editSeq);
    return 1;
}

LRESULT CALLBACK mouseProc(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION && h && (wp == WM_LBUTTONDOWN || wp == WM_RBUTTONDOWN || wp == WM_MBUTTONDOWN)) {
        h->session.reset();  // caret probably moved
        h->arming.click();
    }
    return CallNextHookEx(nullptr, code, wp, lp);
}

// Marks the focused field of `tid` NoDirect (the TIP composes there) and logs it.
void markNoDirect(DWORD tid, const char* why) {
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    HWND field = (tid && GetGUIThreadInfo(tid, &gi)) ? gi.hwndFocus : nullptr;
    if (!field) field = h ? h->fgHwnd : nullptr;
    if (field) SetPropW(field, kNoDirectProp, reinterpret_cast<HANDLE>(1));
    if (h && h->fgHwnd && field != h->fgHwnd) SetPropW(h->fgHwnd, kNoDirectProp, reinterpret_cast<HANDLE>(1));
    directLog(std::string("direct mode -> composition for this field: ") + why);
}

// kDirectOnProp: the TIP stays out of a window only while this is set (handover ack).
void setAck(HWND w) {
    if (h->ackHwnd == w) return;
    if (h->ackHwnd) RemovePropW(h->ackHwnd, kDirectOnProp);
    h->ackHwnd = w;
    if (w) SetPropW(w, kDirectOnProp, reinterpret_cast<HANDLE>(1));
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
                    std::unique_ptr<Foreground> f(reinterpret_cast<Foreground*>(msg.lParam));
                    const bool wasEngaged = h->wanted && h->fgHwnd == f->hwnd;
                    h->fgExe = f->exe;
                    h->app = f->app;
                    h->fgThread = f->tid;
                    h->fgHwnd = f->hwnd;
                    h->direct = f->direct;
                    applyWanted(f->install);
                    const bool typing = f->install && f->direct;
                    HWND root = f->hwnd ? GetAncestor(f->hwnd, GA_ROOT) : nullptr;
                    setAck(typing ? root : nullptr);
                    if (!f->install) h->arming.disengaged();
                    else if (!wasEngaged) h->arming.engaged(f->fresh);  // same window: keep state
                    break;
                }
                case kCmdDisableHere:
                    applyWanted(false);
                    setAck(nullptr);
                    h->arming.disengaged();
                    appLog("hook", "stopped for this field (Direct fell back to composition)");
                    break;
                case kCmdQuit: PostQuitMessage(0); break;
                default: break;
            }
            continue;
        }
        DispatchMessageW(&msg);
    }
    removeHooks();
    setAck(nullptr);
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

bool processIntegrity(DWORD pid, DWORD& rid) {
    bool known = false;
    if (HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
        known = integrityOf(p, rid);
        CloseHandle(p);
    }
    return known;
}

void publishForeground(bool fresh) {
    const AppMode mode = resolveAppMode(narrow(u->fgExe), u->settings.appModes);
    HWND fg = GetForegroundWindow();
    DWORD pid = 0, fgRid = 0, ourRid = 0x2000;
    if (fg) GetWindowThreadProcessId(fg, &pid);
    const bool known = processIntegrity(pid, fgRid);
    integrityOf(GetCurrentProcess(), ourRid);
    const bool direct = mode == AppMode::Direct || u->directFromTip;
    bool hookOn = mode == AppMode::HookFallback || direct;
    const char* why = hookOn ? "rule/handover" : "no hook rule";
    // A field already marked NoDirect keeps composing. A console's reported thread is
    // cmd's (no GUI info): check the window itself too.
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    HWND field = (u->fgThread && GetGUIThreadInfo(u->fgThread, &gi) && gi.hwndFocus) ? gi.hwndFocus : fg;
    if (direct && ((field && GetPropW(field, kNoDirectProp)) || (fg && GetPropW(fg, kNoDirectProp)))) {
        hookOn = false;
        why = "field marked NoDirect";
    }
    // UIPI: SendInput cannot reach a higher-integrity app. Direct simply does not run
    // there — the TIP (in-process) composes instead. Explicit hookFallback apps get the
    // one-time notice, since nothing else types for them.
    if (hookOn && !directUsable(known, fgRid, ourRid)) {
        hookOn = false;
        why = known ? "target integrity higher (UIPI)" : "target integrity unreadable";
        if (!direct && g_elevationNotify && !u->fgExe.empty() && !g_warnedExes.count(u->fgExe)) {
            g_warnedExes.insert(u->fgExe);
            g_elevationNotify(u->fgExe);
        }
    }
    if (appLogging()) {
        char rid[48];
        wsprintfA(rid, " integrity 0x%lx/0x%lx", fgRid, ourRid);
        appLog("hook", "foreground " + narrowAscii(u->fgExe) + " class " + u->fgApp.windowClass + " rule " +
                           std::to_string(static_cast<int>(mode)) + (u->directFromTip ? " +tip-handover" : "") +
                           " -> " + (hookOn ? (direct ? "DIRECT (hook types)" : "hookFallback") : "no hook") + " (" +
                           why + ")" + rid + (fresh ? "" : " [mid-focus]"));
    }
    ensureHookThread();
    directVerifyFocusChanged();
    auto* f = new Foreground{u->fgApp, u->fgExe, u->fgThread, fg, hookOn, direct, fresh};
    if (!PostThreadMessageW(g_hookTid, kCmdForeground, 0, reinterpret_cast<LPARAM>(f))) delete f;
}

void onForeground(HWND hwnd) {
    if (!u || !hwnd) return;
    u->fgApp = describeWindow(hwnd);
    u->fgExe = u->fgApp.identity;
    u->fgThread = u->fgApp.tid;
    u->directFromTip = false;  // a new window: the TIP re-evaluates its field
    publishForeground(true);
}

void CALLBACK winEventProc(HWINEVENTHOOK, DWORD event, HWND hwnd, LONG idObject, LONG, DWORD, DWORD) {
    if (event == EVENT_SYSTEM_FOREGROUND && idObject == OBJID_WINDOW) onForeground(hwnd);
}

}  // namespace

void hookConfigure(const Settings& s) {
    if (!u) u = new UiState();
    u->settings = s;
    appSetLogging(s.debugLogging);
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
    appLog("hook", std::string("TIP handover: direct ") + (on ? "requested" : "released"));
    publishForeground(false);
}

void hookSetElevationNotifier(void (*notify)(const std::wstring& exe)) { g_elevationNotify = notify; }

void hookDisableCurrentField() {
    if (g_hookTid) PostThreadMessageW(g_hookTid, kCmdDisableHere, 0, 0);
}

void hookShutdown() {
    directVerifyShutdown();
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
