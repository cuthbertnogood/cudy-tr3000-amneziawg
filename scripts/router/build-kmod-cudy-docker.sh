#!/usr/bin/env bash
# Сборка amneziawg.ko для Cudy TR3000 v1 (OpenWrt 24.10.x mediatek/filogic) на Mac через Docker.
# Результат: ./out/amneziawg-cudy.ko
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${ROOT}/out/amneziawg-cudy.ko"
AWG_MODULE_TAG="${AWG_MODULE_TAG:-v3.1.20260812}"
OPENWRT_RELEASE="${OPENWRT_RELEASE:-24.10.5}"
SDK_URL="${SDK_URL:-https://downloads.openwrt.org/releases/${OPENWRT_RELEASE}/targets/mediatek/filogic/openwrt-sdk-${OPENWRT_RELEASE}-mediatek-filogic_gcc-13.3.0_musl.Linux-x86_64.tar.zst}"

if ! docker info >/dev/null 2>&1; then
  echo "error: docker daemon недоступен — запустите Docker Desktop" >&2
  exit 1
fi

mkdir -p "${ROOT}/out"

SDK_TAR="${SDK_TAR:-/tmp/sdk-filogic-${OPENWRT_RELEASE}.tar.zst}"
if [ ! -s "${SDK_TAR}" ]; then
  echo "Скачиваем SDK ${OPENWRT_RELEASE}..."
  curl -fsSL -o "${SDK_TAR}" "${SDK_URL}"
fi

docker run --rm --platform linux/amd64 \
  -v "${ROOT}:/work" \
  -v "${SDK_TAR}:/sdk.tar.zst:ro" \
  -e AWG_MODULE_TAG="${AWG_MODULE_TAG}" \
  ubuntu:24.04 bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq git zstd ca-certificates build-essential
    WORK=/tmp/awg-build
    rm -rf "$WORK"
    mkdir -p "$WORK"
    cd "$WORK"
    mkdir -p openwrt-sdk
    tar --zstd -xf /sdk.tar.zst -C openwrt-sdk --strip-components=1
    LINUX_DIR=$(find openwrt-sdk/build_dir -type d -name "linux-6.*" | head -1)
    test -f "${LINUX_DIR}/Makefile"
    GCC=$(find "${WORK}/openwrt-sdk/staging_dir" -type f -name "aarch64-openwrt-linux-musl-gcc" | head -1)
    test -n "${GCC}"
    CROSS="$(dirname "${GCC}")/aarch64-openwrt-linux-musl-"
    export PATH="$(dirname "${GCC}"):${PATH}"
    echo "gcc=${GCC}"
    echo "linux=${LINUX_DIR}"
    git clone --depth 1 --branch "${AWG_MODULE_TAG}" \
      https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git
    SRC="${WORK}/amneziawg-linux-kernel-module/src"
    rm -rf "${SRC}/kernel"
    mkdir -p "${SRC}/kernel"
    cp -a "${LINUX_DIR}/." "${SRC}/kernel/"
    make -C "${LINUX_DIR}" ARCH=arm64 CROSS_COMPILE="${CROSS}" M="${SRC}" modules
    install -m 644 "${SRC}/amneziawg.ko" /work/out/amneziawg-cudy.ko
    strings /work/out/amneziawg-cudy.ko | grep vermagic || true
  '

echo "Built: ${OUT}"
ls -la "${OUT}"
