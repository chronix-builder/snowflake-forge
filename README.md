<div align="center">

# Snowflake-Revived

[![Release](https://img.shields.io/github/release-date/chronix-builder/snowflake-forge?label=Release&labelColor=1f2328&color=6e56cf)](https://github.com/chronix-builder/snowflake-forge/releases)
[![Downloads](https://img.shields.io/github/downloads/chronix-builder/snowflake-forge/total?label=Downloads&labelColor=1f2328&color=6e56cf)](https://github.com/chronix-builder/snowflake-forge/releases)
[![License](https://img.shields.io/github/license/chronix-builder/snowflake-forge?label=License&labelColor=1f2328&color=6e56cf)](LICENSE)

</div>

GitHub Actions builder for **Snowflake-Revived**, the non-GKI kernel for the Xiaomi Redmi Note 7 Pro ([violet](https://www.gsmarena.com/xiaomi_redmi_note_7_pro-9521.php)) maintained by [Chronix](https://github.com/chronix-builder). It compiles [kernel_xiaomi_sm6150](https://github.com/chronix-builder/kernel_xiaomi_sm6150) with a pinned AOSP Clang toolchain, keeping close to the source tree's own configuration so the kernel stays as stable and predictable as it was made.

## Approach

Built for those who want the stability of a stock kernel but still want root when they need it. The `ksu` build adds **KernelSU-Next** with **SuSFS** on top, and nothing else, while the `nsu` build is the vanilla kernel.

### KernelSU-Next + SuSFS (`ksu` variant)

| Component | Version | Why |
| :--- | :--- | :--- |
| [KernelSU-Next](https://kernelsu-next.github.io/webpage/) | [`v3.4.0-legacy-susfs-v2`](https://github.com/sidex15/KernelSU-Next/tree/legacy-susfs-v2) from [sidex15](https://github.com/sidex15/KernelSU-Next), pinned by commit in `config.env` | The non-GKI integration [KernelSU-Next documents](https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html) is the `legacy` branch, and the upstream `legacy` tags carry no SuSFS at all (upstream SuSFS is a GKI/LKM feature). This fork of that `legacy` branch with SuSFS v2 merged in is what KernelSU-Next's maintainers point non-GKI users to when they ask for SuSFS (issues [#1387](https://github.com/KernelSU-Next/KernelSU-Next/issues/1387), [#1429](https://github.com/KernelSU-Next/KernelSU-Next/issues/1429)). |
| [SuSFS](https://gitlab.com/simonpunk/susfs4ksu) | `v2.3.0` kernel patches + inline hook patches, pinned in `config.env` | Kernel-side SuSFS for 4.14, wired up with the manual (non-kprobe) hooks — the hook mode KernelSU-Next legacy uses on 4.14. |

The build fails loudly if the pinned KernelSU-Next ref does not carry SuSFS, if the SuSFS patch leaves real rejects, if the injected hooks still reference symbols the driver does not export, or if `CONFIG_KSU`/`CONFIG_KSU_MANUAL_HOOK`/`CONFIG_KSU_SUSFS` are not `=y` in the final `.config` — a kernel that would have booted without root is not a successful `ksu` build.

One SuSFS option is deliberately off: `CONFIG_KSU_SUSFS_TRY_UMOUNT`. The driver's calls into it need kernel-side helpers (`susfs_try_umount`, `susfs_add_try_umount`) that no 4.14 SuSFS patch set provides, so enabling it fails at link time; KernelSU-Next falls back to its own `ksu_handle_umount()`, so mount hiding still works.

## Building

Trigger it from **Actions → Build Kernel → Run workflow**:

| Input | Meaning |
| :--- | :--- |
| `device` | Device to build. Leave empty to build every supported device (violet). |
| `branch` | Kernel branch to build. Leave empty to use the device default (`snowy`), or pass e.g. `lineage-24.0` / `dev` to build another branch of the kernel source. |
| `create_release` | Publish a GitHub Release from the build artifacts. Scheduled runs always release. |

## Compatibility

| Supported devices | Kernel version | Supported Android versions |
| :--- | :---: | :---: |
| Xiaomi Redmi Note 7 Pro ([violet](https://www.gsmarena.com/xiaomi_redmi_note_7_pro-9521.php)) | 4.14 | Android 13 – 17 |

## Installation

> [!CAUTION]
> Your warranty is now void. I am not responsible for bricked devices or dead SD cards. Please do some research if you have any concerns about the features this builder includes in its kernels before flashing them! YOU are choosing to make these modifications, and if you point the finger at me for messing up your device, I will laugh at you.

> [!IMPORTANT]
> Back up your current `boot` (and `dtbo`, if your device has one) partitions.

### Flash
1. Download the zip for your variant (`nsu` or `ksu`) from [Releases](../../releases).
2. Reboot to recovery.
3. Flash or sideload the zip.
4. Reboot to system.
5. Install [KernelSU-Next Manager](https://github.com/KernelSU-Next/KernelSU-Next/releases) if needed (`ksu` only) — only the official KernelSU-Next manager signature is baked into the kernel.
6. To use SuSFS, flash the [susfs4ksu module](https://github.com/sidex15/susfs4ksu-module) on top (`ksu` only).

### Restore to stock
1. Reboot to bootloader.
2. Flash the stock boot image: `fastboot flash boot boot.img`
3. If you backed up `dtbo`, restore it too: `fastboot flash dtbo dtbo.img`
4. Reboot: `fastboot reboot`

## Release schedule

New builds are released on the **1st of every month**. Each release rebuilds every supported device and variant from the latest kernel source. An emergency release may follow between cycles if the kernel source or build dependencies change significantly.

## Credits

- **[zincore-forge](https://github.com/yureixen/zincore-forge) by [yureixen](https://github.com/yureixen)** — the original builder this project is based on. Huge thanks for the base; all credit for the workflow and scripts design goes to them.
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) for the legacy (non-GKI) KernelSU-Next line this kernel is built on.
- [sidex15](https://github.com/sidex15/KernelSU-Next) for the SuSFS-enabled `legacy-susfs-v2` integration.
- [JackA1ltman](https://github.com/JackA1ltman) for the non-GKI SuSFS kernel patches and manual hook script.
- [LineageOS](https://github.com/LineageOS) for kernel source.
- [osm0sis](https://github.com/osm0sis/AnyKernel3) for AnyKernel3.
- [riarumoda](https://github.com/riarumoda/perf_neon-builder) for the inspiration.
- [simonpunk](https://gitlab.com/simonpunk/susfs4ksu) for SuSFS.
- [tiann](https://github.com/tiann/KernelSU) for the original KernelSU.
