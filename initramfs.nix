# dictyonos/initramfs.nix
#
# Builds the stage-1 initramfs. It is intentionally independent of the sixos
# "configuration" derivation so that the two do not reference each other: the
# configuration path is passed on the kernel command line (sixos writes
# configuration=<store-path> into boot/kernel-params), with the
# /nix/var/nix/profiles/nextboot symlink as a fallback.
{ pkgs }:

let
  # Static busybox: the initramfs has no dynamic loader.
  busybox = pkgs.pkgsStatic.busybox;

  # Built with plain builtins.replaceStrings + writeTextFile so that it does not
  # depend on nixpkgs helpers (replaceVarsWith / substituteAll) that have come
  # and gone across releases.
  stage1 = pkgs.writeTextFile {
    name = "dictyonos-init";
    executable = true;
    text = builtins.replaceStrings [ "@busybox@" ] [ "${busybox}" ] (
      builtins.readFile ./stage1-init.sh
    );
  };
in
pkgs.makeInitrd {
  contents = [
    {
      object = "${busybox}/bin";
      symlink = "/bin";
    }
    {
      object = stage1;
      symlink = "/init";
    }
  ];
}
