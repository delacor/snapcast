#!/usr/bin/env bash
# Build OpenSSL static libraries for Android from the official source tarball.
# Produces per-ABI installs consumed by package_openssl_aar.sh (CI) or
# referenced directly via -DOPENSSL_ROOT in a local Gradle/CMake build.
#
# Required env:
#   ANDROID_NDK_HOME  or  ANDROID_NDK_ROOT – path to the Android NDK
#
# Optional env:
#   OPENSSL_VERSION      – defaults to 3.4.1
#   OPENSSL_URL          – full download URL (overrides version-based URL)
#   OPENSSL_SRC_DIR      – where to unpack/reuse the source tree
#   OPENSSL_INSTALL_DIR  – root install prefix; per-ABI dirs created inside
#   ANDROID_API          – minimum API level, defaults to 21
#
# Usage (from snapcast repo root):
#   ANDROID_NDK_HOME=/path/to/ndk bash build_openssl_android.sh

set -euo pipefail

OPENSSL_VERSION="${OPENSSL_VERSION:-3.4.1}"
OPENSSL_URL="${OPENSSL_URL:-https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz}"
ANDROID_API="${ANDROID_API:-21}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSSL_INSTALL_DIR="${OPENSSL_INSTALL_DIR:-${SCRIPT_DIR}/build/openssl-install}"
OPENSSL_SRC_DIR="${OPENSSL_SRC_DIR:-${SCRIPT_DIR}/build/openssl-src}"

if [ -n "${ANDROID_NDK_HOME:-}" ]; then
    NDK_ROOT="${ANDROID_NDK_HOME}"
elif [ -n "${ANDROID_NDK_ROOT:-}" ]; then
    NDK_ROOT="${ANDROID_NDK_ROOT}"
else
    echo "ERROR: Set ANDROID_NDK_HOME or ANDROID_NDK_ROOT to your NDK path." >&2
    exit 1
fi

# ── helpers ──────────────────────────────────────────────────────────────────

build_abi() {
    local abi="$1"          # e.g. arm64-v8a
    local target="$2"       # OpenSSL Configure target, e.g. android-arm64
    local src="$3"
    local dest="$4"         # DESTDIR for this ABI

    echo "==> Building OpenSSL ${OPENSSL_VERSION} for ${abi} (${target}) ..."

    PREBUILT="$(ls -d "${NDK_ROOT}/toolchains/llvm/prebuilt/"* 2>/dev/null | head -1)"
    if [ -z "${PREBUILT}" ]; then
        echo "ERROR: Could not find NDK toolchains/llvm/prebuilt" >&2
        exit 1
    fi

    export ANDROID_NDK_ROOT="${NDK_ROOT}"
    export PATH="${PREBUILT}/bin:${PATH}"

    (
        cd "${src}"
        make clean 2>/dev/null || true
        ./Configure "${target}" \
            -D__ANDROID_API__="${ANDROID_API}" \
            --prefix=/usr/local \
            no-shared no-tests -fPIC
        make -j"$(nproc 2>/dev/null || echo 4)" build_libs
        make install_sw DESTDIR="${dest}"
        make clean 2>/dev/null || true
    )
}

# ── skip if already built ────────────────────────────────────────────────────

if [ -f "${OPENSSL_INSTALL_DIR}/arm64-v8a/usr/local/lib/libssl.a" ] && \
   [ -f "${OPENSSL_INSTALL_DIR}/armeabi-v7a/usr/local/lib/libssl.a" ] && \
   [ -f "${OPENSSL_INSTALL_DIR}/x86/usr/local/lib/libssl.a" ] && \
   [ -f "${OPENSSL_INSTALL_DIR}/x86_64/usr/local/lib/libssl.a" ]; then
    echo "OpenSSL already built for all ABIs at ${OPENSSL_INSTALL_DIR}"
    exit 0
fi

# ── download source ───────────────────────────────────────────────────────────

if [ ! -f "${OPENSSL_SRC_DIR}/Configure" ]; then
    echo "Downloading OpenSSL ${OPENSSL_VERSION} from ${OPENSSL_URL} ..."
    BUILD_PARENT="$(dirname "${OPENSSL_SRC_DIR}")"
    mkdir -p "${BUILD_PARENT}"
    (cd "${BUILD_PARENT}" && curl -fsSL "${OPENSSL_URL}" | tar xz)

    # The tarball expands to openssl-<version>/; rename to our fixed src dir
    EXTRACTED="$(ls -d "${BUILD_PARENT}/openssl-"* 2>/dev/null | head -1)"
    if [ -z "${EXTRACTED}" ] || [ ! -f "${EXTRACTED}/Configure" ]; then
        echo "ERROR: Could not find extracted OpenSSL source under ${BUILD_PARENT}" >&2
        exit 1
    fi
    rm -rf "${OPENSSL_SRC_DIR}"
    mv "${EXTRACTED}" "${OPENSSL_SRC_DIR}"
fi

mkdir -p "${OPENSSL_INSTALL_DIR}"

# ── build each ABI ───────────────────────────────────────────────────────────

build_abi "armeabi-v7a" "android-arm"    "${OPENSSL_SRC_DIR}" "${OPENSSL_INSTALL_DIR}/armeabi-v7a"
build_abi "arm64-v8a"   "android-arm64"  "${OPENSSL_SRC_DIR}" "${OPENSSL_INSTALL_DIR}/arm64-v8a"
build_abi "x86"         "android-x86"    "${OPENSSL_SRC_DIR}" "${OPENSSL_INSTALL_DIR}/x86"
build_abi "x86_64"      "android-x86_64" "${OPENSSL_SRC_DIR}" "${OPENSSL_INSTALL_DIR}/x86_64"

echo ""
echo "OpenSSL ${OPENSSL_VERSION} built and installed under ${OPENSSL_INSTALL_DIR}"
