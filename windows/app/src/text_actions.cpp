// text_actions.cpp — see text_actions.h. Win32 half of Công cụ văn bản; the decisions are
// in app/core/text_action_logic.* (unit-tested), the transforms in windows/engine.
#include "text_actions.h"

#include <memory>
#include <new>
#include <string>
#include <vector>

#include <viettelex/text_tools.hpp>

#include "app.h"
#include "app_messages.h"
#include "app_policy.h"
#include "foreground.h"
#include "../res/data_ids.h"
#include "settings_store.h"
#include "strings.h"
#include "text_action_logic.h"
#include "text_tool_ipc.h"
#include "caret_hint_ipc.h"
#include "learned_words.h"
#include "typo_fix.h"
#include "word_prediction.h"

#include <shlobj.h>

namespace vtx::app {

namespace {

constexpr int kHotkeyId = 0x5654;
constexpr UINT_PTR kTimerStart = 0x5401;  // tray path: the app we returned to has focus
constexpr UINT_PTR kTimerTip = 0x5402;    // the TIP did not answer -> clipboard fallback
constexpr UINT_PTR kTimerDone = 0x5403;   // the TIP took the result but never confirmed
constexpr UINT_PTR kTimerLearnSave = 0x5404;  // Học từ bạn gõ: save 5 s after the last word
constexpr UINT kLearnSaveDelayMs = 5000;
// Main-window messages: app_messages.h (kMsgUpdateChecked/Downloaded share this window).
constexpr UINT kMsgWork = kMsgTextToolWork;
constexpr UINT kMsgClipDone = kMsgTextToolClipDone;
constexpr UINT kStartDelayMs = 150, kTipWaitMs = 600, kDoneWaitMs = 3000;

enum class Stage { Idle, Starting, WaitTip, Transform, WaitReplace, Clipboard };

// One request at a time (macOS TextActionRunner.busy): repeated hotkey presses never
// stack Ctrl+C / Ctrl+V on top of each other. UI thread only.
struct Job {
    Stage stage = Stage::Idle;
    uint32_t request = 0;
    text::Tool tool = text::Tool::AddTones;
    HWND target = nullptr;  // top-level window of the app
    HWND tipWnd = nullptr;
    std::u16string selection;
};
Job g_job;
uint32_t g_seq = 0;
bool g_hotkeyOn = false;
HWND g_lastFg = nullptr;

const char* toolName(text::Tool t) {
    switch (t) {
        case text::Tool::AddTones: return "addTones";
        case text::Tool::Upper: return "upper";
        case text::Tool::Lower: return "lower";
        case text::Tool::Title: return "title";
        case text::Tool::Sentence: return "sentence";
        case text::Tool::StripDiacritics: return "stripDiacritics";
    }
    return "?";
}

// Language data for Thêm dấu, read in place from this exe's RCDATA (image-mapped) on
// first use; thread-safe static init (the clipboard worker may be first).
const addtones::LanguageData* languageData() {
    static const addtones::LanguageData* data = []() -> const addtones::LanguageData* {
        auto res = [](int id, size_t& n) -> const uint8_t* {
            n = 0;
            HRSRC r = FindResourceW(nullptr, MAKEINTRESOURCEW(id), MAKEINTRESOURCEW(10) /* RT_RCDATA */);
            if (!r) return nullptr;
            HGLOBAL g = LoadResource(nullptr, r);
            if (!g) return nullptr;
            n = SizeofResource(nullptr, r);
            return static_cast<const uint8_t*>(LockResource(g));
        };
        size_t nl = 0, ne = 0, nm = 0;
        const uint8_t* vl = res(IDR_VNLEXICON, nl);
        const uint8_t* el = res(IDR_ENLEXICON, ne);
        const uint8_t* lm = res(IDR_VNLM, nm);
        auto* d = new (std::nothrow) addtones::LanguageData();
        if (!d) return nullptr;
        if (!d->load(vl, nl, el, ne, lm, nm)) {
            appLog("text", "language data missing or corrupt: Thêm dấu unavailable");
            delete d;
            return nullptr;
        }
        appLog("text", std::string("language data loaded: ") + std::to_string(d->lexicon.count()) + " syllables, " +
                           std::to_string(d->english.size()) + " English words, LM " + (d->lm.ok() ? "ok" : "missing"));
        return d;
    }();
    return data;
}

// ---- Gợi ý cạnh con trỏ: jobs from the TIPs (caret_hint_ipc.h) --------------------------
// Only the latest job is kept: a newer key in the TIP makes an older answer useless anyway.
struct HintWork {
    bool pending = false;
    HWND tip = nullptr;
    HintMessage msg;
} g_hintWork;

bool isTipWindow(HWND h) {
    if (!h || !IsWindow(h)) return false;
    wchar_t title[64] = {};
    GetWindowTextW(h, title, 64);
    return wcsncmp(title, L"VietTelexTip:", 13) == 0;
}

HintJobs& hintJobs() {
    // The loader runs on the first job that needs data (never at start: textActionsConfigure
    // only clears the learned model here; a portable copy has no TIP, so no job ever comes).
    static HintJobs jobs(HintJobs::DataLoader([] { return languageData(); }));
    return jobs;
}

// ---- Học từ bạn gõ (learned_words.h) — UI thread only -------------------------------------
std::unique_ptr<learn::Model> g_learned;  // loaded on first use, dropped when off
std::vector<LearnEvent> g_learnQueue;     // from WM_COPYDATA, recorded in kMsgLearnWork

bool learningOn() { return g_settings.learnWords && g_settings.systemTextPrediction; }

int64_t nowMs() {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    const uint64_t t = (static_cast<uint64_t>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    return static_cast<int64_t>(t / 10000 - 11644473600000ull);  // 1601 -> 1970, ms
}

std::wstring learnedPath() {
    PWSTR base = nullptr;
    std::wstring p;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base)) && base) p = base;
    if (base) CoTaskMemFree(base);
    if (p.empty()) return p;
    return p + L"\\VietTelex\\" + learn::kFileName;
}

learn::Model* learnedModel() {
    if (g_learned) return g_learned.get();
    auto known = [](const std::string& w) { return hintJobs().knownWord(w); };
    const std::wstring path = learnedPath();
    std::vector<uint8_t> bytes;
    if (!path.empty()) {
        HANDLE f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
        if (f != INVALID_HANDLE_VALUE) {
            LARGE_INTEGER sz{};
            if (GetFileSizeEx(f, &sz) && sz.QuadPart > 0 && sz.QuadPart < (8 << 20)) {
                bytes.resize(static_cast<size_t>(sz.QuadPart));
                DWORD got = 0;
                if (!ReadFile(f, bytes.data(), static_cast<DWORD>(bytes.size()), &got, nullptr) || got != bytes.size())
                    bytes.clear();
            }
            CloseHandle(f);
        }
    }
    if (!bytes.empty()) g_learned = learn::Model::decode(bytes.data(), bytes.size(), known);
    if (!bytes.empty() && !g_learned) appLog("predict", "learned words: file unreadable -> starting empty");
    if (!g_learned) g_learned = std::make_unique<learn::Model>(known, nowMs());
    g_learned->decayIfDue(nowMs());
    if (g_learned->changes() > 0 && g_mainWnd) SetTimer(g_mainWnd, kTimerLearnSave, kLearnSaveDelayMs, nullptr);
    return g_learned.get();
}

void learnedSave() {
    if (g_mainWnd) KillTimer(g_mainWnd, kTimerLearnSave);
    if (!g_learned || g_learned->changes() == 0) return;
    const std::wstring path = learnedPath();
    if (path.empty()) return;
    const std::vector<uint8_t> bytes = g_learned->encode();
    g_learned->markSaved();
    CreateDirectoryW(path.substr(0, path.rfind(L'\\')).c_str(), nullptr);
    const std::wstring tmp = path + L".tmp";
    HANDLE f = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    DWORD put = 0;
    const bool ok = WriteFile(f, bytes.data(), static_cast<DWORD>(bytes.size()), &put, nullptr) && put == bytes.size() &&
                    FlushFileBuffers(f);
    CloseHandle(f);
    if (!ok || !MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(tmp.c_str());
        appLog("predict", "learned words: save failed");
    }
}

void onLearnWork() {
    std::vector<LearnEvent> q;
    q.swap(g_learnQueue);
    if (q.empty() || !learningOn()) return;
    learn::Model* m = learnedModel();
    for (const LearnEvent& e : q) {
        const std::u32string w = text::fromUtf16(e.word), p1 = text::fromUtf16(e.prev1);
        // learned casing: mid-sentence only (the TIP cuts prev1 at sentence / field start)
        m->record(text::toUtf8(w), text::toUtf8(p1), text::toUtf8(text::fromUtf16(e.prev2)), e.weight,
                  predict::casingEvidence(w, p1));
    }
    if (g_mainWnd) SetTimer(g_mainWnd, kTimerLearnSave, kLearnSaveDelayMs, nullptr);
}

void onHintWork() {
    if (!g_hintWork.pending) return;
    g_hintWork.pending = false;
    HintJobs& jobs = hintJobs();
    jobs.setFilterSensitive(g_settings.filterSensitive);
    jobs.setLearned(learningOn() && g_hintWork.msg.job == static_cast<uint32_t>(HintJob::Predict) ? learnedModel()
                                                                                                 : nullptr);
    HintMessage reply;
    reply.request = g_hintWork.msg.request;
    reply.job = g_hintWork.msg.job;
    reply.text = jobs.answer(g_hintWork.msg);
    const std::vector<uint8_t> b = packHintMessage(reply);
    COPYDATASTRUCT cds;
    cds.dwData = kCopyHintReply;
    cds.cbData = static_cast<DWORD>(b.size());
    cds.lpData = const_cast<uint8_t*>(b.data());
    DWORD_PTR r = 0;
    SendMessageTimeoutW(g_hintWork.tip, WM_COPYDATA, reinterpret_cast<WPARAM>(g_mainWnd), reinterpret_cast<LPARAM>(&cds),
                        SMTO_ABORTIFHUNG, 250, &r);
}

// ---- Gợi ý từ: Windows' text-suggestion setting (word_prediction.h) ----------------------
HKEY g_predKey = nullptr;
bool g_predSubtree = false;
HANDLE g_predEvent = nullptr, g_predWait = nullptr;

void armPredictionWatch() {
    if (!g_predKey || !g_predEvent) return;
    // One-shot: re-armed on the main thread after every change (the registration belongs to
    // the calling thread, which must outlive it — the UI thread does).
    RegNotifyChangeKeyValue(g_predKey, g_predSubtree, REG_NOTIFY_CHANGE_LAST_SET | REG_NOTIFY_CHANGE_NAME,
                            g_predEvent, TRUE);
}

VOID CALLBACK onPredictionEvent(PVOID, BOOLEAN) {
    if (g_mainWnd) PostMessageW(g_mainWnd, kMsgPredictSetting, 0, 0);
}

void onPredictionSettingChanged() {
    armPredictionWatch();
    const bool on = readSystemTextPrediction();
    if (on == g_settings.systemTextPrediction) return;
    g_settings.systemTextPrediction = on;
    learnedSettingsChanged();  // Học từ bạn gõ follows word prediction
    saveSettings(g_settings);  // the snapshot only: the mirror is never stored under VietTelex
    appLog("predict", std::string("Windows text suggestions (physical keyboard): ") + (on ? "on" : "off"));
}

void finish(bool beep, const char* why) {
    if (g_mainWnd) {
        KillTimer(g_mainWnd, kTimerStart);
        KillTimer(g_mainWnd, kTimerTip);
        KillTimer(g_mainWnd, kTimerDone);
    }
    if (why) appLog("text", std::string("text tool ") + toolName(g_job.tool) + ": " + why);
    g_job = Job();
    if (beep) MessageBeep(MB_OK);
}

// Mandatory integrity RID (0x2000 medium, 0x3000 high); false = unreadable.
bool processIntegrity(DWORD pid, DWORD& rid) {
    HANDLE p = pid ? OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid) : GetCurrentProcess();
    if (!p) return false;
    bool ok = false;
    HANDLE tok = nullptr;
    if (OpenProcessToken(p, TOKEN_QUERY, &tok)) {
        BYTE buf[128];
        DWORD len = 0;
        if (GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof buf, &len)) {
            auto* til = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf);
            rid = *GetSidSubAuthority(til->Label.Sid, *GetSidSubAuthorityCount(til->Label.Sid) - 1);
            ok = true;
        }
        CloseHandle(tok);
    }
    if (pid) CloseHandle(p);
    return ok;
}

// UIPI: our SendInput / messages cannot reach a higher-integrity (elevated) app.
bool reachable(DWORD pid) {
    DWORD theirs = 0, ours = 0x2000;
    processIntegrity(0, ours);
    return processIntegrity(pid, theirs) && theirs <= ours;
}

// Classic Edit password box (ES_PASSWORD) on the target's focus.
bool focusIsPassword(HWND target) {
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    if (!GetGUIThreadInfo(GetWindowThreadProcessId(target, nullptr), &gi) || !gi.hwndFocus) return false;
    wchar_t cls[64] = {};
    GetClassNameW(gi.hwndFocus, cls, 64);
    CharLowerW(cls);
    return wcsstr(cls, L"edit") != nullptr && (GetWindowLongW(gi.hwndFocus, GWL_STYLE) & ES_PASSWORD) != 0;
}

// ---------------------------------------------------------------- clipboard (worker thread)

struct ClipItem {
    UINT format = 0;
    std::vector<uint8_t> data;
    HENHMETAFILE emf = nullptr;
};

bool openClipboard(HWND owner) {
    for (int i = 0; i < 25; ++i) {
        if (OpenClipboard(owner)) return true;
        Sleep(20);  // another app holds it (the copying app, a clipboard manager)
    }
    return false;
}

void setDwordFormat(UINT fmt, DWORD v) {
    if (!fmt) return;
    HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, sizeof v);
    if (!g) return;
    if (void* p = GlobalLock(g)) {
        memcpy(p, &v, sizeof v);
        GlobalUnlock(g);
        if (SetClipboardData(fmt, g)) return;
    }
    GlobalFree(g);
}

// Our temporary content (and the restore of the user's) stays out of Win+V history and
// cloud clipboard, and clipboard monitors ignore it (the documented opt-out formats).
void addPrivacyFormats() {
    static const UINT exclude = RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
    static const UINT history = RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
    static const UINT cloud = RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
    setDwordFormat(exclude, 0);
    setDwordFormat(history, 0);
    setDwordFormat(cloud, 0);
}

// Every format the clipboard holds (macOS PasteboardBridge.Snapshot). False = could not
// open it: then nothing is touched at all.
bool snapshotClipboard(HWND owner, std::vector<ClipItem>& items) {
    if (!openClipboard(owner)) return false;
    for (UINT f = EnumClipboardFormats(0); f; f = EnumClipboardFormats(f)) {
        const ClipFormatKind kind = clipboardFormatKind(f);
        if (kind == ClipFormatKind::Skip) continue;
        HANDLE h = GetClipboardData(f);
        if (!h) continue;
        ClipItem it;
        it.format = f;
        if (kind == ClipFormatKind::EnhMetafile) {
            it.emf = CopyEnhMetaFile(static_cast<HENHMETAFILE>(h), nullptr);
            if (!it.emf) continue;
        } else {
            const SIZE_T n = GlobalSize(h);
            if (!n) continue;
            const void* p = GlobalLock(h);
            if (!p) continue;
            it.data.assign(static_cast<const uint8_t*>(p), static_cast<const uint8_t*>(p) + n);
            GlobalUnlock(h);
        }
        items.push_back(std::move(it));
    }
    CloseClipboard();
    return true;
}

void freeSnapshot(std::vector<ClipItem>& items) {
    for (ClipItem& it : items)
        if (it.emf) DeleteEnhMetaFile(it.emf);
    items.clear();
}

void restoreClipboard(HWND owner, std::vector<ClipItem>& items) {
    if (!openClipboard(owner)) return;
    EmptyClipboard();
    for (ClipItem& it : items) {
        if (it.emf) {
            if (SetClipboardData(CF_ENHMETAFILE, it.emf)) it.emf = nullptr;  // the clipboard owns it now
            continue;
        }
        HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, it.data.size());
        if (!g) continue;
        void* p = GlobalLock(g);
        if (!p) {
            GlobalFree(g);
            continue;
        }
        memcpy(p, it.data.data(), it.data.size());
        GlobalUnlock(g);
        if (!SetClipboardData(it.format, g)) GlobalFree(g);
    }
    if (!items.empty()) addPrivacyFormats();
    CloseClipboard();
}

bool readClipboardText(HWND owner, std::u16string& out) {
    out.clear();
    if (!openClipboard(owner)) return false;
    bool ok = false;
    if (HANDLE h = GetClipboardData(CF_UNICODETEXT)) {
        const SIZE_T n = GlobalSize(h) / sizeof(wchar_t);
        if (const auto* p = static_cast<const char16_t*>(GlobalLock(h))) {
            size_t len = 0;
            while (len < n && p[len]) ++len;
            out.assign(p, len);
            GlobalUnlock(h);
            ok = true;
        }
    }
    CloseClipboard();
    return ok;
}

bool writeClipboardText(HWND owner, const std::u16string& text) {
    if (!openClipboard(owner)) return false;
    bool ok = false;
    EmptyClipboard();
    if (HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, (text.size() + 1) * sizeof(char16_t))) {
        if (auto* p = static_cast<char16_t*>(GlobalLock(g))) {
            memcpy(p, text.data(), text.size() * sizeof(char16_t));
            p[text.size()] = 0;
            GlobalUnlock(g);
            ok = SetClipboardData(CF_UNICODETEXT, g) != nullptr;
        }
        if (!ok) GlobalFree(g);
    }
    if (ok) addPrivacyFormats();
    CloseClipboard();
    return ok;
}

// The hotkey (Ctrl+Alt+T…) may still be held: Ctrl+C sent now would arrive as
// Ctrl+Alt+C. Wait for every modifier to be released (≤ 1 s, like macOS).
void waitModifiersReleased() {
    for (int i = 0; i < 50; ++i) {
        const bool held = (GetAsyncKeyState(VK_CONTROL) | GetAsyncKeyState(VK_SHIFT) | GetAsyncKeyState(VK_MENU) |
                           GetAsyncKeyState(VK_LWIN) | GetAsyncKeyState(VK_RWIN)) &
                          0x8000;
        if (!held) return;
        Sleep(20);
    }
}

// Ctrl + key as one SendInput batch, marked as ours (the hook and the TIP skip it).
bool sendCtrl(WORD vk) {
    INPUT in[4] = {};
    auto key = [&in](int i, WORD v, bool up) {
        in[i].type = INPUT_KEYBOARD;
        in[i].ki.wVk = v;
        in[i].ki.wScan = static_cast<WORD>(MapVirtualKeyW(v, MAPVK_VK_TO_VSC));
        in[i].ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        in[i].ki.dwExtraInfo = kInjectedMagic;
    };
    key(0, VK_CONTROL, false);
    key(1, vk, false);
    key(2, vk, true);
    key(3, VK_CONTROL, true);
    return SendInput(4, in, sizeof(INPUT)) == 4;
}

struct ClipWork {
    text::Tool tool;
    HWND target;
};

// Ctrl+C → transform → Ctrl+V, clipboard restored (macOS PasteboardBridge). Returns false
// (beep) when nothing was replaced.
bool runClipboard(const ClipWork& w, const char*& why) {
    HWND owner = CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, g_inst, nullptr);
    if (!owner) {
        why = "no clipboard window";
        return false;
    }
    waitModifiersReleased();
    std::vector<ClipItem> saved;
    bool ok = false;
    if (GetForegroundWindow() != w.target) {
        why = "the app lost focus";
    } else if (!snapshotClipboard(owner, saved)) {
        why = "clipboard busy";
    } else {
        const DWORD before = GetClipboardSequenceNumber();
        bool changed = false;
        if (sendCtrl('C')) {
            for (int i = 0; i < 25 && !changed; ++i) {
                Sleep(20);
                changed = GetClipboardSequenceNumber() != before;
            }
        }
        std::u16string sel, out;
        if (!changed) {
            why = "no selection (copy changed nothing)";
        } else if (!readClipboardText(owner, sel) || sel.empty()) {
            why = "no text in the copied selection";
            restoreClipboard(owner, saved);
        } else if (!transformText(w.tool, sel, w.tool == text::Tool::AddTones ? languageData() : nullptr, out)) {
            why = "unchanged";
            restoreClipboard(owner, saved);
        } else if (GetForegroundWindow() != w.target) {
            why = "the app lost focus";
            restoreClipboard(owner, saved);
        } else if (!writeClipboardText(owner, out)) {
            why = "clipboard busy (paste)";
            restoreClipboard(owner, saved);
        } else {
            const DWORD ours = GetClipboardSequenceNumber();
            ok = sendCtrl('V');
            // Apps read the clipboard asynchronously after Ctrl+V: restoring too early
            // pastes the old content (macOS waits 0.6 s too).
            Sleep(600);
            if (GetClipboardSequenceNumber() == ours) restoreClipboard(owner, saved);
            why = ok ? "replaced (clipboard)" : "SendInput refused";
        }
    }
    freeSnapshot(saved);
    DestroyWindow(owner);
    return ok;
}

DWORD WINAPI clipThread(void* p) {
    const ClipWork w = *static_cast<ClipWork*>(p);
    delete static_cast<ClipWork*>(p);
    const char* why = "";
    const bool ok = runClipboard(w, why);
    appLog("text", std::string("text tool ") + toolName(w.tool) + " (clipboard): " + why);
    PostMessageW(g_mainWnd, kMsgClipDone, ok ? 1 : 0, 0);
    return 0;
}

// ---------------------------------------------------------------- flow (UI thread)

void startClipboard() {
    KillTimer(g_mainWnd, kTimerTip);
    const FgApp app = describeWindow(g_job.target);
    if (!clipboardFallbackAllowed(narrow(app.identity), app.console, app.windowClass))
        return finish(true, "no Ctrl+C/Ctrl+V fallback in this app (terminal / remote)");
    if (focusIsPassword(g_job.target)) return finish(true, "password field");
    g_job.stage = Stage::Clipboard;
    auto* w = new (std::nothrow) ClipWork{g_job.tool, g_job.target};
    if (!w) return finish(true, "out of memory");
    HANDLE t = CreateThread(nullptr, 0, clipThread, w, 0, nullptr);
    if (!t) {
        delete w;
        return finish(true, "no worker thread");
    }
    CloseHandle(t);
}

HWND findTipWindow(DWORD tid) {
    return tid ? FindWindowExW(HWND_MESSAGE, nullptr, nullptr, textToolWindowTitle(tid).c_str()) : nullptr;
}

void dispatch() {
    HWND target = g_job.target;
    if (!target || !IsWindow(target)) return finish(true, "target window gone");
    DWORD pid = 0;
    const DWORD tid = GetWindowThreadProcessId(target, &pid);
    if (!reachable(pid)) return finish(true, "the app runs elevated (UIPI)");
    // The TIP of the thread that has keyboard focus (usually the window's own thread).
    DWORD ftid = tid;
    GUITHREADINFO gi = {};
    gi.cbSize = sizeof gi;
    if (GetGUIThreadInfo(tid, &gi) && gi.hwndFocus) ftid = GetWindowThreadProcessId(gi.hwndFocus, nullptr);
    HWND tip = findTipWindow(ftid);
    if (!tip && ftid != tid) tip = findTipWindow(tid);
    if (!tip) {
        appLog("text", "no VietTelex TIP in that thread (another keyboard active?) -> clipboard");
        return startClipboard();
    }
    g_seq = (g_seq + 1) & kTextToolRequestMask;
    if (!g_seq) g_seq = 1;
    g_job.request = g_seq;
    g_job.tipWnd = tip;
    g_job.stage = Stage::WaitTip;
    if (!PostMessageW(tip, kTipTextToolMsg, static_cast<WPARAM>(g_job.tool), static_cast<LPARAM>(g_job.request)))
        return startClipboard();
    SetTimer(g_mainWnd, kTimerTip, kTipWaitMs, nullptr);
}

void start(text::Tool tool, HWND target, bool afterRefocus) {
    if (g_job.stage != Stage::Idle) {
        MessageBeep(MB_OK);
        return;
    }
    if (!target || !IsWindow(target)) {
        MessageBeep(MB_OK);
        return;
    }
    g_job.tool = tool;
    g_job.target = target;
    g_job.stage = Stage::Starting;
    if (afterRefocus) {
        // Back to the app the tray menu came from; let focus (and the TIP's OnSetFocus)
        // settle before asking for the selection.
        SetForegroundWindow(target);
        SetTimer(g_mainWnd, kTimerStart, kStartDelayMs, nullptr);
    } else {
        dispatch();
    }
}

// The TIP sent the selection: transform here, answer with the result.
void onWork() {
    if (g_job.stage != Stage::Transform) return;
    std::u16string out;
    const bool changed = transformText(g_job.tool, g_job.selection,
                                       g_job.tool == text::Tool::AddTones ? languageData() : nullptr, out);
    if (!changed) return finish(true, "unchanged / nothing to do");
    const std::vector<uint8_t> b = packTextToolData(g_job.request, static_cast<uint32_t>(g_job.tool), out);
    COPYDATASTRUCT cds;
    cds.dwData = kCopyResult;
    cds.cbData = static_cast<DWORD>(b.size());
    cds.lpData = const_cast<uint8_t*>(b.data());
    DWORD_PTR r = 0;
    g_job.stage = Stage::WaitReplace;
    if (!SendMessageTimeoutW(g_job.tipWnd, WM_COPYDATA, reinterpret_cast<WPARAM>(g_mainWnd),
                             reinterpret_cast<LPARAM>(&cds), SMTO_ABORTIFHUNG, 1000, &r) ||
        !r)
        return finish(true, "the TIP did not take the result");
    SetTimer(g_mainWnd, kTimerDone, kDoneWaitMs, nullptr);
}

}  // namespace

bool textActionsBusy() { return g_job.stage != Stage::Idle; }

void textActionsConfigure() {
    learnedSettingsChanged();
    if (!g_mainWnd) return;
    if (g_hotkeyOn) {
        UnregisterHotKey(g_mainWnd, kHotkeyId);
        g_hotkeyOn = false;
    }
    unsigned mods = 0, vk = 0;
    if (!addTonesHotkeyKeys(g_settings.addTonesHotkey, mods, vk)) return;
    g_hotkeyOn = RegisterHotKey(g_mainWnd, kHotkeyId, mods | MOD_NOREPEAT, vk) != FALSE;
    if (!g_hotkeyOn) appLog("text", "add-tones hotkey " + g_settings.addTonesHotkey + ": taken by another app");
}

void predictionWatchStart() {
    if (g_predEvent) return;
    // The value's key does not exist until the toggle was used once: then watch its parent.
    if (RegOpenKeyExW(HKEY_CURRENT_USER, predict::kHwkbPredictionKey, 0, KEY_NOTIFY, &g_predKey) == ERROR_SUCCESS) {
        g_predSubtree = false;
    } else if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Input", 0, KEY_NOTIFY, &g_predKey) == ERROR_SUCCESS) {
        g_predSubtree = true;
    } else {
        g_predKey = nullptr;
        appLog("predict", "cannot watch the Windows text-suggestion setting (read at start only)");
        return;
    }
    g_predEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);  // auto-reset
    if (!g_predEvent || !RegisterWaitForSingleObject(&g_predWait, g_predEvent, onPredictionEvent, nullptr, INFINITE,
                                                     WT_EXECUTEDEFAULT)) {
        predictionWatchStop();
        return;
    }
    armPredictionWatch();
}

void predictionWatchStop() {
    if (g_predWait) UnregisterWaitEx(g_predWait, INVALID_HANDLE_VALUE);  // waits for a running callback
    g_predWait = nullptr;
    if (g_predKey) RegCloseKey(g_predKey);  // also cancels the pending notification
    g_predKey = nullptr;
    if (g_predEvent) CloseHandle(g_predEvent);
    g_predEvent = nullptr;
}

void textActionsShutdown() {
    if (g_hotkeyOn && g_mainWnd) UnregisterHotKey(g_mainWnd, kHotkeyId);
    g_hotkeyOn = false;
    learnedSave();  // Học từ bạn gõ: what the last 5 s learned
}

void learnedClear() {
    g_learnQueue.clear();
    if (g_mainWnd) KillTimer(g_mainWnd, kTimerLearnSave);
    if (g_learned) g_learned->clear(nowMs());
    if (g_learned) g_learned->markSaved();
    const std::wstring path = learnedPath();
    if (!path.empty()) DeleteFileW(path.c_str());
    appLog("predict", "learned words cleared");
}

void learnedSettingsChanged() {
    hintJobs().setLearned(nullptr);
    if (learningOn() || !g_learned) return;
    learnedSave();
    g_learned.reset();
}

bool textActionsMessage(UINT msg, WPARAM wp, LPARAM lp, LRESULT& result) {
    switch (msg) {
        case WM_HOTKEY:
            if (static_cast<int>(wp) != kHotkeyId) return false;
            start(text::Tool::AddTones, GetForegroundWindow(), false);
            result = 0;
            return true;
        case WM_COPYDATA: {
            const auto* cds = reinterpret_cast<const COPYDATASTRUCT*>(lp);
            if (cds && cds->dwData == kCopyHintRequest) {
                result = FALSE;
                HintMessage m;
                if (!isTipWindow(reinterpret_cast<HWND>(wp)) || !unpackHintMessage(cds->lpData, cds->cbData, m))
                    return true;
                if (m.job == static_cast<uint32_t>(HintJob::Learn)) {  // one-way: queue, record later
                    if (learningOn() && g_learnQueue.size() < 512) {
                        for (LearnEvent& e : unpackLearnEvents(m.text)) g_learnQueue.push_back(std::move(e));
                        PostMessageW(g_mainWnd, kMsgLearnWork, 0, 0);
                    }
                    result = TRUE;
                    return true;
                }
                g_hintWork.pending = true;
                g_hintWork.tip = reinterpret_cast<HWND>(wp);
                g_hintWork.msg = std::move(m);
                PostMessageW(g_mainWnd, kMsgHintWork, 0, 0);  // answer outside the TIP's SendMessage
                result = TRUE;
                return true;
            }
            if (!cds || cds->dwData != kCopySelection) return false;
            result = FALSE;
            uint32_t request = 0, tool = 0;
            std::u16string text;
            if (g_job.stage != Stage::WaitTip || reinterpret_cast<HWND>(wp) != g_job.tipWnd ||
                !unpackTextToolData(cds->lpData, cds->cbData, request, tool, text) || request != g_job.request ||
                tool != static_cast<uint32_t>(g_job.tool))
                return true;
            KillTimer(g_mainWnd, kTimerTip);
            g_job.selection = std::move(text);
            g_job.stage = Stage::Transform;
            PostMessageW(g_mainWnd, kMsgWork, 0, 0);  // answer outside the TIP's SendMessage
            result = TRUE;
            return true;
        }
        case kMsgWork:
            onWork();
            result = 0;
            return true;
        case kMsgHintWork:
            onHintWork();
            result = 0;
            return true;
        case kMsgPredictSetting:
            onPredictionSettingChanged();
            result = 0;
            return true;
        case kMsgLearnWork:
            onLearnWork();
            result = 0;
            return true;
        case kMsgClipDone:
            if (g_job.stage == Stage::Clipboard) finish(wp == 0, nullptr);
            result = 0;
            return true;
        case WM_TIMER:
            if (wp == kTimerLearnSave) {
                learnedSave();
                result = 0;
                return true;
            }
            if (wp == kTimerStart) {
                KillTimer(g_mainWnd, kTimerStart);
                if (g_job.stage == Stage::Starting) dispatch();
            } else if (wp == kTimerTip) {
                KillTimer(g_mainWnd, kTimerTip);
                if (g_job.stage == Stage::WaitTip) {
                    appLog("text", "the TIP did not answer -> clipboard");
                    startClipboard();
                }
            } else if (wp == kTimerDone) {
                finish(false, "no confirmation from the TIP");
            } else {
                return false;
            }
            result = 0;
            return true;
        default: return false;
    }
}

void textActionsTipReply(LPARAM lp) {
    const uint32_t v = static_cast<uint32_t>(lp);
    if (g_job.stage == Stage::Idle || textToolReplyRequest(v) != g_job.request) return;
    switch (textToolReplyStatus(v)) {
        case TextToolStatus::Fallback:
            if (g_job.stage == Stage::WaitTip) startClipboard();
            break;
        case TextToolStatus::Refused: finish(true, "password field (TIP)"); break;
        case TextToolStatus::Replaced: finish(false, "replaced (TSF)"); break;
        case TextToolStatus::Failed: finish(true, "nothing selected / selection changed (TIP)"); break;
    }
}

void textActionsNoteForeground(HWND hwnd) {
    if (!hwnd || !IsWindowVisible(hwnd)) return;
    char cls[64] = {};
    GetClassNameA(hwnd, cls, sizeof cls);
    if (isShellSurfaceClass(cls)) return;
    g_lastFg = hwnd;
}

void appendTextToolsMenu(HMENU menu, UINT firstId) {
    if (!g_settings.textToolsInMenu) return;
    HMENU sub = CreatePopupMenu();
    if (!sub) return;
    static const S kLabels[text::kToolCount] = {S::ToolAddTones, S::ToolUpper,    S::ToolLower,
                                                S::ToolTitle,    S::ToolSentence, S::ToolStrip};
    for (int i = 0; i < text::kToolCount; ++i) {
        const text::Tool t = kTextToolMenuOrder[i];
        std::wstring label = tr(kLabels[static_cast<int>(t)]);
        if (t == text::Tool::AddTones) {
            const HotkeyChoice& hk = kAddTonesHotkeys[addTonesHotkeyIndex(g_settings.addTonesHotkey)];
            if (hk.label) label += std::wstring(L"\t") + hk.label;
        }
        AppendMenuW(sub, MF_STRING, firstId + static_cast<UINT>(i), label.c_str());
    }
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(sub), tr(S::MenuTextTools));
}

bool runTextToolMenuCommand(UINT cmd, UINT firstId) {
    if (cmd < firstId || cmd >= firstId + static_cast<UINT>(text::kToolCount)) return false;
    start(kTextToolMenuOrder[cmd - firstId], g_lastFg, true);
    return true;
}

}  // namespace vtx::app
