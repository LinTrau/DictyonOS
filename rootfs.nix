# dictyonos/rootfs.nix
#
# Assembles the whole system into one ext2 image -- entirely inside the Nix
# build sandbox. Nothing is copied out of the host store by hand, and the result
# is a content-addressed derivation like any other package.
#
# Layout produced:
#
#   /nix/store/<every path in the closure of the configuration>
#   /etc/{passwd,group,hosts,services,protocols,doas.conf,profile}  -> configuration
#   /etc/nix/nix.conf                                               -> configuration
#   /etc/resolv.conf                                                -> static, DHCP overwrites
#   /bin/sh, /usr/bin/env                                           -> configuration/sw/bin
#   /nix/var/nix/profiles/nextboot                                  -> configuration
#   /{proc,sys,dev,run,tmp,var}                                     -> mount points
#
# The /etc and /bin links are what sixos' own activation would create on first
# boot. Pre-creating them keeps that branch from running: it calls chattr, which
# Asterinas' ext2 does not implement.
{
  pkgs,
  configuration,
  closureInfo,
  # QEMU user-mode networking hands out this resolver.
  nameserver ? "10.0.2.3",
}:

pkgs.stdenvNoCC.mkDerivation {
  pname = "dictyonos-rootfs";
  version = "1";

  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.e2fsprogs
  ];

  dontStrip = true;

  buildCommand = ''
    set -euo pipefail

    root="$TMPDIR/root"
    rm -rf "$root"

    mkdir -p "$root/nix/store"
    mkdir -p "$root/nix/var/nix/profiles" "$root/nix/var/nix/gcroots" \
             "$root/nix/var/nix/db" "$root/nix/var/nix/temproots"
    mkdir -p "$root/proc" "$root/sys" "$root/dev" "$root/run" "$root/tmp" \
             "$root/etc" "$root/bin" "$root/sbin" "$root/usr/bin" \
             "$root/var/log" "$root/var/tmp" "$root/root" "$root/var/empty"
    chmod 1777 "$root/tmp" "$root/var/tmp"

    # 1. every store path the configuration needs, straight from the closure
    while IFS= read -r p; do
      cp -a "$p" "$root/nix/store/"
    done < ${closureInfo}/store-paths

    cfg=${configuration}

    # 2. the /etc and /bin glue
    for f in passwd group hosts services protocols doas.conf profile; do
      ln -sfn "$cfg/etc/$f" "$root/etc/$f"
    done
    ln -sfn "$cfg/sw/bin/sh"  "$root/bin/sh"
    ln -sfn "$cfg/sw/bin/env" "$root/usr/bin/env"
    ln -sfn "$cfg" "$root/nix/var/nix/profiles/nextboot"

    mkdir -p "$root/etc/nix"
    cp -f "$cfg/etc/nix/nix.conf" "$root/etc/nix/nix.conf"

    # 3. resolv.conf, so name resolution works even if DHCP never comes up
    printf 'nameserver %s\n' "${nameserver}" > "$root/etc/resolv.conf"

    # 4. mkfs, with 40% headroom for ext2 metadata
    used="$(du -sB1 "$root" | cut -f1)"
    size="$(( (used * 140 / 100 + 67108864 + 1048575) / 1048576 ))"
    echo "dictyonos-rootfs: $used bytes of payload -> $size MiB image"
    truncate -s "$size"M "$out"
    mkfs.ext2 -q -b 4096 -d "$root" -F "$out"
  '';

  passthru = {
    inherit configuration;
  };
}
