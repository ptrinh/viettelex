#include "updater.h"

#include <shellapi.h>
#include <softpub.h>
#include <wincrypt.h>
#include <winhttp.h>
#include <wintrust.h>

#include <ctime>
#include <string>

#include "settings_store.h"
#include "setup_helper_logic.h"
#include "update_check.h"
#include "version.h"

namespace vtx::app {

namespace {

constexpr wchar_t kHost[] = L"viettelex.com";
constexpr wchar_t kPath[] = L"/stable.json";
constexpr size_t kMaxJson = 64 * 1024;
constexpr size_t kMaxMsi = 64 * 1024 * 1024;

// Publisher name the MSI must be signed with (Azure Trusted Signing certificate
// subject). Empty = only require a valid, trusted Authenticode chain. Set at build
// time with -DVTX_EXPECTED_PUBLISHER=L"..." once the signing identity exists.
#ifndef VTX_EXPECTED_PUBLISHER
#define VTX_EXPECTED_PUBLISHER L""
#endif

bool httpGet(const wchar_t* host, const wchar_t* path, size_t limit, std::string& body, HANDLE file = nullptr) {
    bool ok = false;
    HINTERNET s = WinHttpOpen(L"VietTelex/" VTX_VER_STRING_W, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                              WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!s) return false;
    DWORD redirect = WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP;
    WinHttpSetOption(s, WINHTTP_OPTION_REDIRECT_POLICY, &redirect, sizeof redirect);
    HINTERNET c = WinHttpConnect(s, host, INTERNET_DEFAULT_HTTPS_PORT, 0);
    HINTERNET r = c ? WinHttpOpenRequest(c, L"GET", path, nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                         WINHTTP_FLAG_SECURE)
                    : nullptr;
    if (r && WinHttpSendRequest(r, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(r, nullptr)) {
        DWORD status = 0, sz = sizeof status;
        WinHttpQueryHeaders(r, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX,
                            &status, &sz, WINHTTP_NO_HEADER_INDEX);
        if (status == 200) {
            ok = true;
            size_t total = 0;
            char buf[16384];
            for (;;) {
                DWORD got = 0;
                if (!WinHttpReadData(r, buf, sizeof buf, &got)) { ok = false; break; }
                if (got == 0) break;
                total += got;
                if (total > limit) { ok = false; break; }
                if (file) {
                    DWORD w = 0;
                    if (!WriteFile(file, buf, got, &w, nullptr) || w != got) { ok = false; break; }
                } else {
                    body.append(buf, got);
                }
            }
        }
    }
    if (r) WinHttpCloseHandle(r);
    if (c) WinHttpCloseHandle(c);
    WinHttpCloseHandle(s);
    return ok;
}

bool splitUrl(const std::wstring& url, std::wstring& host, std::wstring& path) {
    const std::wstring pre = L"https://";
    if (url.compare(0, pre.size(), pre) != 0) return false;
    size_t slash = url.find(L'/', pre.size());
    if (slash == std::wstring::npos) return false;
    host = url.substr(pre.size(), slash - pre.size());
    path = url.substr(slash);
    return !host.empty();
}

bool nativeArm64() {
    SYSTEM_INFO si;
    GetNativeSystemInfo(&si);
    return si.wProcessorArchitecture == 12;  // PROCESSOR_ARCHITECTURE_ARM64
}

struct CheckJob {
    HWND notify;
    bool interactive;
};

DWORD WINAPI checkThread(void* p) {
    auto* job = static_cast<CheckJob*>(p);
    HWND notify = job->notify;
    auto* info = new UpdateInfo();
    info->interactive = job->interactive;
    delete job;
    std::string body;
    WindowsRelease rel;
    if (httpGet(kHost, kPath, kMaxJson, body) && parseStableJson(body, rel)) {
        info->ok = true;
        const std::string& url = nativeArm64() && !rel.arm64.empty() ? rel.arm64 : rel.x64;
        if (isNewer(rel.version, VTX_VER_STRING) && isTrustedDownloadUrl(url)) {
            info->available = true;
            lstrcpynW(info->version, widen(rel.version).c_str(), 32);
            lstrcpynW(info->url, widen(url).c_str(), 512);
        }
    }
    // Reachable but no parseable "windows" entry → report "couldn't check", NOT "you're on
    // the latest" (bug 26/09/2026: stable.json had no windows key → misleading "mới nhất").
    if (!PostMessageW(notify, kMsgUpdateChecked, 0, reinterpret_cast<LPARAM>(info))) delete info;
    return 0;
}

struct DownloadJob {
    HWND notify;
    std::wstring url;
};

bool signerMatches(HANDLE stateData) {
    const std::wstring expected = VTX_EXPECTED_PUBLISHER;
    if (expected.empty()) return true;
    CRYPT_PROVIDER_DATA* pd = WTHelperProvDataFromStateData(stateData);
    CRYPT_PROVIDER_SGNR* sg = pd ? WTHelperGetProvSignerFromChain(pd, 0, FALSE, 0) : nullptr;
    if (!sg || !sg->pasCertChain || sg->csCertChain == 0) return false;
    wchar_t name[256];
    DWORD n = CertGetNameStringW(sg->pasCertChain[0].pCert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr, name, 256);
    return n > 1 && expected == name;
}

bool verifyAuthenticode(const std::wstring& path) {
    WINTRUST_FILE_INFO fi = {};
    fi.cbStruct = sizeof fi;
    fi.pcwszFilePath = path.c_str();
    WINTRUST_DATA wd = {};
    wd.cbStruct = sizeof wd;
    wd.dwUIChoice = WTD_UI_NONE;
    wd.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN;
    wd.dwUnionChoice = WTD_CHOICE_FILE;
    wd.pFile = &fi;
    wd.dwStateAction = WTD_STATEACTION_VERIFY;
    GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    LONG st = WinVerifyTrust(static_cast<HWND>(INVALID_HANDLE_VALUE), &action, &wd);
    bool ok = st == ERROR_SUCCESS && signerMatches(wd.hWVTStateData);
    wd.dwStateAction = WTD_STATEACTION_CLOSE;
    WinVerifyTrust(static_cast<HWND>(INVALID_HANDLE_VALUE), &action, &wd);
    return ok;
}

DWORD WINAPI downloadThread(void* p) {
    auto* job = static_cast<DownloadJob*>(p);
    WPARAM status = kDownloadFailed;
    wchar_t* outPath = nullptr;
    std::wstring host, path;
    wchar_t tmp[MAX_PATH];
    if (splitUrl(job->url, host, path) && GetTempPathW(MAX_PATH, tmp)) {
        std::wstring file = std::wstring(tmp) + L"VietTelex-update.msi";
        HANDLE f = CreateFileW(file.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (f != INVALID_HANDLE_VALUE) {
            std::string unused;
            bool got = httpGet(host.c_str(), path.c_str(), kMaxMsi, unused, f);
            CloseHandle(f);
            if (!got) {
                DeleteFileW(file.c_str());
            } else if (!verifyAuthenticode(file)) {
                DeleteFileW(file.c_str());
                status = kDownloadBadSignature;
            } else {
                status = kDownloadOk;
                outPath = new wchar_t[file.size() + 1];
                lstrcpyW(outPath, file.c_str());
            }
        }
    }
    if (!PostMessageW(job->notify, kMsgUpdateDownloaded, status, reinterpret_cast<LPARAM>(outPath))) delete[] outPath;
    delete job;
    return 0;
}

}  // namespace

void startUpdateCheck(HWND notify, bool interactive) {
    auto* job = new CheckJob{notify, interactive};
    HANDLE t = CreateThread(nullptr, 0, checkThread, job, 0, nullptr);
    if (t) CloseHandle(t);
    else delete job;
}

void startDownload(HWND notify, const wchar_t* url) {
    auto* job = new DownloadJob{notify, url};
    HANDLE t = CreateThread(nullptr, 0, downloadThread, job, 0, nullptr);
    if (t) CloseHandle(t);
    else delete job;
}

bool runInstaller(const wchar_t* msiPath, const wchar_t* version) {
    // msiexec elevates itself. We get its process handle so a detached watcher can bring
    // the app back if the install is cancelled or fails (setup_helper_logic.h). Always
    // with a verbose log: %LOCALAPPDATA%\VietTelex\update-<version>.log.
    std::wstring args = L"/i \"" + std::wstring(msiPath) + L"\"";
    wchar_t lad[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", lad, MAX_PATH);
    if (n > 0 && n < MAX_PATH) {
        const std::wstring dir = std::wstring(lad) + L"\\VietTelex";
        CreateDirectoryW(dir.c_str(), nullptr);
        args += L" /l*v \"" + dir + L"\\" + vtx::updateLogName(narrow(version ? version : L"")) + L"\"";
    }
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof sei;
    sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
    sei.lpVerb = L"open";
    sei.lpFile = L"msiexec.exe";
    sei.lpParameters = args.c_str();
    sei.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&sei)) return false;
    if (sei.hProcess) {
        const DWORD pid = GetProcessId(sei.hProcess);
        CloseHandle(sei.hProcess);
        // Watcher = a COPY of this exe in %TEMP%: it holds no installed file open.
        wchar_t self[MAX_PATH], tmp[MAX_PATH];
        if (pid && GetModuleFileNameW(nullptr, self, MAX_PATH) && GetTempPathW(MAX_PATH, tmp)) {
            const std::wstring watcher = std::wstring(tmp) + vtx::kWatcherFileName;
            if (CopyFileW(self, watcher.c_str(), FALSE)) {
                std::wstring cmd = L"\"" + watcher + L"\" " + vtx::watcherArgs(pid);
                STARTUPINFOW si = {};
                si.cb = sizeof si;
                PROCESS_INFORMATION pi = {};
                if (CreateProcessW(watcher.c_str(), &cmd[0], nullptr, nullptr, FALSE, DETACHED_PROCESS, nullptr,
                                   nullptr, &si, &pi)) {
                    CloseHandle(pi.hThread);
                    CloseHandle(pi.hProcess);
                }
            }
        }
    }
    return true;
}

bool autoCheckDue() {
    unsigned long long last = readQword(L"lastAutoUpdateCheckAt");
    unsigned long long now = static_cast<unsigned long long>(time(nullptr));
    return now < last || now - last >= 24ull * 3600ull;
}

void markAutoChecked() { writeQword(L"lastAutoUpdateCheckAt", static_cast<unsigned long long>(time(nullptr))); }

}  // namespace vtx::app
