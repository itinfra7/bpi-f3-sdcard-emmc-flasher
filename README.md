# bpi-f3-sdcard-emmc-flasher

Interactive SD card to eMMC flasher and release script for Banana Pi BPI-F3 (`riscv64`) on openSUSE Tumbleweed.

## Keywords

Keywords: `#opensuse #suse #tumbleweed #riscv64 #risc-v #bpif3 #bananapi #spacemitk1 #emmc #sdcard #flasher #installer #bianbu #dd`

## Overview

This repository provides a reproducible flashing workflow for moving an openSUSE Tumbleweed installation from an SD card to the internal eMMC on Banana Pi BPI-F3 systems.

The script supports both English and `한국어` prompts.

## Technical Design

This workflow recreates the expected BPI-F3 eMMC GPT layout, flashes the vendor boot chain into the dedicated `env`, `opensbi`, and `uboot` partitions, copies the boot and root partitions from the selected openSUSE image, rewrites SD-card block-device references to the eMMC target, and writes `bootinfo_emmc.bin` plus `FSBL.bin` into the eMMC boot hardware area.

## Target Profile

- Reference firmware bundle directory: `bianbu-23.10-nas-k1-v1.0rc1-release-20240429192450`
- Reference image filename: `2024-09-09-openSUSE-Tumbleweed-RISC-V-LXQT.riscv64-rootfs.riscv64-2024.09.02-Build1.9.tar.xz-bpi-f3-7356MB.img`
- Download page: https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3#_system_image
- Board: Banana Pi BPI-F3 / SpacemiT K1
- Architecture: `riscv64`
- Host workflow: openSUSE Tumbleweed booted from SD card
- Default eMMC block device: `/dev/mmcblk2`
- Default eMMC boot device: `/dev/mmcblk2boot0`

## Included Files

- `bpi-f3-sdcard-emmc-flasher.sh` validates the host environment, confirms the target paths and devices, recreates the eMMC partition map, flashes the board-specific boot components, copies the boot and root filesystems from the selected image, updates boot-time storage references, writes the eMMC boot area, and optionally powers the machine off at the end.

## Quick Start

Open a root shell before running the flasher.

The commands below are intended to be run as `root`.

```sh
wget https://github.com/itinfra7/bpi-f3-sdcard-emmc-flasher/releases/latest/download/bpi-f3-sdcard-emmc-flasher.sh
chmod +x bpi-f3-sdcard-emmc-flasher.sh
./bpi-f3-sdcard-emmc-flasher.sh
```

## Workflow

1. Check that it is running as `root` and verify the required Linux utilities.
2. Confirm the firmware directory, OS image path, target eMMC device, and target `boot0` device.
3. Wipe the target eMMC and recreate the fixed BPI-F3 partition layout: `env`, `opensbi`, `uboot`, `bootfs`, and `rootfs`.
4. Flash `env.bin`, `fw_dynamic.itb`, and `u-boot.itb` into the dedicated boot-chain partitions.
5. Attach the selected openSUSE image with `losetup` and copy its first two partitions into `bootfs` and `rootfs`.
6. Mount the new eMMC filesystems and rewrite `env_k1-x.txt`, `armbianEnv.txt`, and `/etc/fstab` so they point to the eMMC target instead of the SD card.
7. Unlock `boot0` temporarily and write `bootinfo_emmc.bin` plus `FSBL.bin`.
8. Print the final block-device layout and power the host off unless `--no-poweroff` was requested.

## Release Assets

The latest release publishes the following assets:

- `bpi-f3-sdcard-emmc-flasher.sh`

## Credits

[Banana Pi](https://www.banana-pi.org/) and the BPI-F3 / SpacemiT K1 platform provide the target hardware context for this workflow.

[openSUSE](https://www.opensuse.org/) provides the operating system environment used for the SD-card-to-eMMC migration workflow documented here.

[itinfra7](https://github.com/itinfra7) is credited for the original BPI-F3 SD-card-to-eMMC flashing workflow and the script packaging behind this repository.
