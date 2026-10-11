"""Ngôn ngữ giao diện (vi | en) — cùng cách làm với iOS/Shared/L10n.swift.

Chữ gốc tiếng Việt CHÍNH LÀ khoá: `_("Gõ tắt")` trả "Gõ tắt" (mặc định) hoặc "Shortcuts" khi
người dùng chọn English (config.toml [general] ui_language = "en"). Mặc định LUÔN "vi" —
KHÔNG nhìn locale của máy (LANG/LC_*), quy ước chung mọi bản VietTelex.

Thêm chuỗi mới: bọc `_("…")` (hoặc `N_("…")` cho hằng cấp module, dịch lúc hiển thị bằng
`_(x)`) và thêm bản dịch vào `EN` — tests/test_i18n.py quét mã nguồn, thiếu là đỏ. Tham số
`%s` / `%d` phải giữ đúng số lượng và thứ tự. Tên riêng (VietTelex, Fcitx5, IBus, Telex,
VNI…) giữ nguyên.

Module thuần Python (không GTK) để test chạy được ở mọi máy.
"""

SUPPORTED = ("vi", "en")

_lang = "vi"


def normalized(value):
    """Giá trị đã lưu → "vi" | "en"; thiếu/lạ ⇒ "vi"."""
    return "en" if value == "en" else "vi"


def set_language(value):
    global _lang
    _lang = normalized(value)


def language():
    return _lang


def _(vi):
    if _lang != "en":
        return vi
    return EN.get(vi, vi)


def N_(vi):
    """Đánh dấu để dịch (hằng cấp module) — trả nguyên chuỗi, dịch lúc hiển thị bằng `_`."""
    return vi


EN = {
    # --- chế độ theo app / hộp thoại chung
    "Tự động": "Automatic",
    "Chữ đang gõ (preedit)": "Composition (preedit)",
    "Sửa trực tiếp (surrounding)": "Edit in place (surrounding)",
    "Gõ thẳng, sửa bằng Backspace": "Type directly, fix with Backspace",
    "Tắt tiếng Việt": "Vietnamese off",
    "Huỷ": "Cancel",
    "Lưu file": "Save file",
    "Mở file": "Open file",
    "Lưu": "Save",
    "Mở": "Open",
    "VietTelex — Cài đặt": "VietTelex — Settings",
    "Đang kiểm tra…": "Checking…",

    # --- Kiểu gõ
    "Kiểu gõ": "Typing",
    "Bộ gõ": "Input method",
    "Hướng dẫn bật bộ gõ…": "Setup guide…",
    "Gõ dấu bằng chữ số": "Tones with number keys",
    "Gõ dấu bằng chữ số thay cho chữ cái Telex: 1-5 = sắc/huyền/hỏi/ngã/nặng, 6 = â/ê/ô, "
    "7 = ơ/ư, 8 = ă, 9 = đ, 0 = bỏ dấu. Chữ cái giữ nguyên. Nên bật “Kiểm tra chính tả khi gõ” "
    "để số như “mp3” không bị biến thành dấu.":
        "Type marks with digits instead of Telex letters: 1-5 = acute/grave/hook/tilde/dot, "
        "6 = â/ê/ô, 7 = ơ/ư, 8 = ă, 9 = đ, 0 = remove marks. Letters stay as typed. Turn on "
        "“Spell-check while typing” so numbers like “mp3” don’t turn into marks.",
    "Telex đơn giản": "Simple Telex",
    "Chữ w đứng một mình luôn là 'w' (gõ 'uw' để ra ư). Tắt = Telex đầy đủ (cw→cư).":
        "A lone w always stays 'w' (type 'uw' for ư). Off = full Telex (cw→cư).",
    "Chính tả teencode": "Teencode spelling",
    "Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó) và bíe, thík, gòy, "
    "ừk. Tắt = chỉ chính tả chuẩn, nên từ tiếng Anh như was, war, worse, zoo giữ nguyên.":
        "Accept chat spellings: w/z/k for qu/d/c (wá, zui zẻ, kó) and bíe, thík, gòy, ừk. "
        "Off = standard spelling only, so English words like was, war, worse, zoo stay as typed.",
    "Gõ nhanh (Quick Telex)": "Quick Telex",
    "Gõ đúp phụ âm đầu để ra phụ âm ghép: cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th.":
        "Double a first consonant for a digraph: cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th.",
    "Bỏ dấu tự do": "Free tone placement",
    "Tắt = Telex nghiêm ngặt: dấu chỉ nhận khi gõ sát nguyên âm, hợp cho English/code "
    "(data→data). Bật: dấu đặt tự do (ama→âm).":
        "Off = strict Telex: marks only apply right after a vowel, good for English/code "
        "(data→data). On: marks can be typed anywhere (ama→âm).",
    "Phím ngoặc: [ ra ơ, ] ra ư": "Bracket keys: [ types ơ, ] types ư",
    "Thói quen UniKey: “th[” → “thơ”, “ng]” → “ngư” ({ và } ra chữ hoa). Nếu bạn gõ code thì "
    "nên để TẮT — khi bật, [ và ] thuộc về từ đang gõ thay vì kết thúc từ.":
        "UniKey habit: “th[” → “thơ”, “ng]” → “ngư” ({ and } give capitals). Leave OFF if you "
        "write code — when on, [ and ] belong to the word being typed instead of ending it.",
    "Bỏ dấu kiểu mới (oà, uý)": "Modern tone placement (oà, uý)",
    "Tắt = kiểu cũ (hòa, thủy, khỏe). Bật = kiểu mới (hoà, thuý, khoẻ). Chỉ đổi vị trí dấu ở "
    "oa/oe/uy.":
        "Off = classic style (hòa, thủy, khỏe). On = modern style (hoà, thuý, khoẻ). Only moves "
        "the mark in oa/oe/uy.",
    "VietTelex đang hoạt động": "VietTelex is running",
    "Bộ khung gõ: %s. Chuyển Việt/Anh bằng %s.": "Framework: %s. Switch Vietnamese/English with %s.",
    "menu bộ gõ": "the input method menu",
    "Chưa có bộ khung gõ Fcitx5 hoặc IBus": "No Fcitx5 or IBus framework found",
    "Cài gói viettelex-fcitx5 (khuyên dùng) hoặc viettelex-ibus, rồi làm theo hướng dẫn.":
        "Install viettelex-fcitx5 (recommended) or viettelex-ibus, then follow the guide.",
    "VietTelex chưa được bật trong %s": "VietTelex is not enabled in %s",
    "Bấm “Hướng dẫn bật bộ gõ…” để làm từng bước.": "Click “Setup guide…” for step-by-step help.",

    # --- Tuỳ chỉnh
    "Tuỳ chỉnh": "Options",
    "Chính tả": "Spelling",
    "Tự khôi phục từ không hợp lệ": "Restore invalid words",
    "Từ không phải tiếng Việt hợp lệ sẽ tự trả về đúng phím đã gõ khi kết thúc từ "
    "(retore → retore).":
        "A word that isn’t valid Vietnamese goes back to the exact keys typed when the word "
        "ends (retore → retore).",
    "Kiểm tra chính tả khi gõ": "Spell-check while typing",
    "Ngừng bỏ dấu ngay khi từ không thể là tiếng Việt (google, github…) thay vì đợi hết từ.":
        "Stop adding marks as soon as a word can’t be Vietnamese (google, github…) instead of "
        "waiting for the word to end.",
    "Quyết định theo ngữ cảnh": "Decide by context",
    "Sau một từ tiếng Anh, từ nhập nhằng kế tiếp mà chuỗi phím tạo thành một từ tiếng Anh sẽ "
    "được giữ tiếng Anh thay vì tiếng Việt — “he is” → “he is”, không phải “he í”. Sau từ "
    "tiếng Việt hoặc không rõ thì để tiếng Việt — “sao í”.":
        "After an English word, an ambiguous next word whose keys spell an English word stays "
        "English — “he is” → “he is”, not “he í”. After a Vietnamese or unclear word it stays "
        "Vietnamese — “sao í”.",
    "Gõ thêm dấu cho từ ngay trước con trỏ": "Add marks to the word before the cursor",
    "Đặt con trỏ ngay sau một từ đã gõ rồi gõ phím dấu để sửa dấu từ đó (toan + s → toán).":
        "Put the cursor right after a typed word and press a mark key to fix its marks "
        "(toan + s → toán).",
    "Gạch đỏ âm tiết sai chính tả khi gõ": "Underline misspelled syllables while typing",
    "Chữ đang gõ được đánh dấu khi nó không thể thành âm tiết tiếng Việt (đc, hópng, tòc): IBus "
    "gạch lượn sóng + chữ đỏ, Fcitx5 gạch chân. Chỉ ở chế độ chữ đang gõ (preedit); từ giữ "
    "nguyên phím gõ hoặc sẽ tự khôi phục (tiếng Anh) không bị đánh dấu.":
        "The word being typed is marked when it can’t become a Vietnamese syllable (đc, hópng, "
        "tòc): IBus draws a wavy underline and red text, Fcitx5 an underline. Preedit mode only; "
        "words left as typed or auto-restored (English) are never marked.",
    "Khi từ vừa là tiếng Anh vừa là tiếng Việt": "When a word is both English and Vietnamese",
    "Cho các từ như last/lát, list/lít, his/hí. Ưu tiên tiếng Việt: gõ đúp phím dấu để giữ "
    "tiếng Anh (lisst → list). Ưu tiên tiếng Anh: đặt dấu ở cuối từ để ra tiếng Việt "
    "(lits → lít). Trong câu tiếng Anh thì từ vẫn giữ tiếng Anh dù chọn gì.":
        "For words like last/lát, list/lít, his/hí. Prefer Vietnamese: double the mark key to "
        "keep English (lisst → list). Prefer English: put the mark at the end for Vietnamese "
        "(lits → lít). Inside an English sentence the word stays English either way.",
    "Ưu tiên": "Preference",
    "Ưu tiên tiếng Việt": "Prefer Vietnamese",
    "Ưu tiên tiếng Anh": "Prefer English",
    "Hiển thị chữ đang gõ": "Composition display",
    "Chữ đang gõ (preedit): đúng chữ ở mọi app (GTK, Qt, Chrome, Electron). Sửa trực tiếp: "
    "giống macOS, chỉ áp dụng ở app hỗ trợ surrounding text — LibreOffice và app không hỗ trợ "
    "tự về preedit. Chỉnh riêng từng app ở tab Bảng cơ chế gõ.":
        "Composition (preedit): correct text in every app (GTK, Qt, Chrome, Electron). Edit in "
        "place: like macOS, only in apps that support surrounding text — LibreOffice and "
        "unsupported apps fall back to preedit. Set it per app in the App modes tab.",
    "Cách hiện từ đang gõ": "Show the word being typed as",
    "Gạch chân chữ đang gõ": "Underline the word being typed",
    "Tắt = chữ đang gõ trông như chữ thường ở app GTK, Qt, VTE (X11). Chrome/Electron và app "
    "Wayland trên GNOME vẫn tự vẽ gạch chân.":
        "Off = the word being typed looks like normal text in GTK, Qt and VTE apps (X11). "
        "Chrome/Electron and Wayland apps on GNOME still draw their own underline.",
    "Terminal: gõ thẳng, sửa dấu bằng Backspace": "Terminals: type directly, fix marks with Backspace",
    "Giống UniKey: không gạch chân trong gnome-terminal, tilix, konsole… khi app nhận phím qua "
    "IBus GTK3 hoặc Fcitx5 (fcitx5-gtk3/fcitx5-qt). Terminal GTK4 (Ptyxis, Console) và phiên "
    "Wayland GNOME vẫn dùng preedit.":
        "Like UniKey: no underline in gnome-terminal, tilix, konsole… when the app gets keys "
        "through IBus GTK3 or Fcitx5 (fcitx5-gtk3/fcitx5-qt). GTK4 terminals (Ptyxis, Console) "
        "and GNOME Wayland sessions still use preedit.",
    "Bỏ gạch chân trong Chrome/Electron (thử nghiệm)":
        "No underline in Chrome/Electron (experimental)",
    "Chrome, VS Code, Slack, Discord… gõ thẳng như ở app khác; sửa dấu bằng phím Backspace, lỗi "
    "thì tự về gạch chân. Chỉ GNOME Wayland (IBus hoặc Fcitx5) và KDE Wayland (Fcitx5). Bật lên, "
    "VietTelex tự thêm cờ IME Wayland vào lối tắt của các app này — mở lại app là xong.":
        "Chrome, VS Code, Slack, Discord… type directly like other apps; marks are fixed with "
        "Backspace, and on any error it falls back to the underline. GNOME Wayland (IBus or "
        "Fcitx5) and KDE Wayland (Fcitx5) only. When on, VietTelex adds the Wayland IME flags to "
        "these apps’ launchers — just reopen the app.",
    "Phiên này là X11: không áp dụng, Chrome/Electron vẫn gạch chân.":
        "This is an X11 session: not applicable, Chrome/Electron keep the underline.",
    "GNOME 50 (Ubuntu 26.04) bỏ mất phím Backspace mà bộ gõ gửi (lỗi GNOME, "
    "đã sửa ở GNOME 51): VietTelex tạm giữ gạch chân ở Chrome/Electron để "
    "không gõ sai chữ.":
        "GNOME 50 (Ubuntu 26.04) drops the Backspace keys an input method sends (a GNOME bug, "
        "fixed in GNOME 51): VietTelex keeps the underline in Chrome/Electron for now so no "
        "letters come out wrong.",
    "KDE cần Fcitx5; IBus trên KDE chưa hỗ trợ.": "KDE needs Fcitx5; IBus on KDE is not supported.",
    "Desktop này (%s) chưa hỗ trợ — chỉ GNOME và KDE Plasma.":
        "This desktop (%s) is not supported — GNOME and KDE Plasma only.",
    "Đã thêm cờ cho: %s.": "Flags added for: %s.",
    "Đã bật sẵn, không cần cờ: %s.": "Already on by default, no flags needed: %s.",
    "Đang chạy bản cũ — thoát hẳn rồi mở lại: %s.": "Running without the flags — quit fully and reopen: %s.",
    "Lối tắt bạn tự sửa (đã có cờ): %s.": "Launchers you edited yourself (flags present): %s.",
    "Không sửa lối tắt bạn tự tạo: %s — tự thêm %s vào dòng Exec=.":
        "Not touching launchers you created: %s — add %s to the Exec= line yourself.",
    "Đang ép chạy X11, giữ nguyên (vẫn gạch chân): %s.":
        "Forced to X11, left as is (keeps the underline): %s.",
    "Không tự thêm cờ được: %s.": "Could not add the flags automatically: %s.",
    "Chưa thấy app Chrome/Electron nào cài trên máy.": "No Chrome/Electron apps found on this computer.",
    "Lỗi khi ghi lối tắt: %s": "Error writing launchers: %s",
    "Đã tắt — Chrome/Electron về gạch chân như cũ.": "Off — Chrome/Electron go back to the underline.",
    "Đã bật, nhưng máy này chưa áp dụng được (xem dòng mô tả).":
        "On, but it does not apply on this computer (see the description).",
    "Thoát hẳn rồi mở lại %s để bỏ gạch chân.": "Quit fully and reopen %s to drop the underline.",
    "Đã bật. Mở lại Chrome/Electron để bỏ gạch chân.": "On. Reopen Chrome/Electron to drop the underline.",
    "Công cụ văn bản": "Text tools",
    "Bôi đen chữ ở app bất kỳ rồi chọn trong menu bộ gõ → Công cụ…: Thêm dấu cho vùng chọn, "
    "HOA, thường, Hoa Đầu Từ, Hoa đầu câu, Xoá dấu. Không bao giờ chạy ở ô mật khẩu.":
        "Select text in any app, then pick from the input method menu → Tools…: Add tones to "
        "selection, UPPERCASE, lowercase, Title Case, Sentence case, Remove tones. Never runs in "
        "password fields.",
    "Hiện công cụ văn bản trong menu": "Show text tools in the menu",
    "Menu “Công cụ…” của bộ gõ (khay Fcitx5 / menu IBus) liệt kê 6 công cụ trên.":
        "The input method’s “Tools…” menu (Fcitx5 tray / IBus menu) lists the 6 tools above.",
    "Công cụ cho vùng chọn": "Tools for the selection",
    "Gợi ý cạnh con trỏ": "Suggestions next to the caret",
    "Hiện ngay cạnh con trỏ khi rất chắc; chỉ Tab mới áp dụng, phím khác bỏ qua, "
    "Esc = bỏ gợi ý. Không bao giờ tự thay, không chạy ở ô mật khẩu. Cần gói "
    "viettelex-text-tools.":
        "Shown right next to the caret only when very likely; only Tab applies, any other key "
        "ignores it, Esc dismisses it. Never replaces anything by itself, never in password "
        "fields. Needs the viettelex-text-tools package.",
    "Hiện kết quả phép tính": "Show math results",
    "Gõ phép tính rồi “=” (12*3=, 200+10%=, 125 x (4 + 5.5) =) → kết quả cạnh con trỏ; "
    "Tab hoặc Enter để chèn.":
        "Type a calculation, then “=” (12*3=, 200+10%=, 125 x (4 + 5.5) =) → the result next "
        "to the caret; Tab or Enter inserts it.",
    "Chip số dạng tiền": "Money format for numbers",
    "50k, 1tr2, 2 tỷ + dấu cách → 1.200.000 ₫ cạnh con trỏ; Tab để thay.":
        "50k, 1tr2, 2 tỷ + space → 1.200.000 ₫ next to the caret; Tab replaces.",
    "Gợi ý sửa lỗi gõ sai": "Typo fix suggestions",
    "Từ vừa gõ không phải tiếng Việt, tiếng Anh hay từ chat → gợi ý từ đúng khi gõ nhầm "
    "một phím kề hoặc đảo hai phím (tpoi → tôi). Tab để thay, Esc = đừng gợi ý từ này nữa.":
        "When the word just typed is not Vietnamese, English or a chat word → suggests the right "
        "word for one neighbouring-key slip or two swapped keys (tpoi → tôi). Tab replaces, "
        "Esc = don’t suggest this word again.",
    "Gợi ý thêm dấu cho câu không dấu": "Add tones to unaccented sentences",
    "Từ 3 âm tiết không dấu, sau . ! ? hoặc khi dừng gõ một chút → câu có dấu "
    "(toi di hoc → tôi đi học). Tab để thay cả cụm. Mặc định tắt.":
        "After 3 or more unaccented syllables, on . ! ? or a short pause → the toned sentence "
        "(toi di hoc → tôi đi học). Tab replaces the whole run. Off by default.",
    "Gợi ý ngày giờ": "Date and time suggestions",
    "“hôm nay”, “ngày mai”, “hôm qua” → dd/mm/yyyy; “bây giờ” → giờ:phút (today, tomorrow, "
    "yesterday, now sau một từ tiếng Anh). Tab để thay.":
        "“hôm nay”, “ngày mai”, “hôm qua” → dd/mm/yyyy; “bây giờ” → hh:mm (today, tomorrow, "
        "yesterday, now after an English word). Tab replaces.",
    "menu Công cụ…": "Tools… menu",
    "phép tính": "math",
    "chip số": "money format",
    "sửa lỗi gõ": "typo fixes",
    "thêm dấu": "tones",
    "ngày giờ": "date/time",
    "Đang bật: %s": "On: %s",
    "Đang tắt hết": "All off",
    "Phím tắt Thêm dấu": "Add tones hotkey",
    "Thêm dấu cho đoạn không dấu đang bôi đen (toi di hoc → tôi đi học). Mặc định tắt.":
        "Add tones to the selected unaccented text (toi di hoc → tôi đi học). Off by default.",
    "Tắt phím tắt": "Turn hotkey off",
    "Chuyển Việt/Anh": "Vietnamese/English switch",
    "Phím chuyển Việt/Anh": "Vietnamese/English hotkey",
    "Mặc định Ctrl+Space. Không dùng Super+Space (GNOME dùng để đổi nguồn nhập).":
        "Default Ctrl+Space. Super+Space is not allowed (GNOME uses it to switch input sources).",
    "Về mặc định (Ctrl+Space)": "Reset to default (Ctrl+Space)",
    "Tắt": "Off",
    "Nhớ Việt/Anh theo từng app": "Remember Vietnamese/English per app",
    "Mỗi app giữ trạng thái Việt/Anh riêng — chuyển sang terminal gõ tiếng Anh không làm mất "
    "tiếng Việt ở trình soạn thảo.":
        "Each app keeps its own Vietnamese/English state — typing English in a terminal "
        "doesn’t turn Vietnamese off in your editor.",
    "App mới mở bắt đầu bằng tiếng Việt": "New apps start in Vietnamese",
    "Tắt = app lần đầu gặp bắt đầu ở chế độ tiếng Anh.": "Off = apps seen for the first time start in English.",
    "Quên trạng thái Việt/Anh đã nhớ": "Forget remembered Vietnamese/English states",
    "Xoá trạng thái đã nhớ của mọi app; lần sau mỗi app bắt đầu theo mặc định.":
        "Clear the remembered state of every app; each app starts with the default next time.",
    "Quên tất cả": "Forget all",
    "Nhấn tổ hợp phím mới…": "Press the new key combination…",
    "Cần ít nhất một phím Ctrl/Alt/Shift/Super.": "Needs at least one of Ctrl/Alt/Shift/Super.",
    "Cần ít nhất một phím Ctrl/Alt/Super.": "Needs at least one of Ctrl/Alt/Super.",
    "Esc = huỷ · Backspace = tắt phím chuyển.": "Esc = cancel · Backspace = no switch hotkey.",
    "Esc = huỷ · Backspace = tắt phím tắt.": "Esc = cancel · Backspace = turn the hotkey off.",
    "Cần thêm Ctrl, Alt, Shift hoặc Super": "Add Ctrl, Alt, Shift or Super",
    "Cần thêm Ctrl, Alt hoặc Super": "Add Ctrl, Alt or Super",
    "Không dùng được %s — chọn tổ hợp khác": "%s can’t be used — pick another combination",
    "%s đang là phím chuyển Việt/Anh — chọn tổ hợp khác":
        "%s is the Vietnamese/English hotkey — pick another combination",
    "%s đang là phím tắt Thêm dấu — chọn tổ hợp khác":
        "%s is the Add tones hotkey — pick another combination",
    "Trùng phím tắt GNOME: %s — hãy chọn tổ hợp khác.":
        "Conflicts with the GNOME shortcut %s — please pick another combination.",
    "Không xoá được %s": "Couldn’t delete %s",
    "Đã quên trạng thái Việt/Anh của mọi app.": "Forgot the Vietnamese/English state of every app.",
    "Quên trạng thái Việt/Anh?": "Forget Vietnamese/English states?",
    "Mọi app sẽ bắt đầu lại theo mặc định.": "Every app will start again with the default.",

    # --- Gõ tắt
    "Gõ tắt": "Shortcuts",
    "Bật gõ tắt": "Enable shortcuts",
    "Gõ từ tắt rồi dấu cách/dấu câu để bung ra cụm đầy đủ (ko → không).":
        "Type a shortcut, then space or punctuation, to expand it (ko → không).",
    "Thêm / sửa gõ tắt": "Add / edit shortcut",
    "Bấm một dòng để sửa.": "Click a row to edit it.",
    "gõ": "type",
    "thành": "becomes",
    "Thêm": "Add",
    "Nhập…": "Import…",
    "Xuất ra YAML…": "Export to YAML…",
    "Bảng gõ tắt": "Shortcut list",
    "Chưa có gõ tắt nào": "No shortcuts yet",
    "Thêm ở trên, hoặc Nhập… file YAML/JSON/TXT (mỗi dòng một cặp key: value — cùng định dạng "
    "bản macOS, Gõ Nhanh, EVKey…).":
        "Add one above, or Import… a YAML/JSON/TXT file (one key: value pair per line — same "
        "format as the macOS version, Gõ Nhanh, EVKey…).",
    "Xoá gõ tắt này": "Delete this shortcut",
    "Từ gõ tắt không được trống hay chứa dấu cách (tối đa 64 ký tự).":
        "A shortcut can’t be empty or contain spaces (up to 64 characters).",
    "Nhập cụm từ sẽ thay thế.": "Enter the text to expand to.",
    "Không đọc được file. Định dạng hỗ trợ: JSON, YAML, hoặc mỗi dòng một cặp key:value.":
        "Couldn’t read the file. Supported formats: JSON, YAML, or one key:value pair per line.",
    "Đã nhập %d gõ tắt — gộp vào bảng hiện có (mục trùng lấy giá trị mới).":
        "Imported %d shortcuts — merged into the current list (duplicates take the new value).",
    "Đã lưu %s": "Saved %s",
    "Không lưu được file.": "Couldn’t save the file.",

    # --- Bảng cơ chế gõ
    "Bảng cơ chế gõ": "App modes",
    "Ép cơ chế gõ theo app": "Force a typing mode per app",
    "App gõ sai hoặc hiện gạch chân khó chịu? Chọn riêng cho app đó. Tự động = theo “Cách hiện "
    "từ đang gõ” ở tab Tuỳ chỉnh. Terminal và LibreOffice mặc định dùng preedit (%s); terminal "
    "gõ thẳng khi hệ hỗ trợ. “Gõ thẳng” chỉ có tác dụng ở app nhận phím qua IBus GTK3 / Fcitx5 "
    "GTK3-Qt.":
        "An app types wrong or shows an annoying underline? Pick a mode just for it. Automatic "
        "= follows “Show the word being typed as” in the Options tab. Terminals and LibreOffice "
        "use preedit by default (%s); terminals type directly when the system allows. “Type "
        "directly” only works in apps that get keys through IBus GTK3 / Fcitx5 GTK3-Qt.",
    "Tên app (vd: org.gnome.texteditor, kitty, code)": "App name (e.g. org.gnome.texteditor, kitty, code)",
    "App đã chỉnh": "Customized apps",
    "Tên app: Fcitx5 dùng tên chương trình; IBus dùng app-id Wayland hoặc WM_CLASS (chữ thường).":
        "App name: Fcitx5 uses the program name; IBus uses the Wayland app-id or WM_CLASS "
        "(lowercase).",
    "Chưa có app nào": "No apps yet",
    "Mọi app đang dùng chế độ Tự động.": "Every app uses Automatic mode.",
    "Bỏ ghi đè cho app này": "Remove the override for this app",
    "Nhập tên app (không chứa dấu cách).": "Enter an app name (no spaces).",
    "Đã nhập %d chế độ app. Mục có chế độ không hợp lệ bị bỏ qua.":
        "Imported %d app modes. Entries with an invalid mode were skipped.",

    # --- Tương thích
    "Tương thích": "Compatibility",
    "Tương thích ứng dụng": "App compatibility",
    "Chỉ liệt kê lưu ý khớp với máy này.": "Only issues that apply to this computer are listed.",
    "Không phát hiện vấn đề nào với các ứng dụng đã cài.": "No issues found with the installed apps.",
    "Dò lại": "Check again",
    "Chép lệnh": "Copy command",
    "Đã chép lệnh.": "Command copied.",
    "%s: cần cờ bật bộ gõ trên Wayland": "%s: needs a flag to enable the input method on Wayland",
    "Chrome/Electron trên Wayland: bản mới (Chrome ≥ 137) tự nhận bộ gõ; bản cũ hơn hoặc app "
    "Electron chưa cập nhật cần cờ %s.":
        "Chrome/Electron on Wayland: recent versions (Chrome ≥ 137) pick up the input method on "
        "their own; older ones or outdated Electron apps need the flag %s.",
    " Cờ này chạy tốt với GNOME + IBus.": " This flag works well with GNOME + IBus.",
    " Cách khác: %s (chạy qua XWayland).": " Alternatively: %s (runs through XWayland).",
    "# Chạy thử một lần:": "# Try it once:",
    "# Cố định — sửa dòng Exec của file .desktop:":
        "# Make it permanent — edit the Exec line of the .desktop file:",
    "# %s (snap/flatpak): thêm cờ trên vào dòng Exec= của file .desktop":
        "# %s (snap/flatpak): add the flags above to the Exec= line of the .desktop file",
    "# Hoặc chạy qua XWayland (chắc ăn nhất):  … %s": "# Or run through XWayland (most reliable):  … %s",
    "kitty: cần GLFW_IM_MODULE=ibus": "kitty: needs GLFW_IM_MODULE=ibus",
    "Trên X11, kitty chỉ nhận bộ gõ khi có biến này (dùng cho cả IBus lẫn Fcitx5). Đăng nhập "
    "lại sau khi thêm.":
        "On X11, kitty only uses the input method with this variable (for both IBus and "
        "Fcitx5). Log in again after adding it.",
    "JetBrains IDE: thêm tuỳ chọn JVM": "JetBrains IDEs: add a JVM option",
    "Trên X11, IntelliJ/PyCharm… có thể mất bộ gõ sau khi đổi cửa sổ. Help → Edit Custom VM "
    "Options…, thêm dòng dưới rồi khởi động lại IDE.":
        "On X11, IntelliJ/PyCharm… can lose the input method after switching windows. Help → "
        "Edit Custom VM Options…, add the line below, then restart the IDE.",
    "rofi không hỗ trợ bộ gõ": "rofi doesn’t support input methods",
    "rofi không gõ được tiếng Việt có dấu. Dùng Ulauncher hoặc KRunner (KDE) nếu cần tìm bằng "
    "tiếng Việt.":
        "rofi can’t type accented Vietnamese. Use Ulauncher or KRunner (KDE) to search in "
        "Vietnamese.",
    "Ô tìm kiếm Tổng quan GNOME có thể mất chữ đầu": "GNOME overview search may drop the first letter",
    "Gõ ngay khi vừa mở Tổng quan, chữ đầu tiên có thể bị rơi (lỗi IBus upstream ibus#2246). "
    "Mở Tổng quan, chờ một nhịp rồi gõ.":
        "Typing right as the overview opens can drop the first letter (upstream IBus bug "
        "ibus#2246). Open the overview, pause briefly, then type.",
    "App Snap + Fcitx5 trên Ubuntu 22.04": "Snap apps + Fcitx5 on Ubuntu 22.04",
    "Trên 22.04, app dạng Snap (Firefox, Chromium…) thường không nhận Fcitx5. Dùng IBus "
    "(viettelex-ibus), hoặc cài bản .deb/Flatpak của app.":
        "On 22.04, Snap apps (Firefox, Chromium…) often ignore Fcitx5. Use IBus "
        "(viettelex-ibus), or install the app’s .deb/Flatpak version.",
    "im-config đang để tự động: IBus sẽ thắng Fcitx5": "im-config is on auto: IBus wins over Fcitx5",
    "Máy có cả IBus lẫn Fcitx5; ngoài GNOME, im-config chế độ auto chọn IBus. Muốn dùng "
    "VietTelex qua Fcitx5 thì chọn hẳn Fcitx5 rồi đăng nhập lại.":
        "Both IBus and Fcitx5 are installed; outside GNOME, im-config auto mode picks IBus. To "
        "use VietTelex through Fcitx5, select Fcitx5 explicitly and log in again.",
    "App Qt5 trên Wayland: thiếu QT_IM_MODULE": "Qt5 apps on Wayland: QT_IM_MODULE missing",
    "App Qt5 chạy Wayland gốc không có bộ gõ nếu thiếu QT_IM_MODULE. Qt ≥ 6.8.2 đọc "
    "QT_IM_MODULES (danh sách thử lần lượt). Đăng nhập lại sau khi thêm.":
        "Native Wayland Qt5 apps have no input method without QT_IM_MODULE. Qt ≥ 6.8.2 reads "
        "QT_IM_MODULES (a list tried in order). Log in again after adding it.",
    "Terminal: gõ thẳng khi được, còn lại preedit": "Terminals: direct typing when possible, otherwise preedit",
    "Terminal nhận phím qua IBus GTK3 hoặc Fcitx5 (fcitx5-gtk3, fcitx5-qt) — gnome-terminal, "
    "tilix, konsole… trên X11 — được gõ thẳng như UniKey (sửa dấu bằng Backspace, không gạch "
    "chân). Terminal GTK4 (Ptyxis, Console), phiên Wayland GNOME, kitty/alacritty/foot và "
    "terminal của VS Code dùng preedit: ở đó Backspace gửi đi không chắc đến trước chữ mới.":
        "Terminals that get keys through IBus GTK3 or Fcitx5 (fcitx5-gtk3, fcitx5-qt) — "
        "gnome-terminal, tilix, konsole… on X11 — type directly like UniKey (marks fixed with "
        "Backspace, no underline). GTK4 terminals (Ptyxis, Console), GNOME Wayland sessions, "
        "kitty/alacritty/foot and the VS Code terminal use preedit: there a sent Backspace "
        "isn’t guaranteed to arrive before the new text.",

    # --- Giới thiệu
    "Giới thiệu": "About",
    "Phiên bản %s · Linux": "Version %s · Linux",
    "Học gõ Telex": "Learn Telex",
    "Câu hỏi thường gặp": "FAQ",
    "Hướng dẫn báo lỗi": "How to report a bug",
    "Kiểm tra cập nhật": "Check for updates",
    "Chỉ kết nối mạng khi bạn bấm nút này.": "Only goes online when you click this button.",
    "Kiểm tra": "Check",
    "Mã nguồn mở (MIT) · không thu thập dữ liệu · chạy hoàn toàn trên máy":
        "Open source (MIT) · no data collection · runs entirely on your computer",
    "Không kết nối được máy chủ cập nhật.": "Couldn’t reach the update server.",
    "Mở trang tải": "Open download page",
    "Chưa có thông tin bản Linux trên kênh ổn định — xem trang phát hành.":
        "No Linux release info on the stable channel yet — see the releases page.",
    "Có bản mới: %s": "New version available: %s",
    "Bạn đang dùng bản mới nhất (%s).": "You’re on the latest version (%s).",
    "Cập nhật lên %s": "Update to %s",
    "Đang chuẩn bị cập nhật…": "Preparing the update…",
    "Khởi động lại bộ gõ": "Restart input method",
    "Thử lại": "Try again",
    "Không thấy gói VietTelex nào được cài bằng dpkg/apt.":
        "No VietTelex package installed through dpkg/apt was found.",
    "Chưa có bản cho kiến trúc %s.": "No build for the %s architecture yet.",
    "Chưa có bản cho %s (hỗ trợ: %s).": "No build for %s yet (supported: %s).",
    "hệ điều hành này": "this system",
    "Địa chỉ tải không hợp lệ trong stable.json.": "Invalid download address in stable.json.",
    "Thiếu mã kiểm tra SHA256 cho %s.": "Missing SHA256 checksum for %s.",
    "Đã cập nhật lên %s. Khởi động lại bộ gõ và mở lại ứng dụng này để dùng bản mới.":
        "Updated to %s. Restart the input method and reopen this app to use the new version.",
    "Đã huỷ — chưa cập nhật (cần mật khẩu quản trị).":
        "Cancelled — not updated (an administrator password is required).",
    "Trình quản lý gói đang bận (Software Updater/apt khác đang chạy). Đợi xong rồi thử lại.":
        "The package manager is busy (Software Updater or another apt is running). "
        "Wait for it to finish, then try again.",
    "Cập nhật lỗi (mã %d):\n%s": "Update failed (code %d):\n%s",
    "không có thông báo": "no message",
    "Máy này không dùng dpkg/apt — cập nhật theo cách bạn đã cài.":
        "This system doesn’t use dpkg/apt — update the way you installed it.",
    "Thiếu pkexec hoặc helper cập nhật — cài gói pkexec (22.04: policykit-1) hoặc cập nhật bằng apt.":
        "pkexec or the update helper is missing — install the pkexec package (22.04: "
        "policykit-1) or update with apt.",
    "Địa chỉ tải không hợp lệ: %s": "Invalid download address: %s",
    "Đang tải %d/%d: %s": "Downloading %d/%d: %s",
    "Không tải được %s — kiểm tra mạng rồi thử lại.":
        "Couldn’t download %s — check your connection and try again.",
    "Sai mã SHA256 của %s — đã huỷ, không cài.": "SHA256 mismatch for %s — cancelled, nothing installed.",
    "Đang cài (cần mật khẩu quản trị)…": "Installing (administrator password required)…",
    "Không chạy được pkexec: %s": "Couldn’t run pkexec: %s",

    # --- Hướng dẫn bật bộ gõ (onboarding)
    "Bật bộ gõ VietTelex": "Set up VietTelex",
    "Kiểm tra lại": "Check again",
    "Bộ khung gõ": "Input method framework",
    "VietTelex là một input method của Fcitx5 (khuyên dùng — độ trễ thấp nhất, hợp KDE) hoặc "
    "IBus (mặc định của Ubuntu/GNOME).":
        "VietTelex is an input method for Fcitx5 (recommended — lowest latency, suits KDE) or "
        "IBus (the Ubuntu/GNOME default).",
    "Chưa thấy Fcitx5 hay IBus": "Neither Fcitx5 nor IBus found",
    "Cài một trong hai gói: sudo apt install viettelex-fcitx5 (hoặc viettelex-ibus), rồi mở lại "
    "hướng dẫn này.":
        "Install one of the packages: sudo apt install viettelex-fcitx5 (or viettelex-ibus), then "
        "open this guide again.",
    "Đang dùng %s": "Using %s",
    "Theo tiến trình đang chạy và biến môi trường của phiên đăng nhập này.":
        "Based on the running processes and the environment of this login session.",
    "Bấm “Dùng Fcitx5” ở trên rồi đăng xuất/đăng nhập lại.":
        "Click “Use Fcitx5” above, then log out and back in.",
    "Fcitx5 thay IBus trên GNOME": "Fcitx5 instead of IBus on GNOME",
    "Với Fcitx5, app GTK (Firefox, Terminal, Text Editor…) không gạch chân chữ đang gõ và thanh "
    "trên cùng hiện icon VietTelex. Chrome/Electron vẫn có thể gạch chân (xem tab Tương thích).":
        "With Fcitx5, GTK apps (Firefox, Terminal, Text Editor…) don’t underline the text being "
        "typed and the top bar shows the VietTelex icon. Chrome/Electron may still underline "
        "(see the Compatibility tab).",
    "Đã đặt Fcitx5 chạy thay IBus": "Fcitx5 is set to replace IBus",
    "Đang có hiệu lực.": "In effect.",
    "Chưa có hiệu lực — đăng xuất rồi đăng nhập lại.": "Not in effect yet — log out and back in.",
    "Quay về IBus": "Back to IBus",
    "Dùng Fcitx5 thay IBus": "Use Fcitx5 instead of IBus",
    "Cài gói trước: sudo apt install viettelex-fcitx5": "Install the package first: sudo apt install viettelex-fcitx5",
    "Fcitx5 tự chạy khi đăng nhập, app GTK nhận chữ thẳng từ Fcitx5. Đăng xuất/đăng nhập lại một lần.":
        "Fcitx5 starts at login and GTK apps get text straight from Fcitx5. Log out and back in once.",
    "Dùng Fcitx5": "Use Fcitx5",
    "Không ghi được cấu hình trong ~/.config.": "Couldn’t write the configuration in ~/.config.",
    "Xong — đăng xuất rồi đăng nhập lại để dùng Fcitx5.": "Done — log out and back in to use Fcitx5.",
    "Xong — đăng xuất rồi đăng nhập lại để quay về IBus.": "Done — log out and back in to go back to IBus.",
    "Các bước": "Steps",
    "1. Cài gói %s": "1. Install the %s package",
    "Đã cài.": "Installed.",
    "sudo apt install %s (hoặc cài file .deb tải từ trang phát hành).":
        "sudo apt install %s (or install the .deb from the releases page).",
    "2. Fcitx5 đang chạy": "2. Fcitx5 is running",
    "Đang chạy.": "Running.",
    "Khởi động Fcitx5. Nếu mỗi lần đăng nhập đều phải bật tay: chạy im-config -n fcitx5 rồi "
    "đăng nhập lại.":
        "Start Fcitx5. If you have to start it by hand at every login: run im-config -n fcitx5 "
        "and log in again.",
    "Khởi động Fcitx5": "Start Fcitx5",
    "3. Thêm VietTelex vào nhóm bộ gõ": "3. Add VietTelex to the input method group",
    "Đã có trong nhóm bộ gõ Fcitx5.": "Already in the Fcitx5 input method group.",
    "Thêm “Tiếng Việt (VietTelex)” vào nhóm hiện tại. Không cần đăng xuất.":
        "Add “Tiếng Việt (VietTelex)” to the current group. No need to log out.",
    "Cấu hình Fcitx5…": "Configure Fcitx5…",
    "Đổi thứ tự bộ gõ, phím chuyển giữa các bộ gõ.": "Reorder input methods, change the switch key.",
    "2. IBus đang chạy": "2. IBus is running",
    "Đang chạy. Vừa cài gói xong thì bấm “Khởi động lại IBus” để IBus thấy VietTelex.":
        "Running. If you just installed the package, click “Restart IBus” so IBus sees VietTelex.",
    "Khởi động IBus.": "Start IBus.",
    "Khởi động IBus": "Start IBus",
    "3. Thêm VietTelex vào nguồn nhập": "3. Add VietTelex to input sources",
    "Đã có trong nguồn nhập.": "Already in input sources.",
    "Cài đặt → Bàn phím → Nguồn nhập → + → Tiếng Việt → VietTelex. Hoặc bấm Thêm để làm hộ.":
        "Settings → Keyboard → Input Sources → + → Vietnamese → VietTelex. Or click Add to do "
        "it for you.",
    "Mở IBus Preferences → Input Method → Add → Vietnamese → VietTelex.":
        "Open IBus Preferences → Input Method → Add → Vietnamese → VietTelex.",
    "Khởi động lại IBus": "Restart IBus",
    "Cần sau khi cài/cập nhật gói viettelex-ibus.": "Needed after installing/updating viettelex-ibus.",
    "Mở Cài đặt Bàn phím…": "Open Keyboard Settings…",
    "Nơi thêm/bớt và sắp xếp nguồn nhập của GNOME.": "Where GNOME input sources are added, removed and ordered.",
    "Lưu ý": "Notes",
    "Có bộ gõ tiếng Việt khác: %s": "Another Vietnamese input method is present: %s",
    "Bật cùng lúc hai bộ gõ Việt dễ bị gõ đúp dấu. Chỉ để một bộ trong danh sách nguồn nhập "
    "(hoặc gỡ gói kia).":
        "Two Vietnamese input methods at once easily double the marks. Keep only one in the "
        "input source list (or remove the other package).",
    "fcitx5-lotus đang chạy chế độ uinput": "fcitx5-lotus is running in uinput mode",
    "Lotus ở chế độ uinput gửi phím BackSpace thật: đổi bộ gõ hay cửa sổ giữa chừng một từ có "
    "thể xoá thừa chữ khi gõ bằng VietTelex. Nên chỉ giữ một bộ gõ tiếng Việt; nếu vẫn dùng "
    "Lotus, chuyển Lotus sang Preedit hoặc tắt server: %s":
        "Lotus in uinput mode sends real BackSpace keys: switching input method or window in "
        "the middle of a word can delete extra characters while typing with VietTelex. Keep "
        "only one Vietnamese input method; if you keep Lotus, set it to Preedit or stop its "
        "server: %s",
    "Fcitx5 và IBus cùng chạy": "Fcitx5 and IBus are both running",
    "Nên chỉ dùng một bộ khung gõ: im-config -n fcitx5 (hoặc ibus) rồi đăng nhập lại.":
        "Use only one framework: im-config -n fcitx5 (or ibus), then log in again.",
    "Phiên Wayland: Chrome/Electron (VS Code, Slack…)": "Wayland session: Chrome/Electron (VS Code, Slack…)",
    "Nếu không gõ được tiếng Việt trong Chrome hay app Electron, chạy app với %s (hoặc %s). "
    "Lệnh copy sẵn ở tab Tương thích.":
        "If you can’t type Vietnamese in Chrome or Electron apps, launch them with %s (or %s). "
        "Ready-to-copy commands are in the Compatibility tab.",
    "Thử gõ": "Try it",
    "Bật VietTelex (%s) rồi gõ: vieejt → việt": "Turn VietTelex on (%s), then type: vieejt → việt",
    "Thử gõ tại đây…": "Type here to try…",
    "Không chạy được %s": "Couldn’t run %s",
    "Đã khởi động Fcitx5.": "Fcitx5 started.",
    "Đã khởi động IBus.": "IBus started.",
    "Đã khởi động lại IBus.": "IBus restarted.",
    "VietTelex đã có trong nhóm bộ gõ.": "VietTelex is already in the input method group.",
    "Đã thêm VietTelex vào nhóm “%s”.": "Added VietTelex to the “%s” group.",
    "Không thêm tự động được — hãy thêm “VietTelex” trong cửa sổ cấu hình.":
        "Couldn’t add it automatically — add “VietTelex” in the configuration window.",
    "Không kết nối được Fcitx5 — hãy khởi động Fcitx5 trước.":
        "Couldn’t connect to Fcitx5 — start Fcitx5 first.",
    "Đã thêm VietTelex vào nguồn nhập — chuyển bằng Super+Space.":
        "Added VietTelex to input sources — switch with Super+Space.",
    "Đã thêm VietTelex vào IBus.": "Added VietTelex to IBus.",
    "Không tìm thấy cấu hình IBus.": "IBus configuration not found.",
    "Không thêm được — hãy thêm tay trong Cài đặt → Bàn phím.":
        "Couldn’t add it — add it by hand in Settings → Keyboard.",

    # --- dòng lệnh
    "Mở hướng dẫn bật bộ gõ": "Open the setup guide",
    "Không tự mở hướng dẫn khi bộ gõ chưa bật": "Don’t open the setup guide automatically",
    "Mở tab: typing|options|shortcuts|modes|compat|about": "Open a tab: typing|options|shortcuts|modes|compat|about",
}
