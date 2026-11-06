// portable.h — the portable build (docs/WINDOWS-APP-FEEL-SPEC.md "Bản portable"): the same
// VietTelex.exe, unzipped anywhere, typing with the keyboard-hook path for EVERY app.
// Portable decisions only (unit-tested on any OS); the Win32 side is app/src/main.cpp,
// settings_store.cpp, foreground.cpp and hook_fallback.cpp.
//
//   * Mode: a marker file next to the exe (portable.ini or VietTelex.portable).
//   * Never touches TSF, COM, HKLM or the installed build's data: settings live in
//     settings.ini next to the exe (fallback %APPDATA%\VietTelex\settings.ini when that
//     folder is read-only); its own single-instance mutex and window class, so the
//     installed TIP never talks to it.
//   * Typing: the hook types in every foreground app except "Luôn tiếng Anh" apps and
//     password fields; it YIELDS wherever the installed VietTelex keyboard (or any other
//     Vietnamese keyboard) is active, so no tone is ever added twice.
//   * No self-update: "Kiểm tra cập nhật" opens the download page.
#pragma once
#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "app_policy.h"

namespace vtx::portable {

// Marker files (either one). portable.ini ships in the zip.
constexpr const wchar_t* kMarkerNames[] = {L"portable.ini", L"VietTelex.portable"};
constexpr const wchar_t* kSettingsFileName = L"settings.ini";
// Distinct from the installed app's "Local\VietTelex.App" / "VietTelexAppWindow".
constexpr const wchar_t* kMutexName = L"Local\\VietTelex.Portable";
constexpr const wchar_t* kWindowClass = L"VietTelexPortableWindow";
// Where "Kiểm tra cập nhật" sends a portable user (anchor on the download page).
constexpr const wchar_t* kDownloadPageUrl = L"https://viettelex.com/download/?os=windows#portable";

// "C:\\x\\VietTelex.exe" -> "C:\\x" (no trailing separator); a bare name -> "".
std::wstring exeDirOf(const std::wstring& exePath);
// dir + "\\" + name, without doubling a trailing separator.
std::wstring joinPath(const std::wstring& dir, const std::wstring& name);
// Portable when one of the marker files exists next to the exe.
bool detectPortable(const std::wstring& exeDir, const std::function<bool(const std::wstring&)>& fileExists);
// settings.ini next to the exe when that folder is writable, else under %APPDATA%
// (appData\VietTelex\settings.ini); "" when neither is known.
std::wstring settingsPath(const std::wstring& exeDir, bool exeDirWritable, const std::wstring& appData);

// The installed app (its main window) is running: the portable copy says so and exits
// instead of running a second Ctrl+Shift watcher / tray next to it.
enum class StartAction { Run, ExitInstalledRunning };
inline StartAction decideStart(bool installedAppRunning) {
    return installedAppRunning ? StartAction::ExitInstalledRunning : StartAction::Run;
}

// The installed VietTelex keyboard (tipProp 1/2) or any Vietnamese keyboard (Windows'
// own, the installed TIP before it set its prop) is active in the foreground window:
// the portable hook stays out there.
bool yields(int tipProp, unsigned fgLangId);

// Hook decision for the foreground app. Portable has no TIP behind the hook, so the
// "Direct" echo fallback to composition does not exist: always plain hook typing.
struct HookPlan {
    bool install = false;
    bool direct = false;
};
HookPlan hookPlan(AppMode mode, bool passwordField, bool yieldsHere);
// A classic Win32 password box (Edit / RichEdit with ES_PASSWORD). Browser and UWP password
// fields are not visible to a keyboard hook (documented limit of the portable build).
bool isPasswordField(const std::string& windowClass, uint32_t style);

// HKCU Run value: "<exe>" --background, pointing at THIS copy.
std::wstring autostartCommand(const std::wstring& exePath);
bool autostartPointsHere(const std::wstring& runValue, const std::wstring& exePath);

// ---- settings.ini: the registry values the installed build keeps under HKCU -------------
// One value per line, "name=type:data" (UTF-8). Types: dword (decimal), qword (decimal),
// sz (escaped: \\ \n \r \t), hex (binary). Lines starting with ';' or '#', blank lines
// and a "[VietTelex]" header are ignored, as is any malformed line.
class KeyValueFile {
public:
    enum class Type { Dword, Qword, String, Binary };
    struct Value {
        Type type = Type::Dword;
        uint64_t number = 0;
        std::string bytes;  // String: UTF-8 text; Binary: raw bytes
    };

    bool getDword(const std::string& name, uint32_t& out) const;
    bool getQword(const std::string& name, uint64_t& out) const;
    bool getString(const std::string& name, std::string& out) const;
    bool getBinary(const std::string& name, std::string& out) const;
    void setDword(const std::string& name, uint32_t v);
    void setQword(const std::string& name, uint64_t v);
    void setString(const std::string& name, const std::string& v);
    void setBinary(const std::string& name, const std::string& v);
    void remove(const std::string& name) { map_.erase(name); }
    void clear() { map_.clear(); }
    // Names starting with `prefix` (prefix stripped), DWORD values only.
    std::map<std::string, uint32_t> dwordsWithPrefix(const std::string& prefix) const;
    const std::map<std::string, Value>& entries() const { return map_; }

    std::string serialize() const;
    void parse(const std::string& text);

    // A name must be non-empty, without '=', CR or LF (exe names and setting keys are).
    static bool validName(const std::string& name);

private:
    std::map<std::string, Value> map_;
};

}  // namespace vtx::portable
