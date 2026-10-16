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
#   /etc/iproute2                                                   -> configuration
#   /etc/resolv.conf                                                -> /run (writable)
#   /bin/sh, /usr/bin/env                       -> /run/current-system/sw/bin
#   /root                                                           -> /var/root
#   /nix/var/nix/profiles/nextboot                                  -> configuration
#   /{proc,sys,dev,run,tmp,var}                                     -> mount points
#
# This image is attached read-only, so everything mutable has to live somewhere
# else:
#
#   * /var is grafted over the writable state disk by stage1-init.sh, and /root
#     is a symlink into it so that the shell and sshd have somewhere to write.
#   * /etc/resolv.conf is a symlink into the tmpfs-backed /run, because DHCP
#     rewrites it and /etc itself cannot be written.
#   * /nix/var is bound onto the state disk as well (the Lix daemon wants a
#     socket directory there), while /nix/store stays strictly read-only.
#
# The /etc and /bin links are what sixos' own activation would create on first
# boot. Pre-creating them keeps that branch from running: not only does it call
# chattr (which Asterinas' ext2 does not implement), it would also write to a
# read-only filesystem.
#
# The exact *targets* matter as much as the links themselves.  sixos' activate
# script re-links /bin/sh and /usr/bin/env after comparing readlink(1)'s output
# against the literal string /run/current-system/sw/bin/{sh,env}; if the link
# points somewhere else it runs `ln -sfT`, which cannot succeed on a read-only
# filesystem, and because activate runs under `set -e` it would abort before
# ever reaching s6-rc-init -- leaving the machine stuck in the s6-linux-init
# early getty with no services at all.  Pointing these two links at the literal
# paths activate expects makes both comparisons false, so the whole linkify pass
# becomes a no-op.
{
  pkgs,
  configuration,
  closureInfo,
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

    # /nix/store/.links is where Lix hardlinks identical files when it adds
    # paths.  LocalStore's constructor calls createDirs() on it unconditionally
    # -- even for a pure evaluation -- so on a read-only store the directory has
    # to already exist or every nix invocation dies with
    # "creating directory '/nix/store/.links': Read-only file system".
    mkdir -p "$root/nix/store/.links"
    mkdir -p "$root/nix/var/nix/profiles" "$root/nix/var/nix/gcroots" \
             "$root/nix/var/nix/db" "$root/nix/var/nix/temproots"
    mkdir -p "$root/proc" "$root/sys" "$root/dev" "$root/run" "$root/tmp" \
             "$root/etc" "$root/bin" "$root/sbin" "$root/usr/bin" \
             "$root/var/log" "$root/var/tmp" "$root/var/empty"
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
    # NB: /run/current-system is a symlink to this same configuration; activate
    # creates it before it touches /bin/sh, and only after that does anything
    # need /bin/sh at all (s6-linux-init and rc.init use absolute paths).
    ln -sfn /run/current-system/sw/bin/sh  "$root/bin/sh"
    ln -sfn /run/current-system/sw/bin/env "$root/usr/bin/env"
    ln -sfn "$cfg" "$root/nix/var/nix/profiles/nextboot"

    mkdir -p "$root/etc/nix"
    cp -f "$cfg/etc/nix/nix.conf" "$root/etc/nix/nix.conf"

    # sixos' activation "linkifies" /etc/iproute2 too, and on a read-only /etc a
    # missing link would make it fail. The configuration always generates the
    # directory (see the etc.iproute2 setting in default.nix), so link it here
    # like every other /etc entry.
    ln -sfn "$cfg/etc/iproute2" "$root/etc/iproute2"

    # 3. root's home lives on the writable state disk, so the console shell and
    #    sshd have a writable HOME.
    ln -sfn /var/root "$root/root"

    # 4. resolv.conf has to stay writable (DHCP rewrites it) while /etc is read
    #    only, so it points into the tmpfs-backed /run. The guest seeds the
    #    default resolver before it tries DHCP.
    ln -sfn /run/resolv.conf "$root/etc/resolv.conf"

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
