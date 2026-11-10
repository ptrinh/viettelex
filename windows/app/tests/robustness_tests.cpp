// 2026-11 robustness audit of the Windows app: the pure decisions behind the fixes
// (portable settings saves, the hook's deferred debug lines, "gỡ sạch", the update flow,
// the uninstall watcher).
#include <cwchar>
#include <string>
#include <vector>

#include "log_queue.h"
#include "portable.h"
#include "setup_helper_logic.h"
#include "store_files.h"
#include "strings.h"
#include "test.h"
#include "update_check.h"

using namespace vtx;

// ---- portable settings.ini: written after the lock, in order ---------------------------

// Two saves race to the disk: the later one (staged second under the settings lock) must
// win even when the earlier one reaches the file lock last.
TEST(portable_save_sequencer_never_lets_an_older_save_overwrite) {
    portable::SaveSequencer q;
    const uint64_t a = q.stage(), b = q.stage();
    CHECK(a < b);
    CHECK(q.shouldWrite(b));  // b got the file lock first
    q.done(b);
    CHECK(!q.shouldWrite(a));  // a is older: skipped
    q.done(a);
    const uint64_t c = q.stage();
    CHECK(q.shouldWrite(c));  // a newer one still writes
    q.done(c);
    // A failed write still counts as done: an older save waiting behind it stays skipped.
    const uint64_t d = q.stage(), e = q.stage();
    q.done(e);
    CHECK(!q.shouldWrite(d));
    // In order: each write goes.
    const uint64_t f = q.stage();
    CHECK(q.shouldWrite(f));
    q.done(f);
    const uint64_t g = q.stage();
    CHECK(q.shouldWrite(g));
}

// ---- debug lines of the keyboard hook: queued, one writer, in order --------------------

TEST(deferred_lines_schedule_one_writer_and_keep_order) {
    DeferredLines<int> q;
    CHECK(q.push(1));   // first line: schedule the writer
    CHECK(!q.push(2));  // writer already scheduled
    CHECK(!q.push(3));
    std::vector<int> batch = q.take();
    CHECK(batch.size() == 3 && batch[0] == 1 && batch[1] == 2 && batch[2] == 3);
    CHECK(q.scheduled());  // the writer loops: takes again
    CHECK(!q.push(4));     // queued while the writer still runs: it picks this up
    batch = q.take();
    CHECK(batch.size() == 1 && batch[0] == 4);
    CHECK(q.take().empty());
    CHECK(!q.scheduled());  // done: the next line schedules a new writer
    CHECK(q.push(5));
    q.scheduleFailed();  // TrySubmitThreadpoolCallback failed: kept for the next push / exit flush
    CHECK(q.size() == 1);
    CHECK(q.push(6));
    batch = q.take();
    CHECK(batch.size() == 2 && batch[0] == 5 && batch[1] == 6);
}

TEST(deferred_lines_are_bounded) {
    DeferredLines<int> q;
    for (size_t i = 0; i < DeferredLines<int>::kMaxQueued + 10; ++i) q.push(static_cast<int>(i));
    CHECK(q.size() == DeferredLines<int>::kMaxQueued);
    CHECK(q.takeDropped() == 10);
    CHECK(q.takeDropped() == 0);
}

// ---- "gỡ sạch": every file VietTelex writes, by name ------------------------------------

TEST(uninstall_erases_every_user_data_file_by_name) {
    for (const wchar_t* n : {L"settings.bin", L"settings.bin.tmp", L"learned-words.bin", L"learned-words.bin.tmp",
                             L"applang.txt", L"applang.txt.tmp", L"debug.log", L"debug.1.log", L"update-1.3.21.log",
                             L"update-watcher.log", L"Debug.Log", L"UPDATE-1.0.0.LOG"})
        CHECK(isUserDataFileName(n));
    for (const wchar_t* n : {L"", L"notes.txt", L"settings.ini", L"debug.2.log", L"update-.log", L"update-1.0.0.txt",
                             L"mysettings.bin", L"..\\settings.bin", L"sub/debug.log", L"update.log"})
        CHECK(!isUserDataFileName(n));
}

TEST(app_container_grant_only_when_needed) {
    CHECK(appContainerGrantNeeded(true, true, true));     // folder just created: always
    CHECK(appContainerGrantNeeded(false, false, false));  // first save, grant missing
    CHECK(!appContainerGrantNeeded(false, false, true));  // first save, already there
    CHECK(!appContainerGrantNeeded(false, true, false));  // later saves: never again
}

// ---- update flow ------------------------------------------------------------------------

TEST(update_flow_single_flight) {
    UpdateFlow f;
    CHECK(f.requestCheck(false) == UpdateFlow::Request::Start);   // automatic check
    CHECK(f.requestCheck(true) == UpdateFlow::Request::Joined);   // a click joins it...
    CHECK(f.checkDone());                                          // ...and gets the answer shown
    CHECK(f.phase() == UpdateFlow::Phase::Idle);
    CHECK(f.beginPrompt());
    CHECK(!f.beginPrompt());                                       // never two prompts
    CHECK(f.requestCheck(true) == UpdateFlow::Request::Busy);     // prompt on screen
    CHECK(!f.busyWithDownload());                                  // ...silently
    f.promptDone(true);
    CHECK(f.phase() == UpdateFlow::Phase::Downloading);
    CHECK(f.requestCheck(true) == UpdateFlow::Request::Busy);     // no second download, no failure box
    CHECK(f.busyWithDownload());
    CHECK(f.requestCheck(false) == UpdateFlow::Request::Busy);
    CHECK(!f.beginPrompt());
    f.downloadDone(false);                                         // failed: back to idle
    CHECK(f.phase() == UpdateFlow::Phase::Idle);
    CHECK(f.requestCheck(false) == UpdateFlow::Request::Start);
    CHECK(!f.checkDone());                                         // automatic only: not interactive
    CHECK(f.beginPrompt());
    f.promptDone(false);                                           // "No"
    CHECK(f.phase() == UpdateFlow::Phase::Idle);
    CHECK(f.requestCheck(true) == UpdateFlow::Request::Start);
    f.checkNotStarted();                                           // CreateThread failed
    CHECK(f.phase() == UpdateFlow::Phase::Idle);
    CHECK(f.requestCheck(true) == UpdateFlow::Request::Start);
    CHECK(f.checkDone());
    CHECK(f.beginPrompt());
    f.promptDone(true);
    f.downloadDone(true);                                          // msiexec started: app exits
    CHECK(f.phase() == UpdateFlow::Phase::Installing);
    CHECK(f.requestCheck(true) == UpdateFlow::Request::Busy);
}

TEST(auto_update_check_due_and_timer) {
    const unsigned long long day = kAutoCheckIntervalSec, t = 1'800'000'000ull;
    CHECK(autoCheckDueAt(t, 0));             // never checked
    CHECK(autoCheckDueAt(t, t - day));
    CHECK(!autoCheckDueAt(t, t - day + 1));
    CHECK(autoCheckDueAt(t, t + 10));        // clock went back
    CHECK(autoCheckDelayMs(t, t - day) == 0);
    CHECK(autoCheckDelayMs(t, t) == day * 1000ull);  // just checked: a day from now (fits a timer)
    CHECK(autoCheckDelayMs(t, t - day + 3600) == 3600u * 1000u);
    CHECK(autoCheckDelayMs(t, t - day + 5) == 60000u);  // floor: never a busy timer
    CHECK(autoCheckDelayMs(t, t - day + 5, 1000) == 5000u);
    CHECK(day * 1000ull < 0x7FFFFFFFull);    // USER_TIMER_MAXIMUM
}

TEST(update_signature_offline_is_not_a_wrong_signer) {
    // The pinned publisher is never relaxed: only Trusted installs.
    CHECK(classifySignature(0, true, Signer::Matches) == SignatureCheck::Trusted);
    CHECK(classifySignature(0, true, Signer::Differs) == SignatureCheck::Untrusted);
    CHECK(classifySignature(0, true, Signer::Unknown) == SignatureCheck::Untrusted);
    CHECK(classifySignature(0, false, Signer::Matches) == SignatureCheck::Untrusted);  // dev build: no pin
    for (uint32_t st : {kCertERevocationFailure, kCryptERevocationOffline, kCryptENoRevocationCheck}) {
        CHECK(classifySignature(st, true, Signer::Matches) == SignatureCheck::Unverifiable);
        CHECK(classifySignature(st, true, Signer::Unknown) == SignatureCheck::Unverifiable);
        CHECK(classifySignature(st, true, Signer::Differs) == SignatureCheck::Untrusted);
        CHECK(classifySignature(st, false, Signer::Matches) == SignatureCheck::Untrusted);
    }
    CHECK(classifySignature(0x800B0100u /* TRUST_E_NOSIGNATURE */, true, Signer::Unknown) == SignatureCheck::Untrusted);
    CHECK(classifySignature(0x80096010u /* TRUST_E_BAD_DIGEST */, true, Signer::Matches) == SignatureCheck::Untrusted);
    CHECK(classifySignature(0x800B010Cu /* CERT_E_REVOKED */, true, Signer::Matches) == SignatureCheck::Untrusted);
}

TEST(update_failure_texts_are_not_the_check_failure) {
    using namespace vtx::app;
    for (int en = 0; en < 2; ++en) {
        setEnglish(en != 0);
        CHECK(std::wcscmp(tr(S::UpdateDownloadFailed), tr(S::UpdateFailed)) != 0);
        CHECK(std::wcscmp(tr(S::UpdateUnverified), tr(S::UpdateBadSignature)) != 0);
        CHECK(std::wcslen(tr(S::UpdateBusy)) > 0);
    }
    setEnglish(false);
    CHECK(std::wstring(kWindowsDownloadPageUrl).rfind(L"https://viettelex.com/", 0) == 0);
}

// ---- uninstall through the update watcher -----------------------------------------------

TEST(uninstall_watcher_args_and_msiexec_path) {
    CHECK(watcherArgs(4242) == std::wstring(L"--wait-install 4242"));
    CHECK(watcherArgs(4242, true) == std::wstring(L"--wait-install 4242 --uninstall"));
    unsigned long pid = 0;
    CHECK(parseWaitInstallArg({L"--wait-install", L"4242", L"--uninstall"}, pid) && pid == 4242);
    CHECK(parseWatcherUninstallArg({L"--wait-install", L"4242", L"--uninstall"}));
    CHECK(!parseWatcherUninstallArg({L"--wait-install", L"4242"}));
    // Uninstall cancelled (UAC no = 1223 through ShellExecute, MSI dialog = 1602): the app comes
    // back; done: nothing is installed any more, nothing starts.
    CHECK(afterInstallAction(true, 1602, false, true) == AfterInstall::LaunchInstalled);
    CHECK(afterInstallAction(true, 0, false, false) == AfterInstall::Nothing);
    CHECK(msiexecPath(L"C:\\Windows\\system32") == std::wstring(L"C:\\Windows\\system32\\msiexec.exe"));
    CHECK(msiexecPath(L"C:\\Windows\\system32\\") == std::wstring(L"C:\\Windows\\system32\\msiexec.exe"));
    CHECK(msiexecPath(L"").empty());
}
