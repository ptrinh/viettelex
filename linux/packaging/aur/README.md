# AUR: `viettelex-bin`

Gói Arch Linux đóng lại từ các `.deb` **noble** (Ubuntu 24.04) chính thức trên GitHub Releases —
cùng file nhị phân, đã kiểm SHA256 (`sha256sums_*` lấy từ `docs/stable.json` = `SHA256SUMS`).
x86_64 + aarch64. Một gói gồm engine, addon Fcitx5, engine IBus, công cụ văn bản và app cài đặt.

| Đường dẫn Debian | Trên Arch |
|---|---|
| `usr/lib/<triplet>/fcitx5/viettelex.so` | `usr/lib/fcitx5/viettelex.so` (thư mục addon của Fcitx5 trên Arch) |
| `usr/libexec/ibus-engine-viettelex` | `usr/lib/ibus/ibus-engine-viettelex` (sửa `<exec>` trong component XML) |
| `usr/lib/<triplet>/viettelex/` (libtelexcore, viettelex-text-tool) | giữ nguyên — RPATH và đường dẫn text-tool được biên dịch cứng |
| `usr/libexec/viettelex/viettelex-update` + polkit policy | bỏ — cập nhật một chạm dùng apt/dpkg; app báo "cập nhật theo cách bạn đã cài" |

Phụ thuộc: `fcitx5` (khung gõ khuyên dùng, addon link `libFcitx5*`) + `libibus` (engine IBus link
`libibus-1.0`; khung `ibus` là optdepends) + `python-gobject gtk4 libadwaita` cho app cài đặt.

## Cập nhật khi có bản Linux mới

```sh
linux/packaging/aur/bump.py                 # đọc docs/stable.json (sau khi đã ghi bản mới)
# hoặc: linux/packaging/aur/bump.py --stable https://viettelex.com/stable.json
linux/packaging/aur/test-aur.sh             # archlinux (amd64): makepkg user thường, so .SRCINFO,
                                            # namcap, pacman -U, Fcitx5/IBus nhận viettelex
```

`bump.py --check` (chạy trong CI `linux.yml`) báo lỗi nếu PKGBUILD/.SRCINFO lệch `stable.json`.
Sửa PKGBUILD tay (depends, package()) thì tăng `pkgrel` bằng `bump.py --pkgrel N`.

## Đẩy lên AUR (người phát hành, cần SSH key đã đăng ký trên aur.archlinux.org)

Lần đầu (tạo gói):

```sh
git clone ssh://aur@aur.archlinux.org/viettelex-bin.git ~/aur/viettelex-bin   # repo rỗng
cp linux/packaging/aur/viettelex-bin/{PKGBUILD,.SRCINFO,viettelex.install} ~/aur/viettelex-bin/
cd ~/aur/viettelex-bin
git add PKGBUILD .SRCINFO viettelex.install
git commit -m "viettelex-bin $(sed -n 's/^pkgver=//p' PKGBUILD)-$(sed -n 's/^pkgrel=//p' PKGBUILD)"
git push origin master
```

Các lần sau: `bump.py`, `test-aur.sh`, rồi cùng lệnh `cp` / `git commit` / `git push` như trên
trong `~/aur/viettelex-bin`. AUR chỉ nhận nhánh `master`; dòng `# Maintainer:` trong PKGBUILD có
thể đổi thành tên/email thật ngay trong bản sao `~/aur/…` (không ghi thông tin cá nhân vào repo này).
