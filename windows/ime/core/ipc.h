// ipc.h — messages to VietTelex.exe's hidden window (PostMessage(kAppCommandMsg, cmd,
// lParam)) or `VietTelex.exe --command <n>` when the app is not running. The TIP never
// writes settings itself (spec §9).
//   StateChanged (TIP -> app): lParam 1 = Vietnamese, 0 = English, for the app that has
//   focus — drives the optional tray icon, the only Việt/Anh indicator since 1.0.8.
#pragma once

namespace vtx {

enum class AppCommand : unsigned {
    OpenSettings = 1,
    CheckUpdate = 2,
    SetTelex = 3,
    SetVni = 4,
    OpenAbout = 5,
    StateChanged = 6,
};

inline bool isValidAppCommand(unsigned v) { return v >= 1 && v <= 6; }
// Commands a user may pass as `--command <n>` (StateChanged is TIP-internal).
inline bool isUserCommand(unsigned v) { return v >= 1 && v <= 5; }

}  // namespace vtx
