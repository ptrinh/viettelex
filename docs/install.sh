#!/bin/bash
# VietTelex — cài / cập nhật / gỡ bằng một lệnh (Linux Ubuntu/Debian, Fedora/RHEL, Fedora Atomic,
# Arch & macOS).
#
#   curl -fsSL https://viettelex.com/install.sh | bash
#   curl -fsSL https://viettelex.com/install.sh | bash -s -- --ibus --yes
#
# Tuỳ chọn:
#   --fcitx5 | --ibus   (Linux) chọn bộ khung gõ; mặc định Fcitx5, hỏi nếu máy chỉ có IBus/GNOME
#                       (RHEL/Rocky/Alma: chỉ IBus; Fedora Atomic: theo desktop — KDE Fcitx5, GNOME IBus)
#   --yes, -y           không hỏi, dùng lựa chọn mặc định
#   --pkg               (macOS) cài bằng .pkg kể cả khi có Homebrew
#   --uninstall         gỡ VietTelex (Linux: gói + kho APT/DNF/pacman + khoá; macOS: app)
#   --dry-run           chỉ in ra các bước sẽ làm (macOS: vẫn tải .pkg vào thư mục tạm và
#                       kiểm chữ ký, nhưng KHÔNG cài)
#   --series S          (Linux) ép series kho APT (jammy|noble|resolute|bookworm|trixie) cho
#                       bản phái sinh không tự nhận ra; --print-series in series tự nhận rồi thoát
#                       (Fedora/EL: fedora/44, el/9…; Fedora Atomic: ostree:fedora/44; Arch: arch)
#   --help
#
# An toàn: chỉ tải từ github.com / ptrinh.github.io / viettelex.com qua HTTPS; kho APT được
# kiểm chữ ký với vân tay khoá ghim sẵn bên dưới (kho DNF/pacman: khoá tải về phải đúng vân tay
# đó trước khi được tin, rồi dnf/rpm-ostree/pacman tự kiểm chữ ký gói + metadata); .pkg macOS được kiểm chữ ký Developer ID
# + notarization trước khi cài; mọi lệnh sudo được in ra trước khi chạy. Chạy lại = cập nhật.
# Tương thích bash 3.2 (macOS).
set -euo pipefail

APT_BASE="https://ptrinh.github.io/viettelex-apt"
APT_KEY_FPR="43ADE236BCC43900B8F146B4F57C885055149990"
# Khoá ký kho DNF/pacman = khoá kho APT. Kiểm thử với kho file:// tạm: khoá thử.
KEY_FPR=$APT_KEY_FPR
case "${VT_REPO_BASE:-}" in file://*) KEY_FPR=${VT_TEST_KEY_FPR:-$APT_KEY_FPR} ;; esac
STABLE_JSON="https://viettelex.com/stable.json"
GH_DL="https://github.com/ptrinh/viettelex/releases/download"
MAC_TEAM="Developer ID Installer: SENPRINTS LLC (84T567KMYD)"
BREW_CASK="ptrinh/viettelex/viettelex"
# Kho DNF (Fedora/EL/Atomic) và pacman (Arch) nằm cùng trang Pages với kho APT.
# VT_REPO_BASE=file:///… chỉ để kiểm thử (test-rpm.sh / test-pacman-repo.sh).
REPO_BASE=${VT_REPO_BASE:-https://ptrinh.github.io/viettelex-apt}
RPM_KEY_FILE=/etc/pki/rpm-gpg/RPM-GPG-KEY-viettelex
YUM_REPO=/etc/yum.repos.d/viettelex.repo
PACMAN_CONF=${VT_PACMAN_CONF:-/etc/pacman.conf}
OSTREE_MARKER=${VT_OSTREE_MARKER:-/run/ostree-booted}
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
VietTelex — cài / cập nhật / gỡ (Linux Ubuntu/Debian, Fedora/RHEL, Fedora Atomic, Arch & macOS)
  curl -fsSL https://viettelex.com/install.sh | bash [-s -- TUỲ CHỌN]
  --fcitx5 | --ibus   (Linux) chọn bộ khung gõ (mặc định Fcitx5)
  --yes, -y           không hỏi
  --uninstall         gỡ VietTelex
  --pkg               (macOS) dùng .pkg thay vì Homebrew
  --dry-run           chỉ in các bước sẽ làm
  --series S          (Linux) ép series: jammy noble resolute bookworm trixie
                      (Fedora/EL: fedora/43 fedora/44 el/9 el/10)
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
    file://*) [ -n "${VT_REPO_BASE:-}" ] || die "từ chối tải từ địa chỉ lạ: $1" ;;   # chỉ khi kiểm thử
    *) die "từ chối tải từ địa chỉ lạ: $1" ;;
  esac
  case "$1" in
    file://*) curl -fsSL --proto '=file' -o "$2" "$1" ;;
    *) curl -fsSL --proto '=https' --tlsv1.2 --retry 2 -o "$2" "$1" ;;
  esac
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
SUPPORTED_HUMAN="Ubuntu 22.04/24.04/26.04, Debian 12/13, Fedora 43/44 (cả Silverblue/Kinoite/Bazzite/Bluefin), RHEL/Rocky/Alma 9/10, Arch và bản dựa trên chúng"
# Kho DNF: rpm/fedora/<NN>/, rpm/el/<N>/ (linux/packaging/dnf-repo.sh). Thêm bản: build-rpm.sh + đây.
RPM_SUPPORTED="fedora/43 fedora/44 el/9 el/10"

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

pkg_installed() {
  case "${FAMILY:-apt}" in
    dnf|ostree) rpm -q "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    *) dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^.i' ;;
  esac
}

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
  command -v apt-get >/dev/null 2>&1 || die "cần apt (Ubuntu/Debian). Hỗ trợ: $SUPPORTED_HUMAN."
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

# ------------------------------ họ distro -------------------------------------------------
# FAMILY = apt (Ubuntu/Debian và mọi distro khác — giữ nguyên đường cũ, kể cả thông báo lỗi)
#        | dnf (Fedora, RHEL/CentOS Stream/Rocky/Alma/Oracle) | ostree (Fedora Atomic) | pacman (Arch).
# RPM_DIR = thư mục kho DNF: fedora/<NN> hoặc el/<N>.
FAMILY=apt
RPM_DIR=""
is_ostree() {  # is_ostree "<VARIANT_ID> <ID>"
  [ -e "$OSTREE_MARKER" ] && return 0
  command -v rpm-ostree >/dev/null 2>&1 || return 1
  case " ${1:-} " in
    *" silverblue "*|*" kinoite "*|*" sericea "*|*" onyx "*|*" cosmic-atomic "*|*" budgie-atomic "*) return 0 ;;
    *" kde-atomic "*|*" bazzite"*|*" bluefin"*|*" aurora"*|*" ucore"*) return 0 ;;
  esac
  # /usr chỉ đọc = hệ ostree.
  if command -v findmnt >/dev/null 2>&1; then
    findmnt -no OPTIONS /usr 2>/dev/null | tr ',' '\n' | grep -qx ro && return 0
  fi
  return 1
}

linux_family() {
  local osr=${VT_OS_RELEASE:-/etc/os-release}
  [ -r "$osr" ] || die "không đọc được $osr."
  local ID="" ID_LIKE="" VERSION_ID="" VARIANT_ID="" PRETTY_NAME=""
  # shellcheck disable=SC1090
  . "$osr"
  OS_NAME=${PRETTY_NAME:-Linux}
  FAMILY=apt; RPM_DIR=""
  # --series <tên apt> (không có "/") = ép đường APT như trước.
  case "$SERIES_OVERRIDE" in ""|*/*) ;; *) return 0 ;; esac
  local like=" ${ID:-} ${ID_LIKE:-} " major=${VERSION_ID%%.*}
  case "$like" in
    *" arch "*|*" archarm "*|*" manjaro "*|*" endeavouros "*|*" cachyos "*|*" garuda "*)
      FAMILY=pacman; return 0 ;;
    *" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*)
      FAMILY=dnf
      # Bản dựa trên Fedora khai ID_LIKE="rhel centos fedora" (Nobara…): số bản = số Fedora.
      if [ "${major:-0}" -ge 30 ] 2>/dev/null; then RPM_DIR="fedora/$major"; else RPM_DIR="el/$major"; fi ;;
    *" fedora "*) FAMILY=dnf; RPM_DIR="fedora/$major" ;;
    *) return 0 ;;
  esac
  if is_ostree "${VARIANT_ID:-} ${ID:-}"; then FAMILY=ostree; fi
  case "$SERIES_OVERRIDE" in */*) RPM_DIR=$SERIES_OVERRIDE ;; esac
  case " $RPM_SUPPORTED " in
    *" $RPM_DIR "*) ;;
    *) die "chưa có bản cho $OS_NAME ($RPM_DIR). Hỗ trợ: $SUPPORTED_HUMAN ($RPM_SUPPORTED). Xem https://viettelex.com/download/?os=linux" ;;
  esac
}

# Khoá ký kho (cùng khoá với kho APT): tải về rồi chỉ tin khi đúng vân tay ghim sẵn.
fetch_pinned_key() {  # fetch_pinned_key URL FILE
  fetch "$1" "$2" || die "không tải được khoá ký $1."
  if ! command -v gpg >/dev/null 2>&1; then
    # Bản EL/Fedora tối giản có thể thiếu gpg: cài gnupg2 trước khi tin khoá.
    if [ "$FAMILY" = dnf ]; then
      say "Cài gnupg2 để kiểm khoá ký"
      need_sudo
      srun dnf install -y gnupg2
    fi
    if ! command -v gpg >/dev/null 2>&1; then
      [ "$DRY" = 1 ] && { warn "dry-run: chưa có gpg — bỏ qua kiểm vân tay khoá."; return 0; }
      die "cần gpg để kiểm khoá ký (gói gnupg2 / gnupg)."
    fi
  fi
  local fpr
  # GNUPGHOME tạm: không đụng keyring của người dùng (và chạy được khi HOME không ghi được).
  local gh
  gh=$(mktemp -d)
  fpr=$(GNUPGHOME=$gh gpg --batch --show-keys --with-colons "$2" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}') || true
  rm -rf "$gh"
  [ "$fpr" = "$KEY_FPR" ] || die "khoá ký tải về ($fpr) không phải khoá VietTelex ($KEY_FPR) — dừng lại."
  info "khoá ký hợp lệ ($KEY_FPR)"
}

rpm_arch_ok() {
  ARCH=$(uname -m)
  case "$ARCH" in x86_64|aarch64) ;; *) die "chưa có bản cho kiến trúc $ARCH (hỗ trợ x86_64, aarch64)." ;; esac
}

# File .repo: Fedora theo $releasever (nâng bản Fedora là kho đổi theo), EL cố định bản chính.
# rpm-ostree không kiểm được chữ ký repomd.xml ("Signing key not found" dù có gpgkey=) ⇒ trên
# Fedora Atomic repo_gpgcheck=0; từng gói vẫn phải mang chữ ký đúng khoá (gpgcheck=1).
write_yum_repo() {  # write_yum_repo FILE [repo_gpgcheck=1]
  local dir=$RPM_DIR rg=${2:-1}
  # shellcheck disable=SC2016
  case "$dir" in fedora/*) dir='fedora/$releasever' ;; esac
  # shellcheck disable=SC2016
  printf '[viettelex]\nname=VietTelex\nbaseurl=%s/rpm/%s/$basearch/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=%s\ngpgkey=file://%s\nmetadata_expire=6h\n' \
    "$REPO_BASE" "$dir" "$rg" "$RPM_KEY_FILE" > "$1"
}

rpm_key_name() { printf 'gpg-pubkey-%s' "$(printf '%s' "$KEY_FPR" | tail -c 8 | tr 'A-F' 'a-f')"; }

desktop_frontend() {  # Fedora Atomic: theo desktop — KDE/khác → fcitx5, GNOME → ibus
  [ -n "$FRONTEND" ] && return
  if pkg_installed viettelex-ibus && ! pkg_installed viettelex-fcitx5; then FRONTEND=ibus; return; fi
  if pkg_installed viettelex-fcitx5; then FRONTEND=fcitx5; return; fi
  if is_gnome; then FRONTEND=ibus; else FRONTEND=fcitx5; fi
}

fcitx5_hint() {
  if is_gnome; then
    if [ "$(id -u)" != 0 ] && { command -v viettelex-settings >/dev/null 2>&1 || [ "$DRY" = 1 ]; }; then
      say "Đặt Fcitx5 chạy thay IBus cho người dùng $(id -un) (GNOME)"
      run viettelex-settings --use-fcitx5
    fi
  else
    info "KDE: Cài đặt hệ thống → Bàn phím → Bàn phím ảo → Fcitx 5 (Wayland), rồi đăng nhập lại."
  fi
}

next_steps() {  # next_steps "<cách cập nhật>"
  echo
  echo "Bước tiếp theo:"
  if [ "$FRONTEND" = fcitx5 ]; then
    echo "  1. Đăng xuất rồi đăng nhập lại MỘT lần để Fcitx5 chạy (nếu trước đó dùng IBus)."
    echo "  2. Mở VietTelex trong menu ứng dụng và làm theo hướng dẫn (thêm 'Vietnamese (VietTelex)')."
  else
    echo "  1. Chạy: ibus restart"
    echo "  2. Settings → Keyboard → Input Sources → + → Vietnamese → VietTelex."
  fi
  echo "  Chuyển Việt/Anh: Ctrl+Space. Cập nhật về sau: $1"
}

# ------------------------------ dnf (Fedora, RHEL/Rocky/Alma) ------------------------------
dnf_install() {
  command -v dnf >/dev/null 2>&1 || die "cần dnf."
  command -v curl >/dev/null 2>&1 || die "cần curl: sudo dnf install curl"
  rpm_arch_ok
  TMPD=$(mktemp -d)
  say "Kiểm tra kho VietTelex cho $OS_NAME ($RPM_DIR, $ARCH)"
  fetch "$REPO_BASE/rpm/$RPM_DIR/$ARCH/repodata/repomd.xml" "$TMPD/repomd.xml" 2>/dev/null \
    || die "kho chưa có bản cho $OS_NAME ($RPM_DIR/$ARCH) hoặc mạng lỗi. Xem https://viettelex.com/download/?os=linux"
  fetch_pinned_key "$REPO_BASE/rpm/RPM-GPG-KEY-viettelex" "$TMPD/RPM-GPG-KEY-viettelex"
  case "$RPM_DIR" in
    el/*)
      # EPEL 9/10 không có Fcitx5 ⇒ trên RHEL/Rocky/Alma chỉ có engine IBus.
      [ "$FRONTEND" = fcitx5 ] && die "RHEL/Rocky/Alma chưa có Fcitx5 (EPEL không có gói fcitx5) — dùng --ibus."
      FRONTEND=ibus ;;
    *) choose_frontend ;;
  esac
  say "Bộ khung gõ: $FRONTEND"

  need_sudo
  say "Thêm kho DNF VietTelex (cần quyền quản trị)"
  write_yum_repo "$TMPD/viettelex.repo"
  srun install -d -m 0755 /etc/pki/rpm-gpg
  srun install -m 0644 "$TMPD/RPM-GPG-KEY-viettelex" "$RPM_KEY_FILE"
  srun rpm --import "$RPM_KEY_FILE"
  srun install -m 0644 "$TMPD/viettelex.repo" "$YUM_REPO"

  case "$RPM_DIR" in
    el/*)
      # Phụ thuộc đều ở BaseOS/AppStream; chỉ máy thiếu kho (bản rút gọn) mới cần EPEL/CRB.
      if [ "$DRY" = 0 ] && ! dnf -q repoquery libadwaita 2>/dev/null | grep -q libadwaita; then
        warn "Không thấy libadwaita trong các kho đang bật."
        if ask "Bật EPEL + CRB để lấy phụ thuộc? [c/N]" n; then
          srun dnf install -y epel-release
          srun dnf config-manager --set-enabled crb || true
        fi
      fi ;;
  esac

  say "Cài / cập nhật VietTelex"
  srun dnf install -y --refresh viettelex "viettelex-$FRONTEND"
  if [ "$FRONTEND" = fcitx5 ]; then fcitx5_hint; fi
  say "Xong: $(rpm -q viettelex-settings 2>/dev/null | grep -v 'not installed' || echo 'VietTelex')"
  next_steps "chạy lại lệnh này hoặc sudo dnf upgrade --refresh."
}

# ------------------------------ Fedora Atomic (rpm-ostree) ---------------------------------
offer_reboot() {
  # Không tự khởi động lại kể cả với --yes: phải trả lời "c" thật trên terminal.
  if [ "$DRY" = 1 ]; then info "(dry-run: không khởi động lại)"; return 0; fi
  { : </dev/tty; } 2>/dev/null || return 0
  local ans
  printf 'Khởi động lại ngay? [c/N] ' >/dev/tty
  read -r ans </dev/tty || ans=""
  case "$ans" in y|Y|yes|c|C|co|có) srun systemctl reboot ;; esac
}

ostree_install() {
  command -v rpm-ostree >/dev/null 2>&1 || [ "$DRY" = 1 ] || die "cần rpm-ostree."
  command -v curl >/dev/null 2>&1 || die "cần curl."
  rpm_arch_ok
  case "$RPM_DIR" in fedora/*) ;; *) die "Fedora Atomic: chỉ hỗ trợ bản dựa trên Fedora ($RPM_SUPPORTED)." ;; esac
  TMPD=$(mktemp -d)
  say "Kiểm tra kho VietTelex cho $OS_NAME ($RPM_DIR, $ARCH, rpm-ostree)"
  fetch "$REPO_BASE/rpm/$RPM_DIR/$ARCH/repodata/repomd.xml" "$TMPD/repomd.xml" 2>/dev/null \
    || die "kho chưa có bản cho $OS_NAME ($RPM_DIR/$ARCH) hoặc mạng lỗi."
  fetch_pinned_key "$REPO_BASE/rpm/RPM-GPG-KEY-viettelex" "$TMPD/RPM-GPG-KEY-viettelex"
  desktop_frontend
  say "Bộ khung gõ: $FRONTEND"
  # Fcitx5/IBus có sẵn trong ảnh hệ thống (Silverblue: IBus; Bazzite/Bluefin/Aurora tuỳ bản)
  # thì rpm-ostree không xếp lớp chúng — chỉ xếp các gói VietTelex.
  if rpm -q "$FRONTEND" >/dev/null 2>&1; then info "$FRONTEND đã có trong ảnh hệ thống — không xếp lớp thêm."
  else info "$FRONTEND chưa có trong ảnh — rpm-ostree xếp lớp cùng VietTelex."; fi

  need_sudo
  say "Thêm kho VietTelex vào /etc/yum.repos.d (cần quyền quản trị)"
  write_yum_repo "$TMPD/viettelex.repo" 0
  srun install -d -m 0755 /etc/pki/rpm-gpg
  srun install -m 0644 "$TMPD/RPM-GPG-KEY-viettelex" "$RPM_KEY_FILE"
  srun install -m 0644 "$TMPD/viettelex.repo" "$YUM_REPO"
  say "Xếp lớp VietTelex vào ảnh hệ thống (rpm-ostree)"
  srun rpm-ostree install --idempotent --allow-inactive viettelex "viettelex-$FRONTEND"
  echo
  say "CẦN KHỞI ĐỘNG LẠI để dùng VietTelex (rpm-ostree áp dụng ở lần khởi động sau): systemctl reboot"
  offer_reboot
  next_steps "VietTelex cập nhật cùng hệ thống — rpm-ostree upgrade rồi khởi động lại (Bazzite/Bluefin/Aurora: tự cập nhật hoặc ujust update)."
}

# ------------------------------ pacman (Arch và bản dựa trên Arch) -------------------------
pacman_install() {
  command -v pacman >/dev/null 2>&1 || die "cần pacman."
  command -v curl >/dev/null 2>&1 || die "cần curl: sudo pacman -S curl"
  rpm_arch_ok
  TMPD=$(mktemp -d)
  say "Kiểm tra kho VietTelex cho $OS_NAME ($ARCH)"
  fetch "$REPO_BASE/arch/$ARCH/viettelex.db" "$TMPD/viettelex.db" 2>/dev/null \
    || die "kho pacman chưa có bản cho $ARCH hoặc mạng lỗi. Xem https://viettelex.com/download/?os=linux"
  fetch_pinned_key "$REPO_BASE/viettelex-archive-keyring.gpg" "$TMPD/viettelex.gpg"
  choose_frontend
  say "Bộ khung gõ: $FRONTEND"

  need_sudo
  say "Thêm kho pacman [viettelex] + khoá ký (cần quyền quản trị)"
  srun pacman-key --add "$TMPD/viettelex.gpg"
  # Máy chưa từng chạy pacman-key --init (vd. ảnh container) thì chưa có khoá chủ để lsign.
  srun pacman-key --lsign-key "$KEY_FPR" || { srun pacman-key --init && srun pacman-key --lsign-key "$KEY_FPR"; }
  if grep -q '^\[viettelex\]' "$PACMAN_CONF" 2>/dev/null; then
    info "$PACMAN_CONF đã có [viettelex]"
  else
    # shellcheck disable=SC2016
    printf '\n[viettelex]\nSigLevel = Required DatabaseRequired\nServer = %s/arch/$arch\n' "$REPO_BASE" > "$TMPD/section"
    srun sh -c "cat '$TMPD/section' >> '$PACMAN_CONF'"
  fi
  local extra="fcitx5-gtk fcitx5-qt fcitx5-configtool"
  [ "$FRONTEND" = ibus ] && extra="ibus"
  say "Cài / cập nhật VietTelex"
  # shellcheck disable=SC2086
  srun pacman -Sy --needed --noconfirm viettelex $extra
  if [ "$FRONTEND" = fcitx5 ]; then fcitx5_hint; fi
  say "Xong: $(pacman -Q viettelex 2>/dev/null || echo 'VietTelex')"
  next_steps "chạy lại lệnh này hoặc sudo pacman -Syu."
}

# Gỡ trên Fedora/EL (dnf), Fedora Atomic (rpm-ostree), Arch (pacman). APT: linux_uninstall.
other_uninstall() {
  need_sudo
  if [ "$(id -u)" != 0 ] && command -v viettelex-settings >/dev/null 2>&1; then
    run viettelex-settings --use-ibus >/dev/null   # gỡ autostart/env Fcitx5 do VietTelex đặt (GNOME)
  fi
  local p present=""
  case "$FAMILY" in
    ostree)
      # Chỉ gỡ gói đã xếp lớp theo yêu cầu (viettelex + frontend); phụ thuộc tự đi theo.
      local req
      req=$(rpm-ostree status --json 2>/dev/null | tr -d ' \n' | grep -o '"requested-packages":\[[^]]*\]' | head -1 || true)
      for p in viettelex viettelex-fcitx5 viettelex-ibus; do
        case "$req" in *"\"$p\""*) present="$present $p" ;; esac
      done
      if [ -n "$present" ]; then
        say "Gỡ lớp rpm-ostree:$present"
        # shellcheck disable=SC2086
        srun rpm-ostree uninstall $present
      else
        say "Không có gói VietTelex nào được xếp lớp."
      fi ;;
    dnf)
      for p in $PKGS_ALL; do pkg_installed "$p" && present="$present $p"; done
      if [ -n "$present" ]; then
        say "Gỡ gói:$present"
        # shellcheck disable=SC2086
        srun dnf remove -y $present
      else
        say "Không có gói VietTelex nào đang cài."
      fi ;;
    pacman)
      # pacman -Q khớp cả tên "provides" (viettelex provides viettelex-bin) ⇒ so đúng tên.
      for p in viettelex viettelex-bin; do
        [ "$(pacman -Qq "$p" 2>/dev/null)" = "$p" ] && present="$present $p"
      done
      if [ -n "$present" ]; then
        say "Gỡ gói:$present"
        # shellcheck disable=SC2086
        srun pacman -Rns --noconfirm $present
      else
        say "Không có gói VietTelex nào đang cài."
      fi
      if grep -q '^\[viettelex\]' "$PACMAN_CONF" 2>/dev/null; then
        say "Xoá mục [viettelex] khỏi $PACMAN_CONF"
        # Bỏ dòng [viettelex] và các dòng sau nó tới mục [..] kế tiếp.
        srun sed -i -e '/^\[viettelex\]$/,/^\[/{/^\[viettelex\]$/d;/^\[/!d;}' "$PACMAN_CONF"
      fi
      if pacman-key --list-keys "$KEY_FPR" >/dev/null 2>&1 || [ "$DRY" = 1 ]; then
        say "Xoá khoá ký VietTelex khỏi pacman-key"
        srun pacman-key --delete "$KEY_FPR"
      fi ;;
  esac
  case "$FAMILY" in
    dnf|ostree)
      if [ -e "$YUM_REPO" ] || [ -e "$RPM_KEY_FILE" ]; then
        say "Xoá kho DNF + khoá"
        srun rm -f "$YUM_REPO" "$RPM_KEY_FILE"
      fi
      if [ "$FAMILY" = dnf ] && rpm -q "$(rpm_key_name)" >/dev/null 2>&1; then
        srun rpm -e "$(rpm_key_name)"
      fi ;;
  esac
  say "Đã gỡ. Cài đặt cá nhân vẫn ở ~/.config/viettelex (xoá tay nếu muốn)."
  if [ "$FAMILY" = ostree ]; then
    say "Khởi động lại để rpm-ostree bỏ VietTelex: systemctl reboot"
    offer_reboot
  fi
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
  # macOS 27 đổi tên mục quyền (Accessibility → Device Control and Data Access).
  local pane="Accessibility" pane_vi="Trợ năng"
  if [ "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" -ge 27 ] 2>/dev/null; then
    pane="Device Control and Data Access" pane_vi="Điều khiển thiết bị và truy cập dữ liệu"
  fi
  echo "  2. Lần đầu gõ, macOS hỏi quyền $pane_vi ($pane): bật VietTelex trong"
  echo "     System Settings → Privacy & Security → $pane."
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
  if [ "$PRINT_SERIES" = 1 ]; then
    linux_family
    case "$FAMILY" in
      dnf) echo "$RPM_DIR" ;;
      ostree) echo "ostree:$RPM_DIR" ;;
      pacman) echo arch ;;
      *) linux_series; echo "$SERIES" ;;
    esac
    exit 0
  fi
  [ "$DRY" = 1 ] && say "DRY-RUN: chỉ in các bước, không thay đổi hệ thống."
  case "$(uname -s)" in
    Linux)
      linux_family
      case "$FAMILY:$UNINSTALL" in
        apt:1) linux_uninstall ;;
        apt:0) linux_install ;;
        *:1) other_uninstall ;;
        dnf:0) dnf_install ;;
        ostree:0) ostree_install ;;
        pacman:0) pacman_install ;;
      esac ;;
    Darwin) if [ "$UNINSTALL" = 1 ]; then mac_uninstall; else mac_install; fi ;;
    *) die "chưa hỗ trợ $(uname -s). Windows: tải .msi tại https://viettelex.com/download/?os=windows" ;;
  esac
}

main "$@"
