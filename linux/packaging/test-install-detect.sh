#!/bin/bash
# Kiểm docs/install.sh nhận đúng series kho APT từ /etc/os-release của các distro
# (Ubuntu, Debian và bản phái sinh). Không cần mạng/root; chạy được trên macOS lẫn Linux, CI.
#
#   linux/packaging/test-install-detect.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
INSTALL="$HERE/../../docs/install.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAILS=0

# check "<mô tả>" "<series mong đợi | REJECT>" "<nội dung os-release>" [tham số thêm…]
check() {
  local name=$1 want=$2 body=$3; shift 3
  printf '%s\n' "$body" > "$TMP/os-release"
  local got rc
  got=$(VT_OS_RELEASE="$TMP/os-release" bash "$INSTALL" --print-series "$@" 2>/dev/null); rc=$?
  if [ "$want" = REJECT ]; then
    if [ $rc != 0 ]; then echo "ok   $name → từ chối"; else echo "FAIL $name: nhận '$got', mong từ chối"; FAILS=$((FAILS+1)); fi
  elif [ $rc = 0 ] && [ "$got" = "$want" ]; then
    echo "ok   $name → $got"
  else
    echo "FAIL $name: '$got' (rc=$rc), mong '$want'"; FAILS=$((FAILS+1))
  fi
}

check "Ubuntu 22.04" jammy 'ID=ubuntu
ID_LIKE=debian
VERSION_CODENAME=jammy
UBUNTU_CODENAME=jammy'
check "Ubuntu 24.04" noble 'ID=ubuntu
ID_LIKE=debian
VERSION_CODENAME=noble
UBUNTU_CODENAME=noble'
check "Ubuntu 26.04" resolute 'NAME="Ubuntu"
VERSION_ID="26.04"
ID=ubuntu
ID_LIKE=debian
VERSION_CODENAME=resolute
UBUNTU_CODENAME=resolute'
check "Ubuntu 25.10 (hết hạn, không có gói)" REJECT 'ID=ubuntu
ID_LIKE=debian
VERSION_CODENAME=questing
UBUNTU_CODENAME=questing'
check "Linux Mint 22" noble 'ID=linuxmint
ID_LIKE="ubuntu debian"
VERSION_CODENAME=wilma
UBUNTU_CODENAME=noble'
check "Pop!_OS 24.04" noble 'ID=pop
ID_LIKE="ubuntu debian"
VERSION_CODENAME=noble
UBUNTU_CODENAME=noble'
check "Zorin OS 17" jammy 'ID=zorin
ID_LIKE=ubuntu
VERSION_CODENAME=jammy
UBUNTU_CODENAME=jammy'
check "elementary OS 8" noble 'ID=elementary
ID_LIKE=ubuntu
VERSION_CODENAME=circe
UBUNTU_CODENAME=noble'
check "Debian 12" bookworm 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
ID=debian
VERSION_CODENAME=bookworm'
check "Debian 13" trixie 'ID=debian
VERSION_CODENAME=trixie'
check "Debian testing/sid (forky)" REJECT 'PRETTY_NAME="Debian GNU/Linux forky/sid"
ID=debian
VERSION_CODENAME=forky'
check "LMDE 6" bookworm 'ID=linuxmint
ID_LIKE=debian
VERSION_CODENAME=faye
DEBIAN_CODENAME=bookworm'
check "LMDE 7" trixie 'ID=linuxmint
ID_LIKE=debian
VERSION_CODENAME=gigi
DEBIAN_CODENAME=trixie'
check "MX Linux 23" bookworm 'PRETTY_NAME="MX 23"
ID=debian
VERSION_CODENAME=bookworm'
check "Raspberry Pi OS 64-bit" bookworm 'ID=debian
VERSION_CODENAME=bookworm'
check "Kali rolling" trixie 'ID=kali
ID_LIKE=debian
VERSION_CODENAME=kali-rolling'
check "Fedora" REJECT 'ID=fedora
VERSION_CODENAME=""'
check "Arch" REJECT 'ID=arch'
check "Fedora + --series noble (ép)" noble 'ID=fedora' --series noble
check "Debian + --series lạ" REJECT 'ID=debian
VERSION_CODENAME=bookworm' --series bogus

echo "RESULT FAILS=$FAILS"
[ "$FAILS" = 0 ]
