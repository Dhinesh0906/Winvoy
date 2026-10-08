#!/bin/bash
# Configure wine/build-macos (headers + host tools) for the ntdll/win32u/wineserver
# unix builds, then enable the GnuTLS paths the iOS crypto unixlibs need.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
mkdir -p "$R/wine/build-macos" && cd "$R/wine/build-macos"
[ -f Makefile ] || ../configure --disable-tests --without-x --without-freetype --enable-win64
make -j"$(sysctl -n hw.ncpu)" __tooldeps__
make -j"$(sysctl -n hw.ncpu)" -C include
C=include/config.h
sed -i '' 's|^/\* #undef HAVE_GNUTLS_CIPHER_INIT \*/|#define HAVE_GNUTLS_CIPHER_INIT 1|; s|^/\* #undef SONAME_LIBGNUTLS \*/|#define SONAME_LIBGNUTLS "libgnutls.dylib"|' "$C"
grep -n "HAVE_GNUTLS_CIPHER_INIT\|SONAME_LIBGNUTLS" "$C"
