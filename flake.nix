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

    # sixos' s6-rc patch series (sixos/pkgs/patches/s6-rc) only applies to the
    # 24.05 s6-rc, so this revision is load-bearing.
    nixpkgs-sixos = {
      url = "github:NixOS/nixpkgs/nixos-24.05";
      flake = false;
    };

    # Lix is taken prebuilt from a newer nixpkgs; 24.05 predates
    # lixPackageSets and compiling ../lix from source is expensive.
    nixpkgs-lix = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
      flake = false;
    };

    # The Asterinas kernel payload produced by ./scripts/build-kernel.sh.
    # Declared as a path input so it is read from the working tree rather than
    # from the git-filtered flake source (the payload is a large, untracked
    # build artifact).
    kernel = {
      url = "path:./kernel";
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
      kernel,
    }:
    let
      system = "x86_64-linux";

      dictyonos = import ./default.nix {
        inherit system;
        nixpkgs-src = nixpkgs-sixos;
        lixPkgs = import nixpkgs-lix { inherit system; };
        sixos-src = sixos;
        infuse-src = infuse;
        kernelElf = kernel + "/asterinas-osdk-bin.elf";
      };

      rootfs = import ./rootfs.nix {
        pkgs = dictyonos.pkgs;
        inherit (dictyonos) configuration closureInfo;
      };

      # One-shot launcher: bakes every artifact path in and defers to the
      # script, which still accepts KERNEL_ELF / INITRAMFS / ROOTFS / CONFIG
      # overrides.
      runVm = dictyonos.pkgs.writeShellScriptBin "dictyonos-run-vm" ''
        export DICTYONOS_PACKAGED=1
        export DICTYONOS_KERNEL_ELF=${dictyonos.kernelPayload}
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

        inherit rootfs;
        inherit (dictyonos) initramfs;

        # The sixos top-level configuration derivation (what ownerboot/kexec
        # would normally have handed to the kernel).
        system = dictyonos.configuration;

        # Source tree of the pinned Asterinas checkout; scripts/build-kernel.sh
        # uses this when it is not running against a sibling working copy.
        asterinas-source = asterinas.outPath;
      };

      apps.${system}.default = {
        type = "app";
        program = "${runVm}/bin/dictyonos-run-vm";
      };

      devShells.${system} = {
        # The Asterinas toolchain (Rust nightly + OSDK prerequisites).
        default = asterinas.devShells.${system}.default;
        kernel = asterinas.devShells.${system}.default;
      };

      formatter.${system} = dictyonos.pkgs.nixfmt-rfc-style;
    };
}
