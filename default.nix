# dictyonos/default.nix
#
# Glue layer that fuses three independent upstream projects:
#
#   * the Asterinas kernel      (Safe-Rust framekernel, Linux-ABI compatible)
#   * sixos + infuse.nix        (s6 / s6-rc instead of systemd, infuse instead
#                                of the NixOS module system)
#   * Lix                       (the system-default package manager)
#
# into a bootable QEMU machine, deliberately bypassing sixos' ownerboot/kexec
# path (Asterinas does not implement kexec).
#
# Every source is an explicit argument: this file never reaches into a parent
# directory. flake.nix wires the flake inputs in; for a hand-rolled invocation
# see the "Without flakes" section of README.md.
{
  system ? "x86_64-linux",

  # nixpkgs used for sixos itself. Must be a revision whose s6-rc still accepts
  # sixos' patch series (see sixos/pkgs/patches/s6-rc).
  nixpkgs-src,

  # A package set that provides lixPackageSets.stable.lix. Kept separate because
  # the sixos nixpkgs predates Lix, and compiling Lix from source is expensive.
  lixPkgs,

  # sixos and infuse.nix sources (flake inputs declared with flake = false).
  sixos-src,
  infuse-src,

  # The Asterinas kernel payload (packages.<system>.kernel), i.e.
  # <kernel>/asterinas-osdk-bin.elf.
  #
  # Optional only so that default.nix can still be evaluated on its own. Note
  # that this must be the *store path* of a derivation output, not a path on
  # disk: a derivation output does not exist yet at evaluation time, so probing
  # it with builtins.pathExists would wrongly conclude there is no kernel.
  kernelElf ? null,

  hostName ? "dictyonos",
}:

let
  lib = import (nixpkgs-src + "/lib");

  infuse = ((import infuse-src) { inherit lib; }).v1.infuse;

  # sixos patches busybox / s6-rc / abduco, so the packageset the services are
  # built against must carry those patches.
  sixosOverlays = (import (sixos-src + "/pkgs/overlays.nix")) { inherit lib infuse; };

  pkgs = import nixpkgs-src {
    inherit system;
    overlays = sixosOverlays;
  };

  lix = lixPkgs.lixPackageSets.stable.lix;

  # ---------------- kernel --------------------------------------------

  # Stands in for <configuration>/boot/kernel when no payload was supplied.
  # Nothing in the boot path reads it: QEMU gets the kernel via -kernel.
  kernelPlaceholder = pkgs.writeText "asterinas-kernel-placeholder" ''
    dictyonos: place-holder for the Asterinas kernel payload.

    This system boots with QEMU direct kernel boot, so the kernel is handed to
    the machine on the QEMU command line (-kernel) rather than read out of
    <configuration>/boot/kernel. flake.nix always passes the real payload, which
    is packages.<system>.kernel.
  '';

  haveKernel = kernelElf != null;

  kernelPayload = if haveKernel then kernelElf else kernelPlaceholder;

  # ---------------- initramfs -----------------------------------------

  initramfs = import ./initramfs.nix { inherit pkgs; };

  # ---------------- /etc bits -----------------------------------------

  # Asterinas does not implement the full namespace set a strict Nix sandbox
  # needs, and it has no page-cache pressure reclaim yet, so the sandbox has to
  # stay off. (Lix 2.94 removed filter-syscalls entirely, so that knob no longer
  # exists and setting it would only produce an "unknown setting" warning.)
  nixConf = pkgs.writeText "dictyonos-nix.conf" ''
    sandbox = false
    build-users-group =
    require-sigs = false
    experimental-features = nix-command flakes
    substituters = https://cache.nixos.org/
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
  '';

  profile = pkgs.writeText "dictyonos-profile" ''
    export PATH=/run/current-system/sw/bin
    export EDITOR=vi
  '';

  # ---------------- services ------------------------------------------

  # The Lix daemon, so that multi-store access works the way nix expects.
  lixDaemonRun = pkgs.writeScript "lix-daemon-run" ''
    #!${pkgs.busybox}/bin/sh
    exec 2>&1
    mkdir -p /nix/var/nix/daemon-socket
    exec ${lix}/bin/nix-daemon
  '';

  # Called by udhcpc once a lease arrives.
  udhcpcScript = pkgs.writeScript "dictyonos-udhcpc" ''
    #!${pkgs.busybox}/bin/sh
    case "$1" in
      bound|renew)
        ${pkgs.busybox}/bin/ip addr add "$ip/$mask" dev "$interface" 2>/dev/null || true
        ${pkgs.busybox}/bin/ip route add default via "$router" dev "$interface" 2>/dev/null || true
        if [ -n "$dns" ]; then
          echo "nameserver $dns" > /etc/resolv.conf
        fi
        ;;
    esac
    exit 0
  '';

  # Best-effort DHCP for the QEMU user-mode NIC. It must never block boot, so
  # every step is guarded and the script always exits 0.
  netScript = pkgs.writeScript "dictyonos-net-dhcp" ''
    #!${pkgs.busybox}/bin/sh
    set +e

    # /etc/resolv.conf points into /run and does not exist on a fresh boot. Seed
    # the QEMU user-mode resolver so name resolution works before (and even
    # without) a DHCP lease.
    [ -s /etc/resolv.conf ] || echo "nameserver 10.0.2.3" > /etc/resolv.conf

    ifaces="$(ls /sys/class/net 2>/dev/null)"
    for iface in $ifaces; do
      [ "$iface" = "lo" ] && continue
      echo "net-dhcp: bringing up $iface"
      ${pkgs.busybox}/bin/ip link set "$iface" up
      ${pkgs.busybox}/bin/timeout 25 ${pkgs.busybox}/bin/udhcpc \
        -n -q -t 3 -T 3 -i "$iface" -s ${udhcpcScript} || true
    done
    echo "net-dhcp: done"
    exit 0
  '';


  # Minimal SSH: dropbear, public-key only. The launcher generates a throwaway
  # keypair on the host and passes the public half on the kernel command line as
  #   dictyonos.ssh_key_type=ssh-ed25519 dictyonos.ssh_key=<base64 blob>
  # The blob carries no whitespace, which is what makes it survive the kernel
  # splitting /proc/cmdline on spaces.
  sshRun = pkgs.writeScript "dropbear-run" ''
    #!${pkgs.busybox}/bin/sh
    exec 2>&1

    KEYDIR=/var/lib/dropbear
    AUTH=/root/.ssh/authorized_keys
    mkdir -p "$KEYDIR" "$(dirname "$AUTH")"

    ktype=""
    kblob=""
    for x in $(cat /proc/cmdline); do
      case "$x" in
        dictyonos.ssh_key_type=*) ktype="''${x#dictyonos.ssh_key_type=}" ;;
        dictyonos.ssh_key=*)      kblob="''${x#dictyonos.ssh_key=}" ;;
      esac
    done

    if [ -n "$kblob" ]; then
      echo "''${ktype:-ssh-ed25519} $kblob dictyonos" > "$AUTH"
      echo "dropbear: installed the authorized key from the kernel command line"
    elif [ ! -s "$AUTH" ]; then
      echo "dropbear: no authorized key; pass dictyonos.ssh_key=... or write $AUTH"
    fi

    # Bind the interface's own address, not the wildcard.  Asterinas resolves
    # bind() addresses in its local routing table (route::lookup_local_iface)
    # and rejects anything that is not a local address, so both bind(0.0.0.0:22)
    # and bind(::) fail with EADDRNOTAVAIL ("Cannot assign requested address").
    # Plain "-p 22" is worse still: dropbear would take the IPv6 wildcard from
    # getaddrinfo, fail, and give up with "No listening ports available" without
    # ever trying IPv4.
    #
    # The address is not known until the DHCP client has a lease, and this
    # service may well start first, so wait for it -- a few seconds of waiting
    # in a longrun costs nothing.
    addr=""
    tries=0
    while [ "$tries" -lt 60 ]; do
      addr="$(${pkgs.busybox}/bin/ip -4 addr show 2>/dev/null | ${pkgs.busybox}/bin/awk '/inet /{print $2}' | ${pkgs.busybox}/bin/cut -d/ -f1 | ${pkgs.busybox}/bin/grep -v '^127[.]' | ${pkgs.busybox}/bin/head -1)"
      [ -n "$addr" ] && break
      sleep 1
      tries=$((tries + 1))
    done
    if [ -z "$addr" ]; then
      echo "dropbear: no IPv4 address after 60s; listening on loopback only"
      addr=127.0.0.1
    fi
    echo "dropbear: listening on $addr:22"
    set -- -F -E -s -p "$addr:22"

    # A host key on the state disk survives reboots; without one, fall back to
    # ephemeral in-memory keys.
    if [ ! -s "$KEYDIR/dropbear_ed25519_host_key" ]; then
      ${pkgs.dropbear}/bin/dropbearkey -t ed25519 -f "$KEYDIR/dropbear_ed25519_host_key" >/dev/null 2>&1 || true
    fi
    if [ -s "$KEYDIR/dropbear_ed25519_host_key" ]; then
      set -- "$@" -r "$KEYDIR/dropbear_ed25519_host_key"
    else
      set -- "$@" -R
    fi

    exec ${pkgs.dropbear}/bin/dropbear "$@"
  '';
  # ---------------- sixos site ----------------------------------------

  siteDir = {
    globals = { };

    # sixos apply-tags starts from an empty attrset when no tag overlay is
    # active (lib.composeManyExtensions [] evaluates to (_: _: {})), which
    # collapses the whole host down to nothing. This always-on tag carries an
    # identity overlay so the host survives the tag pass. The tag set is
    # otherwise left empty on purpose: every upstream tag drags in
    # kexec/ownerboot/initrd machinery we do not want on Asterinas.
    tags.dictyonos = {
      overlays = [ (final: prev: prev) ];
      implies = { };
    };

    subnets = { };
    overlay = [ ];

    hosts.${hostName} = hostFinal: hostPrev: {
      canonical = "x86_64-linux-gnu";
      inherit pkgs;

      tags = hostPrev.tags // {
        dictyonos = true;
        has-initrd = false;
        has-initrd-abduco = false;
        has-initrd-lvm = false;
        has-initrd-mount-root = false;
        has-initrd-switch-root = false;
        is-bootloader-grub = false;
        # "The machine has a hardware clock."  Asterinas has no RTC driver, so
        # that is not literally true, but the tag's only two effects here are
        # both wanted:
        #   * it stops sixos from installing its *file-backed* fake hwclock
        #     (hwclock-fake + hwclock-fake-updater, which redirfd a state file
        #     into /etc).  On a read-only root that dies immediately and
        #     s6-supervise restarts it about once a second, forever -- taking
        #     the whole console with it, since every death also runs sixos'
        #     generated finish.user, which prints "execlineb: fatal: ...".
        #   * it installs the real hwclock oneshot instead, whose scripts end in
        #     "|| true" and therefore cannot fail or spin.
        # Either way the clock at boot comes from the kernel.
        has-hwclock = true;
        system-isx86_64 = false;
      };

      boot = hostPrev.boot // {
        rootfs = {
          label = "dictyonos";
          parameter = "/dev/vda";
          first-mount-is-readonly = false;
        };

        kernel = hostPrev.boot.kernel // {
          # sixos only needs payload (what the bootloader consumes) and params;
          # there is no Linux module tree underneath Asterinas.
          package = pkgs.runCommand "dictyonos-kernel-pkg" { } "mkdir -p $out";
          modules = null;
          modules-blacklist = [ ];
          firmware = [ ];
          image = kernelPayload;
          payload = kernelPayload;
          params = [
            "root=/dev/vda"
            "rw"
            "console=ttyS0"
            "loglevel=warn"
            "earlycon"
            "panic=1"
          ];
          console = {
            device = "ttyS0";
            baud = 115200;
          };
        };

        # We supply our own initramfs and drive the handoff ourselves, but sixos
        # reads boot.initrd.image when writing boot/kernel-params, so point it at
        # the real thing.
        initrd = {
          image = "${initramfs}/initrd";
          contents = { };
          ttys = { };
          mount-root = [ ];
        };
      };

      # Global userland. Lix replaces Nix as the default package manager.
      sw = pkgs.buildEnv {
        name = "dictyonos-sw";
        paths = [
          pkgs.busybox
          pkgs.s6
          pkgs.s6-rc
          pkgs.s6-portable-utils
          pkgs.doas
          lix
        ];
        pathsToLink = [ "/bin" "/sbin" "/share" ];
        ignoreCollisions = true;
      };

      # Extra symlinks that mkConfiguration plants inside the configuration tree.
      extra-configuration-links = {
        "etc/nix/nix.conf" = nixConf;
        "etc/profile" = profile;
      };

      # iproute2's routing-table names. sixos' activation links
      # /etc/iproute2 -> /run/current-system/etc/iproute2 on first boot, and on a
      # read-only root that `ln` cannot succeed -- under `set -e` it would kill
      # activation before s6-rc-init. Baking the file into the configuration makes
      # the link rootfs.nix creates valid, so the linkify pass is skipped
      # entirely. hostPrev.etc has to be carried over by hand because extension
      # sets are merged shallowly (same reason as `tags` and `boot` above).
      etc = (hostPrev.etc or { hosts = { }; }) // {
        iproute2.rt_tables = {
          local = 255;
          main = 254;
          default = 253;
          unspec = 0;
        };
      };

      doas-conf = [ "permit nopass root" ];

      # Deliberately minimal target set: no mdevd (Asterinas has no netlink
      # hotplug daemon), no dnscache, no syslog.
      targets = {
        default = hostFinal.six.mkBundle { };
        global.mounts = hostFinal.six.mkBundle { passthru.before = [ hostFinal.targets.default ]; };
        global.coldplug = hostFinal.six.mkBundle { };
        global.set-hostname = hostFinal.six.mkBundle { };
        global.hwclock = hostFinal.six.mkBundle { };

        set-hostname = hostFinal.services.set-hostname { hostname = hostFinal.name; };

        mounts = {
          # The initramfs already moved a live /proc and /sys into the new root;
          # re-mounting them would fail with EBUSY, so these stay empty bundles
          # while still satisfying the after references other targets make.
          proc = hostFinal.six.mkBundle { };
          sys = hostFinal.six.mkBundle { };
          dev.pts = hostFinal.services.mount { where = "/dev/pts"; };
          dev.shm = hostFinal.services.mount { where = "/dev/shm"; };
          tmp = hostFinal.services.mount {
            where = "/tmp";
            fstype = "tmpfs";
            options = [ "nodev" "nosuid" "mode=1777" "size=256m" ];
          };
          # The root filesystem is attached read-only on purpose -- /nix/store
          # is a shared, content-addressed artifact and must never be written
          # to. Mutable state lives on a separate disk that stage1 grafts over
          # /var. Remounting / read-write would therefore both fail (EROFS) and
          # defeat the design, so like proc/sys this is an empty bundle that
          # exists only to satisfy the after-references other targets make.
          "" = hostFinal.six.mkBundle { };
        };

        # Best-effort DHCP; guarded so a missing or unsupported NIC cannot stall
        # the boot.
        net-dhcp = hostFinal.six.mkOneshot {
          up = netScript;
          timeout-up = 60000;
          passthru.after = [ hostFinal.targets.mounts."" ];
        };

        # Long-running services must go through mkFunnel: it is the sixos helper
        # that produces the ./run script s6-rc-compile expects, and it also wires
        # up the per-service logger.
        #
        # There is deliberately no getty target here: s6-linux-init-maker is
        # invoked with -G (see sixos/mkConfiguration/default.nix, which derives
        # it from boot.kernel.console), so it already supervises an "early
        # getty" on ttyS0. A second getty cannot take the controlling terminal
        # and just fails with TIOCSCTTY.
        lix-daemon = hostFinal.six.mkFunnel {
          run = lixDaemonRun;
          passthru.after = [ hostFinal.targets.mounts."" ];
        };

        # Remote access, so the serial console is not the only way in.
        ssh = hostFinal.six.mkFunnel {
          run = sshRun;
          passthru.after = [ hostFinal.targets.mounts."" ];
        };
      };
    };
  };

  sixos = import sixos-src {
    nixpkgs-path = nixpkgs-src;
    inherit infuse;
    # The upstream yants types lag behind the host attribute set (they still
    # describe boot.rootfs as a string); the runtime shape is checked by sixos
    # itself, so skip the stale static check.
    check-types = false;
    site-dir = siteDir;
  };

  host = sixos.hosts.${hostName};

  # Everything that has to end up inside the root filesystem image.
  closureInfo = pkgs.closureInfo { rootPaths = [ host.configuration ]; };
in
{
  inherit lib pkgs lix lixPkgs infuse system;
  inherit initramfs kernelPayload haveKernel closureInfo;
  inherit (host) configuration;
  inherit host;

  configurationPath = "${host.configuration}";
  kernelParamsFile = "${host.configuration}/boot/kernel-params";
}
