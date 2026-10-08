#include "game_mode.h"

#include <shellapi.h>

#include <string>

#include "app.h"
#include "foreground.h"
#include "game_ipc.h"
#include "game_logic.h"
#include "hook_fallback.h"
#include "strings.h"
#include "switch_toast.h"
#include "text_tool_ipc.h"

namespace vtx::app {

namespace {

constexpr int kGameHotkeyId = 0x5655;        // text_actions.cpp uses 0x5654
constexpr UINT_PTR kTimerRecheck = 0x5501;   // fullscreen re-check (one-shot chain)

HWINEVENTHOOK g_fgHook = nullptr;
FullscreenTracker g_tracker;
bool g_hotkeyOn = false;
bool g_lastGameMode = false;
HWND g_recheckWnd = nullptr;   // the foreground window the re-checks are about
size_t g_recheckStep = 0;

bool isShellClass(const wchar_t* cls) {
    return lstrcmpW(cls, L"Progman") == 0 || lstrcmpW(cls, L"WorkerW") == 0 || lstrcmpW(cls, L"Shell_TrayWnd") == 0 ||
           lstrcmpW(cls, L"Shell_SecondaryTrayWnd") == 0;
}

ForegroundProbe probe(HWND hwnd) {
    ForegroundProbe p;
    p.quns = currentNotificationState();
    HWND root = hwnd ? GetAncestor(hwnd, GA_ROOT) : nullptr;
    if (!root) {
        p.shellOrDesktop = true;
        return p;
    }
    wchar_t cls[64] = {};
    GetClassNameW(root, cls, 64);
    p.shellOrDesktop = root == GetShellWindow() || root == GetDesktopWindow() || isShellClass(cls);
    DWORD pid = 0;
    GetWindowThreadProcessId(root, &pid);
    p.ownProcess = pid == GetCurrentProcessId();
    p.hasCaption = (GetWindowLongPtrW(root, GWL_STYLE) & WS_CAPTION) == WS_CAPTION;
    RECT wr;
    MONITORINFO mi = {};
    mi.cbSize = sizeof mi;
    if (GetWindowRect(root, &wr) && GetMonitorInfoW(MonitorFromWindow(root, MONITOR_DEFAULTTONEAREST), &mi))
        p.coversMonitor = coversMonitor(Rect{wr.left, wr.top, wr.right, wr.bottom},
                                        Rect{mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right,
                                             mi.rcMonitor.bottom});
    return p;
}

// Post the suspension bits to every VietTelex TIP window of the window's threads (its own
// thread and the one holding keyboard focus).
void postToTips(HWND root, uint32_t bits) {
    if (!root) return;
    const DWORD tid = GetWindowThreadProcessId(root, nullptr);
    DWORD ftid = tid;
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    if (GetGUIThreadInfo(tid, &gi) && gi.hwndFocus) ftid = GetWindowThreadProcessId(gi.hwndFocus, nullptr);
    const auto post = [bits](DWORD t) {
        if (HWND tip = FindWindowExW(HWND_MESSAGE, nullptr, nullptr, textToolWindowTitle(t).c_str()))
            PostMessageW(tip, kTipSuspendMsg, bits, 0);
    };
    post(tid);
    if (ftid != tid) post(ftid);
}

uint32_t gameBit() { return g_settings.gameMode ? kSuspendGameMode : 0; }

// The hook thread is told only when its state actually changes (a re-check mid-word must
// not reset the word it is typing).
bool g_hookSuspended = false;
void syncHookSuspension() {
    const bool want = g_tracker.suspended() != 0 || g_settings.gameMode;
    if (want == g_hookSuspended) return;
    g_hookSuspended = want;
    hookSetSuspended(want);
}

void applyStep(const FullscreenTracker::Step& s) {
    if (s.resume) {
        HWND w = reinterpret_cast<HWND>(s.resume);
        if (IsWindow(w)) {
            RemovePropW(w, kSuspendProp);
            postToTips(w, gameBit());
        }
        appLog("game", "fullscreen app left the foreground / exclusive mode: typing back on");
    }
    if (s.suspend) {
        HWND w = reinterpret_cast<HWND>(s.suspend);
        SetPropW(w, kSuspendProp, reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(kSuspendFullscreen)));
        postToTips(w, kSuspendFullscreen | gameBit());
        appLog("game", "exclusive fullscreen / slideshow in front: keys pass through");
    }
    syncHookSuspension();
}

void evaluate(HWND hwnd, bool fresh) {
    HWND root = hwnd ? GetAncestor(hwnd, GA_ROOT) : nullptr;
    const ForegroundProbe p = probe(root);
    const bool on = g_settings.autoOffFullscreen;
    applyStep(g_tracker.update(reinterpret_cast<uintptr_t>(root), fullscreenSuspends(on, p)));
    if (fresh) {
        KillTimer(g_mainWnd, kTimerRecheck);
        g_recheckWnd = root;
        g_recheckStep = 0;
    }
    const bool suspendedHere = g_tracker.suspended() == reinterpret_cast<uintptr_t>(root) && root;
    if (fullscreenRecheckWanted(on, p, suspendedHere) && root == g_recheckWnd &&
        g_recheckStep < kFullscreenRecheckCount) {
        const UINT delay = kFullscreenRecheckDelaysMs[g_recheckStep] -
                           (g_recheckStep ? kFullscreenRecheckDelaysMs[g_recheckStep - 1] : 0);
        ++g_recheckStep;
        SetTimer(g_mainWnd, kTimerRecheck, delay, nullptr);
    }
}

void CALLBACK fgEvent(HWINEVENTHOOK, DWORD, HWND hwnd, LONG idObject, LONG, DWORD, DWORD) {
    if (idObject != OBJID_WINDOW || !hwnd) return;
    evaluate(hwnd, true);
}

void syncForegroundWatch() {
    if (g_settings.autoOffFullscreen) {
        if (!g_fgHook) {
            g_fgHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, fgEvent, 0, 0,
                                       WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
            evaluate(GetForegroundWindow(), true);
        }
        return;
    }
    // Off: zero cost — no hook, no timers, nothing left suspended.
    if (g_fgHook) {
        UnhookWinEvent(g_fgHook);
        g_fgHook = nullptr;
    }
    if (g_mainWnd) KillTimer(g_mainWnd, kTimerRecheck);
    applyStep(g_tracker.clear());
}

void syncHotkey() {
    if (!g_mainWnd) return;
    if (g_hotkeyOn) {
        UnregisterHotKey(g_mainWnd, kGameHotkeyId);
        g_hotkeyOn = false;
    }
    unsigned mods = 0, vk = 0;
    if (!gameModeHotkeyKeys(g_settings.gameModeHotkey, mods, vk)) return;
    g_hotkeyOn = RegisterHotKey(g_mainWnd, kGameHotkeyId, mods | MOD_NOREPEAT, vk) != FALSE;
    if (!g_hotkeyOn) appLog("game", "game-mode hotkey " + g_settings.gameModeHotkey + ": taken by another app");
}

}  // namespace

int currentNotificationState() {
    QUERY_USER_NOTIFICATION_STATE s{};
    return SUCCEEDED(SHQueryUserNotificationState(&s)) ? static_cast<int>(s) : 0;
}

bool gameSuspendedNow() {
    if (g_settings.gameMode) return true;
    const uintptr_t s = g_tracker.suspended();
    return s && s == reinterpret_cast<uintptr_t>(GetAncestor(GetForegroundWindow(), GA_ROOT));
}

void gameConfigure() {
    syncHotkey();
    syncForegroundWatch();
    if (g_settings.gameMode != g_lastGameMode) {
        g_lastGameMode = g_settings.gameMode;
        // The snapshot is already saved (settingsChanged); tell the foreground TIP now so the
        // change applies without a focus change. Other processes read it at their next focus.
        HWND fg = GetForegroundWindow();
        HWND root = fg ? GetAncestor(fg, GA_ROOT) : nullptr;
        const bool fs = root && g_tracker.suspended() == reinterpret_cast<uintptr_t>(root);
        postToTips(root, (fs ? kSuspendFullscreen : 0) | gameBit());
        syncHookSuspension();
        appLog("game", g_settings.gameMode ? "game mode on" : "game mode off");
    }
}

void toggleGameMode() {
    g_settings.gameMode = !g_settings.gameMode;
    settingsChanged();
    refreshSettingsWindow();
    // Feedback even with the indicator off: the chord gives no other sign. Not over an
    // exclusive-fullscreen game (it would minimise some of them).
    const int q = currentNotificationState();
    if (q != static_cast<int>(Quns::D3DFullScreen)) toastShow(tr(g_settings.gameMode ? S::ToastGameOn : S::ToastGameOff));
}

void gameShutdown() {
    if (g_fgHook) {
        UnhookWinEvent(g_fgHook);
        g_fgHook = nullptr;
    }
    if (g_mainWnd) {
        KillTimer(g_mainWnd, kTimerRecheck);
        if (g_hotkeyOn) UnregisterHotKey(g_mainWnd, kGameHotkeyId);
    }
    g_hotkeyOn = false;
    const FullscreenTracker::Step s = g_tracker.clear();
    if (s.resume && IsWindow(reinterpret_cast<HWND>(s.resume))) {
        RemovePropW(reinterpret_cast<HWND>(s.resume), kSuspendProp);
        postToTips(reinterpret_cast<HWND>(s.resume), 0);
    }
}

bool gameMessage(UINT msg, WPARAM wp, LPARAM, LRESULT& result) {
    if (msg == WM_HOTKEY && static_cast<int>(wp) == kGameHotkeyId) {
        toggleGameMode();
        result = 0;
        return true;
    }
    if (msg == WM_TIMER && wp == kTimerRecheck) {
        KillTimer(g_mainWnd, kTimerRecheck);
        HWND fg = GetForegroundWindow();
        if (fg && GetAncestor(fg, GA_ROOT) == g_recheckWnd) evaluate(fg, false);
        result = 0;
        return true;
    }
    return false;
}

}  // namespace vtx::app
