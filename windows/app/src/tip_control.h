// tip_control.h — per-user setup the per-machine MSI cannot do: add the VietTelex
// keyboard to the current user's language list, autostart, and clean removal.
#pragma once

namespace vtx::app {

bool addKeyboardForUser();     // InstallLayoutOrTip("042A:{CLSID}{PROFILE}")
bool removeKeyboardForUser();  // same with ILOT_UNINSTALL
void setAutostart(bool on);    // HKCU\...\Run "VietTelex" = "<exe>" --background
bool autostartEnabled();

}  // namespace vtx::app
