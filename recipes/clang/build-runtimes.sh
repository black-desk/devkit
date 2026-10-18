#!/usr/bin/env bash
# Sourced by build.sh after installing LLVM/Clang; shares its toolchain flags.
# Compiler-rt probes add -nodefaultlibs/-Werror. Scope unused-argument handling
# to our driver configuration so those probes still diagnose their own flags.
RUNTIME_C_FLAGS="--start-no-unused-arguments ${COMMON_FLAGS} --end-no-unused-arguments"
RUNTIME_CXX_FLAGS="--start-no-unused-arguments ${CXX_FLAGS} --end-no-unused-arguments"
RUNTIME_LINK_FLAGS="--start-no-unused-arguments ${LINK_FLAGS} --end-no-unused-arguments"
# The private fuzzer libc++ supplies its own C++ headers. In particular, do
# not inherit the recipe's clang.cfg, which also adds installed libc++ headers.
PRIVATE_LIBCXX_FLAGS="--start-no-unused-arguments --no-default-config --sysroot=${SYSROOT} --gcc-toolchain=${PREFIX}/lib/devkit/share/devkit/no-gcc --rtlib=compiler-rt --end-no-unused-arguments -O2 -fPIC"
cmake -S "${SRC_DIR}/compiler-rt" -B runtime-build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN/..' \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_ASM_COMPILER="${CC}" \
  -DCMAKE_C_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_ASM_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_AR="${BUILD_PREFIX}/bin/llvm-ar" -DCMAKE_RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib" \
  -DCMAKE_NM="${BUILD_PREFIX}/bin/llvm-nm" \
  -DCMAKE_OBJCOPY="${BUILD_PREFIX}/bin/llvm-objcopy" \
  -DCMAKE_LINKER="${BUILD_PREFIX}/bin/ld.lld" \
  -DCMAKE_C_FLAGS="${RUNTIME_C_FLAGS}" -DCMAKE_CXX_FLAGS="${RUNTIME_CXX_FLAGS}" \
  -DCMAKE_ASM_FLAGS="${RUNTIME_C_FLAGS}" \
  -DCMAKE_EXE_LINKER_FLAGS="${RUNTIME_LINK_FLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${RUNTIME_LINK_FLAGS}" -DCMAKE_MODULE_LINKER_FLAGS="${RUNTIME_LINK_FLAGS}" \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DLLVM_CMAKE_DIR="${PREFIX}/lib/devkit/lib/cmake/llvm" \
  -DPython3_EXECUTABLE="$(command -v python3)" \
  -DCOMPILER_RT_LIBCXX_C_FLAGS="${PRIVATE_LIBCXX_FLAGS}" \
  -DCOMPILER_RT_LIBCXX_CXX_FLAGS="${PRIVATE_LIBCXX_FLAGS}" \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
  -DCOMPILER_RT_BUILD_BUILTINS=OFF \
  -DCOMPILER_RT_BUILD_SANITIZERS=ON -DCOMPILER_RT_BUILD_XRAY=ON \
  -DCOMPILER_RT_BUILD_LIBFUZZER=ON -DCOMPILER_RT_BUILD_PROFILE=ON \
  -DCOMPILER_RT_BUILD_ORC=ON -DCOMPILER_RT_BUILD_MEMPROF=ON \
  -DCOMPILER_RT_BUILD_CTX_PROFILE=ON -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DSANITIZER_CXX_ABI=libcxxabi \
  -DCOMPILER_RT_INSTALL_LIBRARY_DIR="${PREFIX}/lib/devkit/lib/linux" \
  -DCOMPILER_RT_INSTALL_INCLUDE_DIR="${PREFIX}/lib/devkit/lib/clang/23/include" \
  -DCOMPILER_RT_INSTALL_DATA_DIR="${PREFIX}/lib/devkit/lib/clang/23/share" \
  -DCOMPILER_RT_INSTALL_BINARY_DIR="${PREFIX}/lib/devkit/libexec/compiler-rt/bin"
cmake --build runtime-build --parallel "${JOBS}"
cmake --install runtime-build
# llvm-libgcc owns builtins and CRT; do not duplicate those files here.
for runtime in asan ubsan_standalone tsan profile fuzzer xray; do
  test -f "${PREFIX}/lib/devkit/lib/linux/libclang_rt.${runtime}-x86_64.a"
done
test -f "${PREFIX}/lib/devkit/lib/linux/liborc_rt-x86_64.a"
