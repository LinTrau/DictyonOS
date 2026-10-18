#!/usr/bin/env bash
#
# Assemble a prebuilt, Nix-free dictyonos release bundle in dist/.
#
#   ./scripts/make-release-bundle.sh dictyonos-v0.1.0-x86_64
#
# The bundle is what a release attaches: the kernel ELF, the stage-1
# initramfs, the ext2 root filesystem, the kernel command line that goes with
# them, and a start.sh that boots all of it.  A host with qemu-system-x86_64,
# e2fsprogs and openssh can run it without Nix.
#
# Everything is resolved through the Nix store rather than copied out of a
# build directory, so the bundle is byte-for-byte the same wherever it is
# assembled.  Nothing here is committed: dist/ is ignored.
set -euo pipefail

name=${1:?usage: make-release-bundle.sh <bundle-name>}
cd "$(dirname "$0")/.."

kernel=$(nix build .#kernel --no-link --print-out-paths)
initrd=$(nix build .#initramfs --no-link --print-out-paths)
rootfs=$(nix build .#rootfs --no-link --print-out-paths)
system=$(nix build .#system --no-link --print-out-paths)

bundle="dist/$name"
rm -rf "$bundle"
mkdir -p "$bundle"

install -m 0555 "$kernel/asterinas-osdk-bin.elf" "$bundle/asterinas-osdk-bin.elf"
install -m 0444 "$initrd/initrd" "$bundle/initramfs.cpio.gz"
install -m 0444 "$rootfs" "$bundle/rootfs.ext2"
install -m 0444 "$system/boot/kernel-params" "$bundle/kernel-params"
install -m 0644 LICENSE README.md README.zh-CN.md ACCEPTANCE.md flake.lock "$bundle/"
# The READMEs point at assets/logo.png; keep the bundle's copy of them valid.
install -d "$bundle/assets"
install -m 0644 assets/logo.png "$bundle/assets/logo.png"
install -m 0755 scripts/run-vm.sh "$bundle/run-vm.sh"

cat > "$bundle/start.sh" <<'START_SH'
#!/usr/bin/env sh
#
# Boot the prebuilt dictyonos VM. Everything it needs is in this directory:
# a host with qemu-system-x86_64, mkfs.ext2/e2fsck (e2fsprogs) and ssh/ssh-keygen
# (openssh) is enough. No Nix, no compiler, nothing to build.
#
#   ./start.sh                  interactive serial console (ctrl-a x to quit)
#   AUTO=1 ./start.sh           boot twice, run the acceptance checks, exit
#   EPHEMERAL=1 ./start.sh      start from a blank state disk
#
# The writable state disk lives in ./.dictyonos-vm/state.ext2 unless you set
# DICTYONOS_STATE or DICTYONOS_WORKDIR. ssh is forwarded to 127.0.0.1:2222.
set -eu
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export DICTYONOS_KERNEL_ELF="$DIR/asterinas-osdk-bin.elf"
export DICTYONOS_INITRAMFS="$DIR/initramfs.cpio.gz"
export DICTYONOS_ROOTFS="$DIR/rootfs.ext2"
if [ -z "${CMDLINE:-}" ]; then
  CMDLINE="$(cat "$DIR/kernel-params")"
  export CMDLINE
fi
exec "$DIR/run-vm.sh" "$@"
START_SH
chmod 0755 "$bundle/start.sh"

tar -C dist -I 'zstd -19 -T0' -cf "dist/$name-qemu.tar.zst" "$name"
# The bare ELF is attached next to the archive as well: it is the one file
# someone may want on its own, and rm -f keeps a read-only copy from an
# earlier run from turning install into EACCES.
rm -f dist/asterinas-osdk-bin.elf
install -m 0644 "$kernel/asterinas-osdk-bin.elf" dist/asterinas-osdk-bin.elf
( cd dist && sha256sum "$name-qemu.tar.zst" asterinas-osdk-bin.elf > SHA256SUMS )

echo "== $bundle"
ls -l "$bundle"
echo
echo "== dist"
ls -l dist
echo
cat dist/SHA256SUMS
