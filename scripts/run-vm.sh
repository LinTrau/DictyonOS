#!/usr/bin/env bash
#
# dictyonos/scripts/run-vm.sh -- boot dictyonos under QEMU.
#
# Direct kernel boot: the Asterinas ELF goes straight to QEMU with -kernel, the
# stage-1 initramfs with -initrd, and the sixos closure as an ext2 -drive.
# Neither GRUB nor sixos' ownerboot/kexec path is involved.
#
#   ./scripts/run-vm.sh                 interactive serial console
#   AUTO=1 ./scripts/run-vm.sh          boot, run the acceptance checks, exit
#   NET=0 ./scripts/run-vm.sh           boot without a NIC
#   TIMEOUT=300 ./scripts/run-vm.sh     give up after N seconds
#
# Environment (all optional):
#   DICTYONOS_KERNEL_ELF / DICTYONOS_INITRAMFS / DICTYONOS_ROOTFS / DICTYONOS_CONFIG
#       override the artifacts (nix run sets these for you)
#   MEM, SMP, CPU, QEMU_BIN, ENABLE_KVM, NET, AUTO, AUTO_WAIT, TIMEOUT, CMDLINE
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

KERNEL_ELF="${DICTYONOS_KERNEL_ELF:-$ROOT/kernel/asterinas-osdk-bin.elf}"
ROOTFS="${DICTYONOS_ROOTFS:-$ROOT/build/rootfs.ext2}"
CONFIG="${DICTYONOS_CONFIG:-$ROOT/build/result}"
INITRAMFS="${DICTYONOS_INITRAMFS:-$ROOT/build/initramfs/initrd}"

MEM="${MEM:-8G}"
SMP="${SMP:-1}"
NET="${NET:-1}"
TIMEOUT="${TIMEOUT:-240}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
# 'nix run' executes this from the store, where $ROOT is read-only; log to the
# caller's working directory instead.
LOG="${SERIAL_LOG:-$PWD/serial.log}"

for f in "$KERNEL_ELF" "$ROOTFS" "$INITRAMFS"; do
  if [ ! -e "$f" ]; then
    echo "error: missing $f" >&2
    echo "       build the artifacts first: ./scripts/build-kernel.sh && nix build .#rootfs" >&2
    exit 1
  fi
done

# CMDLINE can be overridden to experiment with kernel parameters without
# rebuilding the image.
CMDLINE="${CMDLINE:-$(cat "$CONFIG/boot/kernel-params")}"

# The rootfs produced by nix is an immutable, read-only store object, and a
# running system needs a writable disk. Boot from a private copy instead.
WORKDIR="${DICTYONOS_WORKDIR:-$PWD/.dictyonos-vm}"
if [ -w "$ROOTFS" ]; then
  DISK="$ROOTFS"
else
  mkdir -p "$WORKDIR"
  DISK="$WORKDIR/rootfs.ext2"
  if [ "${RESET_DISK:-1}" = "1" ] || [ ! -e "$DISK" ] || [ "$ROOTFS" -nt "$DISK" ]; then
    echo "==> staging a writable copy of the root filesystem"
    cp -f "$ROOTFS" "$DISK"
    chmod u+w "$DISK"
  fi
fi

ACCEL=""
CPU="${CPU:-Icelake-Server,+x2apic,+vmx}"
if [ "${ENABLE_KVM:-1}" = "1" ] && [ -e /dev/kvm ]; then
  ACCEL="-accel kvm"
  # A named CPU model only works under KVM when the host supports every feature
  # it implies; the host CPU is the safe default.
  CPU="${CPU:-host}"
fi

NET_ARGS=()
if [ "$NET" != "0" ]; then
  # QEMU user-mode networking: 10.0.2.0/24, gateway 10.0.2.2, DNS 10.0.2.3.
  NET_ARGS=(
    -netdev "user,id=net0"
    -device "virtio-net-pci,netdev=net0,disable-legacy=on,disable-modern=off"
  )
fi

QEMU_ARGS=(
  -machine q35,kernel-irqchip=split
  -cpu "$CPU"
  -smp "$SMP"
  -m "$MEM"
  --no-reboot
  -nographic
  -display none
  -monitor none
  -serial stdio
  $ACCEL
  -kernel "$KERNEL_ELF"
  -initrd "$INITRAMFS"
  -append "$CMDLINE"
  -drive if=none,format=raw,id=rootfs,file="$DISK"
  -device virtio-blk-pci,bus=pcie.0,addr=0xc,drive=rootfs,serial=vrootfs,disable-legacy=on,disable-modern=off,queue-size=64,num-queues=1,request-merging=off,backend_defaults=off,discard=off,write-zeroes=off,event_idx=off,indirect_desc=off,queue_reset=off
  -device virtio-serial-pci,disable-legacy=on,disable-modern=off
  -object rng-random,id=rng0,filename=/dev/urandom
  -device virtio-rng-pci,bus=pcie.0,addr=0x9,disable-legacy=on,disable-modern=off,rng=rng0
  "${NET_ARGS[@]}"
)

echo "==> dictyonos"
echo "    kernel : $KERNEL_ELF"
echo "    initrd : $INITRAMFS"
echo "    rootfs : $DISK"
echo "    net    : $NET"
echo "    cmdline: $CMDLINE"
echo

run_qemu() {
  timeout --foreground "$TIMEOUT" "$QEMU_BIN" "${QEMU_ARGS[@]}" 2>&1 | tee "$LOG"
}

if [ "${AUTO:-0}" = "1" ]; then
  # Feed the acceptance commands to the serial getty. The guest needs a while to
  # reach a shell, hence the sleeps.
  {
    sleep "${AUTO_WAIT:-30}"
    echo ""
    echo "echo ==== DICTYONOS ACCEPTANCE ===="
    sleep 1
    echo "uname -a"
    sleep 2
    echo "cat /proc/version 2>/dev/null; cat /proc/1/comm 2>/dev/null"
    sleep 2
    echo "echo ---- PID 1 ----; readlink /proc/1/exe; ps aux 2>/dev/null | head -20"
    sleep 3
    echo "echo ---- s6 ----; ls /run/s6-rc /run/service 2>/dev/null"
    sleep 3
    echo "echo ---- net ----; ip -o addr 2>/dev/null; cat /etc/resolv.conf 2>/dev/null"
    sleep 3
    echo "echo ---- LIX ----; nix --version"
    sleep 3
    echo "nix eval --expr '1 + 1'"
    sleep 4
    echo "echo DICTYONOS-DONE"
    sleep 2
    echo "poweroff -f"
    sleep 5
  } | run_qemu
else
  run_qemu
fi

echo
echo "==> serial log: $LOG"
