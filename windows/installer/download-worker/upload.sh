#!/usr/bin/env bash
# Upload a Windows release's MSIs to R2 — viettelex.com/download/windows/<ver>/… is served
# from there by the viettelex-download Worker (see wrangler.jsonc for why).
#   CLOUDFLARE_ACCOUNT_ID=<id> windows/installer/download-worker/upload.sh 1.3.5
set -euo pipefail
VERSION="${1:?usage: upload.sh <version>}"
cd "$(dirname "$0")/../../../docs/download"
for arch in x64 arm64; do
  f="windows/$VERSION/VietTelex-$VERSION-$arch.msi"
  npx -y wrangler r2 object put "viettelex-downloads/$f" --file "$f" \
    --content-type application/x-msi --remote
  want=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f")
  got=$(curl -sSI "https://viettelex.com/download/$f" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}')
  [ "$got" = "$want" ] || { echo "MISMATCH $f: served $got, file $want" >&2; exit 1; }
  echo "ok $f ($got bytes)"
done
