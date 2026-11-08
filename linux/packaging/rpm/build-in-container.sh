#!/bin/bash
# Chạy TRONG container Fedora / Rocky / Alma (root): cài build-deps theo spec, dàn tarball
# nguồn từ /src (monorepo, chỉ đọc) rồi rpmbuild. Gọi bởi linux/packaging/build-rpm.sh.
#
#   build-in-container.sh --out /out [--swift-dir /swift] [--nocheck]
#
# --swift-dir: thư mục có libtelexcore.so + viettelex-text-tool build sẵn (ảnh swift:rhel-ubi9);
# thiếu ⇒ CMake gọi swift trên PATH.
set -euo pipefail
OUT=/out
SWIFT_DIR=""
NOCHECK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift ;;
    --swift-dir) SWIFT_DIR=$2; shift ;;
    --nocheck) NOCHECK=--nocheck ;;   # chỉ để gỡ lỗi; phát hành luôn chạy %check
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
SRC=/src
SPEC=$SRC/linux/packaging/rpm/viettelex.spec
VT_VERSION=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$SRC/linux/settings/viettelex_settings/__init__.py")
[ -n "$VT_VERSION" ] || { echo "cannot read VERSION" >&2; exit 1; }

. /etc/os-release
echo "==> $PRETTY_NAME ($(uname -m)), VietTelex $VT_VERSION"
dnf -y -q install dnf-plugins-core rpm-build rpmdevtools >/dev/null
case " ${ID_LIKE:-} $ID " in
  *" rhel "*|*" centos "*)
    # ibus-devel ở CRB; extra-cmake-modules (chỉ cần khi có Fcitx5) ở EPEL.
    dnf config-manager --set-enabled crb >/dev/null
    ;;
esac
dnf -y -q builddep --define "vt_version $VT_VERSION" --define "vt_changelog_date Mon Jan 01 2024" "$SPEC" >/dev/null

TOP=$(mktemp -d)
mkdir -p "$TOP"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}
STAGE="$TOP/stage/viettelex-$VT_VERSION"
mkdir -p "$STAGE"
# Cùng danh sách với build-deb.sh: TelexCore + linux/ + nguồn/dữ liệu iOS mà
# viettelex-text-tool symlink tới + fixture chung.
( cd "$SRC" && tar -cf - \
    --exclude='.build' --exclude='.swiftpm' --exclude='__pycache__' \
    --exclude='linux/packaging/out' --exclude='linux/dist' --exclude='*.o' \
    LICENSE sample-shortcuts.yml typing-modes.yml TelexCore linux \
    iOS/Keyboard/TextTools.swift iOS/Keyboard/AddTones.swift iOS/Keyboard/SyllableLM.swift \
    iOS/Keyboard/VNLexicon2.swift iOS/Keyboard/VNSuggest.swift iOS/Keyboard/SwipeLexicon.swift \
    iOS/Keyboard/SwipeEnglish.swift \
    iOS/Keyboard/AdjacentKeyFixer.swift iOS/Keyboard/AutoCorrect.swift iOS/Keyboard/MathResults.swift \
    iOS/Keyboard/NumberChips.swift iOS/Keyboard/SeedData.swift \
    iOS/Keyboard/SuggestionSupport.swift iOS/Keyboard/DisplayCase.swift iOS/Keyboard/SensitiveWords.swift \
    App/Sources/SeedNextData.swift App/Sources/LearnedModel.swift App/Sources/LunarCalendar.swift \
    iOS/Keyboard/UserLMTables.swift \
    iOS/Keyboard/CuratedPairs.swift \
    iOS/Keyboard/Resources/vnlexicon.bin iOS/Keyboard/Resources/vnlm.bin iOS/Keyboard/Resources/enlexicon.bin \
    iOS/KeyboardTests/Fixtures/text-tools.txt iOS/KeyboardTests/Fixtures/add-tones.txt \
    iOS/KeyboardTests/Fixtures/math-results.txt iOS/KeyboardTests/Fixtures/number-chips.txt \
    windows/app/tests/fixtures/word-prediction.tsv windows/app/tests/fixtures/learned-words.bin \
    android/telexcore/src/test/resources/golden.tsv.gz ) | tar -xf - -C "$STAGE"
DANGLING=$(cd "$STAGE" && find linux -type l ! -exec test -e {} \; -print)
[ -z "$DANGLING" ] || { echo "✗ symlink chưa dàn vào build (thêm vào danh sách tar):" >&2; echo "$DANGLING" >&2; exit 1; }
tar -czf "$TOP/SOURCES/viettelex-$VT_VERSION.tar.gz" -C "$TOP/stage" "viettelex-$VT_VERSION"
cp "$SPEC" "$TOP/SPECS/"

# Ngày changelog = ngày của mục đầu debian/changelog (cùng phiên bản) ⇒ build lặp lại được.
DEB_DATE=$(sed -n 's/^ -- .*>  \(.*\)$/\1/p' "$SRC/linux/packaging/debian/changelog" | head -1)
CL_DATE=$(LC_ALL=C date -d "$DEB_DATE" '+%a %b %d %Y')
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(date -d "$DEB_DATE" +%s)

DEFS=(--define "_topdir $TOP" --define "vt_version $VT_VERSION" --define "vt_changelog_date $CL_DATE"
      --define "_vpath_srcdir linux" --define "use_source_date_epoch_as_buildtime 1"
      --define "clamp_mtime_to_source_date_epoch 1")
if [ -n "$SWIFT_DIR" ]; then
  test -f "$SWIFT_DIR/libtelexcore.so" && test -x "$SWIFT_DIR/viettelex-text-tool" \
    || { echo "--swift-dir $SWIFT_DIR thiếu libtelexcore.so / viettelex-text-tool" >&2; exit 1; }
  DEFS+=(--define "vt_swift_dir $SWIFT_DIR")
fi
# ctest có test IBus/D-Bus thật: cần HOME ghi được, không cần màn hình.
export HOME=$TOP/home; mkdir -p "$HOME"
rpmbuild -ba $NOCHECK "${DEFS[@]}" "$TOP/SPECS/viettelex.spec" >"$OUT/build.log" 2>&1 \
  || { tail -60 "$OUT/build.log"; exit 1; }
grep -E "^(Wrote|[0-9]+% tests passed|Total Test)" "$OUT/build.log" || true
mkdir -p "$OUT/rpms"
find "$TOP/RPMS" "$TOP/SRPMS" -name '*.rpm' -exec cp {} "$OUT/rpms/" \;
ls -l "$OUT/rpms"
