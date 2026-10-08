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

# Chỉ những gì gói cần: engine Swift dùng chung (TelexCore) + cây linux/ + file mẫu +
# nguồn iOS mà viettelex-text-tool symlink tới (Thêm dấu/TextTools + dữ liệu + fixture chung).
( cd "$REPO" && tar -cf - \
    --exclude='.build' --exclude='.swiftpm' --exclude='__pycache__' \
    --exclude='linux/packaging/out' --exclude='linux/dist' --exclude='*.o' \
    LICENSE sample-shortcuts.yml typing-modes.yml TelexCore linux \
    iOS/Keyboard/TextTools.swift iOS/Keyboard/AddTones.swift iOS/Keyboard/SyllableLM.swift \
    iOS/Keyboard/VNLexicon2.swift iOS/Keyboard/VNSuggest.swift iOS/Keyboard/SwipeLexicon.swift \
    iOS/Keyboard/SwipeEnglish.swift \
    iOS/Keyboard/AdjacentKeyFixer.swift iOS/Keyboard/AutoCorrect.swift iOS/Keyboard/MathResults.swift \
    iOS/Keyboard/NumberChips.swift iOS/Keyboard/SeedData.swift \
    iOS/Keyboard/Resources/vnlexicon.bin iOS/Keyboard/Resources/vnlm.bin iOS/Keyboard/Resources/enlexicon.bin \
    iOS/KeyboardTests/Fixtures/text-tools.txt iOS/KeyboardTests/Fixtures/add-tones.txt \
    iOS/KeyboardTests/Fixtures/math-results.txt iOS/KeyboardTests/Fixtures/number-chips.txt \
    android/telexcore/src/test/resources/golden.tsv.gz ) | tar -xf - -C "$STAGE"
cp -a "$HERE/debian" "$STAGE/debian"
# Symlink trong linux/ trỏ ra ngoài cây đã dàn (thêm file iOS mới mà quên liệt kê ở trên) ⇒ dừng
# ngay, rõ ràng — đừng để make báo "No rule to make target" giữa chừng build (1.0.5).
DANGLING=$(cd "$STAGE" && find linux -type l ! -exec test -e {} \; -print)
[ -z "$DANGLING" ] || { echo "✗ symlink chưa dàn vào build (thêm vào danh sách tar):" >&2; echo "$DANGLING" >&2; exit 1; }

if [ -n "${DEBFULLNAME:-}" ] && [ -n "${DEBEMAIL:-}" ]; then
  sed -i "s|VietTelex Maintainers <maintainers@viettelex.invalid>|$DEBFULLNAME <$DEBEMAIL>|" \
    "$STAGE/debian/control" "$STAGE/debian/changelog"
fi
if [ -n "$SERIES" ]; then
  sed -i "1s/^viettelex (\([^)]*\)) UNRELEASED;/viettelex (\1~${SERIES}1) ${SERIES};/" \
    "$STAGE/debian/changelog"
fi

# jammy (22.04) chưa có fcitx5-frontend-qt6 (có từ noble) → bỏ khỏi Recommends để control sạch.
TARGET_SERIES=${SERIES:-$( . /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")}
if [ "$TARGET_SERIES" = jammy ]; then
  sed -i '/^ *fcitx5-frontend-qt6,$/d' "$STAGE/debian/control"
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
find "$WORK" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.ddeb' -o -name '*.dsc' -o -name '*.tar.*' \
  -o -name '*.changes' -o -name '*.buildinfo' \) -exec cp {} "$OUT/" \;
ls -l "$OUT"
