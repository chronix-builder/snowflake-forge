# Zincore Forge

GitHub Actions builder for non-GKI kernels. It builds the kernel your device already runs: the source maintained by teams like LineageOS and PixelOS, compiled with a pinned AOSP Clang toolchain, with every kernel option left to the device's own defconfig. Nothing is rewritten, so the kernel stays as stable and predictable as its maintainers made it.

## What is it for?

It is made for people who want the stability of a stock kernel but still want root when they need it. The `ksu` build adds BakaSU and SuSFS on top and nothing else, while the `nsu` build is the vanilla kernel.

## Disclaimer

***Your warranty is now void. I am not responsible for bricked devices, dead SD cards, or you getting fired because an alarm failed to work. Please do some research if you have any concerns about features included before flashing it! YOU are choosing to make these modifications, and if you point the finger at me for messing up your device, I will laugh at you.***
<p align="right">Your typical XDA Forum Disclaimer.</p>

## Compatibility

| Supported devices | Supported Android versions |
| :--- | :---: |
| Xiaomi Redmi 7/Y3 ([onclite](https://www.gsmarena.com/xiaomi_redmi_7-9498.php)) | Android 13 – 17 |
| Xiaomi Redmi Note 10 Pro/Max ([sweet](https://www.gsmarena.com/xiaomi_redmi_note_10_pro-10662.php)) | Android 13 – 17 |
| Xiaomi Redmi Note 7 Pro ([violet](https://www.gsmarena.com/xiaomi_redmi_note_7_pro-9521.php)) | Android 13 – 17 |

## Variants

| Build | What it includes |
| :--- | :--- |
| **`ksu`** | BakaSU and SuSFS |
| **`nsu`** | No additions |

## Installation

### Flash
1. Download the zip for your variant (`nsu` or `ksu`) from [Releases](../../releases).
2. Back up your current `boot` (and `dtbo`, if your device has one) partitions.
3. Reboot to recovery.
4. Flash or sideload the zip.
5. Reboot to system.
6. Install [BakaSU Manager](https://github.com/Baka-SU/BakaSU/releases) if needed (`ksu` only).

### Restore to stock
1. Reboot to bootloader.
2. Flash the stock boot image: `fastboot flash boot boot.img`
3. If you backed up `dtbo`, restore it too: `fastboot flash dtbo dtbo.img`
4. Reboot: `fastboot reboot`

## Release schedule

New builds are published on the 1st of every month. Emergency releases may follow sooner if the kernel source or build dependencies change significantly.

## Credits

- [Baka-SU](https://github.com/Baka-SU) for KernelSU on non-GKI.
- [Hadad](https://codeberg.org/hadad) for kernel source.
- [JackA1ltman](https://github.com/JackA1ltman) for SuSFS patches.
- [LineageOS](https://github.com/LineageOS) for kernel source.
- [PixelOS-Devices](https://github.com/PixelOS-Devices) for kernel source.

## License

Released under the [GNU General Public License v2.0](LICENSE).
