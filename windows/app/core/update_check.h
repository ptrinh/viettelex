// update_check.h — parse stable.json and decide whether an update is offered.
//
// Same file the macOS updater reads (docs/stable.json), plus a "windows" object:
//   { "version": "1.7.12", "url": "...", "build": 108,
//     "windows": { "version": "0.2.0", "x64": "https://…/VietTelex-0.2.0-x64.msi",
//                  "arm64": "https://…/VietTelex-0.2.0-arm64.msi",
//                  "notes": "https://github.com/…/releases/tag/win-v0.2.0" } }
// The MSI is only ever run after its Authenticode signature verifies (updater.cpp).
#pragma once
#include <cstdint>
#include <string>

namespace vtx {

struct WindowsRelease {
    std::string version;
    std::string x64;
    std::string arm64;
    std::string notes;
};

// False when there is no usable "windows" object (missing, malformed, no version).
bool parseStableJson(const std::string& json, WindowsRelease& out);

// Dotted numeric compare ("0.10.0" > "0.9.3"); non-numeric parts compare as 0.
int compareVersions(const std::string& a, const std::string& b);
inline bool isNewer(const std::string& candidate, const std::string& current) {
    return compareVersions(candidate, current) > 0;
}

// Only https:// URLs on hosts we publish from are accepted for the download.
bool isTrustedDownloadUrl(const std::string& url);

// Where a failed self-update sends the user (download by hand).
constexpr const wchar_t* kWindowsDownloadPageUrl = L"https://viettelex.com/download/?os=windows";

// ---- 2026-11 audit: the update flow (UI thread; app/src/main.cpp, updater.cpp) ----------

// Single flight: one check, one "update?" prompt, one download at a time. A second check
// while one runs joins it (shown if either asked interactively); while the prompt is up or a
// download / install runs, a check starts nothing — no second download, no failure box.
class UpdateFlow {
public:
    enum class Phase { Idle, Checking, Prompting, Downloading, Installing };
    enum class Request { Start, Joined, Busy };

    Request requestCheck(bool interactive) {
        if (phase_ == Phase::Idle) {
            phase_ = Phase::Checking;
            interactive_ = interactive;
            return Request::Start;
        }
        if (phase_ == Phase::Checking) {
            interactive_ = interactive_ || interactive;
            return Request::Joined;
        }
        return Request::Busy;
    }
    // The check thread could not be started.
    void checkNotStarted() {
        if (phase_ == Phase::Checking) phase_ = Phase::Idle;
    }
    // The result is in. True = present it as an interactive check (someone clicked).
    bool checkDone() {
        if (phase_ == Phase::Checking) phase_ = Phase::Idle;
        const bool i = interactive_;
        interactive_ = false;
        return i;
    }
    // Before showing "update available?": false = another prompt / download owns the flow.
    bool beginPrompt() {
        if (phase_ != Phase::Idle) return false;
        phase_ = Phase::Prompting;
        return true;
    }
    // The prompt closed; `download` = the user said yes and the download thread started.
    void promptDone(bool download) {
        if (phase_ == Phase::Prompting) phase_ = download ? Phase::Downloading : Phase::Idle;
    }
    // Download finished; `installing` = msiexec is starting (the app exits right after).
    void downloadDone(bool installing) {
        if (phase_ == Phase::Downloading) phase_ = installing ? Phase::Installing : Phase::Idle;
    }
    Phase phase() const { return phase_; }
    // A click while busy says so only for a running download / install (a prompt is on screen).
    bool busyWithDownload() const { return phase_ == Phase::Downloading || phase_ == Phase::Installing; }

private:
    Phase phase_ = Phase::Idle;
    bool interactive_ = false;
};

// "Once a day": the automatic check was only consulted at app start, so a PC that stays on
// (sleep / resume) never checked again. Due when 24 h passed since the last automatic check
// (or the clock went back). Times in seconds (time()).
constexpr unsigned long long kAutoCheckIntervalSec = 24ull * 3600ull;
inline bool autoCheckDueAt(unsigned long long now, unsigned long long last) {
    return now < last || now - last >= kAutoCheckIntervalSec;
}
// Milliseconds for a one-shot timer to the next due check (no polling): 0 = due now. Never
// below `floorMs` when not due (a timer that fires early re-arms for the rest).
inline unsigned autoCheckDelayMs(unsigned long long now, unsigned long long last, unsigned floorMs = 60000) {
    if (autoCheckDueAt(now, last)) return 0;
    const unsigned long long ms = (kAutoCheckIntervalSec - (now - last)) * 1000ull;
    return ms < floorMs ? floorMs : static_cast<unsigned>(ms);
}

// The downloaded MSI's Authenticode check. The pinned publisher is never relaxed; only the
// reason is told apart: a chain whose revocation status could not be fetched (offline, a
// proxy blocking the CRL / OCSP servers) is "could not verify", worth a retry or a manual
// download — not "wrongly signed". Only Trusted is ever installed.
//   wvtStatus  WinVerifyTrust's result as an HRESULT
//   signer     the leaf signer's name vs the pinned publisher (Unknown: not readable)
enum class SignatureCheck { Trusted, Unverifiable, Untrusted };
enum class Signer { Matches, Differs, Unknown };
constexpr uint32_t kCertERevocationFailure = 0x800B010Eu;   // CERT_E_REVOCATION_FAILURE
constexpr uint32_t kCryptERevocationOffline = 0x80092013u;  // CRYPT_E_REVOCATION_OFFLINE
constexpr uint32_t kCryptENoRevocationCheck = 0x80092012u;  // CRYPT_E_NO_REVOCATION_CHECK
inline bool revocationUnreachable(uint32_t wvtStatus) {
    return wvtStatus == kCertERevocationFailure || wvtStatus == kCryptERevocationOffline ||
           wvtStatus == kCryptENoRevocationCheck;
}
inline SignatureCheck classifySignature(uint32_t wvtStatus, bool publisherPinned, Signer signer) {
    if (!publisherPinned || signer == Signer::Differs) return SignatureCheck::Untrusted;
    if (wvtStatus == 0) return signer == Signer::Matches ? SignatureCheck::Trusted : SignatureCheck::Untrusted;
    return revocationUnreachable(wvtStatus) ? SignatureCheck::Unverifiable : SignatureCheck::Untrusted;
}

}  // namespace vtx
