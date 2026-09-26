# VietTelex Linux — đóng gói (.deb, PPA)

## Gói

| Gói | Arch | Nội dung |
|---|---|---|
| `viettelex-settings` | all | App cài đặt GTK4/libadwaita (`linux/settings`), desktop file, AppStream, icon hicolor |
| `libviettelex-core` | any | `usr/lib/<multiarch>/viettelex/libtelexcore.so` (engine Swift, static stdlib, thư mục riêng) |
| `viettelex-fcitx5` | any | `usr/lib/<multiarch>/fcitx5/viettelex.so`, `usr/share/fcitx5/{addon,inputmethod}/viettelex.conf` |
| `viettelex-ibus` | any | `usr/libexec/ibus-engine-viettelex`, `usr/share/ibus/component/viettelex.xml` |

Đường dẫn cài của engine/frontend là **hợp đồng với CMake ở `linux/CMakeLists.txt`**
(`debian/*.install`). Đổi bên nào thì sửa bên kia.

Tên dùng chung: IM Fcitx5 = `viettelex`, engine IBus = `viettelex`, icon = `viettelex`
(do `viettelex-settings` cài), app id = `com.viettelex.Settings`.

## Build (trên Ubuntu 22.04 / 24.04 / 26.04, hoặc container)

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

`data/icons/hicolor/<N>x<N>/apps/viettelex.png` (16…512) thu nhỏ từ đúng logo iOS/macOS
`iOS/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Đổi logo thì sinh lại (macOS):

```sh
for s in 16 22 24 32 48 64 128 256 512; do
  sips -z $s $s iOS/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png \
    --out linux/packaging/data/icons/hicolor/${s}x${s}/apps/viettelex.png; done
```

## Phát hành (GitHub Releases + kho APT)

```sh
linux/packaging/build-all.sh     # jammy+noble × amd64+arm64 → linux/dist/<series>/*.deb
VT_APT_KEY=<fingerprint> linux/packaging/apt-repo.sh --out <thư mục repo viettelex-apt>
```

`build-all.sh` build trong `swift:<series>` (amd64 dùng `--platform linux/amd64`, Rosetta trên
OrbStack). Lintian có warning là build hỏng. Sau đó script cài thử trong `ubuntu:<ver>` sạch:
fcitx5 phải liệt kê `viettelex`, và `ibus list-engine` phải thấy engine. Phiên bản là
`<changelog>~<series>1`. Kho APT: xem [APT.md](APT.md). PPA: xem [PPA.md](PPA.md).
