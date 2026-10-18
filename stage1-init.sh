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

# Asterinas' devpts exposes the multiplexing master as /dev/pts/ptmx and expects
# /dev/ptmx to be a symlink to it (see devpts/mod.rs). Without that symlink
# posix_openpt() answers ENOENT, so every program that wants a pty -- Lix among
# them, since it runs each builder under one -- dies with "opening
# pseudoterminal master: No such file or directory".
[ -e /dev/ptmx ] || $BB ln -s pts/ptmx /dev/ptmx

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

# Which configuration to boot is decided further down, after the state disk is
# mounted: the profiles directory lives in /nix/var, and a generation recorded
# there is invisible until that is in place. The configuration the launcher
# passed on the command line is the fallback.

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
# stays with the read-only image. The image's own profiles are hidden by this
# bind, so remember what it says about itself first: on a state disk that has
# never carried a generation, that is what nextboot is seeded with.
IMAGE_NEXTBOOT="$($BB readlink "$NEWROOT/nix/var/nix/profiles/nextboot" 2>/dev/null || true)"
$BB mount --bind "$NEWROOT/var/nix-var" "$NEWROOT/nix/var"
PROFILES="$NEWROOT/nix/var/nix/profiles"
$BB mkdir -p "$PROFILES"
if [ -n "$IMAGE_NEXTBOOT" ] && [ ! -e "$PROFILES/nextboot" ]; then
    $BB ln -s "$IMAGE_NEXTBOOT" "$PROFILES/nextboot" \
        && msg "seeded nextboot from the system image: $IMAGE_NEXTBOOT"
fi

# --- a writable /nix/store --------------------------------------------------
# On the read-only system image the store is read-only with it, so Lix can
# evaluate but never build or substitute anything into it. Asterinas 0.19
# implements overlayfs, so the store becomes a merged view: the image is the
# lower layer, and two directories on the writable /var are the upper layer and
# the work directory overlayfs needs beside it. Whatever a build or a
# substitution writes lands in /var/nix-store-upper, which lives on /dev/vdb,
# so the state-sync service commits it and it survives a reboot. Without a
# state disk /var is a tmpfs and the overlay is writable but ephemeral, which
# is still better than failing.
#
# Nothing here may keep the machine from booting: if the overlay cannot be
# mounted (an older kernel without overlayfs, an upper filesystem without the
# xattrs overlayfs wants), fall back to the read-only self-bind below.
OVERLAY=0
$BB mkdir -p "$NEWROOT/var/nix-store-upper" "$NEWROOT/var/nix-store-work"
if $BB mount -t overlay overlay \
        -o "lowerdir=$NEWROOT/nix/store,upperdir=$NEWROOT/var/nix-store-upper,workdir=$NEWROOT/var/nix-store-work" \
        "$NEWROOT/nix/store"; then
    OVERLAY=1
    msg "mounted a writable overlay on /nix/store (upper layer under /var)"
else
    msg "warning: could not mount an overlay on /nix/store; the store stays read-only"
fi

# Lix insists on making its store writable before it opens the store database
# (LocalStore::makeStoreWritable in libstore/local-store.cc):
#
#     mount("", /nix/store, "none", MS_REMOUNT | MS_BIND, 0)
#
# The kernel only accepts that when the target is the root of a mount, otherwise
# it is EINVAL -- and Lix then refuses to run at all ("remounting /nix/store
# writable: Invalid argument"), including for pure evaluations such as
# `nix eval --expr '1 + 1'`. The overlay above is a mount of its own, so
# only the fallback path still needs one. A self-bind does not make the image
# writable: the superblock stays read-only because the disk is, so it only
# clears the per-mount flag.
if [ "$OVERLAY" = 0 ]; then
    $BB mount --bind "$NEWROOT/nix/store" "$NEWROOT/nix/store" \
        || msg "warning: could not bind-mount /nix/store onto itself; Lix may refuse to run"
fi

# --- which configuration to boot --------------------------------------------
# Now that the overlay is on, everything the store contains is visible, including
# a generation that lives in the writable upper layer rather than in the image.
# The order is prevboot (only when the kernel command line asks for
# dictyonos.rollback=1), then nextboot, then the configuration= the launcher
# passed. A candidate is used only if it is really present under the mounted
# store, so a stale symlink -- /nix/store rebuilt, the path garbage-collected, a
# state disk from a different image -- falls through to the next one instead of
# bricking the boot.
ROLLBACK=""
for x in $CMDLINE; do
    case "$x" in
        dictyonos.rollback=*) ROLLBACK="${x#dictyonos.rollback=}" ;;
    esac
done

FOUND=""
FROM=""
try() {
    # try <what named it> <path>; sets FOUND/FROM and returns 0 when it is usable.
    _label="$1"
    _candidate="$2"
    [ -n "$_candidate" ] || return 1
    # boot/init is normally a symlink into the same /nix/store, whose target is
    # an absolute path. That path only resolves after switch_root, so test for
    # the symlink itself rather than following it here.
    if [ -d "$NEWROOT$_candidate" ] &&
       { [ -L "$NEWROOT$_candidate/boot/init" ] || [ -e "$NEWROOT$_candidate/boot/init" ]; }; then
        FOUND="$_candidate"
        FROM="$_label"
        return 0
    fi
    msg "$_label names $_candidate, which is not a usable configuration"
    return 1
}

if [ -n "$ROLLBACK" ] && [ "$ROLLBACK" != 0 ]; then
    msg "dictyonos.rollback=$ROLLBACK: prevboot before nextboot"
    try "prevboot" "$($BB readlink "$PROFILES/prevboot" 2>/dev/null || true)" || true
fi
[ -n "$FOUND" ] || try "nextboot" "$($BB readlink "$PROFILES/nextboot" 2>/dev/null || true)" || true
[ -n "$FOUND" ] || try "the kernel command line" "$CONFIGURATION" || true

if [ -z "$FOUND" ]; then
    msg "no usable sixos configuration found under $NEWROOT/nix/store"
    msg "  nextboot: $($BB readlink "$PROFILES/nextboot" 2>/dev/null || true)"
    msg "  prevboot: $($BB readlink "$PROFILES/prevboot" 2>/dev/null || true)"
    die "cannot continue"
fi
msg "handing off to $FOUND/boot/init (from $FROM)"

# --- hand the pseudo filesystems over ---------------------------------------
$BB mkdir -p "$NEWROOT/proc" "$NEWROOT/sys" "$NEWROOT/dev" "$NEWROOT/run"

# sixos' mount targets for /proc and /sys are intentionally no-ops because the
# handoff happens here (s6-linux-init itself needs a working /proc).
$BB mount --move /proc "$NEWROOT/proc"
$BB mount --move /sys  "$NEWROOT/sys"
$BB mount --move /dev  "$NEWROOT/dev"

# Commit the state disk only. A system-wide sync(2) also walks the read-only
# system disk and logs "block: failed to do Write on the device with error
# status: IoError" for it, without reliably reaching /dev/vdb at all (gotcha
# 11). syncfs on /var covers the state disk, and with it the overlay's upper
# layer, which lives there.
$BB sync -f "$NEWROOT/var" 2>/dev/null || true

exec $BB switch_root "$NEWROOT" "$FOUND/boot/init"
