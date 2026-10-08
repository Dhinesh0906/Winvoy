#!/bin/bash
# Merge DXMT's unix objects with the LLVM iOS libraries into the archive the app links.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$R/build/dxmt-ios"
xcrun -sdk iphoneos libtool -static -o libdxmt_combined.a obj/*.o "$R/toolchains/llvm-ios-build/lib/"*.a 2>&1 | grep -v "has no symbols" || true
cp libdxmt_combined.a "$R/app/Madeira/libdxmt_combined.a"
ls -l "$R/app/Madeira/libdxmt_combined.a"
