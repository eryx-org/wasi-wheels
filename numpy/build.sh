#!/bin/bash

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ARCH_TRIPLET=_wasi_wasm32-wasi

# Apply source-level patches to the numpy submodule and its vendored meson.
# These are idempotent: skipped if already applied.
apply_patch() {
  local repo=$1
  local patch=$2
  if ! (cd "$repo" && git apply --reverse --check "$patch" 2>/dev/null); then
    (cd "$repo" && git apply "$patch")
  fi
}
apply_patch "${HERE}/src" "${HERE}/patches/0001-temp_elide-skip-wasi.patch"
apply_patch "${HERE}/src/vendored-meson/meson" "${HERE}/patches/0002-meson-disable-group-flags-on-wasi.patch"

if [ ! -e venv ]; then
  python3.14 -m venv venv
fi

. venv/bin/activate

export CC="${WASI_SDK_PATH}/bin/clang"
export CXX="${WASI_SDK_PATH}/bin/clang++"
export AR="${WASI_SDK_PATH}/bin/ar"
export RANLIB=true
export LDSHARED=${CC}

export CFLAGS="--target=wasm32-wasip2 -fPIC -I${CROSS_PREFIX}/include/python3.14 -D__EMSCRIPTEN__=1 -DNPY_NO_SIGNAL"
export CXXFLAGS="--target=wasm32-wasip2 -fPIC -I${CROSS_PREFIX}/include/python3.14"

# Build stubs for the Itanium C++ exception ABI that wasi-sdk's libc++abi
# lacks on wasm32-wasip2. Link them into every shared object we produce so
# the component linker sees no unresolved imports. Code paths that actually
# throw (numpy.fft pocketfft error cases, unique.cpp) will trap at runtime.
CXA_STUB_OBJ="${HERE}/cxa_stubs.o"
"${CC}" --target=wasm32-wasip2 -fPIC -c "${HERE}/cxa_stubs.c" -o "${CXA_STUB_OBJ}"

export LDFLAGS="--target=wasm32-wasip2 -shared ${CROSS_PREFIX}/lib/libpython3.14.so ${CXA_STUB_OBJ}"

# wasi-sdk's clang defaults to `wasm-component-ld` for wasip2, which meson's
# linker probe doesn't recognise. Force it to use lld's wasm driver instead.
export CC_LD=lld
export CXX_LD=lld

# wasm-ld does not understand --start-group/--end-group. The patch above adds
# an env-gated opt-out to meson's vendored clike.py.
export WASI_WHEELS_NO_LINK_GROUPS=1

export _PYTHON_SYSCONFIGDATA_NAME=_sysconfigdata_${ARCH_TRIPLET}
export PYTHONPATH=$CROSS_PREFIX/lib/python3.14

export PKG_CONFIG_LIBDIR=${CROSS_PREFIX}/lib/pkgconfig
export PKG_CONFIG_PATH=${CROSS_PREFIX}/lib/pkgconfig

export NPY_DISABLE_SVML=1
export NPY_BLAS_ORDER=
export NPY_LAPACK_ORDER=

pip install --upgrade pip
pip install "meson-python>=0.18.0" "cython>=3.0.6" "ninja" "pyproject-metadata" "setuptools>=61"

cd src

cat > build.meson.cross <<EOF
[binaries]
pkgconfig = 'pkg-config'

[properties]
needs_exe_wrapper = true
skip_sanity_check = true
longdouble_format = 'IEEE_QUAD_LE'

[host_machine]
system = 'wasi'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'
EOF

rm -rf build wheels
mkdir -p wheels

CROSS_FILE=$(pwd)/build.meson.cross

pip wheel . \
  -w wheels \
  -v \
  --no-build-isolation \
  --no-deps \
  -Csetup-args="--cross-file=${CROSS_FILE}" \
  -Csetup-args="-Dallow-noblas=true" \
  -Csetup-args="-Ddisable-optimization=true"

# Unpack the wheel into the layout expected by the Makefile (build/lib.*/numpy).
WHEEL=$(ls wheels/numpy-*.whl | head -1)
DEST="build/lib.wasi-wasm32-3.14"
rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q -o "$WHEEL" -d "$DEST"
