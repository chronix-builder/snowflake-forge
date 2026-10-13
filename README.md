# Zincore Forge

Built around one thing: adding ReSukiSU and SuSFS on top of a stock kernel — without dragging in extra modules or tweaks you never asked for.

# Disclaimer

***Your warranty is now void. I am not responsible for bricked devices, dead SD cards, or you getting fired because an alarm failed to work. Please do some research if you have any concerns about features included before flashing it! YOU are choosing to make these modifications, and if you point the finger at me for messing up your device, I will laugh at you.***
<p align="right">Your typical XDA Forum Disclaimer.</p>

# Compatibility

**Device**
- Redmi Note 10 Pro / Pro Max ([`sweet`](https://www.gsmarena.com/xiaomi_redmi_note_10_pro-10662.php))

**Supports**
- Android 13 – 16

# Variants

**ksu**
- ReSukiSU — a KernelSU-based root solution for Android
- SuSFS — an addon root-hiding solution for KernelSU

**nsu**
- Stock kernel — no additions

# Installation

**Flash**
1. Download the zip for your variant (`nsu` or `ksu`) from [Releases](../../releases)
2. Back up your current `boot` and `dtbo` partitions
3. Reboot to recovery
4. Flash or sideload the zip
5. Reboot to system
6. Install [Baka-SU Manager](https://github.com/Baka-SU/BakaSU/releases) if needed. (`ksu` only)

**Restore to stock**
1. Reboot to bootloader
2. Flash the stock boot image: `fastboot flash boot boot.img`
3. Flash the stock dtbo image: `fastboot flash dtbo dtbo.img`
4. Reboot: `fastboot reboot`

# Release schedule

New builds are published monthly. Emergency releases may follow sooner if the kernel source or build dependencies change significantly.

# Credits

- [Baka-SU](https://github.com/Baka-SU) for KernelSU on non-GKI.
- [Hadad Darajat](https://codeberg.org/hadad) for kernel source.
- [JackA1ltman](https://github.com/JackA1ltman) for SuSFS patches.
- [LineageOS](https://github.com/LineageOS) for kernel source.
- [PixelOS-Devices](https://github.com/PixelOS-Devices) for kernel source.
