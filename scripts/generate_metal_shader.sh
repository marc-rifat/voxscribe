#!/bin/bash
# whisper.cpp compiles the Metal shader at runtime, injecting preprocessor
# macros that depend on the GPU it finds (GGML_METAL_HAS_BF16, HAS_TENSOR --
# see ggml-metal-device.m). A shader precompiled by Xcode has neither macro,
# so the bf16/tensor kernels are compiled out and transcription silently
# returns garbage. So we ship the source and let whisper.cpp compile it.

set -e

METAL_DIR="${SRCROOT}/libs/whisper.cpp/ggml/src/ggml-metal"
COMMON_H="${SRCROOT}/libs/whisper.cpp/ggml/src/ggml-common.h"
RESOURCES="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

for required in "${METAL_DIR}/kernels/common.h" "${METAL_DIR}/ggml-metal-impl.h" "${COMMON_H}"; do
    if [ ! -f "$required" ]; then
        echo "error: missing Metal shader input: $required" >&2
        exit 1
    fi
done

rm -rf "${RESOURCES}/kernels"
mkdir -p "${RESOURCES}/kernels"

cp "${METAL_DIR}"/kernels/*.metal "${METAL_DIR}"/kernels/*.h "${RESOURCES}/kernels/"
cp "${METAL_DIR}/ggml-metal-impl.h" "${COMMON_H}" "${RESOURCES}/"

echo "Copied Metal kernel sources to: ${RESOURCES}/kernels"
