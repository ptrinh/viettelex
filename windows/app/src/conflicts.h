// conflicts.h — other Vietnamese input methods (app/core/onboarding.h): which run, which
// Microsoft Vietnamese keyboards are in the user's list, and the actions the warning
// offers. Runs only when the welcome window or the Kiểu gõ page is shown — never in the
// background. VietTelex never quits or uninstalls other software.
#pragma once
#include <windows.h>

#include <string>
#include <vector>

#include "onboarding.h"

namespace vtx::app {

struct FoundConflict {
    ConflictKind kind = ConflictKind::UniKey;
    std::wstring name;   // product name, or the keyboard's description
    std::wstring path;   // running image (third-party IMEs)
    ViProfile profile;   // Microsoft keyboards
};

std::vector<FoundConflict> detectConflicts();
std::wstring conflictNames(const std::vector<FoundConflict>& list);  // "UniKey, Vietnamese Telex"
// The warning's sentence(s): two IMEs at once, and/or Windows' own Ctrl+Shift.
std::wstring conflictDescription(const std::vector<FoundConflict>& list);
// Task dialog: open the other app's folder / how to quit it / remove a Microsoft keyboard
// from the list (InstallLayoutOrTip ILOT_UNINSTALL, else ms-settings:regionlanguage).
void resolveConflicts(HWND owner, const std::vector<FoundConflict>& list);
// One click (welcome row / conflict dialog): remove every Windows built-in Vietnamese
// keyboard of `list` from the user's own list (app_feel.h builtInKeyboardRemovals), then
// make VietTelex the default input method and select it. Third-party software untouched.
// True = all removed.
bool removeBuiltInVietnameseKeyboards(const std::vector<FoundConflict>& list);

}  // namespace vtx::app
