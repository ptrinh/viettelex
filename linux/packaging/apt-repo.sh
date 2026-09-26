#!/bin/sh
# Dựng repo APT (layout chuẩn, cho GitHub Pages) từ linux/dist/<series>/*.deb và ký trên HOST.
#
#   VT_APT_KEY=<key id/fingerprint> linux/packaging/apt-repo.sh --out DIR [--dist DIR] [--no-sign]
#
#   DIR/
#     viettelex-archive-keyring.gpg            khoá công khai (binary, dearmored)
#     pool/main/v/viettelex/*.deb
#     dists/<series>/Release, InRelease, Release.gpg
#     dists/<series>/main/binary-{amd64,arm64}/Packages(.gz)
#
# - Index (Packages, Release) sinh bằng apt-ftparchive: dùng bản cài sẵn nếu có, không thì
#   chạy trong container ubuntu:24.04 (không cài gì lên host).
# - Ký bằng `gpg` của máy đang chạy script với khoá $VT_APT_KEY: khoá bí mật KHÔNG bao giờ
#   vào container hay repo. `--no-sign` để thử layout không cần khoá.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DIST="$REPO/linux/dist"
OUT=""
SIGN=1
ARCHES="amd64 arm64"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift ;;
    --dist) DIST=$2; shift ;;
    --no-sign) SIGN=0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$OUT" ] || { echo "usage: VT_APT_KEY=… $0 --out DIR [--dist DIR] [--no-sign]" >&2; exit 2; }
if [ "$SIGN" = 1 ] && [ -z "${VT_APT_KEY:-}" ]; then
  echo "VT_APT_KEY is not set (or pass --no-sign)" >&2; exit 2
fi

SERIES=$(cd "$DIST" && for d in */; do d=${d%/}; ls "$d"/*.deb >/dev/null 2>&1 && echo "$d"; done)
[ -n "$SERIES" ] || { echo "no .deb under $DIST/<series>/" >&2; exit 1; }

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/dists" "$OUT/pool"
POOL="$OUT/pool/main/v/viettelex"
mkdir -p "$POOL"
for s in $SERIES; do cp "$DIST/$s"/*.deb "$POOL/"; done

# ---- index (không cần bí mật) -------------------------------------------------------
INDEX_SCRIPT='set -eu
cd "$1"; shift
series="$1"; arches="$2"
for s in $series; do
  for a in $arches; do
    d="dists/$s/main/binary-$a"; mkdir -p "$d"
    # --arch a: gói của arch đó + _all; lọc tiếp theo hậu tố phiên bản ~<series>N.
    apt-ftparchive --arch "$a" packages pool/main \
      | awk -v s="~$s" "BEGIN{RS=\"\"; ORS=\"\n\n\"} \$0 ~ (\"\nVersion: [^\n]*\" s \"[0-9]+\") {print}" > "$d/Packages"
    gzip -9nc "$d/Packages" > "$d/Packages.gz"
    printf "Archive: %s\nComponent: main\nOrigin: VietTelex\nLabel: VietTelex\nArchitecture: %s\n" "$s" "$a" > "$d/Release"
  done
  ( cd "dists/$s" && apt-ftparchive \
      -o APT::FTPArchive::Release::Origin=VietTelex \
      -o APT::FTPArchive::Release::Label=VietTelex \
      -o APT::FTPArchive::Release::Suite="$s" \
      -o APT::FTPArchive::Release::Codename="$s" \
      -o APT::FTPArchive::Release::Architectures="$arches" \
      -o APT::FTPArchive::Release::Components=main \
      -o APT::FTPArchive::Release::Description="VietTelex Vietnamese input method" \
      release . > ../Release.tmp && mv ../Release.tmp Release )
done'

printf '%s\n' "$INDEX_SCRIPT" > "$OUT/.index.sh"
if command -v apt-ftparchive >/dev/null 2>&1; then
  sh "$OUT/.index.sh" "$OUT" "$SERIES" "$ARCHES"
else
  docker run --rm -v "$OUT:/repo" -e "SERIES=$SERIES" -e "ARCHES=$ARCHES" -e "OWNER=$(id -u):$(id -g)" \
    ubuntu:24.04 sh -c 'apt-get update -qq >/dev/null && apt-get install -y -qq apt-utils >/dev/null &&
      sh /repo/.index.sh /repo "$SERIES" "$ARCHES" && chown -R "$OWNER" /repo'
fi
rm -f "$OUT/.index.sh"

for s in $SERIES; do
  for a in $ARCHES; do
    n=$(grep -c '^Package:' "$OUT/dists/$s/main/binary-$a/Packages" || true)
    echo "dists/$s/main/binary-$a: $n packages"
  done
done

# ---- ký trên host ------------------------------------------------------------------
if [ "$SIGN" = 1 ]; then
  for s in $SERIES; do
    r="$OUT/dists/$s"
    rm -f "$r/InRelease" "$r/Release.gpg"
    gpg --batch --yes --local-user "$VT_APT_KEY" --digest-algo SHA512 --clearsign \
        -o "$r/InRelease" "$r/Release"
    gpg --batch --yes --local-user "$VT_APT_KEY" --digest-algo SHA512 --armor --detach-sign \
        -o "$r/Release.gpg" "$r/Release"
  done
  gpg --batch --yes --export "$VT_APT_KEY" > "$OUT/viettelex-archive-keyring.gpg"
  [ -s "$OUT/viettelex-archive-keyring.gpg" ] || { echo "public key export failed" >&2; exit 1; }
  echo "signed with $VT_APT_KEY"
fi
# GitHub Pages: phục vụ nguyên file, không qua Jekyll.
: > "$OUT/.nojekyll"
echo "repo ready: $OUT"
