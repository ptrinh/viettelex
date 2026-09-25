#!/bin/sh
# Fails when TelexCore/Sources/TelexCore gains/loses an engine file that
# engine-capi/Sources/TelexCoreEngine does not symlink (ClientPolicy.swift is excluded on
# purpose: it is the only Foundation user and not part of the engine).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
src="$here/../../TelexCore/Sources/TelexCore"
dst="$here/Sources/TelexCoreEngine"
status=0
for f in "$src"/*.swift; do
  b=$(basename "$f")
  [ "$b" = ClientPolicy.swift ] && continue
  if [ ! -e "$dst/$b" ]; then echo "missing symlink: $dst/$b -> $f" >&2; status=1; fi
done
for f in "$dst"/*.swift; do
  [ -e "$f" ] || { echo "dangling symlink: $f" >&2; status=1; }
done
exit $status
