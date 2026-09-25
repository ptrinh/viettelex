#!/bin/sh
# Dàn nguồn gói Debian từ monorepo rồi build .deb (chạy TRÊN Ubuntu / trong container).
#
#   linux/packaging/build-deb.sh [--settings-only] [--source] [--series jammy|noble|…] [--out DIR]
#
#   --settings-only  chỉ build viettelex-settings (profile pkg.viettelex.noengine) —
#                    không cần Swift / headers Fcitx5, IBus.
#   --source         build source package (.dsc/.tar.xz/_source.changes) cho PPA, không ký
#                    (ký sau bằng debsign — xem PPA.md).
#   --series S       đặt distribution + hậu tố phiên bản ~S1 trong changelog (PPA mỗi series
#                    cần phiên bản khác nhau).
#
# Maintainer lấy từ $DEBFULLNAME / $DEBEMAIL nếu có (không ghi thông tin cá nhân vào repo).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
SETTINGS_ONLY=0
SOURCE=0
SERIES=""
OUT="$REPO/linux/packaging/out"

while [ $# -gt 0 ]; do
  case "$1" in
    --settings-only) SETTINGS_ONLY=1 ;;
    --source) SOURCE=1 ;;
    --series) SERIES=$2; shift ;;
    --out) OUT=$2; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

VERSION=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$REPO/linux/settings/viettelex_settings/__init__.py")
[ -n "$VERSION" ] || { echo "cannot read VERSION" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/viettelex-$VERSION"
mkdir -p "$STAGE"

# Chỉ những gì gói cần: engine Swift dùng chung (TelexCore) + cây linux/ + file mẫu.
( cd "$REPO" && tar -cf - \
    --exclude='.build' --exclude='.swiftpm' --exclude='__pycache__' \
    --exclude='linux/packaging/out' --exclude='*.o' \
    LICENSE sample-shortcuts.yml typing-modes.yml TelexCore linux \
    android/telexcore/src/test/resources/golden.tsv.gz ) | tar -xf - -C "$STAGE"
cp -a "$HERE/debian" "$STAGE/debian"

if [ -n "${DEBFULLNAME:-}" ] && [ -n "${DEBEMAIL:-}" ]; then
  sed -i "s|VietTelex Maintainers <maintainers@viettelex.invalid>|$DEBFULLNAME <$DEBEMAIL>|" \
    "$STAGE/debian/control" "$STAGE/debian/changelog"
fi
if [ -n "$SERIES" ]; then
  sed -i "1s/^viettelex (\([^)]*\)) UNRELEASED;/viettelex (\1~${SERIES}1) ${SERIES};/" \
    "$STAGE/debian/changelog"
fi

cd "$STAGE"
if [ "$SOURCE" = 1 ]; then
  dpkg-buildpackage -S -d -us -uc
else
  if [ "$SETTINGS_ONLY" = 1 ]; then
    DEB_BUILD_PROFILES=pkg.viettelex.noengine dpkg-buildpackage -b -us -uc -Ppkg.viettelex.noengine
  else
    dpkg-buildpackage -b -us -uc
  fi
fi

mkdir -p "$OUT"
find "$WORK" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.dsc' -o -name '*.tar.*' \
  -o -name '*.changes' -o -name '*.buildinfo' \) -exec cp {} "$OUT/" \;
ls -l "$OUT"
