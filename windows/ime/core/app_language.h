// app_language.h — per-app Vietnamese/English memory (the in-TIP switch: Ctrl+Shift,
// Alt+Z, tray). Keyed by app identity (lower-case exe; WebView2 -> the owning app's exe,
// consoles -> conhost.exe), default Vietnamese, survives restarts.
//
// Store of record: HKCU\Software\VietTelex\AppLanguage\<exe> (DWORD). AppContainer and
// low-IL hosts (Start search, UWP) can neither read nor write HKCU, so VietTelex.exe
// mirrors the map to %LOCALAPPDATA%\VietTelex\applang.txt (readable by AppContainers)
// and records their toggles for them (AppCommand::SetAppLanguage). This is the text
// form of that mirror. Pure; unit-tested.
#pragma once
#include <map>
#include <string>

namespace vtx {

class AppLanguageStore {
public:
    bool vietnamese(const std::string& app) const;  // default true
    bool known(const std::string& app) const { return map_.count(app) != 0; }
    void set(const std::string& app, bool vietnamese);
    const std::map<std::string, bool>& entries() const { return map_; }

    // "exe<TAB>0|1" per line, sorted; parse() ignores malformed lines.
    std::string serialize() const;
    void parse(const std::string& text);

private:
    std::map<std::string, bool> map_;
};

}  // namespace vtx
