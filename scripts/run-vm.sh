#!/usr/bin/env bash
#
# dictyonos/scripts/run-vm.sh -- boot dictyonos under QEMU.
#
# Direct kernel boot: the Asterinas ELF goes straight to QEMU with -kernel, the
# stage-1 initramfs with -initrd, and the sixos closure as an ext2 -drive.
# Neither GRUB nor sixos ownerboot/kexec is involved.
#
# Two disks are attached:
#
#   /dev/vda  the system image, read-only. It is a content-addressed artifact
#             shared through the Nix store, so it must never be written to.
#   /dev/vdb  a small writable state disk, created on first run and reused
#             afterwards. stage1 grafts it over /var. EPHEMERAL=1 throws it
#             away and starts from a blank one.
#
# Usage:
#   ./scripts/run-vm.sh                 interactive serial console
#   AUTO=1 ./scripts/run-vm.sh          boot, run the acceptance checks, exit
#   EPHEMERAL=1 ./scripts/run-vm.sh     start with a blank state disk
#   NET=0 ./scripts/run-vm.sh           boot without a NIC (and without ssh)
#   TIMEOUT=300 ./scripts/run-vm.sh     give up after N seconds
#
# Environment (all optional):
#   DICTYONOS_KERNEL_ELF / DICTYONOS_INITRAMFS / DICTYONOS_ROOTFS / DICTYONOS_CONFIG
#       override the artifacts (nix run sets these for you)
#   DICTYONOS_STATE / DICTYONOS_WORKDIR   where the state disk lives
#   SSH_KEY / SSH_PORT / SSH_WAIT          ssh keypair, forwarded port, timeout
#   MEM, SMP, CPU, QEMU_BIN, ENABLE_KVM, NET, AUTO, AUTO_WAIT, TIMEOUT,
#   CMDLINE, SERIAL_LOG
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

KERNEL_ELF="${DICTYONOS_KERNEL_ELF:-}"
ROOTFS="${DICTYONOS_ROOTFS:-}"
CONFIG="${DICTYONOS_CONFIG:-}"
INITRAMFS="${DICTYONOS_INITRAMFS:-}"

# When invoked through nix run the launcher exports all four of these; called
# directly from a checkout, ask the flake for them instead (a no-op once they
# have been built).
if [ -z "$KERNEL_ELF" ] || [ -z "$ROOTFS" ] || [ -z "$CONFIG" ] || [ -z "$INITRAMFS" ]; then
  KERNEL_ELF="${KERNEL_ELF:-$(nix build --no-link --print-out-paths "$ROOT#kernel")/asterinas-osdk-bin.elf}"
  ROOTFS="${ROOTFS:-$(nix build --no-link --print-out-paths "$ROOT#rootfs")}"
  CONFIG="${CONFIG:-$(nix build --no-link --print-out-paths "$ROOT#system")}"
  INITRAMFS="${INITRAMFS:-$(nix build --no-link --print-out-paths "$ROOT#initramfs")/initrd}"
fi

MEM="${MEM:-8G}"
SMP="${SMP:-1}"
NET="${NET:-1}"
TIMEOUT="${TIMEOUT:-240}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
SSH_PORT="${SSH_PORT:-2222}"
LOG="${SERIAL_LOG:-$PWD/serial.log}"
WORKDIR="${DICTYONOS_WORKDIR:-$PWD/.dictyonos-vm}"
STATE="${DICTYONOS_STATE:-$WORKDIR/state.ext2}"

for f in "$KERNEL_ELF" "$ROOTFS" "$INITRAMFS"; do
  if [ ! -e "$f" ]; then
    echo "error: missing $f" >&2
    echo "       build the artifacts first: nix build .#rootfs" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------- state disk
mkdir -p "$WORKDIR"
if [ "${EPHEMERAL:-0}" = "1" ] || [ ! -e "$STATE" ]; then
  echo "==> creating a 512 MiB state disk at $STATE"
  rm -f "$STATE"
  truncate -s 512M "$STATE"
  mkfs.ext2 -q -F "$STATE"
fi

# ------------------------------------------------------------------ ssh keys
# A throwaway keypair is generated on the host and the public half is handed to
# the guest on the kernel command line. The blob carries no whitespace, which is
# what makes it survive the kernel splitting /proc/cmdline on spaces.
EXTRA_CMDLINE=""
if [ "$NET" != "0" ]; then
  SSH_KEY="${SSH_KEY:-$WORKDIR/id_ed25519}"
  if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -q -t ed25519 -N "" -C dictyonos -f "$SSH_KEY"
  fi
  read -r KEY_TYPE KEY_BLOB _ < "$SSH_KEY.pub"
  EXTRA_CMDLINE="dictyonos.ssh_key_type=$KEY_TYPE dictyonos.ssh_key=$KEY_BLOB"
fi

CMDLINE="${CMDLINE:-$(cat "$CONFIG/boot/kernel-params")}"
CMDLINE="$CMDLINE $EXTRA_CMDLINE"

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
  # QEMU user-mode networking: 10.0.2.0/24, gateway 10.0.2.2, DNS 10.0.2.3, and
  # tcp/<SSH_PORT> on the host forwarded to port 22 in the guest.
  NET_ARGS=(
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
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
  -drive if=none,format=raw,id=rootfs,file="$ROOTFS",readonly=on
  -device virtio-blk-pci,bus=pcie.0,addr=0xc,drive=rootfs,serial=vrootfs,disable-legacy=on,disable-modern=off,queue-size=64,num-queues=1,request-merging=off,backend_defaults=off,discard=off,write-zeroes=off,event_idx=off,indirect_desc=off,queue_reset=off
  -drive if=none,format=raw,id=state,file="$STATE"
  -device virtio-blk-pci,bus=pcie.0,addr=0xd,drive=state,serial=vstate,disable-legacy=on,disable-modern=off,queue-size=64,num-queues=1,request-merging=off,backend_defaults=off,discard=off,write-zeroes=off,event_idx=off,indirect_desc=off,queue_reset=off
  -device virtio-serial-pci,disable-legacy=on,disable-modern=off
  -object rng-random,id=rng0,filename=/dev/urandom
  -device virtio-rng-pci,bus=pcie.0,addr=0x9,disable-legacy=on,disable-modern=off,rng=rng0
  "${NET_ARGS[@]}"
)

echo "==> dictyonos"
echo "    kernel : $KERNEL_ELF"
echo "    initrd : $INITRAMFS"
echo "    rootfs : $ROOTFS (read-only vda)"
echo "    state  : $STATE (writable vdb)"
echo "    net    : $NET"
if [ "$NET" != "0" ]; then
  echo "    ssh    : ssh -i $SSH_KEY -p $SSH_PORT root@127.0.0.1"
fi
echo "    cmdline: $CMDLINE"
echo

run_qemu() {
  timeout --foreground "$TIMEOUT" "$QEMU_BIN" "${QEMU_ARGS[@]}" 2>&1 | tee "$LOG"
}

# Poll for a real ssh handshake and show it in the transcript.
verify_ssh() {
  local deadline=$((SECONDS + ${SSH_WAIT:-120}))
  local opts=(-i "$SSH_KEY" -p "$SSH_PORT"
              -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
              -o BatchMode=yes -o ConnectTimeout=3)
  echo "==> waiting for sshd on 127.0.0.1:$SSH_PORT"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ssh "${opts[@]}" root@127.0.0.1 "echo SSH-OK" 2>/dev/null | grep -q SSH-OK; then
      echo "==> ssh handshake succeeded; running a remote command"
      ssh "${opts[@]}" root@127.0.0.1 "uname -a; cat /proc/1/comm; echo SSH-REMOTE-OK"
      return 0
    fi
    sleep 2
  done
  echo "==> ssh handshake FAILED within ${SSH_WAIT:-120}s" >&2
  return 1
}

if [ "${AUTO:-0}" = "1" ]; then
  # Feed the acceptance commands to the serial getty while, in parallel,
  # verifying that the machine is reachable over ssh.
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
    echo "echo ---- boot env ----; cat /run/boot/init /run/boot/configuration 2>/dev/null; ls -l /run/current-system /bin/sh /usr/bin/env 2>&1"
    sleep 3
    # If sixos' activation got as far as s6-rc-init there is a live directory
    # and every service is up. If not, it aborted -- trace it, because that
    # leaves the machine with nothing but the s6-linux-init early getty and no
    # way to tell why from the console.
    echo "echo ---- activate ----; if [ ! -d /run/s6-rc ]; then bash -x $CONFIG/bin/activate 2>&1 | tail -30; else echo activation-completed; fi"
    sleep 8
    echo "echo ---- disks ----; mount | grep -E 'vda|vdb|/var'"
    sleep 2
    echo "echo ---- net ----; ip -o addr 2>/dev/null | head -4; cat /etc/resolv.conf 2>/dev/null"
    sleep 3
    echo "echo ---- ssh ----; netstat -ltn 2>/dev/null | grep :22; ls -l /var/lib/dropbear 2>/dev/null"
    sleep 3
    echo "echo ---- LIX ----; nix --version"
    sleep 3
    echo "nix eval --expr '1 + 1'"
    sleep 4
    echo "echo DICTYONOS-DONE"
    sleep 2
    echo "poweroff -f"
    sleep 5
  } | run_qemu &
  QEMU_PID=$!

  SSH_RC=0
  if [ "$NET" != "0" ]; then
    verify_ssh 2>&1 | tee -a "$LOG" || SSH_RC=$?
  fi

  wait "$QEMU_PID" || true
  if [ "$SSH_RC" != "0" ]; then
    echo "==> ssh verification failed" >&2
    exit 1
  fi
else
  run_qemu
fi

echo
echo "==> serial log: $LOG"
