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

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `engine-capi/` | `libtelexcore` — TelexCore Swift xuất C ABI |
| `common/` | logic dùng chung của frontend + [hợp đồng cài đặt](common/SETTINGS.md) |
| `fcitx5/`, `ibus/` | frontend |
| `settings/` | `viettelex-settings` (Python + PyGObject, GTK4 + libadwaita ≥ 1.1) |
| `packaging/` | `debian/`, desktop file, AppStream, icon, `build-all.sh` (mọi series × arch), [kho APT](packaging/APT.md), [PPA](packaging/PPA.md) |

## App cài đặt (`settings/`)

Tab: Kiểu gõ · Tuỳ chỉnh · Gõ tắt · Bảng cơ chế gõ · Giới thiệu. Ghi
`~/.config/viettelex/config.toml` + `shortcuts.yml` (ghi nguyên tử); frontend nghe inotify
nên đổi là có hiệu lực ngay. Gõ tắt và bảng cơ chế gõ nhập/xuất cùng định dạng YAML với
bản macOS (nhận cả JSON / txt `key:value`).

```sh
cd linux/settings
make check                      # unit test (không cần GTK)
./viettelex-settings            # chạy thẳng từ cây nguồn
```

Phụ thuộc lúc chạy: `python3-gi gir1.2-gtk-4.0 gir1.2-adw-1` (có sẵn từ Ubuntu 22.04).
