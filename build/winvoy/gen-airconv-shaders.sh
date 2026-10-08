#!/bin/bash
# Generate DXMT's airconv shader headers into build/dxmt-ios/shader-headers.
# Xcode 27's Metal compiler adds a memory-flags argument to the internal atomic
# builtin used by air_tessellation.metal, so that file is compiled from a
# patched copy (the DXMT source is left as is).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$R/dxmt/src/airconv/shaders"; O="$R/build/dxmt-ios/shader-headers"; T="$(mktemp -d)"
mkdir -p "$O" && cd "$O"
for n in air_msad air_samplepos air_tessellation; do
  src="$S/$n.metal"
  if [ "$n" = air_tessellation ]; then
    sed 's/__METAL_MEMORY_SCOPE_THREADGROUP__);/__METAL_MEMORY_SCOPE_THREADGROUP__, __METAL_MEMORY_FLAGS_NONE__);/' "$src" > "$T/$n.metal"
    src="$T/$n.metal"
  fi
  xcrun -sdk macosx metal -std=metal3.1 --target=air64-apple-macos14.0 -I"$S" -o "$n.air" -c "$src"
  xxd -n "$n" -i "$n.air" "$n.h"
done
echo "airconv shader headers in $O"
