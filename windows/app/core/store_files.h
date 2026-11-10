// store_files.h — the files VietTelex.exe keeps in %LOCALAPPDATA%\VietTelex (2026-11 audit).
// Pure decisions, unit-tested; the Win32 side is app/src/settings_store.cpp.
#pragma once
#include <string>

namespace vtx {

// "Gỡ sạch" (uninstall, --cleanup-user) deletes these by NAME, then removes the folder if it
// is empty — never a wildcard delete of whatever else a user put there:
//   settings.bin(.tmp)        the TIP snapshot
//   learned-words.bin(.tmp)   "Học từ bạn gõ"
//   applang.txt(.tmp)         per-app Việt/Anh mirror for AppContainer hosts
//   debug.log, debug.1.log    "Ghi nhật ký gỡ lỗi"
//   update-*.log              msiexec's verbose logs and update-watcher.log
// Case-insensitive; a bare file name (no folder).
bool isUserDataFileName(const std::wstring& name);

// The folder's ACL grants AppContainers read access (settings.bin, applang.txt). Every save
// rewrote that DACL (GetNamedSecurityInfo + SetEntriesInAcl + SetNamedSecurityInfo). Now:
// when the folder was just created, or once per process when the grant is not there.
inline bool appContainerGrantNeeded(bool folderJustCreated, bool checkedThisProcess, bool grantPresent) {
    if (folderJustCreated) return true;
    return !checkedThisProcess && !grantPresent;
}

}  // namespace vtx
