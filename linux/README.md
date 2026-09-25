# VietTelex cho Linux (Ubuntu 22.04 / 24.04 / 26.04)

Bộ gõ tiếng Việt VietTelex dạng input method chuẩn: **Fcitx5** (khuyên dùng) hoặc **IBus**
(mặc định Ubuntu/GNOME). Cùng engine với bản macOS (`TelexCore`), gõ y hệt. Spec:
[docs/LINUX-SPEC.md](docs/LINUX-SPEC.md).

## Cài đặt

```sh
sudo apt install ./viettelex-settings_*_all.deb ./libviettelex-core_*.deb \
                 ./viettelex-fcitx5_*.deb      # hoặc ./viettelex-ibus_*.deb
viettelex-settings --onboarding                # hướng dẫn bật bộ gõ từng bước
```

- **Fcitx5**: `im-config -n fcitx5`, đăng nhập lại (lần đầu), rồi trong hướng dẫn bấm
  *Thêm* — VietTelex vào nhóm bộ gõ ngay, không cần đăng xuất.
- **IBus (GNOME)**: `ibus restart`, rồi Cài đặt → Bàn phím → Nguồn nhập → + → Tiếng Việt →
  VietTelex (hoặc bấm *Thêm* trong hướng dẫn).

Chuyển Việt/Anh: `Ctrl+Space` (đổi trong Cài đặt → Tuỳ chỉnh).

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `engine-capi/` | `libtelexcore` — TelexCore Swift xuất C ABI |
| `common/` | logic dùng chung của frontend + [hợp đồng cài đặt](common/SETTINGS.md) |
| `fcitx5/`, `ibus/` | frontend |
| `settings/` | `viettelex-settings` (Python + PyGObject, GTK4 + libadwaita ≥ 1.1) |
| `packaging/` | `debian/`, desktop file, AppStream, icon, [PPA](packaging/PPA.md) |

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
