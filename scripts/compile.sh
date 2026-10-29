#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

DEVICE="${1:?Usage: compile.sh <device> <variant>}"
VARIANT="${2:?Usage: compile.sh <device> <variant>}"
DEVICE_JSON="devices/${DEVICE}.json"
OUT_DIR="out"
WORKDIR="$(pwd)"

DEFCONFIG=$(read_field defconfig)
KERNEL_ARCH=$(read_field arch)
AK3_REPO=$(read_field ak3_repo)
AK3_BRANCH=$(read_field ak3_branch)
KERNEL_NAME=$(read_field kernel_name)

: "${DEFCONFIG:?defconfig missing in $DEVICE_JSON}"
: "${AK3_REPO:?ak3_repo missing in $DEVICE_JSON}"
: "${AK3_BRANCH:?ak3_branch missing in $DEVICE_JSON}"
: "${KERNEL_NAME:?kernel_name missing in $DEVICE_JSON}"

log "Building $DEVICE ($VARIANT) — defconfig: $DEFCONFIG"

# AnyKernel3
AK3_DIR="${WORKDIR}/AnyKernel3"
rm -rf "$AK3_DIR"
git clone --depth 1 -b "$AK3_BRANCH" "$AK3_REPO" "$AK3_DIR"

# Base defconfig
mkdir -p "$OUT_DIR"
LLVM_TOOLS="LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip ld-name=lld EXTRAVERSION="
make O="$OUT_DIR" ARCH="$KERNEL_ARCH" $LLVM_TOOLS $DEFCONFIG

# Full kernel name control from builder
./scripts/config --file "${OUT_DIR}/.config" --set-str CONFIG_LOCALVERSION "-${KERNEL_NAME}-${VARIANT}"

# Generic insurance: disable git-dirty auto-suffix
export LOCALVERSION=
./scripts/config --file "${OUT_DIR}/.config" --disable CONFIG_LOCALVERSION_AUTO
./scripts/config --file "${OUT_DIR}/.config" --disable CONFIG_LOCALVERSION_SHA

# Merge config fragments written by variant.sh into out/.config
FRAGMENT_DIR="snowflake_fragments"
if [ -d "$FRAGMENT_DIR" ]; then
    for FRAGMENT in "$FRAGMENT_DIR"/*.config; do
        [ -s "$FRAGMENT" ] || continue
        log "Merging fragment: $FRAGMENT"
        ./scripts/config --file "${OUT_DIR}/.config" $(cat "$FRAGMENT")
    done
fi

# Resolve dependencies after all fragment toggles
make O="$OUT_DIR" ARCH="$KERNEL_ARCH" $LLVM_TOOLS olddefconfig

# A ksu build without a live CONFIG_KSU/SuSFS is a broken build — the kernel
# would flash and boot with no root at all, so fail here instead of packaging it.
if [ "$VARIANT" = "ksu" ]; then
    for OPT in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK CONFIG_KSU_SUSFS CONFIG_KSU_SUSFS_SUS_MAP; do
        grep -q "^${OPT}=y" "${OUT_DIR}/.config" \
            || die "${OPT} is not enabled in the final .config — KernelSU-Next/SuSFS config fragment did not take (olddefconfig dropped it). Check drivers/kernelsu/Kconfig and snowflake_fragments/."
    done
    log "KernelSU-Next + SuSFS config verified in out/.config"
fi

# Save final .config as a debug artifact
cp "${OUT_DIR}/.config" "${WORKDIR}/${DEVICE}-${VARIANT}-config"

# ccache
if command -v ccache >/dev/null 2>&1; then
    export CCACHE_DIR="${CCACHE_DIR:-${HOME}/.ccache}"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"
    export CCACHE_COMPRESS=1
    log "ccache enabled — dir: $CCACHE_DIR, max size: $CCACHE_MAXSIZE"
    CC_WRAPPED="ccache clang"
else
    warn "ccache not found on PATH — building without a compiler cache"
    CC_WRAPPED="clang"
fi

# KCFLAGS: legacy-kernel / modern-clang compatibility shims
export KCFLAGS="-O2 -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types -Wno-error=incompatible-function-pointer-types"

BUILD_LOG="${WORKDIR}/${DEVICE}-${VARIANT}-build.log"
log "Compiling (log: $BUILD_LOG)"
make -j"$(nproc)" O="$OUT_DIR" ARCH="$KERNEL_ARCH" CC="$CC_WRAPPED" $LLVM_TOOLS KCFLAGS="$KCFLAGS" 2>&1 | tee "$BUILD_LOG"

# Fail loudly if the kernel image was never produced, even if make "succeeded"
IMAGE_PATH="${OUT_DIR}/arch/${KERNEL_ARCH}/boot/Image.gz-dtb"
[ -f "$IMAGE_PATH" ] || IMAGE_PATH="${OUT_DIR}/arch/${KERNEL_ARCH}/boot/Image.gz"
[ -f "$IMAGE_PATH" ] || IMAGE_PATH="${OUT_DIR}/arch/${KERNEL_ARCH}/boot/Image"

if [ ! -f "$IMAGE_PATH" ]; then
    die "No kernel image found at expected paths under ${OUT_DIR}/arch/${KERNEL_ARCH}/boot/ — build did not actually produce output, check $BUILD_LOG"
fi
log "Kernel image: $IMAGE_PATH"

if [ "$VARIANT" = "ksu" ]; then
    # KernelSU-Next prints its tag/version from the driver's Kbuild.
    # grep -o emits "KernelSU-Next tag: <tag>" (3 fields), no leading "--".
    KSUN_TAG=$(grep -m1 -oE 'KernelSU-Next tag: [^ ]+' "$BUILD_LOG" | awk '{print $3}' || true)
    KSUN_VER=$(grep -m1 -oE 'KernelSU-Next version: [0-9]+' "$BUILD_LOG" | awk '{print $3}' || true)

    [ -n "$KSUN_TAG" ] || die "KSU build finished but no 'KernelSU-Next tag:' line was found in $BUILD_LOG — the driver's Kbuild did not run (drivers/kernelsu wiring broken?)"
    [ -n "$KSUN_VER" ] || warn "no 'KernelSU-Next version:' line in $BUILD_LOG — reporting the tag only"

    if [ -n "$KSUN_VER" ]; then
        echo "KernelSU-Next ${KSUN_TAG} (driver ${KSUN_VER})" > "${WORKDIR}/${DEVICE}-ksun-version.txt"
    else
        echo "KernelSU-Next ${KSUN_TAG}" > "${WORKDIR}/${DEVICE}-ksun-version.txt"
    fi

    # SuSFS version Kbuild read out of the patched include/linux/susfs.h
    grep -m1 -oE 'SUSFS_VERSION: [^ ]+' "$BUILD_LOG" | awk '{print $2}' > "${WORKDIR}/${DEVICE}-susfs-version.txt" || true
    [ -s "${WORKDIR}/${DEVICE}-susfs-version.txt" ] || die "KSU build finished but no 'SUSFS_VERSION:' line was found in $BUILD_LOG — SuSFS was not integrated into this build (expected '-- SUSFS_VERSION: ...' from the driver Kbuild)"

    # Only the official KernelSU-Next manager signature is baked into the driver.
    KSUN_MGR=$(grep -m1 -oE 'KernelSU-Next Manager package name: .*' "$BUILD_LOG" | sed 's/^.*package name: //' || true)
    echo "${KSUN_MGR:-KernelSU-Next Manager (official release)}" > "${WORKDIR}/${DEVICE}-ksun-managers.txt"
fi

cp "$IMAGE_PATH" "$AK3_DIR/"

# Auto-detect + package whatever boot-related artifacts
BOOT_DIR="${OUT_DIR}/arch/${KERNEL_ARCH}/boot"

for f in dtbo.img dtb.img; do
    if [ -f "${BOOT_DIR}/${f}" ]; then
        cp "${BOOT_DIR}/${f}" "$AK3_DIR/${f%.img}"
        log "${f} included (auto-detected)"
    else
        log "${f} not produced by this build, skipping (not an error)"
    fi
done

DATE_TAG=$(date +%Y%m%d-%H%M)
ZIP_NAME="snowflake-${DEVICE}-${VARIANT}-${DATE_TAG}.zip"

pushd "$AK3_DIR" >/dev/null
zip -r9 "${WORKDIR}/${ZIP_NAME}" . -x ".git/*" -x "*.zip"
popd >/dev/null

log "Packaged: ${ZIP_NAME}"
log "Debug artifacts: ${DEVICE}-${VARIANT}-build.log, ${DEVICE}-${VARIANT}-config"
log "compile.sh done"
