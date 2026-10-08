#!/bin/bash
# LLVM 15.0.7 for iOS (toolchains/llvm-ios-build), needed by build/dxmt-ios.
# Host llvm-tblgen first, then the iOS libraries; AddLLVM.cmake gets the iOS
# -dead_strip fix from build/dxmt-ios/README.md.
set -ex
T="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/toolchains"
cd $T
[ -d llvm-project ] || git clone --depth 1 --branch llvmorg-15.0.7 https://github.com/llvm/llvm-project.git llvm-project
sed -i '' 's/MATCHES "Darwin"/MATCHES "Darwin|iOS"/' llvm-project/llvm/cmake/modules/AddLLVM.cmake
grep -n 'Darwin|iOS' llvm-project/llvm/cmake/modules/AddLLVM.cmake
# host tblgen
cmake -S llvm-project/llvm -B llvm-host-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= -DLLVM_INCLUDE_TESTS=Off -DLLVM_ENABLE_ZLIB=Off
cmake --build llvm-host-build --target llvm-tblgen
# iOS libs
cmake -S llvm-project/llvm -B llvm-ios-build -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 -DCMAKE_BUILD_TYPE=Release -DLLVM_HOST_TRIPLE=arm64-apple-ios17.0 -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios17.0 -DLLVM_TARGET_ARCH=host -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= -DLLVM_BUILD_TOOLS=Off -DLLVM_BUILD_UTILS=Off -DLLVM_INCLUDE_TOOLS=Off -DLLVM_INCLUDE_TESTS=Off -DLLVM_INCLUDE_EXAMPLES=Off -DLLVM_INCLUDE_BENCHMARKS=Off -DLLVM_ENABLE_ZLIB=Off -DLLVM_ENABLE_TERMINFO=Off -DLLVM_TABLEGEN=$T/llvm-host-build/bin/llvm-tblgen
cmake --build llvm-ios-build
echo LLVM-IOS-DONE
