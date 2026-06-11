{
  description = "Rust project with C bindings (via bindgen / cc crate)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    u-boot-secure.url = "github:apal-wucse/u-boot-secure";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      flake-utils,
      treefmt-nix,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "rust-src"
            "rustfmt"
            "clippy"
            "llvm-tools-preview"
            "rust-analyzer"
          ];
        };

        wolfssl-src = pkgs.callPackage ./nix/wolfssl-src.nix { };

        signtool = pkgs.callPackage ./nix/signtool.nix {
          rustPlatform = pkgs.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };
          inherit wolfssl-src;
          src = ./signtool/.;
        };

        signingKeys = pkgs.callPackage ./nix/keys.nix { inherit signtool; };

        opensbi-riscv64 = pkgs.pkgsCross.riscv64.callPackage ./nix/opensbi-cross.nix { };

        qemu-secureboot-riscv64 = pkgs.callPackage ./nix/qemu-secureboot.nix { inherit pkgs; };

        u-boot-secure = {
          qemu = inputs.u-boot-secure.packages.${system}.uboot-riscv64-qemu;
          qemu-ubuntu = inputs.u-boot-secure.packages.${system}.uboot-riscv64-qemu-ubuntu;
        };

        rootfs = pkgs.pkgsCross.riscv64.callPackage ./nix/rootfs.nix {
          inherit
            signtool
            signingKeys
            ;
        };

        loader-signed = pkgs.callPackage ./nix/loader-signed.nix {
          inherit
            signtool
            signingKeys
            ;
          opensbi = opensbi-riscv64;
          u-boot-secure = u-boot-secure.qemu;
        };

        loader-signed-ubuntu = pkgs.callPackage ./nix/loader-signed.nix {
          inherit
            signtool
            signingKeys
            ;
          opensbi = opensbi-riscv64;
          u-boot-secure = u-boot-secure.qemu-ubuntu;
        };

        run-qemu = pkgs.writeShellScriptBin "run-qemu" ''
          image=${rootfs}/images/rootfs.img
          overlay=./rootfs-overlay.qcow2

          if [ ! -f "$overlay" ]; then
            ${qemu-secureboot-riscv64}/bin/qemu-img create -f qcow2 -b "$image" -F raw "$overlay"
          fi

          ${qemu-secureboot-riscv64}/bin/qemu-system-riscv64 -cpu rva23s64 -smp cpus=2 -m 4G -nographic \
            -machine virt,keyfile=${signingKeys}/keys/ed25519_pub_nix.key,keyalgo=ed25519 \
            -bios ${loader-signed}/images/u-boot-spl.bin \
            -device loader,file=${loader-signed}/images/signed-loader.bin,addr=0x80200000 \
            -drive file="$overlay",format=qcow2,if=virtio \
            -netdev user,id=net0 \
            -device virtio-net-device,netdev=net0 \
            -device virtio-rng-pci
        '';

        create-ubuntu-img = pkgs.callPackage ./nix/create-ubuntu-img.nix {
          inherit
            signtool
            signingKeys
            ;
        };

        run-ubuntu = pkgs.writeShellScriptBin "run-ubuntu" ''
          image=./ubuntu-24.04.4-preinstalled-server-riscv64.img

          if [ ! -f "$image" ]; then
            ${create-ubuntu-img}/bin/create-ubuntu-img
          fi

          ${qemu-secureboot-riscv64}/bin/qemu-system-riscv64 -cpu rva23s64 -smp cpus=2 -m 4G -nographic \
            -machine virt,keyfile=${signingKeys}/keys/ed25519_pub_nix.key,keyalgo=ed25519 \
            -bios ${loader-signed-ubuntu}/images/u-boot-spl.bin \
            -device loader,file=${loader-signed-ubuntu}/images/signed-loader.bin,addr=0x80200000 \
            -drive file="$image",format=raw,if=virtio \
            -netdev user,id=net0 \
            -device virtio-net-device,netdev=net0 \
            -device virtio-rng-pci
        '';
      in
      {
        packages = {
          inherit
            signtool
            signingKeys
            opensbi-riscv64
            qemu-secureboot-riscv64
            u-boot-secure
            rootfs
            loader-signed
            loader-signed-ubuntu
            run-qemu
            run-ubuntu
            ;
          default = run-qemu;
          all-qemu = pkgs.symlinkJoin {
            name = "secureboot-qemu";
            paths = [
              signtool
              signingKeys
              opensbi-riscv64
              qemu-secureboot-riscv64
              u-boot-secure.qemu
              rootfs
              loader-signed
              run-qemu
            ];
          };
          all-qemu-ubuntu = pkgs.symlinkJoin {
            name = "secureboot-qemu-ubuntu";
            paths = [
              signtool
              signingKeys
              opensbi-riscv64
              qemu-secureboot-riscv64
              u-boot-secure.qemu-ubuntu
              loader-signed-ubuntu
              run-ubuntu
            ];
          };
        };

        devShells.default = pkgs.mkShell rec {
          inherit (signtool) buildInputs nativeBuildInputs LIBCLANG_PATH;
          RUST_BACKTRACE = "1";
          PKG_CONFIG_PATH = pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" buildInputs;
        };

        formatter = treefmt-nix.lib.mkWrapper pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.rustfmt.enable = true;
        };
      }
    );
}
