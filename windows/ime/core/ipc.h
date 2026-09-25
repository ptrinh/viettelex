// ipc.h — commands the TIP's language-bar menu sends to VietTelex.exe. The TIP never
// writes settings itself (spec §9); it asks the app, which saves and re-publishes the
// snapshot. Transport: PostMessage(kAppCommandMsg, cmd) to the app's hidden window, or
// `VietTelex.exe --command <n>` when the app is not running.
#pragma once

namespace vtx {

enum class AppCommand : unsigned {
    OpenSettings = 1,
    CheckUpdate = 2,
    SetTelex = 3,
    SetVni = 4,
    OpenAbout = 5,
};

inline bool isValidAppCommand(unsigned v) { return v >= 1 && v <= 5; }

}  // namespace vtx
