// updater.h — "Kiểm tra cập nhật": the ONLY network access VietTelex makes, and only
// when the user clicks it or enabled autoUpdateCheck (spec §1, §8).
#pragma once
#include <windows.h>

#include <string>

#include "app_messages.h"
#include "update_check.h"

namespace vtx::app {

// kMsgUpdateChecked / kMsgUpdateDownloaded: app_messages.h (one list for the main window).

struct UpdateInfo {
    bool ok = false;        // request + parse succeeded
    bool available = false;
    bool interactive = false;
    wchar_t version[32] = {};
    wchar_t url[512] = {};
};

// kDownloadBadSignature: not our publisher / invalid. kDownloadUnverified: the signature
// could not be checked (revocation servers unreachable: offline, proxy) — never installed.
enum DownloadStatus : WPARAM {
    kDownloadOk = 0,
    kDownloadFailed = 1,
    kDownloadBadSignature = 2,
    kDownloadUnverified = 3,
};

// The single-flight state of check -> prompt -> download -> install (UI thread).
UpdateFlow& updateFlow();
// Worker thread; posts kMsgUpdateChecked to `notify`. Single flight (update_check.h): a
// check already running answers this one too; while the prompt is up or a download runs,
// nothing starts (an interactive click while downloading says so).
void startUpdateCheck(HWND notify, bool interactive);
// Worker thread; downloads to %TEMP%, verifies Authenticode, posts kMsgUpdateDownloaded.
// False = the thread could not start.
bool startDownload(HWND notify, const wchar_t* url);
// msiexec /i <path> (elevation handled by msiexec) + a detached watcher that restarts the
// installed app if nothing else did. The caller must EXIT right after (it is one of the
// files being replaced). False = msiexec could not be started.
bool runInstaller(const wchar_t* msiPath, const wchar_t* version);
// %SystemRoot%\System32\msiexec.exe <args> + the detached watcher (`uninstall`: msiexec /x —
// a cancelled UAC prompt / MSI dialog brings the app back). False = not started.
bool runMsiexecWithWatcher(const std::wstring& args, bool uninstall);

// Daily auto-check bookkeeping (autoUpdateCheck).
bool autoCheckDue();
unsigned autoCheckDelay();  // ms to the next due check (one-shot timer), 0 = due now
void markAutoChecked();

}  // namespace vtx::app
