# Kho APT của VietTelex / VietTelex APT repository

Kho: `https://ptrinh.github.io/viettelex-apt/` — Ubuntu 22.04 (jammy) và 24.04 (noble),
amd64 + arm64. Được ký bằng GPG; `apt` tự kiểm chữ ký.

## Tiếng Việt — cài đặt

```sh
# 1. Khoá ký của kho
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://ptrinh.github.io/viettelex-apt/viettelex-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/viettelex.gpg >/dev/null

# 2. Khai báo kho (định dạng deb822)
sudo tee /etc/apt/sources.list.d/viettelex.sources >/dev/null <<EOF
Types: deb
URIs: https://ptrinh.github.io/viettelex-apt/
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /etc/apt/keyrings/viettelex.gpg
EOF

# 3. Cài — chọn MỘT bộ khung gõ
sudo apt update
sudo apt install viettelex-fcitx5     # khuyên dùng (KDE, hoặc GNOME sau khi chuyển sang Fcitx5)
# hoặc: sudo apt install viettelex-ibus   (mặc định Ubuntu/GNOME)
```

Sau khi cài: mở **VietTelex** trong menu ứng dụng (hoặc `viettelex-settings --onboarding`)
và làm theo hướng dẫn bật bộ gõ. Cập nhật về sau: `sudo apt update && sudo apt upgrade`.

Gỡ: `sudo apt remove viettelex-fcitx5 viettelex-ibus viettelex-settings libviettelex-core`,
rồi xoá `/etc/apt/sources.list.d/viettelex.sources` và `/etc/apt/keyrings/viettelex.gpg`.

## English — install

Run the three steps above (add the key to `/etc/apt/keyrings/viettelex.gpg`, add the
`viettelex.sources` file, then `sudo apt update && sudo apt install viettelex-fcitx5`, or
`viettelex-ibus` for IBus). Then open **VietTelex** from the app menu, or run
`viettelex-settings --onboarding`, and follow the setup guide. `apt upgrade` delivers updates.

## Không dùng kho: tải .deb / Without the repository: download the .deb

Mỗi bản phát hành trên GitHub Releases (`https://github.com/ptrinh/viettelex/releases`) có
các file `.deb` theo series và kiến trúc. Tải đúng bộ (vd Ubuntu 24.04, máy Intel/AMD:
các file `~noble1_amd64.deb` + `viettelex-settings_…~noble1_all.deb`) rồi cài một lệnh:

Each GitHub release ships `.deb` files per series and architecture. Download the matching
set, then install it with one command:

```sh
sudo apt install ./libviettelex-core_*_amd64.deb ./viettelex-fcitx5_*_amd64.deb \
                 ./viettelex-settings_*_all.deb
```

Cách này không tự cập nhật; nút *Kiểm tra cập nhật* trong app báo khi có bản mới.
This route does not auto-update. The app's *Kiểm tra cập nhật* button tells you when a new
version is out.

---

## Dành cho người phát hành / For maintainers

```sh
linux/packaging/build-all.sh                         # linux/dist/{jammy,noble}/*.deb, lintian + smoke test
VT_APT_KEY=<fingerprint> linux/packaging/apt-repo.sh --out ../viettelex-apt
```

- `apt-repo.sh` sinh `pool/main/v/viettelex/`, `dists/<series>/main/binary-{amd64,arm64}/Packages(.gz)`
  và `Release` bằng `apt-ftparchive` (trong container `ubuntu:24.04` nếu host không có). Script ký
  `InRelease` (clearsign) và `Release.gpg` (detached) bằng `gpg` **trên host**, rồi xuất khoá công khai
  ra `viettelex-archive-keyring.gpg` (binary). Khoá bí mật không bao giờ vào container hay repo.
- Mỗi series có phiên bản riêng (`1.0.0~jammy1`, `1.0.0~noble1`), nên pool dùng chung được.
  Gói `_all` lấy từ bản build đầu tiên của series để mọi arch cùng trỏ vào một file.
- Đẩy thư mục output lên repo GitHub Pages `viettelex-apt` (có sẵn `.nojekyll`).
- Đổi/xoay khoá: xuất bản khoá mới cùng lúc với khoá cũ trong một thời gian, và báo người dùng
  tải lại `viettelex-archive-keyring.gpg`.
