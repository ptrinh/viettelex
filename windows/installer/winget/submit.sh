#!/usr/bin/env bash
# Regenerate + validate the winget manifests for a published VietTelex for Windows
# release, then PRINT the commands that open the microsoft/winget-pkgs PR.
#
#   windows/installer/winget/submit.sh [X.Y.Z]     (default: docs/stable.json windows.version)
#
# Nothing is forked, pushed or opened by this script. Prerequisites for the printed
# commands: gh (logged in), git. The MSIs must already be on the GitHub release
# windows-v<V> (the URLs the manifests point at).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VERSION="${1:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["windows"]["version"])' "$ROOT/docs/stable.json")}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 [X.Y.Z]" >&2; exit 2; }

python3 "$HERE/gen_manifests.py" --version "$VERSION"

ID=ptrinh.VietTelex
REL="manifests/p/ptrinh/VietTelex/$VERSION"
SRC="$HERE/$REL"
BRANCH="$ID-$VERSION"
# First submission is "New package", later ones "New version" (winget-pkgs PR title
# convention): ask upstream whether the package already exists.
KIND="New package"
if command -v gh >/dev/null 2>&1 && gh api repos/microsoft/winget-pkgs/contents/manifests/p/ptrinh/VietTelex >/dev/null 2>&1; then
  KIND="New version"
fi
TITLE="$KIND: $ID version $VERSION"

cat <<EOF

== Manifests ready: $SRC
   Review them, then submit by hand (nothing below has been run):

# 0. (optional, on a Windows machine/VM) validate + test-install the exact files:
#      winget validate --manifest <copy of $REL>
#      winget settings --enable LocalManifestFiles
#      winget install --manifest <copy of $REL>
#    and check typing works, then: winget uninstall --id $ID

# 1. fork once (no clone), then a shallow sparse clone of your fork
GHUSER="\$(gh api user -q .login)"
gh repo fork microsoft/winget-pkgs --clone=false
WP="\${TMPDIR:-/tmp}/winget-pkgs"
git clone --depth 1 --filter=blob:none --sparse "https://github.com/\$GHUSER/winget-pkgs.git" "\$WP"
git -C "\$WP" sparse-checkout set manifests/p/ptrinh
git -C "\$WP" remote add upstream https://github.com/microsoft/winget-pkgs.git
git -C "\$WP" fetch --depth 1 upstream master
git -C "\$WP" checkout -b $BRANCH upstream/master

# 2. add the manifests and push the branch to your fork
mkdir -p "\$WP/$REL"
cp "$SRC"/*.yaml "\$WP/$REL/"
git -C "\$WP" add $REL
git -C "\$WP" commit -m "$TITLE"
git -C "\$WP" push -u origin $BRANCH

# 3. open the PR against microsoft/winget-pkgs
gh pr create -R microsoft/winget-pkgs --head "\$GHUSER:$BRANCH" --base master \\
  --title "$TITLE" \\
  --body "$TITLE. Signed per-machine MSI (x64 + arm64) from the GitHub release windows-v$VERSION; manifests generated and schema-validated (1.12.0) by windows/installer/winget/gen_manifests.py in ptrinh/viettelex."

# 4. afterwards: rm -rf "\$WP"
EOF
