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

  # The Asterinas kernel payload produced by cargo osdk build.
  #
  # Optional on purpose. dictyonos boots with QEMU direct kernel boot, so the
  # kernel reaches the machine through the -kernel argument and is never read
  # out of /boot. Leaving this null keeps every package in this flake buildable
  # from nothing but a git clone; pass the real payload to also embed it in
  # <configuration>/boot/kernel.
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
    <configuration>/boot/kernel.

    To embed the real payload here as well:
      ./scripts/build-kernel.sh
      nix build .#rootfs --override-input kernel path:./kernel
  '';

  haveKernel = kernelElf != null && builtins.pathExists kernelElf;

  kernelPayload =
    if haveKernel then
      builtins.path {
        name = "asterinas-kernel";
        path = kernelElf;
      }
    else
      kernelPlaceholder;

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
        has-hwclock = false;
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

      doas-conf = [ "permit nopass root" ];

      # Deliberately minimal target set: no mdevd (Asterinas has no netlink
      # hotplug daemon), no dnscache, no sshd, no syslog.
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
          "" = hostFinal.services.mount {
            where = "/";
            options = [ "remount" "rw" ];
          };
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
