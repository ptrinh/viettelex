# VietTelex Linux — Spec (Ubuntu trước, distro khác sau)

> Trạng thái: SPEC (26/09/2026). Nguồn sự thật hành vi: app macOS (`App/`) + engine `TelexCore/`.
> Mục tiêu: **gõ y hệt macOS** (cùng engine, cùng tuỳ chọn, cùng bảng gõ tắt), chạy như
> input method chuẩn của Linux — không hook bàn phím, không cần quyền root khi gõ.

---

## 1. Nguyên tắc

- **Một engine duy nhất**: dùng lại `TelexCore` Swift (engine không import Foundation, chỉ
  `ClientPolicy.swift` dùng Foundation → không mang sang). Không port engine lần thứ ba.
- **Chuẩn IM framework**: là engine của **IBus** (mặc định Ubuntu/GNOME) và **Fcitx5**
  (KDE, người dùng Việt hay dùng). Không dùng uinput/evdev/X11 grab (cần root, vỡ Wayland,
  bị coi là keylogger).
- **Nhẹ**: engine chạy trong process của framework (Fcitx5 addon) hoặc 1 process nhỏ (IBus),
  RAM < 15 MB, 0% CPU khi không gõ, không timer idle, không mạng (trừ *Kiểm tra cập nhật*).
- **Không thu thập dữ liệu**. Mỗi bug sửa kèm regression test (quy ước dự án).

## 2. Kiến trúc

```
VietTelex/linux (cùng repo public)
├── core-c/          libtelexcore: TelexCore Swift build --static-swift-stdlib, xuất C ABI
│   ├── Sources/TelexCoreC/   @_cdecl shim: vt_engine_new/feed/backspace/commit/peek/…
│   └── include/telexcore.h
├── ibus/            ibus-engine-viettelex (C + GLib), component XML
├── fcitx5/          viettelex.so (C++ addon, Fcitx5 InputMethodEngine)
├── settings/        viettelex-settings (GTK4 + libadwaita) — dùng chung cho cả 2 frontend
├── packaging/       .deb (Ubuntu 24.04/26.04), PPA, Flatpak-không (IM không chạy được trong Flatpak), AUR sau
└── tests/           golden corpus + test frontend với mock InputContext
```

- **Engine qua C ABI**: shim `TelexCoreC` bọc `TelexEngine` bằng handle mờ; API = bảng Swift→C:

| Swift | C |
|---|---|
| `TelexEngine()` + flags | `vt_engine_new()`, `vt_engine_set_flag(h, VT_FLAG_*, bool)` |
| `feed(ch) -> TelexAction` | `vt_feed(h, uint32 ch, vt_action* out)` → `{kind, backspaces, insert[utf8]}` |
| `backspace()` | `vt_backspace(h, vt_action*)` |
| `commitBoundary(autoRestore:)` | `vt_commit(h, bool, vt_action*)` |
| `peekCommitText`, `composed`, `rawKeystrokes` | `vt_peek`, `vt_composed`, `vt_raw` (buffer do caller cấp) |
| `reset()`, `resetContext()` | `vt_reset`, `vt_reset_context` |

  Không cấp phát trên đường nóng: `vt_action.insert` là buffer cố định 64 byte trong struct.
- Build: Swift toolchain Linux chính thức (swift.org), `swift build -c release --static-swift-stdlib`
  → `.so` tự chứa (không phụ thuộc libswiftCore hệ thống). Mục tiêu kích thước < 6 MB.
- CI (GitHub Actions `ubuntu-24.04`): build + chạy golden corpus trên Linux mỗi PR.

## 3. Mô hình hiển thị chữ (quan trọng nhất trên Linux)

Linux không có "tap backspace" ổn định như macOS; hai cách chuẩn của IM framework:

| Chế độ | Cách làm | Ưu | Nhược |
|---|---|---|---|
| **Preedit** (mặc định) | từ đang gõ là preedit (gạch chân), commit ở boundary | chạy mọi nơi: GTK, Qt, Electron, Chrome, terminal, Wayland/X11 | có gạch chân như ibus-unikey |
| **Surrounding text** (tuỳ chọn "Sửa trực tiếp") | commit từng phím; sửa dấu bằng `delete_surrounding_text` rồi commit | giống macOS/Windows | chỉ ổn ở app GTK/Qt hỗ trợ surrounding text |
| **Direct** (terminal, tự động) | gõ thẳng; sửa dấu bằng BackSpace *forward* + chữ mới cũng *forward* thành phím (kiểu UniKey/Windows) | không gạch chân trong terminal | chỉ ở host giữ đúng thứ tự phím forward (§3.1) |

- Chế độ 2 tự hạ về Preedit khi `IBUS_CAP_SURROUNDING_TEXT` / `CapabilityFlag::SurroundingText`
  không có, hoặc app nằm trong danh sách ép (terminal: gnome-terminal, konsole, kitty, alacritty,
  wezterm, foot; Electron/Chromium trên Wayland; LibreOffice).
- **Bảng cơ chế theo app** (tương đương tab "Bảng cơ chế gõ" macOS): key = `program`
  (Fcitx5) / `client` + WM_CLASS / app-id Wayland (IBus). User ép tay Preedit/Surrounding.
- Preedit style: **không gạch chân** mặc định (`preedit_underline = false`, "Gạch chân chữ đang
  gõ"); IBus gửi `IBUS_ATTR_UNDERLINE_NONE` tường minh, Fcitx5 gửi `TextFormatFlag::NoFlag`. Ở
  Surrounding/Direct bỏ preedit hoàn toàn.
- Mất focus / click chuột / đổi con trỏ → commit preedit (không nuốt chữ), reset engine.

### 3.1 Direct cho terminal và gạch chân — kết quả đọc mã nguồn (26/09/2026)

**Vì sao không forward BackSpace rồi `commit_text`** (cách ibus-bamboo "BackspaceForwarding"):
module GTK3 của IBus (`client/gtk2/ibusimcontext.c`) đưa phím forward vào hàng đợi bằng
`gdk_event_put`, còn `commit` phát ngay → chữ mới đến **trước** BackSpace. ibus-bamboo chữa bằng
`time.Sleep(30ms × n)` (`engine_backspace.go: SendBackSpace`, ghi chú "serious sync issue").
fcitx5-gtk3 y hệt (`gdk_event_put` + commit tức thì); fcitx5-qt forward qua
`QWindowSystemInterface::handleExtendedKeyEvent` (hàng đợi) còn commit là `sendEvent` (tức thì).

**Cách của VietTelex**: forward **cả BackSpace lẫn chữ mới** thành phím (`ibus_unicode_to_keyval`
/ `Key::keySymFromUnicode`). Phím forward mang `IBUS_FORWARD_MASK`/`IgnoredMask`; module GTK tự
commit phím in được (`ibus_im_context_commit_event`, fallback `GtkIMContextSimple` của fcitx5-gtk),
BackSpace đến widget (VTE gửi `^?` cho pty) → một hàng đợi duy nhất, đúng thứ tự, không sleep.
Engine không bao giờ đọc lại chữ; phím forward quay về engine (có `IBUS_FORWARD_MASK`) bị bỏ qua.
`delete_surrounding_text` vô dụng ở terminal: VTE không nối tín hiệu `delete-surrounding`,
Konsole bỏ qua `replacementStart/Length` của `QInputMethodEvent`. fcitx5-unikey/fcitx5-bamboo
không có chế độ BackSpace: terminal dùng preedit.

| Host (cách client nói chuyện với IM) | Direct? | Lý do |
|---|---|---|
| IBus, client `gtk3-im:` / `gtk-im:` (X11, hoặc Wayland khi `GTK_IM_MODULE=ibus`) | **có** | `gdk_event_put` cho mọi phím forward → đúng thứ tự |
| IBus, client `gtk4-im:` (Ptyxis, Console/kgx) | không | GTK4 forward = `gtk_im_context_filter_key` chỉ tới IM, không tới widget → BackSpace mất |
| IBus trên GNOME Wayland (client `gnome-shell`, text-input-v3) | không | phím forward thành `wl_keyboard`, commit qua text-input → hai kênh |
| IBus Qt (`QIBusInputContext`), IBus XIM (`xim`), IBus < 1.5.28 | không | không biết app/terminal (Qt thì đúng thứ tự nhưng không nhận diện được) |
| Fcitx5 D-Bus có `KeyEventOrderFix` (fcitx5-gtk2/3, fcitx5-qt5/6 — X11 và KDE Wayland khi `QT_IM_MODULE=fcitx`) | **có** | hàng đợi GDK / QWSI cho mọi phím forward |
| Fcitx5 D-Bus không `KeyEventOrderFix` (fcitx5-gtk4) | không | `_fcitx_im_context_forward_key_cb` của GTK4 là hàm rỗng |
| Fcitx5 Wayland (`wayland`/`wayland_v2`), XIM, IBus-emulation | không | kênh khác nhau / XIM forward chỉ mang keycode (mất ư, ơ) / không biết toolkit |

Terminal = cờ ô nhập (IBus `PURPOSE_TERMINAL`, Fcitx5 `Terminal`) hoặc app trong `isTerminalApp`.
Tắt: `terminal_direct = false`; từng app: `[app_modes] "x" = "preedit"`; app thường có thể ép
`"direct"` (chỉ có tác dụng ở host "có"). Kết thúc từ (reset engine): Enter, Tab, mũi tên,
phím tắt Ctrl/Alt (Ctrl+Shift+V), click chuột (VTE gọi `im_reset` mỗi lần nhấn chuột → dán
bằng chuột giữa cũng reset), mất focus. ⌫ giữa từ: engine tự tính lại, xoá bằng BackSpace forward.
Rủi ro còn lại: `IBUS_ENABLE_SYNC_MODE=1` (không mặc định) + gõ rất nhanh có thể xen phím thật vào.

**Ai tôn trọng "không gạch chân"** (đọc mã nguồn):

| Client | Không gạch chân được? | Chi tiết |
|---|---|---|
| GTK3/GTK4 qua module IBus (X11, hoặc `GTK_IM_MODULE=ibus`) | **có** | `ibusimcontext.c` đổi đúng `IBUS_ATTR_TYPE_UNDERLINE` → `pango_attr_underline_new(value)`; GtkEntry/GtkTextView vẽ đúng attr |
| VTE (gnome-terminal, tilix, Ptyxis…) qua module IBus/Fcitx | **có** | `Terminal::draw_cells_with_attributes` dùng attr Pango của preedit; chỉ ô dưới con trỏ preedit bị đảo màu (ta đặt con trỏ ở cuối) |
| fcitx5-gtk2/3/4 | **có** | `NoFlag` → không thêm attr gạch chân (chỉ tự gạch chân khi *không có* danh sách định dạng) |
| Qt qua IBus (`qibustypes.cpp`) / fcitx5-qt | **có** | `UnderlineNone` → `NoUnderline`; fcitx5-qt chỉ gạch khi có cờ `Underline`. Konsole bỏ qua attr, vẽ preedit theo kiểu ô hiện tại |
| Chromium/Electron (X11 qua GTK) | **không** | `composition_text_util_pango.cc`: mọi attr underline (kể cả NONE) → gạch mảnh; không attr → gạch mảnh mặc định |
| GNOME Wayland (mọi app qua text-input-v3) | **không** | gnome-shell `inputMethod.js` bỏ mọi attr kiểu dáng, chỉ chuyển *hint*; GTK3 `imwayland.c` luôn gạch chân; GTK4 gạch chân khi không có hint (bản mới: theo CSS `preedit`) |
| Fcitx5 Wayland (`wayland_v2`) / Qt, GTK text-input-v3 | **không** | text-input-v3 không có kiểu dáng preedit, client tự vẽ gạch chân |
| kitty, alacritty, wezterm, foot | tuỳ app | tự vẽ preedit, thường luôn gạch chân |

## 4. Hành vi gõ (port nguyên từ macOS)

- Kiểu gõ: Telex, Simple Telex, bỏ dấu tự do, Gõ nhanh (cc→ch…), kiểu dấu cũ/mới, VNI,
  kiểm tra chính tả khi gõ, teencode (mặc định TẮT), quyết định theo ngữ cảnh, tự khôi phục
  tiếng Anh, nhận token camelCase. Mặc định giống bản macOS hiện tại.
- Gõ tắt: cùng định dạng YAML như `sample-shortcuts.yml`, import/export.
- Boundary: space, dấu câu, Enter, Tab, phím điều hướng → `vt_commit`.
- Phím có Ctrl/Alt/Super → commit rồi trả phím cho app (không nuốt shortcut).
- Ô mật khẩu (`IBUS_INPUT_PURPOSE_PASSWORD` / `ContentHint`/`Purpose::Password`) → tắt Telex.
- Ô URL/email/terminal-purpose: giữ Telex nhưng ưu tiên khôi phục tiếng Anh (như macOS).
- Bật/tắt tiếng Việt: phím tắt mặc định `Ctrl+Space` (đổi được), không đè Super+Space của GNOME.
  Nhớ trạng thái Việt/Anh theo từng app (tương đương StickyInputSource).
- Bố cục bàn phím không phải US (AZERTY, Dvorak): đọc keysym sau layout, không đọc keycode.

## 5. Frontend

### 5.1 IBus (Ubuntu mặc định)
- `ibus-engine-viettelex` + `/usr/share/ibus/component/viettelex.xml`; tên hiển thị
  **"Tiếng Việt (VietTelex)"**, icon Vᵀ.
- `process_key_event`, `focus_in/out`, `reset`, `set_surrounding_text`, property menu
  (Việt/Anh, Cài đặt…).
- GNOME: người dùng thêm qua Settings → Keyboard → Input Sources → Vietnamese → VietTelex.

### 5.2 Fcitx5
- Addon C++ `viettelex.so` + `viettelex.conf`; config UI Fcitx5 tự sinh từ option descriptor
  cho các tuỳ chọn cơ bản; "Cài đặt nâng cao…" mở `viettelex-settings`.
- Chạy trong process fcitx5 → độ trễ thấp nhất; không crash-loop (catch mọi lỗi ở ranh giới C).

### 5.3 Cài đặt (`viettelex-settings`, GTK4/libadwaita)
- Tab giống macOS: Kiểu gõ · Tuỳ chỉnh · Gõ tắt · Bảng cơ chế gõ · Tương thích · Giới thiệu.
- Tab *Tương thích* (`compat.py`, hàm thuần + test): chỉ liệt kê lưu ý khớp máy, mỗi mục có
  lệnh sửa copy được — Chrome/Electron Wayland, kitty/JetBrains X11, rofi, Tổng quan GNOME,
  Snap + Fcitx5 (22.04), im-config auto khi cài cả hai framework, Qt5 Wayland thiếu
  `QT_IM_MODULE`, terminal luôn preedit.
- Lưu `~/.config/viettelex/config.toml` + `shortcuts.yml`; frontend nghe inotify → áp ngay,
  không cần khởi động lại IM (bài học Android: đổi setting phải có hiệu lực tức thì).

## 6. Riêng Linux cần xử lý

| Vấn đề | Cách xử lý |
|---|---|
| Wayland + Chrome ≥ 140 / Electron ≥ 38 không nhận IM | Cờ `--enable-wayland-ime --wayland-text-input-version=3` (GNOME + IBus), KWin `=1`, hoặc `--ozone-platform=x11`; tự phát hiện và báo trong Cài đặt |
| GNOME Wayland: một input context chung cho mọi app (IBus, Fcitx5 < 5.1.22) | `GnomeAppMonitor` đọc app đang focus từ gnome-shell qua session bus (§6.1) → id thật đi qua `resolveAppPolicy` như mọi app |
| Ubuntu 22.04 IBus 1.5.26 không có app id | App X11/XWayland vẫn là "default"; trên GNOME Wayland "default" cũng được thay bằng app đang focus (§6.1) |
| im-config | GNOME: không tác dụng. Desktop khác: `auto` chọn IBus khi cài cả hai → `im-config -n fcitx5`; Cài đặt cảnh báo |
| Biến môi trường Qt / SDL | Qt ≥ 6.8.2 `QT_IM_MODULES="wayland;fcitx;ibus"`, Qt5 `QT_IM_MODULE`; game SDL `SDL_IM_MODULE`; Cài đặt cảnh báo Qt5 Wayland thiếu biến |
| Compositor khác | Sway ≥ 1.10 (text-input-v3); Hyprland: dùng Fcitx5 |
| LibreOffice Calc | Bấm ra ô khác / AutoInput có thể làm lệch chữ → khuyên tắt AutoInput nếu gặp lỗi |
| Konsole/Kate dưới IBus (Qt) | Khuyên Fcitx5 trên KDE |
| Mật khẩu `sudo` trong terminal | Không phát hiện được ô mật khẩu → hướng dẫn chuyển EN |
| Flatpak/Snap app | Dùng IBus/Fcitx portal sẵn có; ghi chú: Snap Firefox cần `ibus` portal |
| Terminal / vim / tmux | Direct ở host đúng thứ tự (§3.1), còn lại Preedit; Esc kết thúc từ để vim không mất chữ |
| Nhiều bộ gõ Việt cùng bật (ibus-unikey, bamboo) | Không can thiệp; hướng dẫn gỡ nếu bị gõ đúp |
| Xung đột phím tắt GNOME | Không dùng Super+Space; kiểm tra trùng khi đặt phím |
| Remote desktop / VM / Wine | Giống macOS: có sẵn trong danh sách mặc định tắt tiếng Việt (core); khuyên bật bộ gõ ở máy bị điều khiển |

### 6.1 App đang gõ trên GNOME Wayland (`common/src/gnome*.cpp`)

**Vì sao cần**: mọi app Wayland gõ qua *một* input context của gnome-shell → IBus báo
`gnome-shell` (≥ 1.5.28) hoặc `default` (1.5.26, Ubuntu 22.04), Fcitx5 < 5.1.22 báo
`gnome-shell` → không nhớ Việt/Anh theo app, không bật được chế độ không gạch chân.

**Các đường đã xét** (GNOME 42 = 22.04, 46 = 24.04):

| Đường | Kết quả |
|---|---|
| Gọi thẳng `org.gnome.Shell.Introspect.GetRunningApplications` / `GetWindows` | GNOME ≥ 41: `DBusSenderChecker` chỉ cho `org.freedesktop.impl.portal.desktop.{gtk,gnome}` → AccessDenied (trừ unsafe mode). Signal `RunningApplicationsChanged` thì ai cũng nghe được |
| Portal `org.freedesktop.impl.portal.Background.GetAppState` | Chỉ có app Flatpak/Snap (`X-Flatpak` / `sandboxed-app-id`), chỉ báo đổi khi app chạy/tắt → không dùng được |
| AT-SPI focus | Chrome/Electron/Firefox/Qt chỉ bật a11y khi có trình đọc màn hình; tốn CPU mọi app → bỏ |
| Extension GNOME | Phải cài + bật tay, vỡ theo phiên bản shell → chỉ để dự phòng, chưa cần |
| **Theo dõi bus (chọn)** | Như fcitx5 5.1.22 `gnomeappmonitor.cpp` |

**Cơ chế**: gnome-shell phát `RunningApplicationsChanged` *đồng bộ* mỗi khi đổi app focus
(`notify::focus-app`); xdg-desktop-portal-gnome (background.c, 42 và 46) gọi ngay
`GetRunningApplications` (được phép). Một kết nối session bus riêng gọi
`org.freedesktop.DBus.Monitoring.BecomeMonitor` (dbus-daemon/dbus-broker cho phép cùng uid)
với 4 match rule: signal đó, lời gọi `GetRunningApplications` (của bất kỳ ai), các reply của
`org.gnome.Shell`, `PropertiesChanged` `OverviewActive`. Reply `a{sa{sv}}` (khoá = id
ShellApp `org.gnome.TextEditor.desktop`, app focus có `active-on-seats`) → id chuẩn hoá
`org.gnome.texteditor` → `resolveAppPolicy`. Không polling; message xử lý trên thread worker
GDBus, frontend chuyển về main loop (IBus `g_main_context_invoke`, Fcitx5 `EventDispatcher`).

**An toàn (mặc định vẫn là gạch chân)**:
- Chỉ bật khi `XDG_CURRENT_DESKTOP` có `GNOME` và phiên Wayland; chỉ thay id `gnome-shell` /
  `default` / `wayland` / rỗng — id thật (X11, Fcitx5 ≥ 5.1.22) giữ nguyên.
- Sau signal mà chưa có reply cho lời gọi *sau* signal → "pending" → giữ id chung (preedit),
  không đoán theo app cũ. Không có portal / không làm được monitor → luôn id chung.
- Tổng quan đang mở → `gnome-shell-overview` (ép preedit). App không có .desktop (`window:N`)
  → id chung.
- Id thật vẫn qua cổng "surrounding proven" + chặn khi có selection như cũ.
- Hạn chế đã biết: ô nhập của chính shell ngoài Tổng quan (Alt+F2, hộp thoại shell) mang id
  của app đang focus bên dưới; lúc mới khởi động, id chỉ biết từ lần đổi app đầu tiên.

**Kiểm thử tự động**: `test_common` (fixture reply GNOME 42/46, máy trạng thái pending/overview,
policy sau khi resolve); `test_gnome_monitor` chạy dưới `dbus-run-session` với gnome-shell +
portal giả (allow-list, BecomeMonitor thật, reply trễ, gọi theo unique name, unsafe mode).

**Kiểm thử tay** (Ubuntu 22.04 và 24.04, phiên "Ubuntu" Wayland, IBus hoặc Fcitx5):
1. Cài gói, bật VietTelex, bật *Không gạch chân*. Đăng xuất/đăng nhập (hoặc `ibus restart`).
2. `busctl --user status org.freedesktop.impl.portal.desktop.gnome` phải có tiến trình
   (portal chạy). `dbus-monitor --session "member='GetRunningApplications'"` thấy lời gọi mỗi
   khi Alt+Tab.
3. Mở GNOME Text Editor (24.04) / gedit (22.04), gõ `tieengs vieetj ` → không gạch chân.
4. Alt+Tab sang GNOME Terminal, gõ → có gạch chân (terminal ép preedit). Sang Firefox → gạch
   chân. Quay lại Text Editor → lại không gạch chân.
5. Bấm Super, gõ trong ô tìm kiếm Tổng quan → gạch chân.
6. Ctrl+Space tắt tiếng Việt trong Terminal, sang Text Editor → vẫn tiếng Việt; về Terminal →
   English (nhớ theo app). `~/.local/state/viettelex/app-state` có dòng `org.gnome.terminal`.
7. Tắt portal (`systemctl --user mask --runtime --now xdg-desktop-portal-gnome`), Alt+Tab →
   mọi app về gạch chân (an toàn), không treo. Bật lại: `systemctl --user unmask --runtime
   xdg-desktop-portal-gnome`.

## 7. Kiểm thử

- **Golden corpus** `TelexCore` chạy trên Linux qua C ABI: 100% khớp macOS (so bytes).
- **Frontend unit test** với mock InputContext: chuỗi preedit/commit/delete_surrounding
  cho từng kịch bản (gõ, backspace, đổi focus, click giữa từ, Ctrl-shortcut).
- **Ma trận app thật** (Ubuntu 24.04 GNOME Wayland + X11, Kubuntu Fcitx5): gedit/GNOME Text
  Editor, LibreOffice, Firefox (deb + snap), Chrome, VS Code, Slack/Discord (Electron),
  Telegram (Qt), gnome-terminal, konsole, kitty, vim, Zalo web.
- Đo & ghi bảng: độ trễ phím (key → commit), RAM, CPU idle.

## 8. Phát hành

- `.deb` cho Ubuntu 24.04 LTS / 26.04 LTS (amd64, arm64) trên GitHub Releases + **PPA**.
- Gói: `viettelex-ibus`, `viettelex-fcitx5`, `viettelex-settings` (+ `libviettelex-core`).
- Cài `.deb` xong: hướng dẫn 1 bước thêm input source; không cần đăng xuất với Fcitx5,
  IBus cần `ibus restart`.
- AUR/Fedora COPR: sau khi bản Ubuntu ổn định.
- Không auto-update nền; nút *Kiểm tra cập nhật* đọc `docs/stable.json`.

## 9. Milestones

| M | Nội dung | Ước lượng |
|---|---|---|
| L0 | `core-c` build Linux static, C ABI, golden corpus xanh trên CI | 2 ngày |
| L1 | Fcitx5 addon, chế độ Preedit, bật/tắt, mật khẩu | 2–3 ngày |
| L2 | IBus engine, cùng hành vi L1 | 2–3 ngày |
| L3 | Chế độ Surrounding + bảng cơ chế theo app + nhớ trạng thái theo app | 3 ngày |
| L4 | `viettelex-settings` GTK4, gõ tắt, áp setting tức thì | 3 ngày |
| L5 | Ma trận app, đo hiệu năng, .deb + PPA, docs cài đặt | 1 tuần |

## 10. Quyết định còn mở

1. Làm cả IBus lẫn Fcitx5 ngay (đề xuất: **Fcitx5 trước** vì chạy trong process, độ trễ
   thấp; IBus ngay sau vì là mặc định Ubuntu) hay chỉ một?
2. Mặc định **Preedit** (an toàn, có gạch chân) hay **Surrounding** (giống macOS, dễ lỗi ở
   Electron/terminal)? Đề xuất: Preedit mặc định, Surrounding tự bật cho app GTK/Qt đã kiểm.
3. Hỗ trợ Ubuntu 22.04 (GTK4/libadwaita cũ) hay chỉ từ 24.04?

## Quyết định đã chốt (26/09/2026)
1. **Fcitx5 trước**, IBus ngay sau.
2. Mặc định **preedit (gạch chân)**; "Không gạch chân" là tuỳ chọn.
3. **Hỗ trợ cả Ubuntu 22.04** (ngoài 24.04, 26.04).
