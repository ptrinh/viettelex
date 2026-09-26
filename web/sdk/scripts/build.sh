#!/usr/bin/env bash
# Build the 4 WebAssembly variants of the C++ engine (windows/engine, 100% golden parity with
# TelexCore Swift) into dist/, plus the JS entry points:
#   viettelex-wasm.mjs            full, WASM inlined (SINGLE_FILE, base64)   ← @viettelex/core
#   viettelex-lite-wasm.mjs       lite (-DVTX_NO_ENGLISH_TABLES), inlined    ← @viettelex/core/lite
#   viettelex-core.mjs + .wasm    full, separate .wasm (wasmUrl option)      ← @viettelex/core/external
#   viettelex-lite-core.mjs+.wasm lite, separate .wasm                       ← @viettelex/core/lite/external
# Needs Docker; emscripten runs only inside the container (nothing installed on the host).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(cd ../.. && pwd)"
IMAGE="${EMSDK_IMAGE:-emscripten/emsdk:latest}"
FUNCS='["_vtx_create","_vtx_destroy","_vtx_set_flags","_vtx_get_flags","_vtx_feed","_vtx_backspace","_vtx_commit_boundary","_vtx_commit_text","_vtx_peek_commit_text","_vtx_composed","_vtx_raw_keystrokes","_vtx_is_empty","_vtx_is_overflowed","_vtx_reset","_vtx_reset_context","_vtx_previous_word_english","_vtx_can_reopen_last_commit","_vtx_reopen_last_commit","_vtx_forget_last_commit","_vtx_seed","_malloc","_free"]'
mkdir -p dist
rm -f dist/viettelex*.mjs dist/viettelex*.wasm

docker run --rm -v "$ROOT":/src -w /src -e FUNCS="$FUNCS" "$IMAGE" bash -euc '
  SRCS="windows/engine/src/telex_engine.cpp windows/engine/src/syllable_validator.cpp windows/engine/src/vtx_engine.cpp"
  COMMON="-I windows/engine/include -I windows/engine/src -std=c++17 -Oz -flto --closure 1
    -fno-exceptions -fno-rtti -DNDEBUG -sMALLOC=emmalloc
    -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createVietTelexWasm
    -sENVIRONMENT=web,worker,node -sFILESYSTEM=0 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=1MB -sSTACK_SIZE=64KB
    -sINCOMING_MODULE_JS_API=[locateFile,wasmBinary]
    -sEXPORTED_FUNCTIONS=$FUNCS -sEXPORTED_RUNTIME_METHODS=[HEAPU16,HEAP32]"
  build() { # $1 = output, $2 = SINGLE_FILE, $3 = extra defines
    echo "em++ -> $1"
    ENC=""; [ "$2" = 1 ] && ENC="-sSINGLE_FILE_BINARY_ENCODE=0"   # base64: safe whatever charset the page serves
    em++ $SRCS $COMMON -sSINGLE_FILE=$2 $ENC $3 -o web/sdk/dist/$1
  }
  build viettelex-wasm.mjs 1 ""
  build viettelex-lite-wasm.mjs 1 -DVTX_NO_ENGLISH_TABLES
  build viettelex-core.mjs 0 ""
  build viettelex-lite-core.mjs 0 -DVTX_NO_ENGLISH_TABLES
'
cp src/core.mjs src/viettelex.mjs src/viettelex-lite.mjs src/viettelex-external.mjs src/viettelex-lite-external.mjs dist/

echo; printf '%-28s %9s %9s\n' file raw gzip-9
for f in dist/*.mjs dist/*.wasm; do
  printf '%-28s %9d %9d\n' "${f#dist/}" "$(wc -c <"$f")" "$(gzip -9c "$f" | wc -c)"
done
