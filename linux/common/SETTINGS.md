# VietTelex Linux — hợp đồng cài đặt (settings contract)

Chủ sở hữu: frontend (Fcitx5/IBus, agent L1) **đọc**; `viettelex-settings` (GTK4, agent L2) **ghi**.
Parser tham chiếu: `linux/common/src/settings.cpp` (C++17, không phụ thuộc thư viện ngoài).

## 1. Vị trí file

| File | Đường dẫn | Ai ghi |
|---|---|---|
| Cài đặt | `$XDG_CONFIG_HOME/viettelex/config.toml` (mặc định `~/.config/viettelex/config.toml`) | settings app |
| Gõ tắt | `$XDG_CONFIG_HOME/viettelex/shortcuts.yml` | settings app (import/export) |
| Trạng thái Việt/Anh theo app | `$XDG_STATE_HOME/viettelex/app-state` (mặc định `~/.local/state/viettelex/app-state`) | **frontend** (settings app không đụng) |
| Lối tắt Chrome/Electron có cờ IME Wayland (§9) | `$XDG_DATA_HOME/applications/<id>.desktop` có dòng `X-VietTelex-Generated=` | settings app — chỉ file mang dòng đó |

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
display_mode = "preedit"            # "preedit" (chữ đang gõ, mặc định) | "surrounding" (sửa trực tiếp)
preedit_underline = false           # Gạch chân chữ đang gõ (false = gửi attr "không gạch chân")
underline_misspelled = false        # Gạch đỏ âm tiết sai chính tả khi gõ (chỉ preedit; IBus: gạch lỗi + chữ đỏ, Fcitx5: gạch chân)
terminal_direct = true              # Terminal: gõ thẳng, sửa dấu bằng BackSpace forward (khi host hỗ trợ)
toggle_hotkey = "Ctrl+space"        # xem §4; "" = tắt phím chuyển
per_app_state = true                # Nhớ Việt/Anh theo từng app
default_vietnamese = true           # Trạng thái khi gặp app lần đầu
ui_language = "vi"                  # Ngôn ngữ giao diện (app cài đặt + menu bộ gõ): "vi" | "en" — xem §6
text_tools_menu = true              # Hiện "Công cụ…" (công cụ văn bản) trong menu bộ gõ — xem §7
add_tones_hotkey = ""               # Phím tắt "Thêm dấu cho vùng chọn" (cú pháp §4); "" = tắt (mặc định)
math_results = true                 # Gợi ý cạnh con trỏ (§8): kết quả phép tính "12*3=" → 36
number_chips = true                 # chip số dạng tiền "1tr2 " → 1.200.000 ₫
typo_hints = true                   # sửa lỗi gõ sai "tpoi " → tôi
tone_hints = false                  # thêm dấu cho câu không dấu "toi di hoc." → tôi đi học.
date_hints = true                   # ngày giờ "hôm nay " → 28/09/2026, "bây giờ " → 21:35

[experimental]
no_underline = "off"                # "off" | "forward-keys": Chromium/Electron không gạch chân (§9)

[app_modes]
# key = định danh app (Fcitx5: program; IBus: client name / app-id Wayland / WM_CLASS, chữ thường)
# value = "preedit" | "surrounding" | "direct" | "off" (off = không gõ tiếng Việt trong app này)
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

**Chế độ Surrounding tự hạ về Preedit** khi surrounding text chưa được *chứng minh* trong lần
focus này (Fcitx5: có cờ SurroundingText và `surroundingText().isValid()`; IBus: client đã thực
sự gửi `SetSurroundingText` có chữ — chỉ cờ capability thì chưa đủ), hoặc app nằm trong danh
sách ép preedit dựng sẵn (`isForcedPreeditApp` trong `app.cpp`): terminal (gnome-terminal, kgx,
ptyxis, konsole, kitty, alacritty, wezterm, foot, xterm, tilix, terminator, VTE…), LibreOffice,
Chromium/Electron/VS Code (mọi trình duyệt Chromium: Cốc Cốc, Yandex, Thorium, Cromite, Helium,
Slimjet…; editor AI họ VS Code: Antigravity, Windsurf, Kiro, Trae, Void, PearAI, Positron; app
Electron: Signal, Element, Mattermost, Rocket.Chat, Caprine, Ferdium, Beeper, Vesktop, Feishu,
Notion, Logseq, Joplin, Typora, Notesnook, Anytype, Bitwarden, 1Password, Postman, Insomnia,
GitHub Desktop, GitKraken, Claude…; Spotify (CEF); kể cả id Flatpak/snap/AppImage của chúng; web
app/PWA `crx_*` / `chrome-*-default`), Firefox/LibreWolf/Zen/Thunderbird, Wine, gnome-shell (+ overview),
krunner/plasmashell, JetBrains/Java, WPS/OnlyOffice, Steam. Ghi đè tay trong `[app_modes]`
thắng danh sách dựng sẵn (trừ khi surrounding text chưa được chứng minh). Khi không được sửa
chữ quanh con trỏ, sửa dấu từ đã gõ (re-edit) và ⌫ mở lại từ cũng tắt; có vùng chọn (thanh
URL sau Ctrl+L / autocomplete) thì không bao giờ xoá chữ trước con trỏ.

**Kiểm tra trước khi xoá** (`checkScreen` trong `session.cpp`): mọi lần xoá chữ trước con trỏ
(sửa dấu tại chỗ ở Surrounding, ⌫ mở lại từ, re-edit, gõ tắt / tự khôi phục) đọc lại chữ app báo
và so byte với chữ VietTelex đã đặt ở đó (⌫ mở lại: từ + đúng ký tự ranh giới đã gõ). Khớp ⇒ làm.
App chưa kịp nhận commit mới nhất (chữ báo về là tiền tố của chữ mong đợi, hoặc rỗng) ⇒ sửa tại
chỗ vẫn làm (kênh IM giữ thứ tự), ⌫ mở lại / re-edit thì bỏ qua — không bao giờ chờ app. Không
khớp (app tự sửa chữ, commit bị nhân đôi kiểu Draft.js, chữ dạng NFD…) ⇒ bỏ lần sửa đó (phím đi
như thường: ⌫ của app, phím dấu gõ thành chữ) và **đến lần focus sau** coi surrounding của ô này
là không tin được: không re-edit / ⌫ mở lại, từ mới gõ bằng preedit. Không ghi vào config.

**Chế độ Direct** (không bao giờ là `display_mode` toàn cục): terminal (cờ ô nhập hoặc
`isTerminalApp`) hoặc app ép `"direct"`, *chỉ khi* host giữ đúng thứ tự phím forward —
IBus client `gtk3-im:`/`gtk-im:`, Fcitx5 D-Bus có `KeyEventOrderFix` (bảng đầy đủ:
`docs/LINUX-SPEC.md` §3.1). Host khác → Preedit. `terminal_direct = false` hoặc
`"x" = "preedit"` tắt Direct. Pin `"direct"` trên định danh chung chung bị bỏ qua. Direct không
đọc lại chữ (không re-edit, ⌫ không mở lại từ).

**Gạch chân** (`preedit_underline`): chỉ app vẽ đúng attr của IM mới bỏ được gạch chân (GTK/Qt/VTE
qua module IBus/Fcitx5). Chromium/Electron và app Wayland dùng text-input-v3 (GNOME) luôn tự gạch (Chromium/Electron trên
Wayland: thử nghiệm `no_underline = "forward-keys"`, §9).

**Định danh app chung chung** (`isUnknownAppId`): rỗng, `default`, `gnome-shell`,
`qibusinputcontext`, `xim`, `wayland`, `sdl2_application`, `sdl3_application`, `gtk-im`, chỉ
có pid (`(1234)`) — một id cho nhiều app, nên pin `"surrounding"` trên id này bị bỏ qua. Snap
`x_x` được rút về `x` (`firefox_firefox` → `firefox`).

**Kiểu ô nhập** thắng mọi luật theo app: terminal (IBus `PURPOSE_TERMINAL` / Fcitx5
`Terminal`) → Preedit, không sửa chữ quanh con trỏ; URL/email → Preedit; số/điện thoại
(`DIGITS`/`NUMBER`/`PHONE`, Fcitx5 `Digit`/`Number`/`Dialable`) → gõ thẳng không biến đổi;
ô nhạy cảm (Fcitx5 `Sensitive`, IBus `HINT_PRIVATE`) → gõ thẳng và không lưu Việt/Anh theo app.

**Mặc định tắt (English)** (`isDefaultOffApp`): remote desktop / máy ảo — remmina, anydesk,
rustdesk, virtualboxvm, vmware, vmplayer, remote-viewer, gnome-connections, krdc, xfreerdp,
wlfreerdp, sdl-freerdp, moonlight, parsec: phía bên kia tự có bộ gõ. Chương trình Wine
(`wine*-preloader`, id đuôi `.exe`) KHÔNG nằm trong danh sách này (từ 1.0.5) — app chạy tại máy,
gõ tiếng Việt bình thường, ép gạch chân (`isWineApp`, nhận chữ qua XIM). Muốn gõ tiếng Việt ở đó thì thêm bất kỳ mục nào cho app
trong `[app_modes]` (`"remmina" = "preedit"`), mục đó thắng danh sách dựng sẵn.

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

## 6. Ngôn ngữ giao diện (`ui_language`)

`"vi"` (mặc định) hoặc `"en"`; thiếu / giá trị lạ → `"vi"`. **Không bao giờ theo locale của
máy** (quy ước chung với iOS `L10n`): máy tiếng Anh vẫn mở tiếng Việt cho tới khi người dùng
chọn English ở Tuỳ chỉnh → "Ngôn ngữ / Language". Áp dụng ngay: app cài đặt dựng lại cửa sổ;
frontend (qua inotify) đổi nhãn menu bộ gõ (Tiếng Việt/English, Công cụ…, tên 6 công cụ,
Cài đặt…). Tên riêng (VietTelex, Fcitx5, IBus, Telex, VNI) giữ nguyên. Hộp cấu hình gốc của
Fcitx5 (`fcitx5-config-qt`) và tên bộ gõ "Tiếng Việt (VietTelex)" vẫn tiếng Việt.

## 7. Công cụ văn bản (`text_tools_menu`, `add_tones_hotkey`)

Như bản macOS (menu VietTelex → Công cụ…): bôi đen chữ ở app bất kỳ rồi chọn trong menu bộ gõ
(Fcitx5: action "Công cụ…" ở status area/tray; IBus: property menu "Công cụ…") — **Thêm dấu cho
vùng chọn** (toi di hoc → tôi đi học), **HOA**, **thường**, **Hoa Đầu Từ**, **Hoa đầu câu**,
**Xoá dấu**. `add_tones_hotkey` (vd `"Ctrl+Alt+v"`, phải có Ctrl/Alt/Super, không trùng
`toggle_hotkey` — trùng thì phím chuyển thắng) chạy Thêm dấu; bộ gõ nuốt phím đó.

- Biến đổi chạy ở **process con** `/usr/lib/<multiarch>/viettelex/viettelex-text-tool`
  (gói `viettelex-text-tools`, dữ liệu `/usr/share/viettelex/*.bin`) — cùng mã Swift với
  iOS/macOS (`linux/engine-capi/Sources/TextToolCLI`), dữ liệu không bao giờ nằm trong process
  bộ gõ. Thiếu gói → menu tự ẩn. Vùng chọn > 20.000 ký tự: bỏ qua.
- Lấy chữ: surrounding text có vùng chọn (GTK4, Qt, LibreOffice…). App báo surrounding mà không
  có vùng chọn (GTK3 — Firefox, Chromium, app GTK3 — không bao giờ báo vùng chọn): lấy vùng chọn
  PRIMARY nhưng chỉ khi nó nằm sát con trỏ (chữ ngay trước/sau con trỏ trùng nó), không thì không
  làm gì. App không báo surrounding: vùng chọn PRIMARY (Fcitx5: addon
  clipboard; IBus/dự phòng: `wl-paste --primary` / `xclip` / `xsel` nếu có sẵn — không phải
  phụ thuộc bắt buộc).
- Thay: commit kết quả đè lên vùng chọn (gõ đè thay vùng chọn). **Không đụng clipboard** nên
  không có gì phải khôi phục. Nếu menu làm app mất focus, kết quả được commit ở lần focus lại
  (trong 3 giây).
- Không chạy ở ô mật khẩu / ô nhạy cảm và terminal (gõ đè không thay được gì ở đó).

## 8. Gợi ý cạnh con trỏ (`math_results`, `number_chips`, `typo_hints`, `tone_hints`, `date_hints`)

Như bản macOS 1.8.2 (`App/Sources/MathHint.swift`, `CaretSuggestions.swift`). Mỗi loại một
công tắc; tắt hết = một lần đọc cờ mỗi phím, không theo dõi gì.

| Key | Mặc định | Kích hoạt → gợi ý |
|---|---|---|
| `math_results` | bật | phép tính + `=` (`12*3=`, `200+10%=`, `125 x (4 + 5.5) =`) → `= 36`; Tab **hoặc Enter** chèn kết quả sau `=` |
| `number_chips` | bật | `50k` / `1tr2` / `2 tỷ` + dấu cách → `1.200.000 ₫` (chỉ dạng tiền, không đọc số thành chữ); Tab thay |
| `typo_hints` | bật | từ vừa gõ (ranh giới ` , ; ! ? )`) không là âm tiết Việt / tiếng Anh / từ chat → sửa MỘT phím kề trên bàn phím cứng hoặc đảo hai phím liền nhau, cùng ngưỡng macOS (tần suất ≥ 150, hơn ứng viên thứ hai ≥ 80); Tab thay (giữ ký tự ranh giới), Esc = không gợi ý lại từ đó trong phiên |
| `tone_hints` | **tắt** | ≥ 3 âm tiết không dấu liên tiếp, rồi `. ! ?` hoặc dừng gõ 0,9 s sau dấu cách → cụm có dấu (Thêm dấu); Tab thay cả cụm, Esc = không mời lại cụm đó |
| `date_hints` | bật | `hôm nay` / `ngày mai` / `hôm qua` + dấu cách → `dd/MM/yyyy`; `bây giờ` → `HH:mm`; today / tomorrow / yesterday / now chỉ sau một từ tiếng Anh; Tab thay cụm |

Luật chung: chỉ Tab áp dụng (Enter chỉ cho phép tính — sau `50k␣` Enter là gửi tin), phím khác
tắt gợi ý rồi đi tiếp như thường, không bao giờ tự thay, không chạy ở ô mật khẩu / ô nhạy cảm /
khi đang English. Hiển thị: Fcitx5 = aux text của input panel, IBus = auxiliary text — UI của
khung (classicui/kimpanel, ibus-ui-gtk3, popup của GNOME Shell) vẽ ngay cạnh con trỏ; preedit
không bị đụng. Loại thay chữ đã chốt (mọi loại trừ phép tính) chỉ ở nơi bộ gõ được sửa chữ quanh
con trỏ (surrounding đã chứng minh, không phải app ép preedit — Chrome/Firefox/LibreOffice…; hoặc
terminal Direct); trước khi thay, chữ trước con trỏ được đọc lại (khi app báo) và phải khớp.

Chạy ở đâu: bộ gõ chỉ theo dõi đuôi chữ vừa gõ và xét cổng rẻ ở ranh giới từ / phím `=`
(`common/src/caret_hints.cpp`, `vt_is_valid_syllable` / `vt_is_unaccented_syllable`); việc tính
(MathResults, NumberChips, lexicon sửa lỗi, Thêm dấu — mã Swift chung iOS/macOS) ở
`viettelex-text-tool --serve`: một process con sống lâu, bật ở lần kích hoạt đầu, tự thoát sau
2 phút rảnh. Thiếu gói `viettelex-text-tools` → không có gợi ý nào.

## 9. Thử nghiệm: không gạch chân ở Chromium/Electron (`[experimental] no_underline`)

`"off"` (mặc định; giá trị lạ cũng là off) hoặc `"forward-keys"`. App cài đặt: tab **Tuỳ chỉnh →
Hiển thị chữ đang gõ → "Bỏ gạch chân trong Chrome/Electron (thử nghiệm)"** (ghi tại chỗ như mọi
key khác); áp dụng ngay (inotify). Đánh giá đầy đủ + kế hoạch kiểm thử:
`docs/NO-UNDERLINE-SPIKE.md`.

- `"forward-keys"`: app họ Chromium (`isChromiumApp`: Chrome/Chromium/Brave/Edge/Vivaldi/Opera/
  Cốc Cốc…, VS Code + Antigravity/Windsurf/Kiro…, Slack, Discord, Zalo, Obsidian…, PWA `crx_*` / `chrome-*-default`) gõ thẳng
  không gạch chân; sửa dấu bằng **phím BackSpace do bộ gõ forward** rồi commit chữ mới — không
  dùng `delete_surrounding_text` (Draft.js/Lexical ở Messenger không theo được). Chỉ khi:
  host giữ thứ tự phím forward với commit (`hostOrdersForwardedKeys`: IBus trên GNOME Wayland —
  client `gnome-shell`; Fcitx5 frontend `wayland` trên KWin; Fcitx5 frontend `ibus` trên GNOME
  Wayland, chỉ ngữ cảnh của chính gnome-shell — `program` `gnome-shell` hoặc id app `*.desktop` /
  `window:N` của Fcitx5 mới, trong phiên GNOME Wayland; client IBus X11/XWayland khác qua cùng
  frontend vẫn gạch chân) — **trừ GNOME 50** (mutter 50 bỏ phím forward, sửa ở 51:
  `gnome::mutterDeliversForwardedKeys`, NO-UNDERLINE-SPIKE §5.2), app id thật (không phải id chung),
  surrounding text đã chứng minh trong lần focus này, ô không phải URL / terminal / số / mật
  khẩu / nhạy cảm, và app không có mục `[app_modes]` (mục đó luôn thắng). Còn lại: như `"off"`.
- Ở chế độ này không re-edit, ⌫ không mở lại từ (chỉ sửa trong từ đang gõ, gõ tắt, tự khôi
  phục); vùng chọn ở con trỏ thì không gửi BackSpace.
- Mỗi lần sửa được **xác nhận** từ chữ app báo trước con trỏ ở các phím sau. Chữ khác điều
  VietTelex đã gửi (mất / thừa BackSpace, commit đôi…) hoặc quá 1 giây chưa thấy kết quả ⇒ ô đó
  về gạch chân tới lần focus sau. Không bao giờ chờ / ngủ trong đường phím.
- Chrome/Electron phải chạy IME Wayland gốc (text-input), không qua `--gtk-version=4` / XWayland.
  Chrome ≥ 140 và Electron ≥ 38 đã như vậy mặc định trên phiên Wayland (text-input-v3 mặc định
  từ Chromium 137, Wayland mặc định từ Chrome 140 / Electron 38). App cũ hơn cần cờ ⇒ app cài
  đặt tự làm, người dùng không chạy lệnh nào:

### 9.1 Lối tắt có cờ (`viettelex_settings/launchers.py`)

- Khi cờ bật **và** phiên Wayland trên GNOME (IBus/Fcitx5) hoặc KDE (Fcitx5): với mỗi app họ
  Chromium (tên file .desktop hoặc `StartupWMClass` khớp `isChromiumApp` — danh sách Python có
  test so khớp với `app.cpp`) tìm trong `XDG_DATA_DIRS` (+ export Flatpak, `/var/lib/snapd/desktop`),
  chép file sang `$XDG_DATA_HOME/applications/` (mặc định `~/.local/share/applications`, ưu
  tiên cao hơn theo XDG) và chèn `--enable-wayland-ime --wayland-text-input-version=3
  --ozone-platform-hint=auto` vào mọi `Exec=` (mục chính + Desktop Actions): ngay sau chương
  trình (trước tham số và `%U/%F`); `env A=1 /opt/x` ⇒ sau `/opt/x`; `flatpak run … <appid>` ⇒
  sau app id (trước `@@u`); `/snap/bin/x`, `snap run x` ⇒ sau đó. Cờ đã có thì không thêm
  (idempotent). KDE với KWin < 6.7 (còn text-input-v1): `=1`. Mọi key khác (`TryExec`, `Icon`,
  `StartupWMClass`, bản dịch, `X-Flatpak`…) giữ nguyên.
- Bỏ qua (báo trong dòng mô tả): Exec ép X11 (`--ozone-platform=x11`, `GDK_BACKEND=x11`,
  `ELECTRON_OZONE_PLATFORM_HINT=x11`, `--disable-wayland-ime`), wrapper không sửa an toàn
  (`sh -c`, `flatpak run --command=sh`, `gtk-launch`…), `DBusActivatable=true`; Chrome / Edge /
  Chromium (.deb, snap) có phiên bản ≥ 140 đọc được từ `/var/lib/dpkg/status` /
  `snap.yaml` (đã bật mặc định — trừ KDE cần `=1`).
- Sở hữu: file tạo ra có `X-VietTelex-Generated=<sha256(nguồn + cờ)[:16]>` và
  `X-VietTelex-Source=<đường dẫn nguồn>`. Chỉ file có dòng `X-VietTelex-Generated` mới bị sửa/xoá;
  file người dùng tự đặt cùng tên (hoặc symlink) không bao giờ bị ghi đè — chỉ báo lại. Muốn
  giữ file của ta làm của mình: xoá dòng `X-VietTelex-Generated`.
- Làm mới mỗi lần mở app cài đặt và khi bật/tắt: nguồn đổi (hash khác) ⇒ tạo lại; nguồn mất ⇒
  xoá; tắt ⇒ xoá mọi file của ta. Phiên X11 / desktop chưa hỗ trợ mà cờ đang bật: chỉ làm mới /
  xoá file đã có, không tạo mới. Có thay đổi ⇒ `update-desktop-database -q <dir>` nếu có (lỗi bỏ
  qua).
- App đang chạy mà tiến trình chính không mang `--enable-wayland-ime` (mở trước khi có lối tắt)
  ⇒ dòng mô tả + thông báo "thoát hẳn rồi mở lại …".
- Không dùng `~/.config/<app>-flags.conf`: chỉ wrapper của Arch đọc; wrapper của gói .deb Google
  Chrome (`chrome/installer/linux/common/wrapper`) chỉ `exec -a "$0" "$HERE/chrome" "$@"`.
