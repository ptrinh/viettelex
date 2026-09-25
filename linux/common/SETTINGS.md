# VietTelex Linux — hợp đồng cài đặt (settings contract)

Chủ sở hữu: frontend (Fcitx5/IBus, agent L1) **đọc**; `viettelex-settings` (GTK4, agent L2) **ghi**.
Parser tham chiếu: `linux/common/src/settings.cpp` (C++17, không phụ thuộc thư viện ngoài).

## 1. Vị trí file

| File | Đường dẫn | Ai ghi |
|---|---|---|
| Cài đặt | `$XDG_CONFIG_HOME/viettelex/config.toml` (mặc định `~/.config/viettelex/config.toml`) | settings app |
| Gõ tắt | `$XDG_CONFIG_HOME/viettelex/shortcuts.yml` | settings app (import/export) |
| Trạng thái Việt/Anh theo app | `$XDG_STATE_HOME/viettelex/app-state` (mặc định `~/.local/state/viettelex/app-state`) | **frontend** (settings app không đụng) |

- Thiếu file / thiếu key / giá trị sai kiểu → dùng **mặc định** bên dưới (không lỗi, không crash).
- **Ghi nguyên tử**: ghi `config.toml.tmp` rồi `rename()` sang `config.toml` (cùng thư mục).
  Frontend theo dõi **thư mục** `viettelex/` bằng inotify (`IN_CLOSE_WRITE | IN_MOVED_TO |
  IN_DELETE`) và nạp lại ngay — không cần restart IM. Frontend cũng tự kiểm tra `mtime`
  mỗi lần focus-in (dự phòng khi inotify không có).
- Mã hoá UTF-8, xuống dòng `\n`.

## 2. `config.toml` — tập con TOML

Chỉ dùng: bảng `[section]`, `key = value`, giá trị `true`/`false`, số nguyên, chuỗi
`"..."` (escape `\"` `\\` `\n` `\t`), comment `#`. Key trong `[app_modes]` là chuỗi có
ngoặc kép. Không dùng mảng, inline table, chuỗi nhiều dòng.

```toml
[typing]
input_method = "telex"              # "telex" | "vni"
simple_telex = false                # w đứng một mình không thành ư
free_marking = true                 # Bỏ dấu tự do
modern_tone = false                 # Kiểu dấu mới (hoà/khoẻ/thuý); false = kiểu cũ (hòa)
quick_telex = false                 # Gõ nhanh cc→ch, gg→gi, kk→kh, nn→ng, pp→ph, qq→qu, tt→th
spell_check = true                  # Kiểm tra chính tả khi gõ (dừng biến đổi từ không hợp lệ)
auto_restore = true                 # Tự khôi phục từ không phải tiếng Việt (tiếng Anh)
teencode = false                    # Chấp nhận teencode (wá, zô, kó, thík…)
contextual_english = true           # Quyết định theo ngữ cảnh (từ trước là tiếng Anh)
collision_prefers_vietnamese = true # last/lát, his/hí: giữ tiếng Việt
bracket_vowels = false              # [ → ơ, ] → ư
shortcuts_enabled = true            # Bật bảng gõ tắt (shortcuts.yml)
re_edit_word = true                 # Sửa dấu từ đã gõ khi đặt con trỏ ngay sau nó ("toan" + s → toán)

[general]
display_mode = "preedit"            # "preedit" (gạch chân, mặc định) | "surrounding" (không gạch chân)
toggle_hotkey = "Ctrl+space"        # xem §4; "" = tắt phím chuyển
per_app_state = true                # Nhớ Việt/Anh theo từng app
default_vietnamese = true           # Trạng thái khi gặp app lần đầu

[app_modes]
# key = định danh app (Fcitx5: program; IBus: client name / app-id Wayland / WM_CLASS, chữ thường)
# value = "preedit" | "surrounding" | "off" (off = không gõ tiếng Việt trong app này)
"org.gnome.texteditor" = "surrounding"
"kitty" = "preedit"
```

Mặc định = giống bản macOS hiện tại (bảng trên là mặc định chính xác, trừ ví dụ `[app_modes]`
vốn rỗng). Map sang cờ engine (`vt_engine_set_flag`):
`input_method=vni→VT_FLAG_VNI`, `simple_telex→SIMPLE_TELEX`, `free_marking→FREE_MARKING`,
`modern_tone→MODERN_TONE`, `quick_telex→QUICK_TELEX`, `spell_check→LIVE_SPELL_CHECK`,
`teencode→TEENCODE`, `contextual_english→CONTEXTUAL_ENGLISH`,
`collision_prefers_vietnamese→COLLISION_PREFERS_VIETNAMESE`, `bracket_vowels→BRACKET_VOWELS`;
`auto_restore` là tham số của `vt_commit` (không phải cờ).

**Chế độ Surrounding tự hạ về Preedit** khi app không báo hỗ trợ surrounding text, hoặc app
nằm trong danh sách ép preedit dựng sẵn (terminal: gnome-terminal, kgx/ptyxis, konsole,
kitty, alacritty, wezterm, foot, xterm, tilix, terminator; LibreOffice). Ghi đè tay trong
`[app_modes]` thắng danh sách dựng sẵn (trừ khi app không có surrounding text).

**Ghi chung file**: hộp cấu hình Fcitx5 (các tuỳ chọn cơ bản) cũng ghi `config.toml`, nhưng chỉ
sửa đúng dòng của key nó quản lý (`setConfigValue`), giữ nguyên comment và key lạ — settings app
nên làm tương tự (hoặc ít nhất giữ key nó không biết).

**Định danh app**: Fcitx5 = `program` của input context; IBus = client name từ `focus_in_id`
(IBus ≥ 1.5.28, Ubuntu 24.04+). Trên Ubuntu 22.04 (IBus 1.5.26) IBus không báo app → mọi app
dùng chung key `default` (nhớ Việt/Anh chung, `[app_modes]` không áp dụng); Fcitx5 thì có đủ.

## 3. `shortcuts.yml` — cùng định dạng macOS

Flat YAML `key: value`, một mục mỗi dòng, `:` đầu tiên tách key/value; bỏ qua dòng trống và
dòng bắt đầu bằng `#`, `;`, `//`; key không chứa khoảng trắng, ≤ 64 ký tự; value được trim, bỏ
một cặp ngoặc `"…"`/`'…'` bao ngoài. Export: header `# VietTelex — bảng gõ tắt`, key sắp xếp,
value có khoảng trắng đầu/cuối hoặc bắt đầu bằng `'` `"` `#` thì bọc `"…"`. File
`sample-shortcuts.yml` ở gốc repo là ví dụ hợp lệ. Import (settings app) nên chấp nhận thêm JSON
object `{"key":"value"}` như macOS, nhưng **file lưu trên đĩa luôn là flat YAML**.

Khớp khi gõ: ở boundary, tra từ đã ghép (`composed`) trước, rồi phím thô (`raw`) — như macOS.

## 4. Phím chuyển Việt/Anh (`toggle_hotkey`)

Chuỗi `Mod+Mod+key`: modifier trong `Ctrl`, `Alt`, `Shift`, `Super` (không phân biệt hoa thường),
`key` là tên keysym X11 (`space`, `grave`, `z`, `F12`…). Mặc định `Ctrl+space`. Không cho phép
`Super+space` (GNOME dùng). Trên Fcitx5, `Ctrl+space` trùng trigger key mặc định của Fcitx5: khi
VietTelex đang là IM hiện hành, VietTelex bắt phím trước và chỉ đổi Việt/Anh (vẫn ở VietTelex);
khi đang ở keyboard-us thì trigger của Fcitx5 chuyển sang VietTelex như thường. Chuỗi rỗng = không có phím chuyển (vẫn đổi qua menu IM).

## 5. `app-state` (frontend sở hữu)

Dòng `app<TAB>vi|en`. Chỉ frontend đọc/ghi; settings app có thể xoá file để "quên tất cả".
