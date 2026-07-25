#!/bin/bash
# Generates a self-contained ggml-metal.metal into the app bundle's Resources.
#
# whisper.cpp compiles the Metal shader at runtime, injecting preprocessor
# macros that depend on the GPU it finds (GGML_METAL_HAS_BF16, HAS_TENSOR --
# see ggml-metal-device.m). A shader precompiled by Xcode has neither macro,
# so the bf16/tensor kernels are compiled out and transcription silently
# returns garbage. So we ship the source and let whisper.cpp compile it.
#
# The shader's #include directives resolve relative to the working directory,
# which is not the bundle, so the headers are inlined here instead. This
# mirrors the sed substitution in ggml/src/ggml-metal/CMakeLists.txt.

set -e
set -o pipefail

METAL_DIR="${SRCROOT}/libs/whisper.cpp/ggml/src/ggml-metal"
COMMON_H="${SRCROOT}/libs/whisper.cpp/ggml/src/ggml-common.h"
RESOURCES="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

# sed's `r` silently inserts nothing when its file is missing, while the paired
# `d` still deletes the #include -- which would ship a shader stripped of its
# type definitions and fail only at runtime. Upstream moves these files between
# releases, so check them rather than trust the paths.
for required in "${METAL_DIR}/ggml-metal.metal" "${METAL_DIR}/ggml-metal-impl.h" "${COMMON_H}"; do
    if [ ! -f "$required" ]; then
        echo "error: missing Metal shader input: $required" >&2
        exit 1
    fi
done

mkdir -p "$RESOURCES"

sed -e "/#include \"ggml-common.h\"/r ${COMMON_H}" \
    -e "/#include \"ggml-common.h\"/d" \
    "${METAL_DIR}/ggml-metal.metal" \
  | sed -e "/#include \"ggml-metal-impl.h\"/r ${METAL_DIR}/ggml-metal-impl.h" \
        -e "/#include \"ggml-metal-impl.h\"/d" \
  > "${RESOURCES}/ggml-metal.metal"

echo "Generated self-contained shader: ${RESOURCES}/ggml-metal.metal"
