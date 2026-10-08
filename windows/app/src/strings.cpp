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
    {L"VietTelex nhớ Việt/Anh riêng cho từng ứng dụng khi bạn chuyển bằng phím này. Đổi bộ gõ bằng Win+Space thì theo tuỳ chọn của Windows bên dưới.",
     L"VietTelex remembers Vietnamese/English per app when you switch with this key. Switching the input method with Win+Space follows the Windows option below."},
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
    // Bilingual on purpose: findable whichever language the window is in.
    {L"Ngôn ngữ / Language", L"Ngôn ngữ / Language"},
    {L"Ngôn ngữ của cửa sổ này và menu khay. Mặc định tiếng Việt.",
     L"Language of this window and the tray menu. Vietnamese by default."},
    {L"Tự kiểm tra cập nhật", L"Check for updates automatically"},
    {L"Mỗi ngày một lần hỏi viettelex.com có bản mới không. Không gửi dữ liệu nào khác.",
     L"Asks viettelex.com once a day whether a new version exists. Nothing else is sent."},
    {L"Ghi nhật ký gỡ lỗi", L"Record debug log"},
    {L"Ghi sự kiện chẩn đoán vào %LOCALAPPDATA%\\VietTelex\\debug.log (không ghi nội dung bạn gõ).",
     L"Records diagnostic events to %LOCALAPPDATA%\\VietTelex\\debug.log (never the text you type)."},
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

    {L"Gõ viết tắt rồi gõ dấu cách để bung ra nội dung. Nhập/xuất tệp YAML, JSON hoặc văn bản; “Nhập…” đọc "
     L"được cả tệp gõ tắt của UniKey, OpenKey (UTF-8 hoặc UTF-16).",
     L"Type an abbreviation then a space to expand it. Import/export YAML, JSON or plain text; “Import…” also "
     L"reads UniKey and OpenKey macro files (UTF-8 or UTF-16)."},
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
    {L"Trực tiếp (không gạch chân, kiểu UniKey)", L"Direct (no underline, UniKey style)"},
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
    {L"Ứng dụng này chạy với quyền quản trị: chế độ dự phòng không gõ vào được. Chạy VietTelex bằng quyền quản trị hoặc đổi chế độ của ứng dụng.",
     L"This app runs as administrator: fallback mode cannot type into it. Run VietTelex as administrator or change the app's mode."},
    {L"Bạn chuyển Việt/Anh bằng cách đổi bộ gõ của Windows (VietTelex ↔ ENG). Windows đang nhớ bộ gõ riêng cho từng cửa sổ ứng dụng.",
     L"You switch by changing the Windows input method (VietTelex ↔ ENG). Windows keeps a separate input method per app window."},
    {L"Bạn chuyển Việt/Anh bằng cách đổi bộ gõ của Windows (VietTelex ↔ ENG). Hiện đổi ở một ứng dụng là đổi cho mọi ứng dụng — bật tuỳ chọn bên dưới để mỗi ứng dụng giữ bộ gõ riêng.",
     L"You switch by changing the Windows input method (VietTelex ↔ ENG). Right now a change applies to every app — turn on the option below so each app keeps its own."},
    {L"Bạn chuyển Việt/Anh bằng cách đổi bộ gõ của Windows (VietTelex ↔ ENG); nhớ theo từng ứng dụng hay không là do tuỳ chọn Windows bên dưới.",
     L"You switch by changing the Windows input method (VietTelex ↔ ENG); whether it is remembered per app is the Windows option below."},
    {L"Nhớ bộ gõ theo từng ứng dụng (Windows)", L"Input method per app window (Windows)"},
    {L"Đang bật: mỗi cửa sổ ứng dụng giữ bộ gõ riêng (VietTelex hoặc ENG).",
     L"On: each app window keeps its own input method (VietTelex or ENG)."},
    {L"Đang tắt: đổi bộ gõ ở một ứng dụng sẽ đổi cho mọi ứng dụng. Tuỳ chọn “Cho phép dùng bộ gõ khác nhau cho từng cửa sổ ứng dụng” của Windows.",
     L"Off: changing the input method in one app changes it everywhere. Windows option “Let me use a different input method for each app window”."},
    {L"Không đọc được tuỳ chọn này. Mở Cài đặt → Nhập liệu → Cài đặt bàn phím nâng cao để xem.",
     L"Could not read this option. Open Settings → Typing → Advanced keyboard settings to check."},
    {L"Bật", L"Turn on"},
    {L"Mở cài đặt", L"Open Settings"},

    {L"Công cụ văn bản", L"Text tools"},
    {L"Hiện công cụ văn bản trong menu", L"Show text tools in the menu"},
    {L"Bôi đen chữ ở ứng dụng bất kỳ rồi bấm chuột phải biểu tượng VietTelex ở khay → Công cụ văn bản: thêm dấu cho "
     L"đoạn không dấu (toi di hoc → tôi đi học), HOA, thường, Hoa Đầu Từ, Hoa đầu câu, xoá dấu. Cần bật biểu tượng ở khay.",
     L"Select text in any app, then right-click the VietTelex tray icon → Text tools: add tones to unaccented text "
     L"(toi di hoc → tôi đi học), UPPERCASE, lowercase, Title Case, Sentence case, remove tones. Needs the tray icon."},
    {L"Phím tắt Thêm dấu", L"Add-tones hotkey"},
    {L"Thêm dấu cho vùng chọn ở mọi ứng dụng, kể cả khi đang dùng bộ gõ khác. Nơi không đọc được vùng chọn, VietTelex "
     L"sao chép rồi dán kết quả — clipboard của bạn được trả lại. Không chạy trong ô mật khẩu và cửa sổ dòng lệnh.",
     L"Adds tones to the selection in any app, even with another input method active. Where the selection can’t be "
     L"read directly, VietTelex copies it and pastes the result — your clipboard is restored. Never in password "
     L"fields or terminals."},
    {L"Công cụ văn bản", L"Text tools"},
    {L"Thêm dấu cho vùng chọn", L"Add tones to selection"},
    {L"HOA", L"UPPERCASE"},
    {L"thường", L"lowercase"},
    {L"Hoa Đầu Từ", L"Title Case"},
    {L"Hoa đầu câu", L"Sentence case"},
    {L"Xoá dấu", L"Remove tones"},
    {L"Phép tính, chip số, gợi ý sửa lỗi / thêm dấu / ngày giờ, phím tắt Thêm dấu…",
     L"Maths results, number chips, typo/tone/date suggestions, add-tones hotkey…"},
    {L"Hiện kết quả phép tính", L"Show maths results"},
    {L"Gõ phép tính rồi “=” (12*3=, 200+10%=) — kết quả hiện cạnh con trỏ, bấm Tab hoặc Enter để chèn.",
     L"Type a calculation followed by “=” (12*3=, 200+10%=) — the result shows next to the cursor; press Tab or "
     L"Enter to insert it."},
    {L"Chip số", L"Number chips"},
    {L"Gõ số tiền có k/tr/tỷ (50k, 1tr2, 2 tỷ) rồi dấu cách — dạng tiền (1.200.000 ₫) hiện cạnh con trỏ, bấm Tab để "
     L"thay.",
     L"Type an amount with k/tr/tỷ (50k, 1tr2, 2 tỷ) and a space — the money format (1.200.000 ₫) shows next to the "
     L"cursor; press Tab to replace it."},
    {L"Gợi ý sửa lỗi gõ sai", L"Suggest typo fixes"},
    {L"Sau một từ không phải tiếng Việt hay tiếng Anh (tpoi, nayd), từ nhiều khả năng đúng (tôi, này) hiện cạnh con "
     L"trỏ, bấm Tab để thay. Esc: thôi gợi ý từ đó.",
     L"After a word that isn’t Vietnamese or English (tpoi, nayd), a likely fix (tôi, này) shows next to the cursor; "
     L"press Tab to replace it. Esc stops suggesting that word."},
    {L"Gợi ý thêm dấu cho câu không dấu", L"Suggest tones for unaccented sentences"},
    {L"Sau từ 3 âm tiết không dấu trở lên (toi di hoc), khi gõ . ! ? hoặc dừng tay sau dấu cách, câu có dấu (tôi đi "
     L"học) hiện cạnh con trỏ, bấm Tab để thay.",
     L"After 3+ unaccented syllables (toi di hoc), when you type . ! ? or pause after a space, the toned text (tôi đi "
     L"học) shows next to the cursor; press Tab to replace it."},
    {L"Gợi ý ngày giờ", L"Suggest dates and times"},
    {L"Gõ “hôm nay”, “ngày mai”, “hôm qua” hoặc “bây giờ” (sau một từ tiếng Anh: today, tomorrow, yesterday, now) "
     L"rồi dấu cách — ngày (28/09/2026) hoặc giờ (21:35) hiện cạnh con trỏ, bấm Tab để thay cụm đó bằng ngày giờ.",
     L"Type “hôm nay”, “ngày mai”, “hôm qua” or “bây giờ” (after an English word: today, tomorrow, yesterday, now) "
     L"and a space — the date (28/09/2026) or time (21:35) shows next to the cursor; press Tab to replace the words "
     L"with it."},
    {L"Gạch đỏ âm tiết sai chính tả khi gõ", L"Underline misspelled syllables while typing"},
    {L"Từ đang gõ được gạch đỏ khi nó không thể thành âm tiết tiếng Việt (đc, hópng, tòc). Chỉ ở ứng dụng dùng "
     L"chế độ khung soạn (composition); từ giữ nguyên phím gõ hoặc sẽ tự khôi phục (tiếng Anh) không bị gạch.",
     L"The word being typed gets a red squiggle when it can’t become a Vietnamese syllable (đc, hópng, tòc). Only "
     L"in apps that use composition mode; words left as typed or auto-restored (English) are never marked."},

    // Games / fullscreen
    {L"Chơi game / toàn màn hình", L"Games / fullscreen"},
    {L"Tự tắt tiếng Việt khi chơi game toàn màn hình", L"Turn Vietnamese off in fullscreen games"},
    {L"Khi một game (Direct3D toàn màn hình độc quyền) hoặc trình chiếu đang ở phía trước, VietTelex không giữ phím "
     L"nào (WASD không thành ư/ă). Trình duyệt F11, xem video toàn màn hình vẫn gõ bình thường. Game chạy dạng cửa "
     L"sổ không viền: dùng Chế độ game hoặc đặt “Luôn tiếng Anh” ở trang Ứng dụng.",
     L"While a game (exclusive fullscreen Direct3D) or a slideshow is in front, VietTelex holds no key (WASD never "
     L"turns into ư/ă). Browsers in F11 and fullscreen video still type normally. For borderless-window games use "
     L"Game mode, or set the game to “Always English” on the Apps page."},
    {L"Chế độ game", L"Game mode"},
    {L"Mọi phím đi thẳng tới ứng dụng, ở mọi ứng dụng, cho tới khi tắt. Tự tắt khi VietTelex khởi động lại.",
     L"Every key goes straight to the app, in every app, until you turn it off. Turns itself off when VietTelex "
     L"restarts."},
    {L"Phím tắt Chế độ game", L"Game mode hotkey"},
    {L"Bật/tắt Chế độ game từ bất cứ đâu. Mặc định không đặt: phím tắt toàn hệ thống sẽ không còn tới ứng dụng "
     L"khác (Ctrl+Alt là AltGr trên một số bàn phím).",
     L"Turns Game mode on/off from anywhere. None by default: a system-wide hotkey no longer reaches other apps "
     L"(Ctrl+Alt is AltGr on some keyboards)."},
    {L"Hiện V/E khi chuyển Việt/Anh", L"Show V/E when switching"},
    {L"Một chữ V hoặc E nhỏ hiện khoảng 1 giây cạnh con trỏ (hoặc ở góc màn hình) khi bạn bấm phím chuyển. "
     L"“Tự động”: chỉ khi biểu tượng khay đang ẩn. Không bao giờ hiện khi chơi game toàn màn hình.",
     L"A small V or E shows for about a second next to the cursor (or in the screen corner) when you press the "
     L"switch key. “Automatic”: only while the tray icon is hidden. Never shown over a fullscreen game."},
    {L"Tự động", L"Automatic"},
    {L"Game: bật", L"Game: on"},
    {L"Game: tắt", L"Game: off"},

    // Other Vietnamese input methods
    {L"Có bộ gõ tiếng Việt khác", L"Another Vietnamese input method is active"},
    {L"Hai bộ gõ cùng lúc sẽ bỏ dấu hai lần (vieejt → viêệt). Hãy thoát bộ gõ kia hoặc gỡ nó khỏi danh sách.",
     L"Two input methods at once add every tone twice (vieejt → viêệt). Quit the other one or remove it from the "
     L"list."},
    {L"Xử lý…", L"Resolve…"},
    {L"VietTelex sẽ không tự tắt hay gỡ phần mềm khác. Chọn việc cần làm:",
     L"VietTelex never quits or uninstalls other software by itself. Choose what to do:"},
    {L"Mở thư mục của %s", L"Open the folder of %s"},
    {L"Cách thoát %s", L"How to quit %s"},
    {L"Bấm chuột phải vào biểu tượng %s ở khay hệ thống (góc phải thanh tác vụ, có thể trong mũi tên ^) rồi chọn "
     L"Thoát / Kết thúc. Để nó không tự chạy cùng Windows: bỏ “Khởi động cùng Windows” trong %s, hoặc tắt nó ở "
     L"Trình quản lý tác vụ → Ứng dụng khởi động.",
     L"Right-click the %s icon in the notification area (right end of the taskbar, maybe under the ^ arrow) and "
     L"choose Exit. To stop it starting with Windows: turn off its “Run at startup” option in %s, or disable it in "
     L"Task Manager → Startup apps."},
    {L"Gỡ bàn phím “%s” khỏi danh sách ngôn ngữ", L"Remove the “%s” keyboard from the language list"},
    {L"Chỉ gỡ khỏi danh sách bàn phím của bạn; Windows vẫn giữ nó, thêm lại được trong Cài đặt.",
     L"Only removes it from your keyboard list; Windows keeps it and you can add it back in Settings."},
    {L"Mở Cài đặt ngôn ngữ của Windows", L"Open Windows language settings"},
    {L"Đã gỡ bàn phím khỏi danh sách.", L"The keyboard was removed from the list."},
    {L"Không gỡ được tự động. Cài đặt ngôn ngữ của Windows sẽ mở ra: Tiếng Việt → Tuỳ chọn → Bàn phím → Gỡ.",
     L"Could not remove it automatically. Windows language settings will open: Vietnamese → Options → Keyboards → "
     L"Remove."},
    {L"Không thấy bộ gõ tiếng Việt nào khác.", L"No other Vietnamese input method found."},

    // Welcome
    {L"Chào mừng đến với VietTelex", L"Welcome to VietTelex"},
    {L"VietTelex đã được thêm vào bàn phím của bạn. Chọn vài thứ để bắt đầu — đổi lại lúc nào cũng được trong "
     L"Cài đặt.",
     L"VietTelex has been added to your keyboards. Pick a few things to start — you can change them any time in "
     L"Settings."},
    {L"Kiểu gõ", L"Typing method"},
    {L"Phím chuyển Việt/Anh", L"Vietnamese/English switch key"},
    {L"Hiện biểu tượng V/E ở khay hệ thống (như UniKey)", L"Show a V/E icon in the notification area (like UniKey)"},
    {L"Không bật thì biểu tượng bàn phím trên thanh tác vụ và chữ V/E nhỏ khi chuyển cho biết đang gõ gì.",
     L"Without it, the keyboard icon on the taskbar and a small V/E when you switch show the current language."},
    {L"Chuyển gõ tắt từ UniKey / OpenKey…", L"Bring shortcuts from UniKey / OpenKey…"},
    {L"Bắt đầu gõ", L"Start typing"},
    {L"Mở Cài đặt…", L"Open Settings…"},

    // Import result
    {L"Đã nhập %d gõ tắt (%s).", L"Imported %d shortcuts (%s)."},
    {L"%d dòng bị bỏ qua (viết tắt có dấu cách, rỗng hoặc dài quá 64 ký tự).",
     L"%d lines skipped (abbreviation with a space, empty or longer than 64 characters)."},
    {L"Tệp UniKey kiểu cũ (mã VIQR, không có dòng “version=1”): chữ có dấu chưa được chuyển, ví dụ “Vie^.t”. "
     L"Mở tệp trong UniKey rồi lưu lại để có bản UTF-8.",
     L"An old UniKey file (VIQR encoding, no “version=1” line): accented letters were not converted, e.g. "
     L"“Vie^.t”. Open it in UniKey and save it again to get a UTF-8 file."},
};
static_assert(sizeof(kStrings) / sizeof(kStrings[0]) == static_cast<size_t>(S::Count), "string table size");
}  // namespace

const wchar_t* tr(S id) {
    const Pair& p = kStrings[static_cast<size_t>(id)];
    return g_en ? p.en : p.vi;
}

void setEnglish(bool en) { g_en = en; }

}  // namespace vtx::app
