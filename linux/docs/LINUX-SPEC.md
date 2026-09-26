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
| **Surrounding text** (tuỳ chọn "Không gạch chân") | commit từng phím; sửa dấu bằng `delete_surrounding_text` rồi commit | giống macOS/Windows | chỉ ổn ở app GTK/Qt hỗ trợ surrounding text |

- Chế độ 2 tự hạ về Preedit khi `IBUS_CAP_SURROUNDING_TEXT` / `CapabilityFlag::SurroundingText`
  không có, hoặc app nằm trong danh sách ép (terminal: gnome-terminal, konsole, kitty, alacritty,
  wezterm, foot; Electron/Chromium trên Wayland; LibreOffice).
- **Bảng cơ chế theo app** (tương đương tab "Bảng cơ chế gõ" macOS): key = `program`
  (Fcitx5) / `client` + WM_CLASS / app-id Wayland (IBus). User ép tay Preedit/Surrounding.
- Preedit style: gạch chân mảnh; ở Surrounding bỏ preedit hoàn toàn.
- Mất focus / click chuột / đổi con trỏ → commit preedit (không nuốt chữ), reset engine.

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
| GNOME Wayland: một input context chung cho mọi app (IBus, Fcitx5 < 5.1.22) | Không biết app đang gõ → chế độ không gạch chân + nhớ theo app bị hạn chế; ghi rõ trong tài liệu |
| Ubuntu 22.04 IBus 1.5.26 không có app id | Bảng cơ chế gõ theo app không áp được dưới IBus 22.04 |
| im-config | GNOME: không tác dụng. Desktop khác: `auto` chọn IBus khi cài cả hai → `im-config -n fcitx5`; Cài đặt cảnh báo |
| Biến môi trường Qt / SDL | Qt ≥ 6.8.2 `QT_IM_MODULES="wayland;fcitx;ibus"`, Qt5 `QT_IM_MODULE`; game SDL `SDL_IM_MODULE`; Cài đặt cảnh báo Qt5 Wayland thiếu biến |
| Compositor khác | Sway ≥ 1.10 (text-input-v3); Hyprland: dùng Fcitx5 |
| LibreOffice Calc | Bấm ra ô khác / AutoInput có thể làm lệch chữ → khuyên tắt AutoInput nếu gặp lỗi |
| Konsole/Kate dưới IBus (Qt) | Khuyên Fcitx5 trên KDE |
| Mật khẩu `sudo` trong terminal | Không phát hiện được ô mật khẩu → hướng dẫn chuyển EN |
| Flatpak/Snap app | Dùng IBus/Fcitx portal sẵn có; ghi chú: Snap Firefox cần `ibus` portal |
| Terminal / vim / tmux | Preedit ép buộc; commit khi Esc để vim không mất chữ |
| Nhiều bộ gõ Việt cùng bật (ibus-unikey, bamboo) | Không can thiệp; hướng dẫn gỡ nếu bị gõ đúp |
| Xung đột phím tắt GNOME | Không dùng Super+Space; kiểm tra trùng khi đặt phím |
| Remote desktop / VM / Wine | Giống macOS: có sẵn trong danh sách mặc định tắt tiếng Việt (core); khuyên bật bộ gõ ở máy bị điều khiển |

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
