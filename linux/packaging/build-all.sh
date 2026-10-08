#!/bin/sh
# Build .deb cho mọi series × arch bằng Docker/OrbStack (amd64 qua --platform, Rosetta),
# rồi cài thử trong Ubuntu/Debian sạch. Chạy trên HOST (macOS/Linux có docker) hoặc CI
# (.github/workflows/linux-release.yml gọi đúng script này, mỗi job một series × arch).
#
#   linux/packaging/build-all.sh [--series "jammy noble …"] [--arch "amd64 arm64"] [--no-smoke]
#
# Series hỗ trợ (ảnh build = swift:<series>, ảnh smoke = distro sạch — xem image_of/smoke_of):
#   Ubuntu jammy 22.04, noble 24.04, resolute 26.04; Debian bookworm 12, trixie 13.
# Kết quả: linux/dist/<series>/*.deb (gói _all lấy từ bản build đầu tiên của series để
# cùng một file trong pool cho mọi arch). Phiên bản: <changelog>~<series>1.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DIST="$REPO/linux/dist"
SERIES_LIST="jammy noble resolute bookworm trixie"
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
# Ảnh smoke test (distro sạch) theo series. Thêm series mới: thêm một dòng ở đây + một dòng
# trong .github/workflows/linux-release.yml (matrix) — swift:<series> phải có trên Docker Hub.
smoke_of() {
  case "$1" in
    jammy) echo ubuntu:22.04 ;; noble) echo ubuntu:24.04 ;; resolute) echo ubuntu:26.04 ;;
    bookworm) echo debian:12 ;; trixie) echo debian:13 ;;
    *) echo "unknown series: $1 (thêm vào smoke_of trong build-all.sh)" >&2; return 1 ;;
  esac
}
# Ảnh build: toolchain Swift chính thức cho đúng distro. VT_SWIFT_TAG=6.4 ⇒ swift:6.4-<series>
# (ghim phiên bản Swift; mặc định = tag trôi swift:<series>).
image_of() { echo "swift:${VT_SWIFT_TAG:+$VT_SWIFT_TAG-}$1"; }
for s in $SERIES_LIST; do smoke_of "$s" >/dev/null || exit 2; done

mkdir -p "$DIST"
[ -f "$DIST/.gitignore" ] || printf '*\n' > "$DIST/.gitignore"
for s in $SERIES_LIST; do
  rm -rf "${DIST:?}/${s:?}"; mkdir -p "$DIST/$s"
  for a in $ARCH_LIST; do
    img="viettelex-build:$s-$a"
    echo "==> image $img"
    docker build -q --platform "linux/$a" --build-arg "BASE=$(image_of "$s")" \
      -f "$HERE/docker/Dockerfile.build" -t "$img" "$HERE/docker" >/dev/null
    # Tên thư mục mới mỗi lần chạy: xoá rồi tạo lại CÙNG đường dẫn ngay trước bind mount làm
    # OrbStack giữ inode cũ ⇒ "/out/build.log: Directory nonexistent" (08/10/2026).
    out="$DIST/.work/$s-$a-$$"; mkdir -p "$out"
    echo "==> build $s/$a"
    docker run --rm --platform "linux/$a" -v "$REPO:/src:ro" -v "$out:/out" "$img" sh -c \
      "/src/linux/packaging/build-deb.sh --series $s --out /out/pkg >/out/build.log 2>&1 \
         || { tail -40 /out/build.log; exit 1; }
       # Debian ra gói dbgsym dạng .deb (Ubuntu: .ddeb) — không phát hành, không đưa vào kho.
       rm -f /out/pkg/*-dbgsym_*.deb
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
        -v "$HERE/docker/smoke-install.sh:/smoke.sh:ro" "$(smoke_of "$s")" /smoke.sh \
        | tee "$tmp/log"
      grep -q "SMOKE OK" "$tmp/log" || { echo "smoke failed: $s/$a" >&2; exit 1; }
      rm -rf "$tmp"
    done
  done
fi
ls -l "$DIST"/*/
rm -rf "$DIST/.work"
