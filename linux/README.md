# VietTelex cho Linux (Ubuntu, Debian, Fedora, RHEL/Rocky/Alma, Fedora Atomic, Arch)

Bộ gõ tiếng Việt VietTelex dạng input method chuẩn: **Fcitx5** (khuyên dùng) hoặc **IBus**
(mặc định Ubuntu/GNOME). Cùng engine với bản macOS (`TelexCore`), gõ y hệt. Spec:
[docs/LINUX-SPEC.md](docs/LINUX-SPEC.md).

## Cài đặt (tiếng Việt)

Ubuntu 22.04 (jammy) / 24.04 (noble) / 26.04 (resolute), Debian 12 (bookworm) / 13 (trixie)
và bản dựa trên chúng (Mint, Pop!_OS, Zorin, elementary, LMDE, MX…), amd64 + arm64.
**Fedora 43 / 44**, **RHEL / Rocky / Alma / CentOS Stream 9 và 10** (chỉ IBus — EPEL chưa có
Fcitx5) và **Fedora Atomic** (Silverblue, Kinoite, Bazzite, Bluefin, Aurora — qua rpm-ostree), x86_64
+ aarch64: kho DNF đã ký, xem [packaging/RPM.md](packaging/RPM.md).
**Arch Linux** và bản dựa trên Arch (Manjaro, EndeavourOS, CachyOS, Garuda): kho pacman `[viettelex]`
đã ký, xem [packaging/ARCH.md](packaging/ARCH.md). Gói AUR `viettelex-bin` sẽ có sau (AUR đang tạm
đóng đăng ký).

**Nhanh nhất — một lệnh** (tự nhận distro: thêm kho đã ký APT / DNF / pacman — Fedora Atomic thì
xếp lớp bằng rpm-ostree, cần khởi động lại —, cài, bật Fcitx5; chạy lại = cập nhật; `--ibus`
để giữ IBus, `--uninstall` để gỡ):

```sh
curl -fsSL https://viettelex.com/install.sh | bash
```

**Cách 1 — kho APT thủ công (tự cập nhật qua `apt upgrade`):**

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://ptrinh.github.io/viettelex-apt/viettelex-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/viettelex.gpg >/dev/null
sudo tee /etc/apt/sources.list.d/viettelex.sources >/dev/null <<EOF
Types: deb
URIs: https://ptrinh.github.io/viettelex-apt/
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-${DEBIAN_CODENAME:-$VERSION_CODENAME}}")
Components: main
Signed-By: /etc/apt/keyrings/viettelex.gpg
EOF
sudo apt update
sudo apt install viettelex               # hoặc giữ IBus: sudo apt install viettelex viettelex-ibus
# (kho chưa có gói viettelex: sudo apt install viettelex-fcitx5 viettelex-settings)
```

**Cách 2 — tải .deb từ [GitHub Releases](https://github.com/ptrinh/viettelex/releases):**
chọn đúng series (`~jammy1` = Ubuntu 22.04, `~noble1` = 24.04, `~resolute1` = 26.04,
`~bookworm1` = Debian 12, `~trixie1` = Debian 13) và kiến trúc (`amd64` = Intel/AMD,
`arm64` = ARM), rồi cài bằng một lệnh (cách này không tự cập nhật):

```sh
sudo apt install ./libviettelex-core_*_amd64.deb ./viettelex-fcitx5_*_amd64.deb \
                 ./viettelex-text-tools_*_amd64.deb ./viettelex-settings_*_all.deb
                 # IBus: thay viettelex-fcitx5 bằng viettelex-ibus
```

**Sau khi cài:** mở **VietTelex** trong menu ứng dụng (hoặc chạy `viettelex-settings --onboarding`)
và làm theo hướng dẫn:

- **Fcitx5 trên GNOME** (Ubuntu mặc định): trong hướng dẫn bấm *Dùng Fcitx5* (hoặc
  `viettelex-settings --use-fcitx5`; lệnh một dòng ở trên tự làm), rồi đăng xuất/đăng nhập lại
  một lần. Fcitx5 tự chạy thay IBus, app GTK (Firefox, Terminal…) không gạch chân, thanh trên
  cùng hiện icon Vᴛ. *Quay về IBus* (`--use-ibus`) gỡ lại.
- **Fcitx5 (KDE, desktop khác)**: `im-config -n fcitx5`, đăng nhập lại (lần đầu), rồi trong
  hướng dẫn bấm *Thêm* — VietTelex vào nhóm bộ gõ ngay, không cần đăng xuất.
- **IBus (GNOME)**: `ibus restart`, rồi Cài đặt → Bàn phím → Nguồn nhập → + → Tiếng Việt →
  VietTelex (hoặc bấm *Thêm* trong hướng dẫn).

**Fedora / RHEL / Rocky / Alma — kho DNF thủ công** (EL: thay `viettelex-fedora.repo` bằng
`viettelex-el9.repo` hoặc `viettelex-el10.repo`, gói `viettelex` tự kèm IBus):

```sh
sudo curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-viettelex \
  https://ptrinh.github.io/viettelex-apt/rpm/RPM-GPG-KEY-viettelex
sudo curl -fsSLo /etc/yum.repos.d/viettelex.repo \
  https://ptrinh.github.io/viettelex-apt/rpm/viettelex-fedora.repo
sudo dnf install viettelex viettelex-fcitx5      # hoặc giữ IBus: viettelex viettelex-ibus
```

Fedora Atomic: cùng khoá + file `.repo` (đặt `repo_gpgcheck=0`), rồi
`sudo rpm-ostree install viettelex viettelex-ibus` (KDE: `viettelex-fcitx5`) và `systemctl reboot`;
cập nhật cùng hệ thống bằng `rpm-ostree upgrade`. Chi tiết: [packaging/RPM.md](packaging/RPM.md).

**Arch — kho pacman thủ công:**

```sh
curl -fsSLO https://ptrinh.github.io/viettelex-apt/viettelex-archive-keyring.gpg
sudo pacman-key --add viettelex-archive-keyring.gpg
sudo pacman-key --lsign-key 43ADE236BCC43900B8F146B4F57C885055149990
# thêm vào cuối /etc/pacman.conf:
#   [viettelex]
#   SigLevel = Required DatabaseRequired
#   Server = https://ptrinh.github.io/viettelex-apt/arch/$arch
sudo pacman -Sy viettelex
```

Chuyển Việt/Anh: `Ctrl+Space` (đổi trong Cài đặt → Gõ phím → Chuyển Việt/Anh). Chi tiết kho APT và cách gỡ:
[packaging/APT.md](packaging/APT.md); DNF: [packaging/RPM.md](packaging/RPM.md); pacman:
[packaging/ARCH.md](packaging/ARCH.md). Trên Fedora/EL/Arch app cài đặt không có nút cập nhật một
chạm — nó báo lệnh `dnf upgrade` / `rpm-ostree upgrade` / `pacman -Syu`.

## Install (English)

Ubuntu 22.04 / 24.04 / 26.04, Debian 12 / 13 and distributions based on them, amd64 and
arm64; Fedora 43 / 44, RHEL / Rocky / Alma / CentOS Stream 9 and 10 (IBus only: EPEL has no
Fcitx5) and Fedora Atomic desktops (Silverblue, Kinoite, Bazzite, Bluefin, Aurora), x86_64 and
aarch64, from a signed DNF repository ([packaging/RPM.md](packaging/RPM.md)); Arch Linux and
Arch-based distros from a signed pacman repository ([packaging/ARCH.md](packaging/ARCH.md)). The
AUR package `viettelex-bin` comes later (AUR registration is closed for now). The one-line
installer `curl -fsSL https://viettelex.com/install.sh | bash` detects the distro and handles all
of them.

1. **APT repository** (recommended; updates arrive through `apt upgrade`). Run the commands
   above: they save the signing key to `/etc/apt/keyrings/viettelex.gpg` and add a deb822
   `viettelex.sources` file with base URL `https://ptrinh.github.io/viettelex-apt/`. Then run
   `sudo apt install viettelex-fcitx5`, or `viettelex-ibus` for IBus.
2. **Single download** from GitHub Releases. Pick your series (`~jammy1` = Ubuntu 22.04,
   `~noble1` = 24.04, `~resolute1` = 26.04, `~bookworm1` = Debian 12, `~trixie1` = Debian 13)
   and architecture, then run `sudo apt install ./libviettelex-core_*.deb
   ./viettelex-fcitx5_*.deb ./viettelex-text-tools_*.deb ./viettelex-settings_*_all.deb`.
   This route does not auto-update.

Then open **VietTelex** from the app menu and follow the setup guide. On GNOME, *Use Fcitx5*
(or `viettelex-settings --use-fcitx5`) makes Fcitx5 start at login instead of IBus and sets
`GTK_IM_MODULE=fcitx` (no underline in GTK apps); log out and back in once. `Ctrl+Space`
switches between Vietnamese and English.

## Biểu tượng khay, ngôn ngữ, công cụ văn bản / Tray icon, language, text tools

- **Biểu tượng khay / Tray icon** — giống thanh menu macOS: **Vᴛ** trong ô vuông bo góc khi gõ
  tiếng Việt, **E** (cùng kiểu, như logo EN phím cách iOS) khi chuyển sang English. Fcitx5: icon
  bộ gõ theo trạng thái (tray / kimpanel; GNOME hiện đúng icon này); IBus: icon + ký hiệu của
  property InputMode (GNOME Shell chỉ hiện chữ: `Vᴛ` / `E`). Có bản `-symbolic` để GNOME/KDE tự đổi màu theo theme sáng/tối.
  Nguồn: `Scripts/make_linux_status_icons.swift` (cùng hình học `make_space_logo.swift`).
  / *Same as the macOS menu bar: Vᴛ in a rounded square for Vietnamese, E for English (the iOS
  space-bar EN logo). With IBus, GNOME Shell shows only the text symbol `Vᴛ` / `E`.*
- **Ngôn ngữ / Language** — Chung → "Ngôn ngữ / Language": Tiếng Việt (mặc định, kể cả máy
  cài tiếng Anh) hoặc English; áp dụng ngay cho app cài đặt và menu bộ gõ. / *Settings →
  General → "Ngôn ngữ / Language": Vietnamese (default, whatever the system locale) or
  English; applies at once to the settings app and the input-method menu.*
- **Công cụ văn bản / Text tools** — bôi đen chữ ở app bất kỳ rồi mở menu bộ gõ → **Công cụ…**:
  Thêm dấu cho vùng chọn (toi di hoc → tôi đi học), HOA, thường, Hoa Đầu Từ, Hoa đầu câu, Xoá
  dấu. Phím tắt Thêm dấu tuỳ chọn (mặc định tắt) ở Gợi ý & công cụ → Công cụ văn bản. Cần gói
  `viettelex-text-tools` (được cài kèm theo mặc định). Chữ lấy từ surrounding text của app; app
  không báo surrounding thì dùng vùng chọn PRIMARY (Fcitx5 tự đọc; IBus cần `wl-clipboard` hoặc
  `xclip`/`xsel` đã cài sẵn). Không đụng clipboard. Không chạy ở ô mật khẩu và terminal.
  / *Select text anywhere, then input-method menu → **Tools…**: add tones to unaccented text,
  UPPERCASE, lowercase, Title Case, Sentence case, remove tones. Optional Add-tones hotkey (off
  by default). Needs `viettelex-text-tools` (installed as a recommended package). The selection
  comes from the app's surrounding text, else the PRIMARY selection (Fcitx5 built in; IBus via
  an already installed `wl-clipboard` / `xclip` / `xsel`). The clipboard is never touched.
  Disabled in password fields and terminals.*
- **Gợi ý cạnh con trỏ / Suggestions next to the caret** (như macOS 1.8.2; Gợi ý & công cụ →
  Gợi ý cạnh con trỏ): **kết quả phép tính** `12*3=` → `= 36` (Tab hoặc Enter chèn), **chip số**
  `1tr2␣` → `1.200.000 ₫`, **sửa lỗi gõ sai** `tpoi␣` → `tôi`, **ngày giờ** `hôm nay␣` →
  `28/09/2026`, `bây giờ␣` → `21:35` (bật sẵn), **thêm dấu cho câu không dấu** `toi di hoc.` →
  `tôi đi học.` (tắt sẵn). Chỉ Tab áp dụng, phím khác bỏ qua, Esc = bỏ; không bao giờ tự thay,
  không chạy ở ô mật khẩu. Hiện ở ô gợi ý cạnh con trỏ (Fcitx5 / IBus). Cần gói
  `viettelex-text-tools`. / *Math results (Tab or Enter inserts), money format for numbers,
  typo fixes, date/time (on by default) and tones for unaccented sentences (off by default),
  shown in the input method's popup at the caret. Only Tab applies; any other key ignores the
  hint; never automatic, never in password fields. Needs `viettelex-text-tools`.*
- **Văn bản tự động / Automatic text** (Gợi ý & công cụ → Văn bản tự động; **mặc định tắt hết** — bản
  macOS theo cài đặt Nhập văn bản của hệ thống, Linux không có nên là công tắc riêng):
  **thêm dấu chấm khi gõ hai dấu cách** (`chào␣␣` → `chào. `, giữ phím cách thì không), **tự viết
  hoa đầu câu** (sau `. ? !` / xuống dòng; chữ hoa đưa thẳng vào Telex: `dduwowcj` → `Được`; bỏ
  qua viết tắt, email, URL; xoá chữ hoa đó thì chữ kế giữ thường; đầu ô chỉ viết hoa ở ô nhiều
  dòng — Fcitx5), **ngoặc kép cong và gạch dài** (`"` `'` → `“ ” ‘ ’`, `don't` → `don’t`, `--` →
  `—`, thêm `-` → `---`; kiểu ngoặc chọn được: `“ ”` / `„ “` / `« »`), **gợi ý từ** (dừng gõ
  0,3 s → một từ trong ô ứng viên của Fcitx5 / IBus: hoàn thành từ đang gõ, hoặc từ kế tiếp khi
  đã có hai từ trước đó; Tab / click = nhận, Esc = bỏ; phím số vẫn là số; cùng xếp hạng thanh gợi ý iOS,
  dữ liệu có sẵn trong `viettelex-text-tools`). Không chạy trong terminal, trình soạn code (VS
  Code, Zed, JetBrains, Kate…), ô URL/email, ô mật khẩu, khi English. Dấu chấm đúp-cách và `—`
  sửa chữ đã gõ nên chỉ ở app cho bộ gõ đọc chữ quanh con trỏ (không ở Chrome/Firefox/Electron).
  / *All **off by default** (macOS follows its system Text Input settings; Linux has none):
  double-space period (not when the space bar is held), sentence capitals (fed to Telex as an
  uppercase key, so `dduwowcj` → `Được`; abbreviations / e-mails / URLs skipped; delete the
  capital and the next letter stays lowercase; the field start only in multi-line fields),
  smart quotes and dashes (`“ ”` / `„ “` / `« »` style), and word suggestions (after a 0.3 s
  pause, one word in the Fcitx5 / IBus candidate window — a completion, or the next word once
  two words precede it; Tab or a click takes it, Esc dismisses; digits stay digits; iOS suggestion-bar ranking, data
  already in `viettelex-text-tools`). Never in terminals, code editors, URL / e-mail / password
  fields or English mode. The double-space period and `—` edit typed text, so only in apps that
  let the IM read the text around the caret.*

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
  nên *Sửa thẳng trong ô* và nhớ Việt/Anh theo app vẫn dùng được. Chưa biết app → tự về gạch chân.
  / *All apps share one input context; VietTelex reads the focused app from gnome-shell over
  D-Bus (needs xdg-desktop-portal-gnome, installed by default), so "Edit right in the field" and per-app
  memory work. Unknown app → falls back to underline.*
- **Ubuntu 22.04 + IBus 1.5.26**: IBus không báo app nào đang gõ → trên GNOME Wayland lấy app
  đang focus như trên; app X11 riêng lẻ vẫn là "default". / *IBus 1.5.26 reports no app id; on
  GNOME Wayland the focused app is used instead.*
- **im-config**: trên GNOME không có tác dụng (GNOME tự chạy IBus; Ubuntu 26.04
  `im-launch.desktop` là `Exec=/usr/bin/true`) → dùng *Dùng Fcitx5* / `--use-fcitx5` (autostart
  Fcitx5 + `~/.config/environment.d/90-viettelex-fcitx5.conf`). Desktop khác: chế độ `auto`
  chọn IBus nếu cài cả hai → chạy `im-config -n fcitx5` rồi đăng nhập lại. / *No effect on
  GNOME — use* Use Fcitx5 */* `--use-fcitx5` *there; elsewhere `auto` prefers IBus over Fcitx5,
  so run `im-config -n fcitx5`.*
- **Biến Qt / Qt variables**: Qt ≥ 6.8.2 `QT_IM_MODULES="wayland;fcitx;ibus"`; Qt5
  `QT_IM_MODULE=fcitx` (hoặc `ibus`).
- **KDE (KWin)**: Electron cần / needs `--enable-wayland-ime --wayland-text-input-version=1`.
  **Sway** ≥ 1.10. **Hyprland**: dùng Fcitx5 / use Fcitx5. Game SDL: `SDL_IM_MODULE`.
- **Mặc định tắt / Off by default**: remote desktop và máy ảo có sẵn trong danh sách tắt
  tiếng Việt (gõ ở máy bị điều khiển); app Wine gõ tiếng Việt bình thường (gạch chân). / *Remote-desktop and VM apps are in the built-in
  off list; type Vietnamese on the remote machine instead. Wine apps type Vietnamese (preedit).*

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `engine-capi/` | `libtelexcore` — TelexCore Swift xuất C ABI; `viettelex-text-tool` — công cụ văn bản (symlink nguồn iOS `TextTools`/`AddTones`, fixture chung) |
| `common/` | logic dùng chung của frontend + [hợp đồng cài đặt](common/SETTINGS.md) |
| `fcitx5/`, `ibus/` | frontend |
| `settings/` | `viettelex-settings` (Python + PyGObject, GTK4 + libadwaita ≥ 1.1) |
| `packaging/` | `debian/`, `rpm/viettelex.spec`, desktop file, AppStream, icon, `build-all.sh` (mọi series × arch), `build-rpm.sh`, `build-arch.sh`, [kho APT](packaging/APT.md), [kho DNF](packaging/RPM.md), [kho pacman](packaging/ARCH.md), [PPA](packaging/PPA.md) |

## App cài đặt (`settings/`)

Trang: Gõ phím · Gợi ý & công cụ · Gõ tắt · Ứng dụng · Chung (cùng 5 trang với macOS / Windows —
`docs/SETTINGS-CLEANUP-SPEC.md`; giao diện tiếng
Việt mặc định, có English — bảng dịch `viettelex_settings/i18n.py`). Ghi

`~/.config/viettelex/config.toml` + `shortcuts.yml` (ghi nguyên tử); frontend nghe inotify
nên đổi là có hiệu lực ngay. Gõ tắt và bảng cơ chế gõ nhập/xuất cùng định dạng YAML với
bản macOS (nhận cả JSON / txt `key:value`).

Nút thử nghiệm **"Bỏ gạch chân trong Chrome/Electron"** (trang Ứng dụng → Hiển thị chữ đang gõ → Nâng cao) ghi `[experimental]
no_underline` và — trên phiên Wayland GNOME/KDE — tự tạo lối tắt `~/.local/share/applications/*.desktop`
có cờ IME Wayland cho các app Chrome/Electron đã cài (chỉ sửa/xoá file mang dòng
`X-VietTelex-Generated`; tắt nút là gỡ hết). Người dùng chỉ cần mở lại app. Chi tiết:
[SETTINGS.md §9.1](common/SETTINGS.md).

```sh
cd linux/settings
make check                      # unit test (không cần GTK)
./viettelex-settings            # chạy thẳng từ cây nguồn
```

Phụ thuộc lúc chạy: `python3-gi gir1.2-gtk-4.0 gir1.2-adw-1` (có sẵn từ Ubuntu 22.04);
Fedora/EL: `python3-gobject gtk4 libadwaita`; Arch: `python-gobject gtk4 libadwaita`.
