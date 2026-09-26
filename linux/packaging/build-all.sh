#!/bin/sh
# Build .deb cho mọi series × arch bằng Docker/OrbStack (amd64 qua --platform, Rosetta),
# rồi cài thử trong Ubuntu sạch. Chạy trên HOST (macOS/Linux có docker).
#
#   linux/packaging/build-all.sh [--series "jammy noble"] [--arch "amd64 arm64"] [--no-smoke]
#
# Kết quả: linux/dist/<series>/*.deb (gói _all lấy từ bản build đầu tiên của series để
# cùng một file trong pool cho mọi arch). Phiên bản: <changelog>~<series>1.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DIST="$REPO/linux/dist"
SERIES_LIST="jammy noble"
ARCH_LIST="amd64 arm64"
SMOKE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --series) SERIES_LIST=$2; shift ;;
    --arch) ARCH_LIST=$2; shift ;;
    --no-smoke) SMOKE=0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
ubuntu_of() { case "$1" in jammy) echo 22.04 ;; noble) echo 24.04 ;; *) echo "$1" ;; esac; }

mkdir -p "$DIST"
[ -f "$DIST/.gitignore" ] || printf '*\n' > "$DIST/.gitignore"
for s in $SERIES_LIST; do
  rm -rf "$DIST/$s"; mkdir -p "$DIST/$s"
  for a in $ARCH_LIST; do
    img="viettelex-build:$s-$a"
    echo "==> image $img"
    docker build -q --platform "linux/$a" --build-arg "BASE=swift:$s" \
      -f "$HERE/docker/Dockerfile.build" -t "$img" "$HERE/docker" >/dev/null
    out="$DIST/.work/$s-$a"; rm -rf "$out"; mkdir -p "$out"
    echo "==> build $s/$a"
    docker run --rm --platform "linux/$a" -v "$REPO:/src:ro" -v "$out:/out" "$img" sh -c \
      "/src/linux/packaging/build-deb.sh --series $s --out /out/pkg >/out/build.log 2>&1 \
         || { tail -40 /out/build.log; exit 1; }
       cd /out/pkg && lintian --fail-on error,warning *.deb 2>&1 | grep -v 'root privileges' | tee /out/lintian.log
       test ! -s /out/lintian.log"
    for f in "$out"/pkg/*.deb; do
      b=$(basename "$f")
      case "$b" in *_all.deb) [ -e "$DIST/$s/$b" ] && continue ;; esac
      cp "$f" "$DIST/$s/"
    done
    rm -rf "$out"
  done
done

if [ "$SMOKE" = 1 ]; then
  for s in $SERIES_LIST; do
    for a in $ARCH_LIST; do
      tmp="$DIST/.work/smoke-$s-$a"; rm -rf "$tmp"; mkdir -p "$tmp"
      cp "$DIST/$s"/*_"$a".deb "$DIST/$s"/*_all.deb "$tmp/"
      echo "==> smoke $s/$a"
      docker run --rm --platform "linux/$a" -v "$tmp:/debs:ro" \
        -v "$HERE/docker/smoke-install.sh:/smoke.sh:ro" "ubuntu:$(ubuntu_of "$s")" /smoke.sh \
        | tee "$tmp/log"
      grep -q "SMOKE OK" "$tmp/log" || { echo "smoke failed: $s/$a" >&2; exit 1; }
      rm -rf "$tmp"
    done
  done
fi
ls -l "$DIST"/*/
rm -rf "$DIST/.work"
