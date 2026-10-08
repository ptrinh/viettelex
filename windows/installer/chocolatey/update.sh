#!/usr/bin/env bash
# Bump the Chocolatey package (viettelex/) to a published VietTelex for Windows release:
# version in the nuspec, release-notes URL, and the SHA256 of both MSIs (downloaded from
# the GitHub release windows-v<V> and hashed here). Prints the pack/push commands.
#
#   windows/installer/chocolatey/update.sh [X.Y.Z]   (default: docs/stable.json windows.version)
#
# Nothing is packed or pushed: pushing needs a community.chocolatey.org API key.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
PKG="$HERE/viettelex"
VERSION="${1:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["windows"]["version"])' "$ROOT/docs/stable.json")}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 [X.Y.Z]" >&2; exit 2; }
BASE="https://github.com/ptrinh/viettelex/releases/download/windows-v$VERSION"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SHA_x64="" SHA_arm64=""  # no associative arrays: macOS ships bash 3.2
for arch in x64 arm64; do
  f="$TMP/VietTelex-$VERSION-$arch.msi"
  echo "-- downloading $BASE/$(basename "$f")"
  curl -fsSL -o "$f" "$BASE/$(basename "$f")"
  sha="$(shasum -a 256 "$f" | awk '{print toupper($1)}')"
  if [ "$arch" = x64 ]; then SHA_x64="$sha"; else SHA_arm64="$sha"; fi
  if command -v msiinfo >/dev/null 2>&1; then
    pv="$(msiinfo export "$f" Property 2>/dev/null | tr -d '\r' | awk -F'\t' '$1=="ProductVersion"{print $2}')"
    [ "$pv" = "$VERSION" ] || { echo "$arch MSI ProductVersion is '$pv', expected $VERSION" >&2; exit 1; }
  fi
  echo "   $arch sha256 $sha"
done

# In-place edits of the marked lines only (BSD/GNU sed compatible via -i.bak).
sed -i.bak -E \
  -e "s|<version>[^<]*</version>|<version>$VERSION</version>|" \
  -e "s|releases/tag/windows-v[0-9.]+</releaseNotes>|releases/tag/windows-v$VERSION</releaseNotes>|" \
  "$PKG/viettelex.nuspec"
sed -i.bak -E \
  -e "s|^\\\$version( *)= '[^']*'|\$version\\1= '$VERSION'|" \
  -e "s|^\\\$checksumX64( *)= '[^']*'|\$checksumX64\\1= '$SHA_x64'|" \
  -e "s|^\\\$checksumArm64( *)= '[^']*'|\$checksumArm64\\1= '$SHA_arm64'|" \
  "$PKG/tools/chocolateyinstall.ps1"
rm -f "$PKG/viettelex.nuspec.bak" "$PKG/tools/chocolateyinstall.ps1.bak"

grep -q "<version>$VERSION</version>" "$PKG/viettelex.nuspec" || { echo "nuspec version not updated" >&2; exit 1; }
for want in "'$VERSION'" "'$SHA_x64'" "'$SHA_arm64'"; do
  grep -qF "$want" "$PKG/tools/chocolateyinstall.ps1" || { echo "chocolateyinstall.ps1 not updated ($want)" >&2; exit 1; }
done

cat <<EOF

== Chocolatey package bumped to $VERSION: $PKG
   Review + commit, then pack and push by hand (nothing below has been run):

# On Windows (Chocolatey CLI installed), from $PKG:
#   choco pack
#   choco install viettelex --source . -y          # test on a clean VM, then: choco uninstall viettelex -y
#   choco apikey add --source https://push.chocolatey.org/ --key <API-KEY>   # once
#   choco push viettelex.$VERSION.nupkg --source https://push.chocolatey.org/
#
# Or pack from this Mac with the official Linux image (amd64; untested here):
#   docker run --rm -v "$PKG:/pkg" -w /pkg --platform linux/amd64 chocolatey/choco:latest-linux choco pack
EOF
