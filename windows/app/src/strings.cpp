#include "strings.h"

#include <cstddef>

namespace vtx::app {

namespace {
bool g_en = false;

struct Pair {
    const wchar_t* vi;
    const wchar_t* en;
};

const Pair kStrings[] = {
    /* AppName */ {L"VietTelex", L"VietTelex"},
    /* TrayTip */ {L"VietTelex — bộ gõ tiếng Việt", L"VietTelex — Vietnamese input"},
    /* MenuSettings */ {L"Cài đặt…", L"Settings…"},
    /* MenuCheckUpdate */ {L"Kiểm tra cập nhật", L"Check for updates"},
    /* MenuAbout */ {L"Giới thiệu", L"About"},
    /* MenuQuit */ {L"Thoát (vẫn gõ được tiếng Việt)", L"Quit (typing keeps working)"},
    /* TabTyping */ {L"Kiểu gõ", L"Typing"},
    /* TabSpelling */ {L"Chính tả", L"Spelling"},
    /* TabShortcuts */ {L"Gõ tắt", L"Shortcuts"},
    /* TabApps */ {L"Ứng dụng", L"Apps"},
    /* TabAbout */ {L"Giới thiệu", L"About"},
    /* InputMethod */ {L"Kiểu gõ:", L"Input method:"},
    /* Telex */ {L"Telex", L"Telex"},
    /* Vni */ {L"VNI", L"VNI"},
    /* SimpleTelex */ {L"Telex đơn giản (w đứng lẻ giữ nguyên w)", L"Simple Telex (a lone w stays w)"},
    /* FreeMarking */ {L"Bỏ dấu tự do", L"Free tone placement"},
    /* QuickTelex */ {L"Gõ nhanh (cc→ch, nn→ng…)", L"Quick Telex (cc→ch, nn→ng…)"},
    /* ModernOrthography */ {L"Bỏ dấu kiểu mới (hoà, thuý)", L"Modern tone placement (hoà, thuý)"},
    /* BracketVowels */ {L"Phím [ ] gõ ơ ư", L"[ ] keys type ơ ư"},
    /* AutoRestore */ {L"Tự khôi phục từ tiếng Anh", L"Restore English words"},
    /* LiveSpellCheck */ {L"Kiểm tra chính tả khi gõ", L"Spell-check while typing"},
    /* ContextualEnglish */ {L"Quyết định theo ngữ cảnh", L"Decide from context"},
    /* CollisionPrefersVi */ {L"Ưu tiên tiếng Việt khi trùng", L"Prefer Vietnamese on collisions"},
    /* Teencode */ {L"Chính tả teencode", L"Teencode spelling"},
    /* ReEditWord */ {L"Gõ lại dấu cho từ trước con trỏ", L"Re-edit the word before the caret"},
    /* SwitchHotkey */ {L"Phím chuyển Việt/Anh:", L"Vietnamese/English switch:"},
    /* HotkeyCtrlShift */ {L"Ctrl+Shift (kiểu UniKey)", L"Ctrl+Shift (UniKey style)"},
    /* HotkeyWinSpace */ {L"Win+Space (bộ chuyển của Windows)", L"Win+Space (Windows switcher)"},
    /* HotkeyAltZ */ {L"Alt+Z", L"Alt+Z"},
    /* HotkeyOff */ {L"Tắt (bấm nút V/E trên thanh tác vụ)", L"Off (click the V/E taskbar button)"},
    /* HotkeyNote */
    {L"Trạng thái Việt/Anh được nhớ riêng cho từng ứng dụng.",
     L"Vietnamese/English is remembered per application."},
    /* MenuIcon */ {L"Biểu tượng:", L"Icon:"},
    /* MenuIconVt */ {L"Vᴛ", L"Vᴛ"},
    /* MenuIconLetter */ {L"V / E", L"V / E"},
    /* UiLanguage */ {L"Ngôn ngữ giao diện:", L"Interface language:"},
    /* AutoUpdateCheck */ {L"Tự kiểm tra cập nhật (mỗi ngày một lần)", L"Check for updates automatically (daily)"},
    /* DebugLogging */ {L"Ghi log gỡ lỗi (không ghi nội dung gõ)", L"Debug log (never records typed text)"},
    /* ShortcutKey */ {L"Viết tắt", L"Abbreviation"},
    /* ShortcutValue */ {L"Nội dung", L"Expands to"},
    /* Add */ {L"Thêm", L"Add"},
    /* Remove */ {L"Xoá", L"Remove"},
    /* Import */ {L"Nhập…", L"Import…"},
    /* Export */ {L"Xuất…", L"Export…"},
    /* AppExe */ {L"Tệp chạy (vd. notepad.exe)", L"Executable (e.g. notepad.exe)"},
    /* AppModeLabel */ {L"Chế độ", L"Mode"},
    /* ModeComposition */ {L"Mặc định (composition)", L"Default (composition)"},
    /* ModeInPlace */ {L"Sửa trực tiếp (in-place)", L"In-place"},
    /* ModeHook */ {L"Dự phòng (hook bàn phím)", L"Fallback (keyboard hook)"},
    /* ModeOff */ {L"Luôn tiếng Anh", L"Always English"},
    /* AppsNote */
    {L"Chỉ đổi khi một ứng dụng gõ sai. \"Dự phòng\" cần VietTelex đang chạy.",
     L"Only change this for an app that misbehaves. \"Fallback\" needs VietTelex running."},
    /* AboutText */
    {L"VietTelex — bộ gõ tiếng Việt tối giản, nhanh, ổn định.\nKhông thu thập dữ liệu. Mã nguồn mở (MIT).",
     L"VietTelex — a minimal, fast, stable Vietnamese input method.\nNo data collection. Open source (MIT)."},
    /* CheckNow */ {L"Kiểm tra cập nhật", L"Check for updates"},
    /* UpToDate */ {L"Bạn đang dùng bản mới nhất.", L"You are up to date."},
    /* UpdateAvailable */ {L"Có bản mới %s. Tải và cài đặt?", L"Version %s is available. Download and install?"},
    /* UpdateFailed */ {L"Không kiểm tra được cập nhật.", L"Could not check for updates."},
    /* UpdateBadSignature */
    {L"Tệp cài đặt tải về không có chữ ký hợp lệ — đã huỷ.", L"The downloaded installer is not validly signed — cancelled."},
    /* ImportFailed */ {L"Không đọc được tệp gõ tắt.", L"Could not read the shortcut file."},
};
static_assert(sizeof(kStrings) / sizeof(kStrings[0]) == static_cast<size_t>(S::Count), "string table size");
}  // namespace

const wchar_t* tr(S id) {
    const Pair& p = kStrings[static_cast<size_t>(id)];
    return g_en ? p.en : p.vi;
}

void setEnglish(bool en) { g_en = en; }

}  // namespace vtx::app
