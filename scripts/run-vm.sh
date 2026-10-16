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
#   AUTO=1 BOOT2=0 ./scripts/run-vm.sh  only the first of the two acceptance boots
#   EPHEMERAL=1 ./scripts/run-vm.sh     start with a blank state disk
#   NET=0 ./scripts/run-vm.sh           boot without a NIC (and without ssh)
#   TIMEOUT=300 ./scripts/run-vm.sh     give up after N seconds
#
# AUTO=1 boots the machine twice against the same state disk: the first boot runs
# the acceptance checks and writes state, the second proves that the state (and
# dropbear's host key) survived the reboot. See "acceptance" below.
#
# Environment (all optional):
#   DICTYONOS_KERNEL_ELF / DICTYONOS_INITRAMFS / DICTYONOS_ROOTFS / DICTYONOS_CONFIG
#       override the artifacts (nix run sets these for you)
#   DICTYONOS_STATE / DICTYONOS_WORKDIR   where the state disk lives
#   SSH_KEY / SSH_PORT / SSH_WAIT          ssh keypair, forwarded port, timeout
#   SERIAL_LOG / SERIAL_LOG_BOOT2 / SERIAL_LOG_HOST
#       where the boot-1 transcript, the boot-2 transcript and the host-side
#       evidence (ssh, e2fsck, debugfs) are written
#   MEM, SMP, CPU, QEMU_BIN, ENABLE_KVM, NET, AUTO, AUTO_WAIT, BOOT2, TIMEOUT,
#   STEP_WAIT, HALT_WAIT, CMDLINE
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
LOG2="${SERIAL_LOG_BOOT2:-${LOG%.log}-boot2.log}"
HOST_LOG="${SERIAL_LOG_HOST:-${LOG%.log}.host.log}"
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

# Fail immediately if another VM is still holding the forwarded port: QEMU
# would otherwise abort with "Could not set up host forwarding rule" and the
# run would sit through the full TIMEOUT for nothing.
if [ "$NET" != "0" ] && (exec 3<>"/dev/tcp/127.0.0.1/$SSH_PORT") 2>/dev/null; then
  echo "error: 127.0.0.1:$SSH_PORT is already in use (another dictyonos VM?)" >&2
  echo "       stop it, or set SSH_PORT=<other port>" >&2
  exit 1
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

# The transcript goes through a process substitution rather than a pipeline, and
# the shell is replaced by `timeout` itself: that keeps the PID of the pipeline
# element equal to the PID of `timeout`, which is the process stop_vm() has to
# signal (see below), and it keeps QEMU's stdin connected to the feeder.
run_qemu() {
  exec > >(tee "$1") 2>&1
  exec timeout --foreground "$TIMEOUT" "$QEMU_BIN" "${QEMU_ARGS[@]}"
}

# Poll for a real ssh handshake and show it in the transcript. $1 is where the
# host key this boot presents (as a client sees it) is recorded.
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
      # Boot 2 has to present this same key: that is what proves dropbear reused
      # the host key it stored on the state disk instead of making a new one.
      ssh-keyscan -p "$SSH_PORT" -t ed25519 127.0.0.1 2>/dev/null | grep -v '^#' >"$1" || true
      return 0
    fi
    sleep 2
  done
  echo "==> ssh handshake FAILED within ${SSH_WAIT:-120}s" >&2
  return 1
}

# ------------------------------------------------------- host-side checks

# QEMU does not exit when the guest halts: Asterinas cannot power the machine
# off ("Failed to power off the system"), so it halts instead and QEMU sits there
# until `timeout` fires, printing a misleading "terminating on signal 15 ...
# (timeout)" line into the transcript. Wait for the halt and stop the machine.
wait_for_halt() {
  local deadline=$((SECONDS + ${HALT_WAIT:-60}))
  while [ "$SECONDS" -lt "$deadline" ]; do
    grep -q "Halting the machine" "$1" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

# The second boot reuses the same forwarded port and the same state disk, so the
# first machine has to be *gone*: QEMU holds the port for as long as it lives,
# which makes the port a usable proof that the process ended and not just the
# guest.
stop_vm() {
  kill -TERM "$VM_PID" 2>/dev/null || true
  wait "$VM_PID" 2>/dev/null || true
  sleep 1 # let tee finish writing the transcript
  if [ "$NET" = "0" ]; then
    return 0
  fi
  local n
  for n in $(seq 1 20); do
    if ! (exec 3<>"/dev/tcp/127.0.0.1/$SSH_PORT") 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  echo "==> warning: 127.0.0.1:$SSH_PORT is still held after stopping the VM" >&2
  return 1
}

# Everything the guest wrote, read back by the host. debugfs opens the image
# without mounting it (the guest halts rather than shutting down cleanly) and
# e2fsck -fn reports the metadata state of the image.
dump_state() {
  local label="$1" f
  {
    echo
    echo "== $label: e2fsck -fn $STATE =="
    e2fsck -fn "$STATE" 2>&1 || echo "e2fsck exit status: $?"
    for f in /persist-early /persist-late /log/state-sync/current; do
      echo "== $f =="
      debugfs -R "cat $f" "$STATE" 2>/dev/null || true
    done
    echo "== /lib/dropbear =="
    debugfs -R "ls -l /lib/dropbear" "$STATE" 2>/dev/null || true
  } | tee -a "$HOST_LOG"
  rm -f "$WORKDIR/hostkey.file.$label"
  debugfs -R "dump /lib/dropbear/dropbear_ed25519_host_key $WORKDIR/hostkey.file.$label" \
    "$STATE" >/dev/null 2>&1 || true
}

# The host key a client saw, boot 1 against boot 2.
compare_host_keys() {
  {
    echo
    echo "== dropbear host key, as a client sees it =="
    if cmp -s "$WORKDIR/hostkey.scan.boot1" "$WORKDIR/hostkey.scan.boot2"; then
      echo "both boots presented the same key:"
      cat "$WORKDIR/hostkey.scan.boot1"
    else
      echo "MISMATCH between the two boots:"
      echo "  boot 1: $(cat "$WORKDIR/hostkey.scan.boot1" 2>/dev/null)"
      echo "  boot 2: $(cat "$WORKDIR/hostkey.scan.boot2" 2>/dev/null)"
    fi
  } | tee -a "$HOST_LOG"
  cmp -s "$WORKDIR/hostkey.scan.boot1" "$WORKDIR/hostkey.scan.boot2"
}

# The state disk after boot 2: the files the first boot wrote, and the host key
# dropbear must have reused rather than regenerated.
compare_state() {
  local rc=0 early late keys
  early="$(debugfs -R 'cat /persist-early' "$STATE" 2>/dev/null | tr -d '\r\n')"
  late="$(debugfs -R 'cat /persist-late' "$STATE" 2>/dev/null | tr -d '\r\n')"
  if cmp -s "$WORKDIR/hostkey.file.boot1" "$WORKDIR/hostkey.file.boot2"; then
    keys="byte-identical to boot 1"
  else
    keys="CHANGED since boot 1"
    rc=1
  fi
  {
    echo
    echo "== after boot 2, read from the state disk =="
    echo "persist-early: '$early'"
    echo "persist-late:  '$late'"
    echo "host key:      $keys"
  } | tee -a "$HOST_LOG"
  [ "$early" = "early" ] || rc=1
  [ "$late" = "late" ] || rc=1
  return "$rc"
}

# ------------------------------------------------------------------ acceptance
# AUTO=1 boots the machine twice against the same state disk.
#
#   boot 1  the acceptance checks: what the kernel reports, that sixos'
#           activation reached s6-rc, that every longrun is up, that the system
#           disk is read-only and the state disk writable, that the network came
#           up, that Lix evaluates on a read-only store, and that /var reaches
#           the state disk. The host verifies ssh in parallel and then reads the
#           image back with dump_state.
#   boot 2  a fresh machine on that same state disk: the files written by boot 1
#           must still be there with the same contents, and dropbear must present
#           the same host key.
#
# The commands are typed into the guest's serial getty one step at a time. Fixed
# sleeps cannot pace this: one step deliberately sleeps 35 seconds waiting for
# the state-sync tick, and when the host runs ahead the guest's tty echoes the
# next commands while the current one is still running. The transcript then
# interleaves, and anything that cuts it at a marker loses output that was still
# coming. So every step ends with a sentinel that the feeder waits for, typed as
#     echo DICTYONOS-OK-"07"
# so that the echo of the command (the tty echoes what the host types) does not
# itself contain the string being waited for -- only the guest's output does.
AUTO_MARK=0
auto() {
  local mark deadline
  AUTO_MARK=$((AUTO_MARK + 1))
  mark="$(printf '%02d' "$AUTO_MARK")"
  printf '%s; echo DICTYONOS-OK-"%s"\n' "$1" "$mark"
  deadline=$((SECONDS + ${STEP_WAIT:-90}))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if grep -q "DICTYONOS-OK-$mark" "$CURRENT_LOG" 2>/dev/null; then
      sleep 1
      return 0
    fi
    sleep 1
  done
  echo "==> step $AUTO_MARK got no answer from the guest; carrying on" >&2
  return 0
}

auto_boot1() {
  sleep "${AUTO_WAIT:-30}"
  echo ""
  auto "echo ==== DICTYONOS ACCEPTANCE (boot 1) ===="
  auto "uname -a"
  auto "cat /proc/version 2>/dev/null; cat /proc/1/comm 2>/dev/null"
  auto "echo ---- PID 1 ----; readlink /proc/1/exe; ps aux 2>/dev/null"
  # Non-empty means sixos' activation reached s6-rc-init. If it did not, it
  # aborted somewhere in its linkify pass and the machine is sitting in the
  # s6-linux-init early getty with no services at all.
  auto "echo ---- s6 ----; if [ -d /run/s6-rc ]; then echo activation-completed; else echo activation-FAILED; fi; ls /run/service"
  auto "echo ---- svstat ----; for s in ssh ssh-log lix-daemon lix-daemon-log state-sync s6rc-oneshot-runner; do s6-svstat /run/service/\$s; done 2>&1"
  auto "echo ---- svclogs ----; echo '== ssh'; tail -25 /var/log/ssh/current 2>&1; echo '== lix-daemon'; tail -8 /var/log/lix-daemon/current 2>&1; echo '== state-sync'; tail -8 /var/log/state-sync/current 2>&1"
  # Persistence round-trip, run *before* anything else touches the store, so that
  # a failure here isolates the state disk rather than blaming whatever Lix did
  # to /nix/store's mount a moment later.  Only syncfs() on the state disk is
  # asked for: the system-wide sync(2) walks the read-only system disk too and
  # logs "block: failed to do Write ... IoError", which reads like a state-disk
  # failure but is not one.
  auto "echo ---- persist ----; echo early > /var/persist-early; sync -f /var/persist-early; echo targeted-sync-exit=\$?; cat /var/persist-early"
  auto "echo ---- disks ----; mount | grep -E 'vda|vdb|/var'"
  auto "echo ---- net ----; ip -o addr 2>/dev/null | head -4; cat /etc/resolv.conf 2>/dev/null; netstat -ltn 2>/dev/null | grep :22"
  auto "echo ---- LIX ----; nix --version"
  auto "nix eval --expr '1 + 1'"
  # The late half of the round-trip deliberately syncs nothing itself: it waits
  # for the state-sync service's next tick, so the host-side debugfs read proves
  # the service (rather than this shell) committed the state disk.
  auto "echo ---- persist2 ----; echo late > /var/persist-late; sleep 35; cat /var/persist-late; ls -l /var/persist-late /var/persist-early; tail -3 /var/log/state-sync/current"
  auto "echo DICTYONOS-DONE"
  sleep 1
  echo "poweroff -f"
  sleep 5
}

auto_boot2() {
  sleep "${AUTO_WAIT:-30}"
  echo ""
  auto "echo ==== DICTYONOS ACCEPTANCE (boot 2, same state disk) ===="
  auto "echo ---- persistence ----; cat /var/persist-early; cat /var/persist-late; ls -l /var/persist-early /var/persist-late"
  auto "echo ---- host key ----; dropbearkey -y -f /var/lib/dropbear/dropbear_ed25519_host_key | tail -2"
  auto "echo ---- state-sync log ----; tail -3 /var/log/state-sync/current"
  # The verdict is printed with its first word split off, so that this command
  # line -- which the tty echoes back -- does not itself contain the string the
  # host searches the transcript for.
  auto "if [ \"$(cat /var/persist-early 2>/dev/null)\" = early ] && [ \"$(cat /var/persist-late 2>/dev/null)\" = late ]; then echo REBOOT-PERSISTENCE-\"OK\"; else echo REBOOT-PERSISTENCE-\"FAILED\"; fi"
  auto "echo DICTYONOS-DONE"
  sleep 1
  echo "poweroff -f"
  sleep 5
}

# Run one boot: feed it the commands, verify ssh against it while it comes up,
# then stop the machine once it has halted.
VM_PID=""
run_boot() {
  local feeder="$1" log="$2" keys="$3" rc=0
  CURRENT_LOG="$log"
  "$feeder" | run_qemu "$log" &
  VM_PID=$!
  if [ "$NET" != "0" ]; then
    verify_ssh "$keys" 2>&1 | tee -a "$HOST_LOG" || rc=$?
  fi
  if wait_for_halt "$log"; then
    stop_vm
  else
    echo "==> the guest never halted; waiting for TIMEOUT" >&2
    wait "$VM_PID" || true
  fi
  return "$rc"
}

if [ "${AUTO:-0}" = "1" ]; then
  : >"$HOST_LOG"
  FAIL=0
  CURRENT_LOG=""
  VM_PID=""

  if run_boot auto_boot1 "$LOG" "$WORKDIR/hostkey.scan.boot1"; then :; else
    echo "==> boot 1: ssh verification failed" >&2
    FAIL=1
  fi
  dump_state boot1

  if [ "${BOOT2:-1}" = "1" ]; then
    if run_boot auto_boot2 "$LOG2" "$WORKDIR/hostkey.scan.boot2"; then :; else
      echo "==> boot 2: ssh verification failed" >&2
      FAIL=1
    fi
    dump_state boot2
    compare_host_keys || FAIL=1
    compare_state || FAIL=1
    if ! grep -q "REBOOT-PERSISTENCE-OK" "$LOG2"; then
      echo "==> boot 2 did not report REBOOT-PERSISTENCE-OK" >&2
      FAIL=1
    fi
    if grep -q "REBOOT-PERSISTENCE-FAILED" "$LOG2"; then
      echo "==> boot 2 reported REBOOT-PERSISTENCE-FAILED" >&2
      FAIL=1
    fi
  fi

  if [ "$FAIL" != "0" ]; then
    echo "==> acceptance FAILED" >&2
    exit 1
  fi
  if [ "${BOOT2:-1}" = "1" ]; then
    echo "==> REBOOT-PERSISTENCE-OK"
  fi
  echo "==> acceptance passed"
else
  run_qemu "$LOG"
fi

echo
echo "==> boot-1 transcript: $LOG"
if [ "${AUTO:-0}" = "1" ] && [ "${BOOT2:-1}" = "1" ]; then
  echo "==> boot-2 transcript: $LOG2"
fi
echo "==> host-side evidence: $HOST_LOG"
