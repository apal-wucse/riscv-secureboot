# Build
All component are packaged using [Nix](https://nixos.org/), but you can also build manually in the ordinary way.

The experimental features of nix `flakes` and `nix-command` are required.

## All Components and Example System
```bash
# For example system
nix build .#all-qemu
# For ubuntu
nix build .#all-qemu-ubuntu
```
All artifacts will be located under `result/`.

## Bootloader & Firmware

### U-Boot
Source and additional information are located [here](https://github.com/apal-wucse/u-boot-secure). 

In this repository, following command builds the all bootloader binaries.
```bash
# For example rootfs
nix build .#u-boot-secure.qemu
# For Ubuntu
nix build .#u-boot-secure.qemu-ubuntu
```

Build manually:
```bash
git clone --recursive https://github.com/apal-wucse/u-boot-secure.git
cd u-boot-secure
CROSS_COMPILE=riscv64-unknown-linux-gnu- make qemu-riscv64_spl_sb_seq_defconfig
CROSS_COMPILE=riscv64-unknown-linux-gnu- make
```

### OpenSBI
We have no changes from original source. Just build for `generic` platform.

In this repository, following command builds the all opensbi's artifacts.
```bash
nix build .#opensbi-riscv64
```

Build manually:
```bash
git clone https://github.com/riscv-software-src/opensbi.git
cd opensbi
CROSS_COMPILE=riscv64-unknown-linux-gnu- PLATFORM=generic make
```

## QEMU
Source is located [here](https://github.com/apal-wucse/qemu-secureboot.git).

In this repository, all changes are provided as a [patch](../nix/patches/0002-feat-riscv-implement-secureboot-key-insertion.patch) to v10.2.2.
```bash
nix build .#qemu-secureboot-riscv64
```

Build manually:
```bash
git clone https://github.com/apal-wucse/qemu-secureboot.git
cd qemu-secureboot
./configure --target-list=riscv64-softmmu
make
```

## Keytool / Signing Tool
Please see [here](./how-to-sign.md).
