#!/usr/bin/env bash
set -euo pipefail

# scripts/ksu.sh — integrate KernelSU-Next (non-GKI "legacy" line, SuSFS built
# in) and the SuSFS kernel-side patches into the kernel source tree.
#
# Steps, in order:
#   1. clone KernelSU-Next, pinned (no setup.sh — upstream setup.sh hardcodes
#      the KernelSU-Next/KernelSU-Next repo, we need sidex15's legacy-susfs-v2)
#   2. hook the driver into drivers/{Makefile,Kconfig}, exactly like
#      kernel/setup.sh does (symlink drivers/kernelsu -> <clone>/kernel)
#   3. apply the SuSFS 4.14 kernel patch (fs/, include/, kernel/)
#   4. apply the SuSFS inline hook patches (wire ksu_handle_* into the kernel)
#   5. write the config fragment that compile.sh merges into out/.config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

DEVICE="${1:?Usage: ksu.sh <device>}"
DEVICE_JSON="devices/${DEVICE}.json"

: "${KSU_REPO_URL:?KSU_REPO_URL not set — source config.env first}"
: "${KSU_REPO_PIN:?KSU_REPO_PIN not set — source config.env first}"
: "${KSU_REPO_TAG:?KSU_REPO_TAG not set — source config.env first}"
: "${SUSFS_REPO_URL:?SUSFS_REPO_URL not set — source config.env first}"
: "${SUSFS_REPO_PIN:?SUSFS_REPO_PIN not set — source config.env first}"

KERNEL_VERSION=$(read_field kernel_version)
[ -n "$KERNEL_VERSION" ] || die "kernel_version missing in $DEVICE_JSON"

WORKDIR="$(pwd)"
KSU_SRC="${WORKDIR}/.snowflake_deps/KernelSU-Next"
SUSFS_SRC="${WORKDIR}/.snowflake_deps/susfs"
DRIVER_DIR="${WORKDIR}/drivers"
DRIVER_MAKEFILE="${DRIVER_DIR}/Makefile"
DRIVER_KCONFIG="${DRIVER_DIR}/Kconfig"

[ -d "$DRIVER_DIR" ] || die "no drivers/ directory in $(pwd) — run from the kernel source root"
[ -f "$DRIVER_MAKEFILE" ] && [ -f "$DRIVER_KCONFIG" ] || die "drivers/Makefile or drivers/Kconfig missing"

# ---------------------------------------------------------------- 1. sources
mkdir -p "$(dirname "$KSU_SRC")"
rm -rf "$KSU_SRC"

# Not shallow: kernel/Kbuild derives the reported driver version and tag from
# `git rev-list --count` / `git describe --tags` in this clone, and a shallow
# clone reports a bogus count and no tag. Blobless keeps it small while leaving
# full commit/tag history in place (and no .git/shallow, so Kbuild never tries
# to `git fetch --unshallow` mid-build).
log "Cloning KernelSU-Next (non-GKI + SuSFS, pin ${KSU_REPO_TAG})"
git clone --filter=blob:none --no-checkout "$KSU_REPO_URL" "$KSU_SRC"
git -C "$KSU_SRC" checkout --quiet "$KSU_REPO_PIN"

KSU_HEAD=$(git -C "$KSU_SRC" rev-parse HEAD)
[ "$KSU_HEAD" = "$KSU_REPO_PIN" ] || die "KernelSU-Next is at $KSU_HEAD, not the pinned $KSU_REPO_PIN"

log "Cloning SuSFS source (pinned to ${SUSFS_REPO_PIN})"
rm -rf "$SUSFS_SRC"
git init --quiet "$SUSFS_SRC"
git -C "$SUSFS_SRC" remote add origin "$SUSFS_REPO_URL"
git -C "$SUSFS_SRC" fetch --quiet --depth 1 origin "$SUSFS_REPO_PIN"
git -C "$SUSFS_SRC" checkout --quiet FETCH_HEAD

# -------------------------------------------------- 2. hook driver into build
# Same three edits as KernelSU-Next's kernel/setup.sh, but pointed at our pin.
rm -rf "${DRIVER_DIR}/kernelsu"
ln -sfn "$(realpath --relative-to="$DRIVER_DIR" "${KSU_SRC}/kernel")" "${DRIVER_DIR}/kernelsu"
log "drivers/kernelsu -> $(readlink "${DRIVER_DIR}/kernelsu")"

grep -q "kernelsu" "$DRIVER_MAKEFILE" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_MAKEFILE"
grep -q 'source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG" \
    || sed -i '0,/endmenu/s//source "drivers\/kernelsu\/Kconfig"\nendmenu/' "$DRIVER_KCONFIG"

grep -q "kernelsu" "$DRIVER_MAKEFILE" || die "failed to hook drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG" || die "failed to hook drivers/Kconfig"

[ -f "${DRIVER_DIR}/kernelsu/Kconfig" ] || die "drivers/kernelsu/Kconfig not reachable through the symlink"
grep -q "config KSU_SUSFS" "${DRIVER_DIR}/kernelsu/Kconfig" \
    || die "pinned KernelSU-Next (${KSU_REPO_TAG}) does not carry SuSFS in kernel/Kconfig — wrong version for a SuSFS build, check KSU_REPO_TAG/KSU_REPO_PIN in config.env"

# ------------------------------------------------- 3. SuSFS kernel-side patch
FRAGMENT_DIR="snowflake_fragments"
FRAGMENT_FILE="${FRAGMENT_DIR}/kernelsu.config"
mkdir -p "$FRAGMENT_DIR"
: > "$FRAGMENT_FILE"

if grep -q "CONFIG_KSU_SUSFS" "fs/namespace.c" 2>/dev/null; then
    log "SuSFS already patched in this tree, skipping patch step"
else
    SUSFS_PATCH_FILE="${SUSFS_SRC}/Patches/Patch/susfs_patch_to_${KERNEL_VERSION}.patch"

    if [ ! -f "$SUSFS_PATCH_FILE" ]; then
        die "$SUSFS_PATCH_FILE not found in pinned SuSFS source — check that susfs_patch_to_${KERNEL_VERSION}.patch exists at this pinned commit."
    fi

    log "Applying SuSFS kernel patch for kernel $KERNEL_VERSION"
    set +e
    patch -p1 --fuzz=3 < "$SUSFS_PATCH_FILE"
    PATCH_RC=$?
    set -e
    if [ "$PATCH_RC" -gt 1 ]; then
        die "patch exited with code $PATCH_RC — not a hunk rejection but a fatal patch error (malformed patch, unreadable target file). Check $SUSFS_PATCH_FILE."
    fi

    # A reject is ignored only if it is whitespace-only
    ws_only() {
        awk '
            /^--- / || /^\+\+\+ / || /^@@/ { next }
            /^-/ { s = substr($0, 2); gsub(/[[:space:]]/, "", s); m[++nm] = s; next }
            /^\+/ { s = substr($0, 2); gsub(/[[:space:]]/, "", s); p[++np] = s; next }
            END {
                if (nm == 0 || nm != np) exit 1
                for (i = 1; i <= nm; i++) if (m[i] != p[i]) exit 1
            }' "$1"
    }

    REAL_REJ=()
    while IFS= read -r -d '' rej; do
        if ws_only "$rej"; then
            log "Whitespace-only reject ignored: $rej"
            rm -f -- "$rej"
        else
            REAL_REJ+=("$rej")
        fi
    done < <(find . -path ./.snowflake_deps -prune -o -name '*.rej' -print0 2>/dev/null)

    if [ "${#REAL_REJ[@]}" -gt 0 ]; then
        warn "SuSFS patch produced real rejected hunks:"
        for r in "${REAL_REJ[@]}"; do warn "  $r"; done
        die "These must be resolved manually against this kernel tree before a KSU build can be trusted."
    fi
    log "SuSFS patch applied cleanly (no real rejects)"
fi

[ -f "fs/susfs.c" ] || die "fs/susfs.c missing after the SuSFS patch step"
[ -f "include/linux/susfs.h" ] || die "include/linux/susfs.h missing after the SuSFS patch step"

# -------------------------------------------------- 4. SuSFS inline hooks
# Wires ksu_handle_* (KernelSU-Next's non-kprobe entry points) and the SuSFS
# call sites into fs/, kernel/ and security/. Without this the kernel compiles
# but SuSFS/KSU have nothing to hook on a 4.14 kernel with CONFIG_KPROBES=n.
if grep -q "ksu_handle_execveat" "fs/exec.c" 2>/dev/null; then
    log "SuSFS inline hooks already present, skipping hook step"
else
    log "Applying SuSFS inline hook patches"
    HOOK_LOG="${WORKDIR}/${DEVICE}-susfs-hook.log"
    bash "${SUSFS_SRC}/Patches/susfs_inline_hook_patches.sh" | tee "$HOOK_LOG"
fi

# The SuSFS version file is written later by compile.sh, out of the driver
# Kbuild's `-- SUSFS_VERSION:` line — that proves both the kernel-side patch and
# the KernelSU-Next driver saw SuSFS, which a script echo would not.

# --------------------------------------------- KernelSU-Next ABI reconciliation
# susfs_inline_hook_patches.sh also targets other non-GKI KernelSU forks, so
# four of its injections do not exist in KernelSU-Next's driver:
#   * ksu_is_init_rc_hook_enabled / ksu_is_input_hook_enabled — foreign static
#     keys; the driver exports its own gates: ksu_init_rc_hook, ksu_input_hook.
#   * ksu_handle_vfs_fstat, ksu_handle_post_execveat_sucompat — helpers the
#     driver simply does not have (su-compat runs before exec only).
# Re-point the two gates at the driver's flags and drop the two calls, keeping
# every hook that KernelSU-Next does export. Inputs are pinned in config.env,
# and the assertions below fail the build if any of it drifts.
log "Reconciling inline hooks with the KernelSU-Next driver ABI"

# fs/read_write.c — keep the init_rc read proxy, gate it on the driver's flag
sed -i 's|^extern struct static_key_true ksu_is_init_rc_hook_enabled;$|extern bool ksu_init_rc_hook;|' fs/read_write.c
sed -i 's|static_branch_unlikely(&ksu_is_init_rc_hook_enabled)|ksu_init_rc_hook|' fs/read_write.c

# fs/stat.c — no vfs_fstat size-spoof helper in KernelSU-Next, drop the call
sed -i '/^extern struct static_key_true ksu_is_init_rc_hook_enabled;$/d' fs/stat.c
sed -i '/^extern void ksu_handle_vfs_fstat(int fd, loff_t \*kstat_size_ptr);$/d' fs/stat.c
sed -i '/if (static_branch_unlikely(&ksu_is_init_rc_hook_enabled))/,+1d' fs/stat.c

# drivers/input/input.c — keep the volume-key input hook, gate it on the driver's flag
sed -i 's|^extern struct static_key_true ksu_is_input_hook_enabled;$|extern bool ksu_input_hook;|' drivers/input/input.c
sed -i 's|static_branch_unlikely(&ksu_is_input_hook_enabled)|ksu_input_hook|' drivers/input/input.c

# fs/exec.c — no post-exec sucompat hook; the pre-exec hook already handles su
sed -i 's|(void)ksu_handle_post_execveat_sucompat(.*|(void)0; /* KernelSU-Next: no post-exec sucompat hook, the pre-exec hook handles su */|' fs/exec.c
sed -i '/^extern int ksu_handle_post_execveat_sucompat(/,+1d' fs/exec.c

# Nothing foreign may survive, and the hooks that matter must still be there.
FOREIGN=$(grep -rn --include='*.c' --include='*.h' \
    -e 'ksu_is_init_rc_hook_enabled' -e 'ksu_is_input_hook_enabled' \
    -e 'ksu_handle_vfs_fstat' -e 'ksu_handle_post_execveat_sucompat' \
    fs drivers kernel security mm include 2>/dev/null || true)
[ -z "$FOREIGN" ] || die "KernelSU-Next ABI reconciliation incomplete, still referenced:
${FOREIGN}"
grep -q 'ksu_init_rc_hook' fs/read_write.c        || die "init_rc read hook was lost during ABI reconciliation"
grep -q 'ksu_input_hook' drivers/input/input.c    || die "input hook was lost during ABI reconciliation"
log "Inline hooks now match the KernelSU-Next driver ABI"

# Verify the hooks actually landed — a silently skipped hook means a kernel
# that boots with a dead SuSFS.
HOOK_CHECK=0
grep -q "ksu_handle_execveat" fs/exec.c            || { warn "missing ksu_handle_execveat hook in fs/exec.c"; HOOK_CHECK=1; }
grep -q "ksu_handle_faccessat" fs/open.c           || { warn "missing ksu_handle_faccessat hook in fs/open.c"; HOOK_CHECK=1; }
grep -q "ksu_handle_sys_read" fs/read_write.c      || { warn "missing ksu_handle_sys_read hook in fs/read_write.c"; HOOK_CHECK=1; }
grep -q "ksu_handle_stat" fs/stat.c                || { warn "missing ksu_handle_stat hook in fs/stat.c"; HOOK_CHECK=1; }
grep -q "ksu_handle_sys_reboot" kernel/reboot.c    || { warn "missing ksu_handle_sys_reboot hook in kernel/reboot.c"; HOOK_CHECK=1; }
[ "$HOOK_CHECK" -eq 0 ] || die "SuSFS/KernelSU-Next inline hooks incomplete — see warnings above"
log "SuSFS inline hooks verified"

# ------------------------------------------------------- 5. config fragment
log "Writing KernelSU-Next + SuSFS config fragment"

fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU"
# KernelSU-Next's own Kconfig says the kprobe/tracepoint hook "should not be
# used on kernel below 5.10", and the syscall-table hook needs >= 4.17 — so on
# this 4.14 kernel we force the manual (in-source) hook mode.
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_MANUAL_HOOK"

fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_SUS_PATH"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_SUS_MOUNT"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_SUS_KSTAT"
# SuSFS's try_umount needs kernel-side helpers (susfs_try_umount,
# susfs_add_try_umount) that no 4.14 kernel patch set provides for this driver,
# so with it on the kernel fails to link. The driver falls back to its own
# ksu_handle_umount() when this is off, so mount hiding still works — off by
# design, not an oversight.
fragment_add "$FRAGMENT_FILE" "-d CONFIG_KSU_SUSFS_TRY_UMOUNT"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_SPOOF_UNAME"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_ENABLE_LOG"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_OPEN_REDIRECT"
fragment_add "$FRAGMENT_FILE" "-e CONFIG_KSU_SUSFS_SUS_MAP"

# CONFIG_KSU_SUSFS depends on THREAD_INFO_IN_TASK
if grep -q "THREAD_INFO_IN_TASK" "${DRIVER_DIR}/kernelsu/Kconfig" 2>/dev/null; then
    fragment_add "$FRAGMENT_FILE" "-e CONFIG_THREAD_INFO_IN_TASK"
    log "THREAD_INFO_IN_TASK required by this KernelSU Kconfig, added"
fi

log "Fragment written: $FRAGMENT_FILE"
cat "$FRAGMENT_FILE"
