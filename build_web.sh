#!/usr/bin/env bash
set -eu

# Point this to where you installed emscripten. Optional on systems that already
# have `emcc` in the path.
EMSCRIPTEN_SDK_DIR="$HOME/repos/emsdk"
OUT_DIR="build/web"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

# Note RAYLIB_WASM_LIB=env.o -- env.o is an internal WASM object file. You can
# see how RAYLIB_WASM_LIB is used inside <odin>/vendor/raylib/raylib.odin.
#
# The emcc call will be fed the actual raylib library file. That stuff will end
# up in env.o
#
# Note that there is a rayGUI equivalent: -define:RAYGUI_WASM_LIB=env.o
odin build src/main_web -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -define:RAYGUI_WASM_LIB=env.o -vet -strict-style -out:$OUT_DIR/game.wasm.o

ODIN_PATH=$(odin root)

cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

files="$OUT_DIR/game.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a ${ODIN_PATH}/vendor/raylib/wasm/libraygui.a"

# index_template.html contains the javascript code that calls the procedures in
# src/main_web/main_web.odin
flags="-sUSE_GLFW=3 -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sASSERTIONS --shell-file src/main_web/index_template.html --preload-file assets"

# address issues with wasm build
# memory_flags="-sEXPORTED_RUNTIME_METHODS=HEAPF32 -sINITIAL_MEMORY=67108864 -sALLOW_MEMORY_GROWTH"
# memory_flags="-sINITIAL_MEMORY=33554432"
# extra_flags="-sINITIAL_MEMORY=67108864 -sSTACK_SIZE=1048576 -sUSE_GLFW=3 -sASYNCIFY -DPLATFORM_WEB -sALLOW_MEMORY_GROWTH"
extra_flags="-sEXPORTED_RUNTIME_METHODS=HEAPF32 -sSTACK_SIZE=1048576 -sALLOW_MEMORY_GROWTH"

# For debugging: Add `-g` to `emcc` (gives better error callstack in chrome)
emcc -o $OUT_DIR/index.html $files $flags -g $extra_flags

rm $OUT_DIR/game.wasm.o

echo "Web build created in ${OUT_DIR}"
