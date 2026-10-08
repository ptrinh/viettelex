# VietTelex Linux — đóng gói (.deb, PPA)

## Gói

| Gói | Arch | Nội dung |
|---|---|---|
| `viettelex-settings` | all | App cài đặt GTK4/libadwaita (`linux/settings`), desktop file, AppStream, icon hicolor |
| `libviettelex-core` | any | `usr/lib/<multiarch>/viettelex/libtelexcore.so` (engine Swift, static stdlib, thư mục riêng) |
| `viettelex-fcitx5` | any | `usr/lib/<multiarch>/fcitx5/viettelex.so`, `usr/share/fcitx5/{addon,inputmethod}/viettelex.conf` |
| `viettelex-ibus` | any | `usr/libexec/ibus-engine-viettelex`, `usr/share/ibus/component/viettelex.xml` |
| `viettelex-text-tools` | any | `usr/lib/<multiarch>/viettelex/viettelex-text-tool` (công cụ văn bản, Swift + FoundationEssentials static, ~13 MB — process con của frontend) + `usr/share/viettelex/{vnlexicon,vnlm,enlexicon}.bin`; Recommends của hai frontend |


Đường dẫn cài của engine/frontend là **hợp đồng với CMake ở `linux/CMakeLists.txt`**
(`debian/*.install`). Đổi bên nào thì sửa bên kia.

Tên dùng chung: IM Fcitx5 = `viettelex`, engine IBus = `viettelex`, icon = `viettelex`
(do `viettelex-settings` cài), app id = `com.viettelex.Settings`.

## Build (trên Ubuntu 22.04 / 24.04 / 26.04, Debian 12 / 13, hoặc container)

```sh
sudo apt install build-essential debhelper devscripts fakeroot python3
linux/packaging/build-deb.sh --settings-only        # chỉ viettelex-settings
linux/packaging/build-deb.sh                        # cả 4 gói (cần swift trên PATH + dev headers)
VT_CORE_LIB=/path/libtelexcore.so linux/packaging/build-deb.sh   # dùng engine build sẵn
```

Kết quả ở `linux/packaging/out/` (đã gitignore theo quy ước: đừng commit .deb).
Script dàn một cây nguồn tạm (`TelexCore/` + `linux/` + `debian/` + file mẫu) rồi gọi
`dpkg-buildpackage`; profile `pkg.viettelex.noengine` tắt 3 gói engine.

Kiểm tra: `lintian out/*.changes`, `appstreamcli validate data/*.metainfo.xml`,
`desktop-file-validate data/*.desktop`. Unit test app cài đặt chạy trong `dh_auto_test`.

## Icon

- **Icon app** `com.viettelex.Settings` (desktop file, AppStream, cửa sổ): lấy đúng icon app macOS
  `App/Resources/Assets.xcassets/AppIcon.appiconset/icon_<N>.png` → `data/icons/hicolor/<N>x<N>/apps/`
  (16/32/64/128/256/512 copy nguyên; 24/48 thu nhỏ bằng `sips` từ `icon_1024.png`).
- **Icon trạng thái bộ gõ** `viettelex` (Vᴛ = tiếng Việt) / `viettelex-off` (E = tiếng Anh), kèm bản
  `-symbolic`: `data/icons/hicolor/scalable/status/*.svg`, chuyển vector 1:1 từ glyph menu bar macOS
  `App/Resources/MenuIcon1.pdf` (khung bo góc + V + ᴛ; E vẽ cùng độ đậm). Tên này được Fcitx5
  (`Icon=viettelex`, action Việt/Anh) và IBus (`<icon>viettelex</icon>`) dùng; gói `libviettelex-core` cài.

## Phát hành (GitHub Releases + kho APT + AUR)

| Series | Distro | Ảnh build | Ảnh smoke |
|---|---|---|---|
| `jammy` | Ubuntu 22.04 | `swift:jammy` | `ubuntu:22.04` |
| `noble` | Ubuntu 24.04 | `swift:noble` | `ubuntu:24.04` |
| `resolute` | Ubuntu 26.04 LTS | `swift:resolute` | `ubuntu:26.04` |
| `bookworm` | Debian 12 | `swift:bookworm` | `debian:12` |
| `trixie` | Debian 13 | `swift:trixie` | `debian:13` |

Ubuntu 25.10 (questing) không có: hết hỗ trợ 07/2026 và không có ảnh `swift:questing`.
Thêm series: `smoke_of` trong `build-all.sh`, matrix trong `.github/workflows/linux-release.yml`,
`SUPPORTED_SERIES` trong `docs/install.sh` (+ `test-install-detect.sh`).

```sh
linux/packaging/build-all.sh     # mọi series × amd64+arm64 → linux/dist/<series>/*.deb
linux/packaging/build-all.sh --series bookworm --arch arm64     # một phần
VT_APT_KEY=<fingerprint> linux/packaging/apt-repo.sh --out <thư mục repo viettelex-apt>
```

`build-all.sh` build trong `swift:<series>` (amd64 dùng `--platform linux/amd64`, Rosetta trên
OrbStack; `VT_SWIFT_TAG=6.4` ⇒ `swift:6.4-<series>` để ghim bản Swift). Lintian có warning là
build hỏng. Sau đó script cài thử trong distro sạch: fcitx5 phải liệt kê `viettelex`, và
`ibus list-engine` phải thấy engine. Phiên bản là `<changelog>~<series>1`. Debian sinh gói
`-dbgsym` dạng `.deb` — script bỏ chúng (không phát hành).

CI: `.github/workflows/linux.yml` chạy `build-all.sh --series noble` (amd64 + arm64) cho mọi PR/push
đụng tới Linux; `linux-release.yml` (chạy tay) build đủ series × arch + attestation — quy trình
phát hành qua CI và ký kho trên máy local: [APT.md](APT.md#phát-hành-qua-ci-khuyên-dùng).
Kho APT: [APT.md](APT.md). AUR: [aur/README.md](aur/README.md). PPA: [PPA.md](PPA.md).
Bảng distro → series của `install.sh`: `linux/packaging/test-install-detect.sh`.
