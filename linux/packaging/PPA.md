# PPA / Launchpad — ghi chú (không chứa bí mật)

Khoá GPG, tài khoản Launchpad, tên/email người upload **không bao giờ** ghi vào repo.
`build-deb.sh` đọc `DEBFULLNAME`/`DEBEMAIL` từ môi trường; khoá ký nằm trong gpg-agent của máy upload.

## Một lần

1. Tạo PPA trên Launchpad (vd `viettelex`), bật kiến trúc amd64 + arm64.
2. Đăng ký khoá GPG công khai với Launchpad; `~/.dput.cf` mặc định đã có target `ppa:`.

## Mỗi bản phát hành

```sh
export DEBFULLNAME="…" DEBEMAIL="…"       # khớp UID của khoá GPG đã đăng ký
for s in jammy noble; do                   # 22.04, 24.04 (thêm series 26.04 khi có)
  linux/packaging/build-deb.sh --source --series "$s" --out /tmp/ppa-$s
  debsign /tmp/ppa-$s/viettelex_*_source.changes
  dput ppa:<launchpad-user>/viettelex /tmp/ppa-$s/viettelex_*_source.changes
done
```

`--series` đặt distribution và hậu tố phiên bản `~jammy1` / `~noble1` — Launchpad không
nhận cùng một phiên bản cho hai series. Upload lại cùng bản: tăng số cuối (`~noble2`)
bằng cách sửa `debian/changelog` trong cây tạm, hoặc bump `VERSION`.

## Vướng mắc đã biết: toolchain Swift

Máy build Launchpad **không có mạng** và chỉ cài Build-Depends từ archive. Ubuntu 22.04/24.04
không có gói Swift đủ mới trong archive chính, nên PPA không tự build `libtelexcore` được.
Hướng giải (chọn một):

- **(khuyên)** Chỉ đưa `viettelex-settings` + frontend lên PPA sau khi có một gói Swift
  toolchain trong một PPA phụ thuộc (Launchpad cho phép PPA dependency), hoặc
- Build `libtelexcore.so` trên CI (GitHub Actions ubuntu-22.04, swift.org toolchain,
  `--static-swift-stdlib`) và phát hành `.deb` qua GitHub Releases thay cho PPA cho 3 gói
  engine; PPA chỉ mang `viettelex-settings` (`--settings-only` → build profile
  `pkg.viettelex.noengine` — Launchpad không đặt profile, nên khi đó cần một nhánh
  `debian/control` bỏ 3 gói engine).

Bản `.deb` cho GitHub Releases: `build-deb.sh` (đủ 4 gói) trong container
`ubuntu:22.04` (tương thích tiến 24.04/26.04 nhờ glibc cũ hơn) cho amd64 và arm64.
