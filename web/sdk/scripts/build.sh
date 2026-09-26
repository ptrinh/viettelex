#!/usr/bin/env bash
# Build dist/viettelex-core.js: the C++ engine (windows/engine, 100% golden parity with
# TelexCore Swift) compiled to WebAssembly and inlined into one ES module (SINGLE_FILE).
# Needs Docker; emscripten runs only inside the container.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(cd ../.. && pwd)"
IMAGE="${EMSDK_IMAGE:-emscripten/emsdk:latest}"
FUNCS='["_vtx_create","_vtx_destroy","_vtx_set_flags","_vtx_get_flags","_vtx_feed","_vtx_backspace","_vtx_commit_boundary","_vtx_commit_text","_vtx_peek_commit_text","_vtx_composed","_vtx_raw_keystrokes","_vtx_is_empty","_vtx_is_overflowed","_vtx_reset","_vtx_reset_context","_vtx_previous_word_english","_vtx_can_reopen_last_commit","_vtx_reopen_last_commit","_vtx_forget_last_commit","_vtx_seed","_malloc","_free"]'
docker run --rm -v "$ROOT":/src -w /src "$IMAGE" em++ \
  windows/engine/src/telex_engine.cpp windows/engine/src/syllable_validator.cpp windows/engine/src/vtx_engine.cpp \
  -I windows/engine/include -I windows/engine/src -std=c++17 -O3 -flto \
  -fno-exceptions -fno-rtti -DNDEBUG \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createVietTelexWasm -sSINGLE_FILE=1 \
  -sENVIRONMENT=web,worker,node -sFILESYSTEM=0 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=1MB -sSTACK_SIZE=64KB \
  -sEXPORTED_FUNCTIONS="$FUNCS" -sEXPORTED_RUNTIME_METHODS='["HEAPU16","HEAP32"]' \
  -o web/sdk/dist/viettelex-wasm.mjs
ls -la dist/viettelex-wasm.mjs
cp src/viettelex.mjs dist/viettelex.mjs
