#!/bin/bash
# build/wineserver/build.sh only patches an existing libwineserver.a; that base
# archive is not distributed. This compiles every stock wine/server/*.c that
# build.sh does not replace into the base archive it expects.
# Seed build/wineserver/obj/libwineserver.a from stock wine/server/*.c (skipping the files build.sh replaces).
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; B=$R/build/wineserver; W=$R/wine; O=$B/obj
SDK=$(xcrun --sdk iphoneos --show-sdk-path); mkdir -p $O
SKIP=" request main mach unicode fd process window user class region queue mapping winstation thread sock object async event semaphore handle inproc_sync "
FLAGS=(-arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2 -I$W/include -I$W/include/wine -I$W/build-macos/include -I$B -I$W/server -I$R/build/ntdll-unix/shims -I$R/build/madsync -DHAVE_LINUX_NTSYNC_H=1 -include $B/config_ios.h -include stdarg.h -include $B/unicode_fix.h -include $B/wineserver_ios_kill.h -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\" -D__WINESRC__ -DWINE_IOS=1 -Dmain=wineserver_main -Wno-implicit-function-declaration)
OBJS=()
for f in $W/server/*.c; do n=$(basename $f .c); case "$SKIP" in *" $n "*) continue;; esac
  if xcrun -sdk iphoneos clang "${FLAGS[@]}" -c $f -o $O/seed_$n.o 2>$O/seed_$n.err; then OBJS+=($O/seed_$n.o); echo "OK $n"; else echo "FAIL $n"; fi; done
# archive members must carry the original names so build.sh's 'ar d' matches
rm -rf $O/seedtmp; mkdir $O/seedtmp; for o in "${OBJS[@]}"; do cp $o $O/seedtmp/$(basename $o | sed 's/^seed_//'); done
rm -f $O/libwineserver.a; (cd $O/seedtmp && ar rcs ../libwineserver.a *.o)
ar t $O/libwineserver.a | wc -l
