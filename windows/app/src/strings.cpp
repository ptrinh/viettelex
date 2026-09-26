#include "strings.h"

#include <cstddef>

namespace vtx::app {

namespace {
bool g_en = false;

struct Pair {
    const wchar_t* vi;
    const wchar_t* en;
};

// Order == enum S. Setting titles/descriptions follow macOS Localizable.strings.
const Pair kStrings[] = {
    {L"VietTelex", L"VietTelex"},
    {L"VietTelex — bộ gõ tiếng Việt", L"VietTelex — Vietnamese input"},
    {L"Cài đặt…", L"Settings…"},
    {L"Kiểm tra cập nhật", L"Check for updates"},
    {L"Giới thiệu", L"About"},
    {L"Ẩn biểu tượng khay", L"Hide tray icon"},

    {L"Kiểu gõ", L"Typing"},
    {L"Chính tả", L"Spelling"},
    {L"Gõ tắt", L"Shortcuts"},
    {L"Ứng dụng", L"Apps"},
    {L"Giới thiệu", L"About"},

    {L"Kiểu gõ", L"Input style"},
    {L"Chuyển Việt/Anh", L"Vietnamese/English switch"},
    {L"Giao diện", L"Appearance"},
    {L"Chính tả", L"Spelling"},
    {L"Bảng gõ tắt", L"Shortcut table"},
    {L"Chế độ theo ứng dụng", L"Per-app modes"},
    {L"Cập nhật", L"Updates"},
    {L"Chẩn đoán", L"Diagnostics"},
    {L"Gỡ cài đặt", L"Uninstall"},

    {L"Kiểu gõ", L"Typing method"},
    {L"VNI: gõ dấu bằng chữ số — 1-5 = sắc/huyền/hỏi/ngã/nặng, 6 = â/ê/ô, 7 = ơ/ư, 8 = ă, 9 = đ, 0 = bỏ dấu.",
     L"VNI: diacritics with digits — 1-5 = sắc/huyền/hỏi/ngã/nặng, 6 = â/ê/ô, 7 = ơ/ư, 8 = ă, 9 = đ, 0 = clear tone."},
    {L"Telex", L"Telex"},
    {L"VNI", L"VNI"},
    {L"Telex đơn giản", L"Simple Telex"},
    {L"Chữ w đứng một mình luôn là 'w' (gõ 'uw' để ra ư). Tắt = Telex đầy đủ (cw→cư).",
     L"A lone “w” stays “w” (type “uw” for ư). Off = full Telex (cw→cư)."},
    {L"Bỏ dấu tự do", L"Free tone placement"},
    {L"Tắt = Telex nghiêm ngặt: dấu chỉ nhận khi gõ sát nguyên âm, hợp cho English/code (data→data). Bật: dấu đặt tự do (ama→âm).",
     L"Off = strict Telex: tones apply only next to a vowel — good for English/code (data→data). On: free placement (ama→âm)."},
    {L"Gõ nhanh (Quick Telex)", L"Quick Telex"},
    {L"Gõ đúp phụ âm đầu để ra phụ âm ghép: cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th.",
     L"Doubled first consonant expands: cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th."},
    {L"Bỏ dấu kiểu mới (oà, uý)", L"Modern tone placement (oà, uý)"},
    {L"Tắt = kiểu cũ (hòa, thủy, khỏe). Bật = kiểu mới (hoà, thuý, khoẻ). Chỉ đổi vị trí dấu ở oa/oe/uy.",
     L"Off = old style (hòa, thủy, khỏe). On = new style (hoà, thuý, khoẻ). Only oa/oe/uy differ."},
    {L"Phím ngoặc: [ ra ơ, ] ra ư", L"Bracket vowels: [ types ơ, ] types ư"},
    {L"Thói quen UniKey: “th[” → “thơ”, “ng]” → “ngư”. Nếu bạn gõ code thì nên để TẮT.",
     L"The UniKey habit: “th[” → “thơ”, “ng]” → “ngư”. Leave OFF if you type code."},
    {L"Tự khôi phục từ không hợp lệ", L"Auto-restore invalid words"},
    {L"Từ không phải tiếng Việt hợp lệ sẽ tự trả về đúng phím đã gõ khi kết thúc từ (retore → retore).",
     L"A word that isn’t valid Vietnamese snaps back to the keys you typed when the word ends (retore → retore)."},
    {L"Kiểm tra chính tả khi gõ", L"Live spell-check"},
    {L"Ngừng bỏ dấu ngay khi từ không thể là tiếng Việt (google, github…) thay vì đợi hết từ.",
     L"Stop adding tones as soon as a word can’t be Vietnamese (google, github…) instead of waiting for word end."},
    {L"Quyết định theo ngữ cảnh", L"Context-based decision"},
    {L"Sau một từ tiếng Anh, từ nhập nhằng kế tiếp được giữ tiếng Anh — “he is” → “he is”, không phải “he í”. Sau từ tiếng Việt thì để tiếng Việt — “sao í”.",
     L"After an English word, an ambiguous next word stays English — “he is”, not “he í”. After a Vietnamese word it stays Vietnamese — “sao í”."},
    {L"Ưu tiên tiếng Việt khi trùng", L"Prefer Vietnamese on collisions"},
    {L"Cho các từ như last/lát, list/lít, his/hí: gõ đúp phím dấu để giữ tiếng Anh (lisst → list).",
     L"For words like last/lát, list/lít, his/hí: double the tone key to keep English (lisst → list)."},
    {L"Chính tả teencode", L"Teencode spelling"},
    {L"Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó). Tắt = chỉ chính tả chuẩn.",
     L"Accept chat spellings: w/z/k instead of qu/d/c (wá, zui zẻ, kó). Off = standard spelling only."},
    {L"Gõ thêm dấu cho từ trước con trỏ", L"Add diacritics to the word before the caret"},
    {L"Đặt con trỏ ngay sau một từ rồi gõ phím dấu (toan + s → toán); ⌫ ngay sau dấu cách sửa tiếp từ vừa gõ.",
     L"Put the caret right after a word and type a tone key (toan + s → toán); ⌫ right after a space re-opens the word."},
    {L"Phím chuyển Việt/Anh", L"Switch hotkey"},
    {L"Trạng thái Việt/Anh được nhớ riêng cho từng ứng dụng.", L"Vietnamese/English is remembered per application."},
    {L"Ctrl+Shift (kiểu UniKey)", L"Ctrl+Shift (UniKey style)"},
    {L"Win+Space (của Windows)", L"Win+Space (Windows)"},
    {L"Alt+Z", L"Alt+Z"},
    {L"Tắt", L"Off"},
    {L"Biểu tượng bàn phím", L"Keyboard icon"},
    {L"Hiện trên thanh tác vụ và trong danh sách bàn phím (Win+Space); đổi cần quyền quản trị. Bật biểu tượng ở khay nếu muốn thấy trạng thái Việt/Anh.",
     L"Shown on the taskbar and in the keyboard list (Win+Space); changing it needs admin rights. Turn on the tray icon to see Vietnamese/English."},
    {L"Vᴛ", L"Vᴛ"},
    {L"Ngôi sao", L"Star"},
    {L"Cờ Việt Nam", L"Vietnam flag"},
    {L"Logo", L"Logo"},
    {L"Chữ VI", L"VI text"},
    {L"Hiện biểu tượng ở khay hệ thống", L"Show icon in the notification area"},
    {L"Hiện trạng thái Việt/Anh của ứng dụng đang dùng (biểu tượng mờ = tiếng Anh). Tắt thì mở lại Cài đặt bằng VietTelex trong menu Start.",
     L"Shows Vietnamese/English for the app in use (dimmed icon = English). When off, reopen Settings from VietTelex in the Start menu."},
    {L"Ngôn ngữ", L"Language"},
    {L"Ngôn ngữ của cửa sổ này và menu khay.", L"Language of this window and the tray menu."},
    {L"Tự kiểm tra cập nhật", L"Check for updates automatically"},
    {L"Mỗi ngày một lần hỏi viettelex.com có bản mới không. Không gửi dữ liệu nào khác.",
     L"Asks viettelex.com once a day whether a new version exists. Nothing else is sent."},
    {L"Ghi nhật ký gỡ lỗi", L"Record debug log"},
    {L"Ghi sự kiện chẩn đoán (không ghi nội dung bạn gõ).", L"Records diagnostic events (never the text you type)."},
    {L"Kiểm tra cập nhật", L"Check for updates"},
    {L"Chỉ kết nối mạng khi bạn bấm nút này hoặc bật tự kiểm tra.",
     L"VietTelex only goes online when you click this or enable automatic checks."},
    {L"Kiểm tra ngay", L"Check now"},
    {L"Gỡ cài đặt VietTelex", L"Uninstall VietTelex"},
    {L"Gỡ bộ gõ và ứng dụng khỏi máy. Cài đặt của bạn được xoá.",
     L"Removes the input method and the app from this PC. Your settings are deleted."},
    {L"Gỡ cài đặt…", L"Uninstall…"},
    {L"Gỡ VietTelex khỏi máy này? Bộ gõ, ứng dụng và cài đặt của bạn sẽ bị xoá.",
     L"Uninstall VietTelex from this PC? The input method, the app and your settings will be removed."},

    {L"Gõ viết tắt rồi gõ dấu cách để bung ra nội dung. Nhập/xuất tệp YAML, JSON hoặc văn bản.",
     L"Type an abbreviation then a space to expand it. Import/export YAML, JSON or plain text."},
    {L"Viết tắt", L"Abbreviation"},
    {L"Nội dung", L"Expands to"},
    {L"Thêm", L"Add"},
    {L"Xoá", L"Remove"},
    {L"Nhập…", L"Import…"},
    {L"Xuất…", L"Export…"},
    {L"Chỉ đổi khi một ứng dụng gõ sai. “Dự phòng” cần VietTelex đang chạy.",
     L"Only change this for an app that types wrong. “Fallback” needs VietTelex running."},
    {L"Tệp chạy (vd. notepad.exe)", L"Executable (e.g. notepad.exe)"},
    {L"Chế độ", L"Mode"},
    {L"Composition (nếu sửa trực tiếp gõ sai)", L"Composition (if in-place misbehaves)"},
    {L"Mặc định (sửa trực tiếp)", L"Default (in-place)"},
    {L"Dự phòng (hook bàn phím)", L"Fallback (keyboard hook)"},
    {L"Luôn tiếng Anh", L"Always English"},
    {L"Chưa có gõ tắt nào", L"No shortcuts yet"},
    {L"Chưa có ứng dụng nào", L"No apps yet"},

    {L"Bộ gõ tiếng Việt tối giản, nhanh, ổn định. Không thu thập dữ liệu. Mã nguồn mở (MIT).",
     L"A minimal, fast, stable Vietnamese input method. No data collection. Open source (MIT)."},
    {L"Phiên bản", L"Version"},
    {L"viettelex.com", L"viettelex.com"},
    {L"Mã nguồn trên GitHub", L"Source on GitHub"},
    {L"Học gõ Telex", L"Learn Telex typing"},
    {L"Bật", L"On"},
    {L"Tắt", L"Off"},

    {L"Bạn đang dùng bản mới nhất.", L"You are up to date."},
    {L"Có bản mới %s. Tải và cài đặt?", L"Version %s is available. Download and install?"},
    {L"Không kiểm tra được cập nhật.", L"Could not check for updates."},
    {L"Tệp cài đặt tải về không có chữ ký hợp lệ — đã huỷ.", L"The downloaded installer is not validly signed — cancelled."},
    {L"Không đọc được tệp gõ tắt.", L"Could not read the shortcut file."},
};
static_assert(sizeof(kStrings) / sizeof(kStrings[0]) == static_cast<size_t>(S::Count), "string table size");
}  // namespace

const wchar_t* tr(S id) {
    const Pair& p = kStrings[static_cast<size_t>(id)];
    return g_en ? p.en : p.vi;
}

void setEnglish(bool en) { g_en = en; }

}  // namespace vtx::app
