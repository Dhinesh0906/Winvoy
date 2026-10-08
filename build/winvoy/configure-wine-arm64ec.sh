#!/bin/bash
# Configure wine/build-arm64ec and build only what DXMT's PE build links against.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
mkdir -p "$R/wine/build-arm64ec" && cd "$R/wine/build-arm64ec"
[ -f Makefile ] || ../configure --enable-archs=arm64ec --without-x --disable-tests --enable-winegstreamer
make -j"$(sysctl -n hw.ncpu)" __tooldeps__ include
make -j"$(sysctl -n hw.ncpu)" dlls/ntdll/arm64ec-windows/libntdll.a dlls/dbghelp/arm64ec-windows/libdbghelp.a libs/winecrt0/arm64ec-windows/libwinecrt0.a
