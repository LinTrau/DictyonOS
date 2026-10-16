#!/bin/sh
# dictyonos stage-1 init (initramfs, PID 1)
#
# Mounts the pseudo-filesystems, mounts the read-only ext2 system image that
# carries /nix/store plus the sixos "configuration", grafts the writable state
# disk over /var (and /nix/var), and then hands control over to the target s6-
# linux-init entry point.
#
# The split matters because the system image is content-addressed and shared:
# nothing in it may ever be written to. Everything mutable -- logs, /root, the
# Lix daemon socket -- lives on the separate, disposable state disk.
#
# Deliberately minimal: static busybox applets only, and nothing Asterinas does
# not implement (kexec, udev, systemd).

BB="@busybox@/bin/busybox"
export PATH="@busybox@/bin"

msg() { echo "[dictyonos-init] $*"; }
die() { echo "[dictyonos-init] FATAL: $*"; exec $BB sh; }

$BB mkdir -p /proc /sys /dev /sysroot

$BB mount -t proc     none     /proc || die "mounting /proc failed"
$BB mount -t sysfs    none     /sys  || die "mounting /sys failed"
$BB mount -t devtmpfs devtmpfs /dev  || die "mounting /dev failed"

CMDLINE="$($BB cat /proc/cmdline)"
msg "kernel cmdline: $CMDLINE"

CONFIGURATION=""
for x in $CMDLINE; do
    case "$x" in
        configuration=*) CONFIGURATION="${x#configuration=}" ;;
    esac
done
msg "configuration=$CONFIGURATION"

NEWROOT=/sysroot

# --- read-only system image ------------------------------------------------
# /dev/vda is attached with readonly=on. Mount it read-only regardless, so the
# system behaves the same whether or not the launcher remembered the flag.
ROOT=""
for dev in /dev/vda /dev/sda; do
    [ -b "$dev" ] || continue
    if $BB mount -t ext2 -o ro "$dev" "$NEWROOT"; then ROOT="$dev"; break; fi
done
if [ -z "$ROOT" ]; then
    msg "block devices:"
    $BB ls -l /dev | $BB grep "^b" || true
    die "could not mount the system image"
fi
msg "mounted read-only system image from $ROOT on $NEWROOT"

FOUND=""
for candidate in "$CONFIGURATION" \
                 "$($BB readlink "$NEWROOT/nix/var/nix/profiles/nextboot" 2>/dev/null)"; do
    [ -n "$candidate" ] || continue
    # boot/init is normally a symlink into the same /nix/store, whose target is
    # an absolute path. That path only resolves after switch_root, so test for
    # the symlink itself rather than following it here.
    if [ -d "$NEWROOT$candidate" ] &&
       { [ -L "$NEWROOT$candidate/boot/init" ] || [ -e "$NEWROOT$candidate/boot/init" ]; }; then
        FOUND="$candidate"; break
    fi
done

if [ -z "$FOUND" ]; then
    msg "no usable sixos configuration found under $NEWROOT/nix/store"
    die "cannot continue"
fi
msg "handing off to $FOUND/boot/init"

# --- writable state ---------------------------------------------------------
# /dev/vdb holds everything mutable. Without it the machine still boots, with
# /var on a tmpfs -- useful for a throwaway run, but nothing is kept.
# Note that Asterinas never writes dirty pages back on its own, and that the
# 'sync' mount option is silently dropped (PerMountFlags has no SYNCHRONOUS
# bit), so durability is the state-sync service's job -- see default.nix.
if [ -b /dev/vdb ] && $BB mount -t ext2 -o rw /dev/vdb "$NEWROOT/var"; then
    msg "mounted writable state disk /dev/vdb on /var"
else
    msg "no state disk; /var will be a tmpfs and nothing will persist"
    $BB mount -t tmpfs -o mode=0755 tmpfs "$NEWROOT/var"
fi
$BB mkdir -p "$NEWROOT/var/log" "$NEWROOT/var/root" "$NEWROOT/var/nix-var"

# /nix/var is mutable too (daemon socket, profiles, gcroots) while /nix/store
# stays with the read-only image.
$BB mount --bind "$NEWROOT/var/nix-var" "$NEWROOT/nix/var"

# Lix insists on making its store writable before it opens the store database
# (LocalStore::makeStoreWritable in libstore/local-store.cc):
#
#     mount("", /nix/store, "none", MS_REMOUNT | MS_BIND, 0)
#
# The kernel only accepts that when the target is the root of a mount, otherwise
# it is EINVAL -- and Lix then refuses to run at all ("remounting /nix/store
# writable: Invalid argument"), including for pure evaluations such as
# `nix eval --expr '1 + 1'`. NixOS has the store on a mount of its own; here a
# self-bind is enough to give the kernel something to remount. It does not make
# the image writable: the superblock stays read-only because the disk is, so
# this only clears the per-mount flag.
$BB mount --bind "$NEWROOT/nix/store" "$NEWROOT/nix/store" \
    || msg "warning: could not bind-mount /nix/store onto itself; Lix may refuse to run"

# --- hand the pseudo filesystems over ---------------------------------------
$BB mkdir -p "$NEWROOT/proc" "$NEWROOT/sys" "$NEWROOT/dev" "$NEWROOT/run"

# sixos' mount targets for /proc and /sys are intentionally no-ops because the
# handoff happens here (s6-linux-init itself needs a working /proc).
$BB mount --move /proc "$NEWROOT/proc"
$BB mount --move /sys  "$NEWROOT/sys"
$BB mount --move /dev  "$NEWROOT/dev"

$BB sync
exec $BB switch_root "$NEWROOT" "$FOUND/boot/init"
