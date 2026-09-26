# VietTelex cho Linux (Ubuntu 22.04 / 24.04 / 26.04)

Bộ gõ tiếng Việt VietTelex dạng input method chuẩn: **Fcitx5** (khuyên dùng) hoặc **IBus**
(mặc định Ubuntu/GNOME). Cùng engine với bản macOS (`TelexCore`), gõ y hệt. Spec:
[docs/LINUX-SPEC.md](docs/LINUX-SPEC.md).

## Cài đặt (tiếng Việt)

Ubuntu 22.04 (jammy) / 24.04 (noble), amd64 + arm64.

**Cách 1 — kho APT (khuyên dùng, tự cập nhật qua `apt upgrade`):**

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://ptrinh.github.io/viettelex-apt/viettelex-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/viettelex.gpg >/dev/null
sudo tee /etc/apt/sources.list.d/viettelex.sources >/dev/null <<EOF
Types: deb
URIs: https://ptrinh.github.io/viettelex-apt/
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /etc/apt/keyrings/viettelex.gpg
EOF
sudo apt update
sudo apt install viettelex-fcitx5        # hoặc: sudo apt install viettelex-ibus
```

**Cách 2 — tải .deb từ [GitHub Releases](https://github.com/ptrinh/viettelex/releases):**
chọn đúng series (`~jammy1` = 22.04, `~noble1` = 24.04) và kiến trúc (`amd64` = Intel/AMD,
`arm64` = ARM), rồi cài bằng một lệnh (cách này không tự cập nhật):

```sh
sudo apt install ./libviettelex-core_*_amd64.deb ./viettelex-fcitx5_*_amd64.deb \
                 ./viettelex-settings_*_all.deb     # IBus: thay viettelex-fcitx5 bằng viettelex-ibus
```

**Sau khi cài:** mở **VietTelex** trong menu ứng dụng (hoặc chạy `viettelex-settings --onboarding`)
và làm theo hướng dẫn:

- **Fcitx5**: `im-config -n fcitx5`, đăng nhập lại (lần đầu), rồi trong hướng dẫn bấm
  *Thêm* — VietTelex vào nhóm bộ gõ ngay, không cần đăng xuất.
- **IBus (GNOME)**: `ibus restart`, rồi Cài đặt → Bàn phím → Nguồn nhập → + → Tiếng Việt →
  VietTelex (hoặc bấm *Thêm* trong hướng dẫn).

Chuyển Việt/Anh: `Ctrl+Space` (đổi trong Cài đặt → Tuỳ chỉnh). Chi tiết kho APT và cách gỡ:
[packaging/APT.md](packaging/APT.md).

## Install (English)

Ubuntu 22.04 / 24.04, amd64 and arm64.

1. **APT repository** (recommended; updates arrive through `apt upgrade`). Run the commands
   above: they save the signing key to `/etc/apt/keyrings/viettelex.gpg` and add a deb822
   `viettelex.sources` file with base URL `https://ptrinh.github.io/viettelex-apt/`. Then run
   `sudo apt install viettelex-fcitx5`, or `viettelex-ibus` for IBus.
2. **Single download** from GitHub Releases. Pick your series (`~jammy1` = 22.04,
   `~noble1` = 24.04) and architecture, then run `sudo apt install ./libviettelex-core_*.deb
   ./viettelex-fcitx5_*.deb ./viettelex-settings_*_all.deb`. This route does not auto-update.

Then open **VietTelex** from the app menu and follow the setup guide. `Ctrl+Space` switches
between Vietnamese and English.

## Tương thích ứng dụng / App compatibility

App cài đặt có tab **Tương thích** chỉ liệt kê lưu ý khớp với máy bạn, kèm nút chép lệnh sửa.
The settings app has a **Tương thích** (compatibility) tab that lists only the issues that apply
to your machine, each with a copy button.

| App / môi trường | Vấn đề (VI) | Issue (EN) | Cách sửa / Fix |
|---|---|---|---|
| Chrome ≥ 140, Chromium, Electron ≥ 38 (VS Code, Slack, Discord) trên **Wayland** | Mặc định chạy Wayland gốc, không nhận bộ gõ | Default to native Wayland and lose the IME | Chạy với / launch with `--enable-wayland-ime --wayland-text-input-version=3` (GNOME + IBus; KDE: chỉ `--enable-wayland-ime`), hoặc / or `--ozone-platform=x11`. Cố định / persist: `~/.config/chrome-flags.conf`, `~/.config/code-flags.conf`, hoặc sửa dòng `Exec=` trong bản sao `.desktop` ở `~/.local/share/applications/` |
| kitty trên X11 | Cần biến môi trường | Needs an env variable | `export GLFW_IM_MODULE=ibus` (cả Fcitx5 / also for Fcitx5) trong `~/.profile` |
| JetBrains IDE trên X11 | Mất bộ gõ sau khi đổi cửa sổ | Loses the IME after switching windows | Help → Edit Custom VM Options → `-Drecreate.x11.input.method=true` |
| rofi | Không hỗ trợ bộ gõ | No IME support | Dùng / use Ulauncher hoặc KRunner |
| Tìm kiếm Tổng quan GNOME / GNOME overview search | Có thể rơi chữ đầu (ibus#2246) | May drop the first letter (upstream ibus#2246) | Mở Tổng quan, chờ một nhịp rồi gõ / pause briefly before typing |
| App Snap + Fcitx5 trên Ubuntu 22.04 | Thường không nhận Fcitx5 | Often ignore Fcitx5 | Dùng IBus (`viettelex-ibus`) hoặc bản .deb / Flatpak của app |
| LibreOffice Calc | Bấm ra ô khác / AutoInput (tự gợi ý) có thể làm lệch chữ đang gõ | Clicking away / AutoInput can garble the word being typed | Nếu gặp lỗi: Công cụ → AutoInput → tắt / if it misbehaves: Tools → AutoInput → off |
| Konsole, Kate (Qt) dưới IBus | Qt qua IBus kém ổn định hơn Fcitx5 | Qt apps under IBus are less reliable than under Fcitx5 | Trên KDE dùng Fcitx5 (`viettelex-fcitx5`) / on KDE prefer Fcitx5 |
| App Qt5 trên Wayland | Không có bộ gõ nếu thiếu `QT_IM_MODULE` | No IME without `QT_IM_MODULE` | `QT_IM_MODULE=fcitx` (hoặc `ibus`); Qt ≥ 6.8.2: `QT_IM_MODULES="wayland;fcitx;ibus"` — trong `~/.config/environment.d/*.conf` |
| Game SDL | Cần biến môi trường | Needs an env variable | `SDL_IM_MODULE=fcitx` (hoặc `ibus`) |
| Ô mật khẩu `sudo` trong terminal | Không nhận ra được là ô mật khẩu | Cannot be detected as a password prompt | Chuyển sang EN trước khi gõ mật khẩu / switch to EN first |
| Terminal GTK4 (Ptyxis, Console), terminal trên GNOME Wayland, kitty/alacritty/foot, terminal VS Code | Gõ preedit (có thể gạch chân) — terminal GTK3/Qt qua IBus-GTK3/Fcitx5 thì gõ thẳng như UniKey | Preedit (may be underlined) — GTK3/Qt terminals via IBus-GTK3/Fcitx5 type directly like UniKey | Chủ đích: ở đó BackSpace gửi đi không chắc đến trước chữ mới / by design |
| Chrome/Electron, app Wayland trên GNOME | Chữ đang gõ luôn gạch chân (app tự vẽ) | Composition is always underlined (drawn by the app) | Không tắt được / cannot be turned off |

### Ghi chú theo môi trường / Desktop notes

- **GNOME Wayland**: mọi app dùng chung một input context (IBus, và Fcitx5 < 5.1.22); VietTelex
  hỏi gnome-shell app nào đang focus (qua D-Bus, cần xdg-desktop-portal-gnome — mặc định có),
  nên *Không gạch chân* và nhớ Việt/Anh theo app vẫn dùng được. Chưa biết app → tự về gạch chân.
  / *All apps share one input context; VietTelex reads the focused app from gnome-shell over
  D-Bus (needs xdg-desktop-portal-gnome, installed by default), so no-underline mode and per-app
  memory work. Unknown app → falls back to underline.*
- **Ubuntu 22.04 + IBus 1.5.26**: IBus không báo app nào đang gõ → trên GNOME Wayland lấy app
  đang focus như trên; app X11 riêng lẻ vẫn là "default". / *IBus 1.5.26 reports no app id; on
  GNOME Wayland the focused app is used instead.*
- **im-config**: trên GNOME không có tác dụng (GNOME tự chạy IBus). Desktop khác: chế độ `auto`
  chọn IBus nếu cài cả hai → chạy `im-config -n fcitx5` rồi đăng nhập lại. / *No effect on
  GNOME; elsewhere `auto` prefers IBus over Fcitx5, so run `im-config -n fcitx5`.*
- **Biến Qt / Qt variables**: Qt ≥ 6.8.2 `QT_IM_MODULES="wayland;fcitx;ibus"`; Qt5
  `QT_IM_MODULE=fcitx` (hoặc `ibus`).
- **KDE (KWin)**: Electron cần / needs `--enable-wayland-ime --wayland-text-input-version=1`.
  **Sway** ≥ 1.10. **Hyprland**: dùng Fcitx5 / use Fcitx5. Game SDL: `SDL_IM_MODULE`.
- **Mặc định tắt / Off by default**: remote desktop, máy ảo và Wine có sẵn trong danh sách tắt
  tiếng Việt (gõ ở máy bị điều khiển). / *Remote-desktop, VM and Wine apps are in the built-in
  off list; type Vietnamese on the remote machine instead.*

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `engine-capi/` | `libtelexcore` — TelexCore Swift xuất C ABI |
| `common/` | logic dùng chung của frontend + [hợp đồng cài đặt](common/SETTINGS.md) |
| `fcitx5/`, `ibus/` | frontend |
| `settings/` | `viettelex-settings` (Python + PyGObject, GTK4 + libadwaita ≥ 1.1) |
| `packaging/` | `debian/`, desktop file, AppStream, icon, `build-all.sh` (mọi series × arch), [kho APT](packaging/APT.md), [PPA](packaging/PPA.md) |

## App cài đặt (`settings/`)

Tab: Kiểu gõ · Tuỳ chỉnh · Gõ tắt · Bảng cơ chế gõ · Tương thích · Giới thiệu. Ghi
`~/.config/viettelex/config.toml` + `shortcuts.yml` (ghi nguyên tử); frontend nghe inotify
nên đổi là có hiệu lực ngay. Gõ tắt và bảng cơ chế gõ nhập/xuất cùng định dạng YAML với
bản macOS (nhận cả JSON / txt `key:value`).

```sh
cd linux/settings
make check                      # unit test (không cần GTK)
./viettelex-settings            # chạy thẳng từ cây nguồn
```

Phụ thuộc lúc chạy: `python3-gi gir1.2-gtk-4.0 gir1.2-adw-1` (có sẵn từ Ubuntu 22.04).
