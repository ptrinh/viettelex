#!/bin/sh
# Runs INSIDE the mstorsjo/llvm-mingw container (release.sh starts it).
#   /src  repo (read-only)     /out  windows/dist (read-write)
# Builds engine + TIP + app for x86, x64, ARM64, then links the ARM64X pure-forwarder
# VietTelexTIP.dll with lld-link. Results: /out/bin/<arch>/.
set -eu
VERSION="$1"
W=/src/windows
for pair in i686:x86 x86_64:x64 aarch64:arm64; do
  triple="${pair%%:*}-w64-mingw32"; arch="${pair##*:}"
  b="/tmp/build-$arch"
  cmake -S "$W" -B "$b" -G Ninja -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER="$triple-clang" -DCMAKE_CXX_COMPILER="$triple-clang++" \
    -DCMAKE_RC_COMPILER="$triple-windres" -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DVTX_BUILD_TESTS=OFF -DVTX_IME_TESTS=OFF -DVTX_VERSION="$VERSION" >/dev/null
  cmake --build "$b" > "$b.log" 2>&1 || { tail -40 "$b.log"; exit 1; }
  if grep -E "warning:" "$b.log" | grep -v character-conversion | grep -q .; then
    grep -E "warning:" "$b.log" | grep -v character-conversion | sort -u >&2
  fi
  mkdir -p "/out/bin/$arch"
  cp "$b/ime/VietTelexTIP.dll" "$b/app/VietTelex.exe" "/out/bin/$arch/"
  echo "  built $arch"
done

# ---- ARM64X pure forwarder (Microsoft "Arm64X pure forwarder DLL" recipe, lld flavour)
a=/out/bin/arm64
mv "$a/VietTelexTIP.dll" "$a/VietTelexTIP_arm64.dll"
cp /out/bin/x64/VietTelexTIP.dll "$a/VietTelexTIP_x64.dll"
f=/tmp/fwd; mkdir -p "$f"
clang --target=aarch64-pc-windows-msvc -x c -c "$W/ime/src/arm64x/empty.cpp" -o "$f/native.obj"
clang --target=arm64ec-pc-windows-msvc -x c -c "$W/ime/src/arm64x/empty.cpp" -o "$f/ec.obj"
# Version/icon resource so the forwarder looks like the product it is.
aarch64-w64-mingw32-windres -I"$W/ime/src" -DVTX_VER_MAJOR="$(echo "$VERSION" | cut -d. -f1)" \
  -DVTX_VER_MINOR="$(echo "$VERSION" | cut -d. -f2)" -DVTX_VER_PATCH="$(echo "$VERSION" | cut -d. -f3)" \
  -DVTX_VER_BUILD=0 -O res "$W/ime/src/VietTelexTIP.rc" "$f/fwd.res"
# _load_config_used comes from the ARM64X-aware mingw-w64 CRT: without a load config
# the loader cannot see the EC (x64) view at all.
L=/opt/llvm-mingw/aarch64-w64-mingw32/lib
lld-link /nologo /dll /noentry /machine:arm64x \
  "/defarm64native:$W/ime/src/arm64x/arm64_exports.def" "/def:$W/ime/src/arm64x/x64_exports.def" \
  "$f/native.obj" "$f/ec.obj" "$f/fwd.res" "$L/libmingwex.a" "$L/libmingw32.a" /include:_load_config_used \
  "/out:$a/VietTelexTIP.dll"
# Prove both views: ARM64X format, native exports -> _arm64, EC exports -> _x64.
info="$(llvm-readobj --file-headers --coff-exports --coff-load-config "$a/VietTelexTIP.dll")"
echo "$info" | grep -q "Format: COFF-ARM64X" || { echo "forwarder is not ARM64X" >&2; exit 1; }
echo "$info" | grep -q "ForwardedTo: VietTelexTIP_arm64.DllGetClassObject" || { echo "no native forward" >&2; exit 1; }
echo "$info" | grep -q "ForwardedTo: VietTelexTIP_x64.DllGetClassObject" || { echo "no EC forward" >&2; exit 1; }
echo "$info" | grep -q "CHPEMetadataPointer: 0x[1-9A-Fa-f]" || { echo "no CHPE metadata" >&2; exit 1; }
echo "  built ARM64X forwarder (native -> VietTelexTIP_arm64.dll, x64 -> VietTelexTIP_x64.dll)"
