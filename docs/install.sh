#!/bin/bash
# VietTelex — cài / cập nhật / gỡ bằng một lệnh (Linux Ubuntu/Debian & macOS).
#
#   curl -fsSL https://viettelex.com/install.sh | bash
#   curl -fsSL https://viettelex.com/install.sh | bash -s -- --ibus --yes
#
# Tuỳ chọn:
#   --fcitx5 | --ibus   (Linux) chọn bộ khung gõ; mặc định Fcitx5, hỏi nếu máy chỉ có IBus/GNOME
#   --yes, -y           không hỏi, dùng lựa chọn mặc định
#   --pkg               (macOS) cài bằng .pkg kể cả khi có Homebrew
#   --uninstall         gỡ VietTelex (Linux: gói + kho APT + khoá; macOS: app)
#   --dry-run           chỉ in ra các bước sẽ làm (macOS: vẫn tải .pkg vào thư mục tạm và
#                       kiểm chữ ký, nhưng KHÔNG cài)
#   --series S          (Linux) ép series kho APT (jammy|noble|resolute|bookworm|trixie) cho
#                       bản phái sinh không tự nhận ra; --print-series in series tự nhận rồi thoát
#   --help
#
# An toàn: chỉ tải từ github.com / ptrinh.github.io / viettelex.com qua HTTPS; kho APT được
# kiểm chữ ký với vân tay khoá ghim sẵn bên dưới; .pkg macOS được kiểm chữ ký Developer ID
# + notarization trước khi cài; mọi lệnh sudo được in ra trước khi chạy. Chạy lại = cập nhật.
# Tương thích bash 3.2 (macOS).
set -euo pipefail

APT_BASE="https://ptrinh.github.io/viettelex-apt"
APT_KEY_FPR="43ADE236BCC43900B8F146B4F57C885055149990"
STABLE_JSON="https://viettelex.com/stable.json"
GH_DL="https://github.com/ptrinh/viettelex/releases/download"
MAC_TEAM="Developer ID Installer: SENPRINTS LLC (84T567KMYD)"
BREW_CASK="ptrinh/viettelex/viettelex"
KEYRING=/etc/apt/keyrings/viettelex.gpg
SOURCES=/etc/apt/sources.list.d/viettelex.sources
PKGS_ALL="viettelex libviettelex-core viettelex-fcitx5 viettelex-ibus viettelex-text-tools viettelex-settings"

FRONTEND=""
ASSUME_YES=0
UNINSTALL=0
DRY=0
FORCE_PKG=0
SERIES_OVERRIDE=""
PRINT_SERIES=0
TMPD=""

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mLỗi:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() { if [ -n "$TMPD" ]; then rm -rf "$TMPD"; fi; }
trap cleanup EXIT

usage() {
  cat <<'EOT'
VietTelex — cài / cập nhật / gỡ (Linux Ubuntu/Debian & macOS)
  curl -fsSL https://viettelex.com/install.sh | bash [-s -- TUỲ CHỌN]
  --fcitx5 | --ibus   (Linux) chọn bộ khung gõ (mặc định Fcitx5)
  --yes, -y           không hỏi
  --uninstall         gỡ VietTelex
  --pkg               (macOS) dùng .pkg thay vì Homebrew
  --dry-run           chỉ in các bước sẽ làm
  --series S          (Linux) ép series: jammy noble resolute bookworm trixie
EOT
}

# In lệnh rồi chạy (hoặc chỉ in khi --dry-run).
run() {
  printf '    $ %s\n' "$*"
  if [ "$DRY" = 1 ]; then return 0; fi
  "$@"
}

SUDO=""
need_sudo() {
  if [ "$(id -u)" = 0 ]; then SUDO=""; return; fi
  command -v sudo >/dev/null 2>&1 || die "cần quyền root: chạy lại bằng root hoặc cài sudo."
  SUDO="sudo"
}
srun() { if [ -n "$SUDO" ]; then run sudo "$@"; else run "$@"; fi; }

fetch() {  # fetch URL FILE — chỉ HTTPS, chỉ các host tin cậy
  case "$1" in
    https://github.com/*|https://ptrinh.github.io/*|https://viettelex.com/*) ;;
    *) die "từ chối tải từ địa chỉ lạ: $1" ;;
  esac
  curl -fsSL --proto '=https' --tlsv1.2 --retry 2 -o "$2" "$1"
}

# Hỏi có/không qua /dev/tty (stdin là script khi chạy bằng curl | bash).
ask() {  # ask "câu hỏi" default(y|n)
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi   # --yes = đồng ý mọi câu hỏi
  if ! { : </dev/tty; } 2>/dev/null; then [ "$2" = y ]; return; fi
  local ans
  printf '%s ' "$1" >/dev/tty
  read -r ans </dev/tty || ans=""
  [ -z "$ans" ] && ans=$2
  case "$ans" in y|Y|yes|c|C|co|có) return 0 ;; *) return 1 ;; esac
}

# ============================== Linux ================================================

# Series có trên kho APT (dists/<series>). Thêm series mới: build-all.sh + đây + APT.md.
SUPPORTED_SERIES="jammy noble resolute bookworm trixie"
SUPPORTED_HUMAN="Ubuntu 22.04/24.04/26.04, Debian 12/13 và bản dựa trên chúng"

# Đặt SERIES (dists/<series> của kho) + OS_NAME từ os-release.
#  - Ubuntu và bản dựa trên Ubuntu (Mint, Pop!_OS, Zorin, elementary, KDE neon…): UBUNTU_CODENAME.
#  - Debian và bản dựa trên Debian (LMDE, MX, Raspberry Pi OS 64-bit, Kali…): DEBIAN_CODENAME
#    (LMDE) hoặc VERSION_CODENAME; Kali rolling ≈ Debian testing → dùng gói trixie (thử nghiệm).
#  - --series S ghi đè (bản phái sinh lạ: chọn series gần nhất, tự chịu rủi ro).
linux_series() {
  local osr=${VT_OS_RELEASE:-/etc/os-release}
  [ -r "$osr" ] || die "không đọc được $osr."
  local ID="" ID_LIKE="" UBUNTU_CODENAME="" DEBIAN_CODENAME="" VERSION_CODENAME="" PRETTY_NAME=""
  # shellcheck disable=SC1090
  . "$osr"
  OS_NAME=${PRETTY_NAME:-Linux}
  local like=" ${ID:-} ${ID_LIKE:-} " guess=""
  case "$like" in
    *" ubuntu "*) guess=${UBUNTU_CODENAME:-$VERSION_CODENAME} ;;
    *" debian "*|*" raspbian "*)
      guess=${DEBIAN_CODENAME:-$VERSION_CODENAME}
      case "$guess" in
        kali-rolling) guess=trixie; warn "Kali rolling: dùng gói Debian 13 (trixie) — chưa kiểm thử chính thức." ;;
      esac ;;
  esac
  SERIES=${SERIES_OVERRIDE:-$guess}
  [ -n "$SERIES" ] || die "hệ điều hành chưa được hỗ trợ ($OS_NAME). Cần $SUPPORTED_HUMAN (hoặc --series <tên>)."
  case " $SUPPORTED_SERIES " in
    *" $SERIES "*) ;;
    *) die "chưa có bản cho $OS_NAME ($SERIES). Hỗ trợ: $SUPPORTED_HUMAN ($SUPPORTED_SERIES). Xem https://viettelex.com/download/?os=linux" ;;
  esac
}

is_gnome() { case "$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')" in *gnome*) return 0 ;; esac; return 1; }

pkg_installed() { dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^.i'; }

choose_frontend() {
  [ -n "$FRONTEND" ] && return
  if pkg_installed viettelex-ibus && ! pkg_installed viettelex-fcitx5; then FRONTEND=ibus; return; fi
  if pkg_installed viettelex-fcitx5; then FRONTEND=fcitx5; return; fi
  local desk
  desk=$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')
  if command -v fcitx5 >/dev/null 2>&1; then FRONTEND=fcitx5; return; fi
  if command -v ibus >/dev/null 2>&1 || case "$desk" in *gnome*) true ;; *) false ;; esac; then
    say "Máy đang dùng IBus (mặc định của Ubuntu/GNOME)."
    info "Fcitx5 được khuyên dùng: gõ mượt hơn, ít lỗi hơn trong Chrome/Electron/terminal."
    info "Cài Fcitx5 sẽ đặt nó làm bộ gõ mặc định thay IBus; cần đăng xuất/đăng nhập một lần."
    if ask "Cài Fcitx5? [C/n] (n = giữ IBus)" y; then FRONTEND=fcitx5; else FRONTEND=ibus; fi
    return
  fi
  FRONTEND=fcitx5
}

linux_install() {
  command -v apt-get >/dev/null 2>&1 || die "cần apt (Ubuntu/Debian). Arch Linux: AUR viettelex-bin."
  command -v curl >/dev/null 2>&1 || die "cần curl: sudo apt install curl"
  linux_series
  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in amd64|arm64) ;; *) die "chưa có bản cho kiến trúc $ARCH (hỗ trợ amd64, arm64)." ;; esac
  TMPD=$(mktemp -d)

  say "Kiểm tra kho VietTelex cho $OS_NAME ($SERIES, $ARCH)"
  if ! fetch "$APT_BASE/dists/$SERIES/InRelease" "$TMPD/InRelease" 2>/dev/null; then
    die "kho chưa có bản cho $OS_NAME ($SERIES) hoặc mạng lỗi. Xem https://viettelex.com/download/?os=linux"
  fi
  fetch "$APT_BASE/viettelex-archive-keyring.gpg" "$TMPD/viettelex.gpg"
  # Khoá tải về phải ký đúng InRelease bằng khoá có vân tay ghim sẵn.
  if ! gpgv --status-fd 1 --keyring "$TMPD/viettelex.gpg" "$TMPD/InRelease" 2>/dev/null \
      | grep -q "^\[GNUPG:\] VALIDSIG $APT_KEY_FPR "; then
    die "chữ ký kho APT không khớp khoá VietTelex ($APT_KEY_FPR) — dừng lại."
  fi
  info "chữ ký kho hợp lệ (khoá $APT_KEY_FPR)"
  choose_frontend
  say "Bộ khung gõ: $FRONTEND"

  need_sudo
  say "Thêm kho APT VietTelex (cần quyền quản trị)"
  printf 'Types: deb\nURIs: %s/\nSuites: %s\nComponents: main\nSigned-By: %s\n' \
    "$APT_BASE" "$SERIES" "$KEYRING" > "$TMPD/viettelex.sources"
  srun install -d -m 0755 /etc/apt/keyrings
  srun install -m 0644 "$TMPD/viettelex.gpg" "$KEYRING"
  srun install -m 0644 "$TMPD/viettelex.sources" "$SOURCES"
  srun apt-get update

  local pkgs
  if [ "$DRY" = 0 ] && ! apt-cache show viettelex >/dev/null 2>&1; then
    pkgs="libviettelex-core viettelex-settings viettelex-$FRONTEND"   # kho chưa có metapackage
  else
    pkgs="viettelex viettelex-$FRONTEND"
  fi
  say "Cài / cập nhật VietTelex"
  # shellcheck disable=SC2086
  srun env DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs

  if [ "$FRONTEND" = fcitx5 ]; then
    if is_gnome; then
      # GNOME: im-config không có tác dụng (gnome-shell tự chạy IBus) ⇒ autostart Fcitx5 +
      # GTK_IM_MODULE=fcitx trong ~/.config (linux/settings/viettelex_settings/gnome_fcitx5.py).
      if [ "$(id -u)" != 0 ] && { command -v viettelex-settings >/dev/null 2>&1 || [ "$DRY" = 1 ]; }; then
        say "Đặt Fcitx5 chạy thay IBus cho người dùng $(id -un) (GNOME)"
        run viettelex-settings --use-fcitx5
      fi
    elif command -v im-config >/dev/null 2>&1 || [ "$DRY" = 1 ]; then
      say "Đặt Fcitx5 làm bộ gõ mặc định cho người dùng $(id -un)"
      run im-config -n fcitx5
    fi
  fi

  say "Xong: $(dpkg-query -W -f='${Package} ${Version}\n' viettelex-settings 2>/dev/null || echo 'VietTelex')"
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ "$(id -u)" != 0 ] && [ "$DRY" = 0 ] \
      && command -v viettelex-settings >/dev/null 2>&1; then
    info "Mở hướng dẫn bật bộ gõ…"
    (nohup viettelex-settings --onboarding >/dev/null 2>&1 &)
  fi
  echo
  echo "Bước tiếp theo:"
  if [ "$FRONTEND" = fcitx5 ]; then
    echo "  1. Đăng xuất rồi đăng nhập lại MỘT lần để Fcitx5 chạy (nếu trước đó dùng IBus)."
    echo "  2. Mở VietTelex trong menu ứng dụng và làm theo hướng dẫn (thêm 'Vietnamese (VietTelex)')."
  else
    echo "  1. Chạy: ibus restart"
    echo "  2. Settings → Keyboard → Input Sources → + → Vietnamese → VietTelex."
  fi
  echo "  Chuyển Việt/Anh: Ctrl+Space. Cập nhật về sau: chạy lại lệnh này hoặc sudo apt upgrade."
}

linux_uninstall() {
  need_sudo
  if [ "$(id -u)" != 0 ] && command -v viettelex-settings >/dev/null 2>&1; then
    run viettelex-settings --use-ibus >/dev/null   # gỡ autostart/env Fcitx5 do VietTelex đặt (GNOME)
  fi
  local p present=""
  for p in $PKGS_ALL; do pkg_installed "$p" && present="$present $p"; done
  if [ -n "$present" ]; then
    say "Gỡ gói:$present"
    # shellcheck disable=SC2086
    srun env DEBIAN_FRONTEND=noninteractive apt-get purge -y $present
  else
    say "Không có gói VietTelex nào đang cài."
  fi
  if [ -e "$SOURCES" ] || [ -e /etc/apt/sources.list.d/viettelex.list ] || [ -e "$KEYRING" ]; then
    say "Xoá kho APT + khoá"
    srun rm -f "$SOURCES" /etc/apt/sources.list.d/viettelex.list "$KEYRING"
  fi
  say "Đã gỡ. Cài đặt cá nhân vẫn ở ~/.config/viettelex (xoá tay nếu muốn)."
  info "Nếu trước đây dùng IBus: đăng xuất/đăng nhập lại (desktop khác GNOME: im-config -n ibus trước)."
}

# ============================== macOS ================================================

MAC_APP_USER="$HOME/Library/Input Methods/VietTelex.app"
MAC_APP_SYS="/Library/Input Methods/VietTelex.app"

json_field() {  # json_field FILE key → giá trị chuỗi ở cấp gốc
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

brew_managed() { command -v brew >/dev/null 2>&1 && brew list --cask viettelex >/dev/null 2>&1; }

mac_verify_pkg() {  # mac_verify_pkg FILE
  local sig
  sig=$(/usr/sbin/pkgutil --check-signature "$1" 2>&1) || die "pkg không có chữ ký hợp lệ."
  printf '%s\n' "$sig" | grep -q "Status: signed by a developer certificate issued by Apple" \
    || die "pkg không được ký bằng chứng chỉ Developer ID của Apple."
  printf '%s\n' "$sig" | grep -qF "$MAC_TEAM" || die "pkg không phải của VietTelex ($MAC_TEAM)."
  local gk
  gk=$(/usr/sbin/spctl -a -vv -t install "$1" 2>&1) || die "Gatekeeper từ chối pkg: $gk"
  printf '%s\n' "$gk" | grep -q "Notarized Developer ID" || die "pkg chưa được Apple notarize."
  info "chữ ký: $MAC_TEAM · đã notarize"
}

mac_install() {
  [ "$(id -u)" != 0 ] || die "trên macOS hãy chạy bằng tài khoản người dùng (không sudo)."
  if [ "$FORCE_PKG" = 1 ] && brew_managed; then
    if [ "$DRY" = 1 ]; then warn "đang cài bằng Homebrew — thật sự chạy --pkg sẽ bị từ chối (gỡ cask trước)."
    else die "VietTelex đang được Homebrew quản lý: chạy 'brew uninstall --cask viettelex' trước khi dùng --pkg."; fi
  fi
  if [ "$FORCE_PKG" = 0 ] && command -v brew >/dev/null 2>&1 && { brew_managed || [ ! -e "$MAC_APP_USER" ]; }; then
    if brew_managed; then
      say "Cập nhật qua Homebrew"
      run brew upgrade --cask viettelex || true
    else
      say "Cài qua Homebrew"
      run brew install --cask "$BREW_CASK"
    fi
  else
    TMPD=$(mktemp -d)
    say "Đọc bản ổn định mới nhất"
    fetch "$STABLE_JSON" "$TMPD/stable.json"
    local ver
    ver=$(json_field "$TMPD/stable.json" version) || die "stable.json lạ."
    case "$ver" in [0-9]*.[0-9]*) ;; *) die "phiên bản lạ trong stable.json: $ver" ;; esac
    if [ -e "$MAC_APP_USER" ]; then
      local cur
      cur=$(/usr/bin/defaults read "$MAC_APP_USER/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
      info "đang cài: $cur → mới nhất: $ver"
    fi
    local pkg="$TMPD/VietTelex-$ver.pkg"
    say "Tải VietTelex $ver (.pkg)"
    fetch "$GH_DL/v$ver/VietTelex-$ver.pkg" "$pkg"
    mac_verify_pkg "$pkg"
    say "Cài vào ~/Library/Input Methods (không cần mật khẩu quản trị)"
    run /usr/sbin/installer -pkg "$pkg" -target CurrentUserHomeDirectory
  fi
  echo
  echo "Bước tiếp theo:"
  echo "  1. System Settings → Keyboard → Input Sources → Edit… → + → Vietnamese → VietTelex."
  echo "  2. Lần đầu gõ, macOS hỏi quyền Trợ năng (Accessibility): bật VietTelex trong"
  echo "     System Settings → Privacy & Security → Accessibility."
  echo "  Chuyển Việt/Anh: phím tắt đổi bộ gõ của macOS (Ctrl+Space hoặc 🌐)."
  if [ "$DRY" = 1 ]; then echo "(dry-run: chưa cài gì)"; fi
}

mac_uninstall() {
  if brew_managed; then
    ask "Gỡ VietTelex (Homebrew cask)? [c/N]" n || { say "Huỷ."; return; }
    run brew uninstall --cask viettelex
  else
    local found=0
    [ -e "$MAC_APP_USER" ] && found=1
    [ -e "$MAC_APP_SYS" ] && found=1
    [ "$found" = 1 ] || { say "Không thấy VietTelex.app."; return; }
    ask "Gỡ VietTelex.app khỏi máy? [c/N]" n || { say "Huỷ."; return; }
    run /usr/bin/pkill -x VietTelex || true
    [ -e "$MAC_APP_USER" ] && run rm -rf "$MAC_APP_USER"
    if [ -e "$MAC_APP_SYS" ]; then
      say "Bản cũ ở /Library/Input Methods (cần mật khẩu quản trị)"
      run sudo rm -rf "$MAC_APP_SYS"
    fi
  fi
  say "Đã gỡ. Đăng xuất/đăng nhập để macOS bỏ VietTelex khỏi Input Sources."
  info "Cài đặt cá nhân: ~/Library/Preferences/com.viettelex.settings.plist (xoá tay nếu muốn)."
}

# ============================== main =================================================

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --fcitx5) FRONTEND=fcitx5 ;;
      --ibus) FRONTEND=ibus ;;
      --yes|-y) ASSUME_YES=1 ;;
      --uninstall) UNINSTALL=1 ;;
      --dry-run) DRY=1 ;;
      --pkg) FORCE_PKG=1 ;;
      --series) [ $# -ge 2 ] || die "--series cần tên (vd bookworm)"; SERIES_OVERRIDE=$2; shift ;;
      --print-series) PRINT_SERIES=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "tuỳ chọn lạ: $1 (xem --help)" ;;
    esac
    shift
  done
  if [ "$PRINT_SERIES" = 1 ]; then linux_series; echo "$SERIES"; exit 0; fi
  [ "$DRY" = 1 ] && say "DRY-RUN: chỉ in các bước, không thay đổi hệ thống."
  case "$(uname -s)" in
    Linux)  if [ "$UNINSTALL" = 1 ]; then linux_uninstall; else linux_install; fi ;;
    Darwin) if [ "$UNINSTALL" = 1 ]; then mac_uninstall; else mac_install; fi ;;
    *) die "chưa hỗ trợ $(uname -s). Windows: tải .msi tại https://viettelex.com/download/?os=windows" ;;
  esac
}

main "$@"
