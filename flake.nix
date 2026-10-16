{
  description = "dictyonos - Asterinas framekernel + sixos/s6 userland + Lix, bootable under QEMU";

  inputs = {
    # The Asterinas framekernel, pinned to the revision this glue layer was
    # developed and verified against.
    asterinas.url = "github:asterinas/asterinas/01acaa7eeed755a32fc658e7d732b080061b4872";

    # sixos and infuse.nix are plain source trees: neither ships a flake.nix.
    sixos = {
      url = "git+https://codeberg.org/amjoseph/sixos?rev=d6d69bda0cdb4ffb634d9e90c7c09d4f8fc6c163";
      flake = false;
    };
    infuse = {
      url = "git+https://codeberg.org/amjoseph/infuse.nix?rev=364ea18b5611b5fd6a6acd7151411b430a70e194";
      flake = false;
    };

    # sixos s6-rc patch series (sixos/pkgs/patches/s6-rc) only applies to the
    # 24.05 s6-rc, so this revision is load-bearing.
    nixpkgs-sixos = {
      url = "github:NixOS/nixpkgs/nixos-24.05";
      flake = false;
    };

    # Lix is taken prebuilt from a newer nixpkgs; 24.05 predates
    # lixPackageSets and compiling Lix from source is expensive.
    #
    # This is a release branch rather than nixos-unstable on purpose: the
    # unstable revision at the time of writing ships a Lix whose meson options
    # no longer match its build script (ERROR: Unknown option: mimalloc), and
    # release branches are guaranteed to be fully substituted. 26.05 is also the
    # channel the Asterinas NixOS distro targets.
    nixpkgs-lix = {
      url = "github:NixOS/nixpkgs/nixos-26.05";
      flake = false;
    };
  };

  outputs =
    {
      self,
      asterinas,
      sixos,
      infuse,
      nixpkgs-sixos,
      nixpkgs-lix,
    }:
    let
      system = "x86_64-linux";
      lib = import (nixpkgs-sixos + "/lib");

      # Run the kernel build in the packageset Asterinas itself pins, with its
      # own overlay applied: that is what supplies the matching Rust nightly and
      # the prebuilt Linux vDSOs the kernel embeds.
      pkgsKernel = import asterinas.inputs.nixpkgs.outPath {
        inherit system;
        overlays = [ asterinas.overlays.default ];
      };

      vendor = import ./vendor.nix {
        pkgs = pkgsKernel;
        inherit asterinas;
        rustToolchain = pkgsKernel.asterinas-rust-toolchain;
      };

      kernel = import ./kernel.nix {
        pkgs = pkgsKernel;
        inherit lib asterinas;
        inherit (vendor) cargoConfig vendor;
      };

      dictyonos = import ./default.nix {
        inherit system;
        nixpkgs-src = nixpkgs-sixos;
        lixPkgs = import nixpkgs-lix { inherit system; };
        sixos-src = sixos;
        infuse-src = infuse;
        # kernelElf is deliberately NOT passed: embedding the kernel in the
        # system image would make <configuration>/boot/kernel a reference to the
        # payload, and Nix's reference scanner follows the store paths its debug
        # info mentions -- which drags the entire Rust toolchain into the image
        # closure (4.3 GiB instead of 0.9 GiB). QEMU gets the kernel through
        # -kernel anyway, so the image keeps the place-holder.
      };

      rootfs = import ./rootfs.nix {
        pkgs = dictyonos.pkgs;
        inherit (dictyonos) configuration closureInfo;
      };

      # One-shot launcher: bakes every artifact path in and defers to the
      # script, which still accepts the DICTYONOS_* overrides. qemu, e2fsprogs
      # and openssh are put on PATH because the launcher runs the machine, makes
      # the state disk and generates the throwaway ssh keypair -- a host that has
      # nothing but Nix installed can run this flake as-is. (export
      # QEMU_BIN=/usr/bin/qemu-system-x86_64 to use the host's qemu instead.)
      runVm = dictyonos.pkgs.writeShellScriptBin "dictyonos-run-vm" ''
        export PATH="${dictyonos.pkgs.qemu}/bin:${dictyonos.pkgs.e2fsprogs}/bin:${dictyonos.pkgs.openssh}/bin:$PATH"
        export DICTYONOS_KERNEL_ELF=${kernel}/asterinas-osdk-bin.elf
        export DICTYONOS_INITRAMFS=${dictyonos.initramfs}/initrd
        export DICTYONOS_ROOTFS=${rootfs}
        export DICTYONOS_CONFIG=${dictyonos.configuration}
        exec ${./scripts/run-vm.sh} "$@"
      '';
    in
    {
      packages.${system} = {
        # nix build / nix run without an attribute.
        default = rootfs;

        inherit rootfs kernel;
        inherit (dictyonos) initramfs;

        # The sixos top-level configuration derivation (what ownerboot/kexec
        # would normally have handed to the kernel).
        system = dictyonos.configuration;
      };

      apps.${system}.default = {
        type = "app";
        program = "${runVm}/bin/dictyonos-run-vm";
      };

      devShells.${system} = {
        # The Asterinas toolchain, for hacking on the kernel itself.
        default = asterinas.devShells.${system}.default;
        kernel = asterinas.devShells.${system}.default;
      };

      formatter.${system} = dictyonos.pkgs.nixfmt-rfc-style;
    };
}
