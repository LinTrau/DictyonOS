#!/bin/sh
# dictyonos stage-1 init (initramfs, PID 1)
#
# Mounts the pseudo-filesystems, locates and mounts the ext2 root filesystem
# that carries /nix/store plus the sixos "configuration" closure, and then
# hands control over to the target's s6-linux-init entry point.
#
# It deliberately avoids anything Asterinas does not implement (kexec, udev,
# systemd) and uses only statically linked busybox applets.

BB="@busybox@/bin/busybox"
export PATH="@busybox@/bin"

msg() { echo "[dictyonos-init] $*"; }
die() { echo "[dictyonos-init] FATAL: $*"; exec $BB sh; }

$BB mkdir -p /proc /sys /dev /sysroot

$BB mount -t proc     none     /proc  || die "mounting /proc failed"
$BB mount -t sysfs    none     /sys   || die "mounting /sys failed"
$BB mount -t devtmpfs devtmpfs /dev   || die "mounting /dev failed"

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

try_mount() {
    $BB mount -t ext2 -o rw "$1" "$NEWROOT" 2>/dev/null && return 0
    $BB mount -t ext2 "$1" "$NEWROOT" 2>/dev/null && return 0
    return 1
}

# Asterinas names the first virtio-blk device /dev/vda; keep a couple of
# fallbacks so the image also boots on a plain Linux host for debugging.
ROOT=""
for dev in /dev/vda /dev/vdb /dev/sda; do
    [ -b "$dev" ] || continue
    if try_mount "$dev"; then ROOT="$dev"; break; fi
done

if [ -z "$ROOT" ]; then
    msg "available block devices:"
    $BB ls -l /dev | $BB grep -i '^b' || true
    die "could not mount the root filesystem"
fi
msg "mounted root filesystem from $ROOT on $NEWROOT"

FOUND=""
for candidate in "$CONFIGURATION" \
                 "$($BB readlink "$NEWROOT/nix/var/nix/profiles/nextboot" 2>/dev/null)" \
                 "$($BB readlink "$NEWROOT/nix/var/nix/profiles/activated" 2>/dev/null)"; do
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

$BB mkdir -p "$NEWROOT/proc" "$NEWROOT/sys" "$NEWROOT/dev" "$NEWROOT/run"

# Hand the already-mounted pseudo filesystems over to the new root.
# sixos' mount targets for /proc and /sys are intentionally no-ops because we
# do this here (s6-linux-init itself needs a working /proc).
$BB mount --move /proc "$NEWROOT/proc"
$BB mount --move /sys  "$NEWROOT/sys"
$BB mount --move /dev  "$NEWROOT/dev"

$BB sync
exec $BB switch_root "$NEWROOT" "$FOUND/boot/init"
