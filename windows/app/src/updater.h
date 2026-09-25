// updater.h — "Kiểm tra cập nhật": the ONLY network access VietTelex makes, and only
// when the user clicks it or enabled autoUpdateCheck (spec §1, §8).
#pragma once
#include <windows.h>

namespace vtx::app {

constexpr UINT kMsgUpdateChecked = WM_APP + 0x61;  // lParam: UpdateInfo* (owned by receiver)
constexpr UINT kMsgUpdateDownloaded = WM_APP + 0x62;  // lParam: wchar_t* path or nullptr; wParam: status

struct UpdateInfo {
    bool ok = false;        // request + parse succeeded
    bool available = false;
    bool interactive = false;
    wchar_t version[32] = {};
    wchar_t url[512] = {};
};

enum DownloadStatus : WPARAM { kDownloadOk = 0, kDownloadFailed = 1, kDownloadBadSignature = 2 };

// Worker thread; posts kMsgUpdateChecked to `notify`.
void startUpdateCheck(HWND notify, bool interactive);
// Worker thread; downloads to %TEMP%, verifies Authenticode, posts kMsgUpdateDownloaded.
void startDownload(HWND notify, const wchar_t* url);
// msiexec /i <path> (elevation handled by the MSI).
void runInstaller(const wchar_t* msiPath);

// Daily auto-check bookkeeping (autoUpdateCheck).
bool autoCheckDue();
void markAutoChecked();

}  // namespace vtx::app
