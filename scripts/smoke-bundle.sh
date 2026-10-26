#!/usr/bin/env bash
#
# Boot a release bundle and prove it is usable before anyone downloads it.
#
#   ./scripts/smoke-bundle.sh dist/dictyonos-v0.2.0-x86_64-qemu.tar.zst
#   ./scripts/smoke-bundle.sh dist/dictyonos-v0.2.0-x86_64
#
# The bundle is unpacked into a scratch directory and booted with the start.sh
# it ships, so the smoke test exercises exactly the files the release attaches
# and nothing from the Nix store. It then waits for ssh, runs a command in the
# guest, asks the guest to power itself off, and checks that the launcher
# translated QEMU's poweroff status into success.
#
# The release workflow calls this before it publishes. A bundle that cannot
# boot, cannot answer ssh, or cannot shut itself down must not be attached to a
# release.
#
# Needs qemu-system-x86_64, mkfs.ext2 (e2fsprogs), ssh/ssh-keygen (openssh),
# timeout (coreutils), pkill (procps) and, for a .tar.zst, zstd.
set -euo pipefail

bundle="${1:-}"
if [ -z "$bundle" ]; then
  echo "usage: smoke-bundle.sh <dist/dictyonos-*-x86_64 | dist/dictyonos-*-x86_64-qemu.tar.zst>" >&2
  exit 2
fi
if [ ! -e "$bundle" ]; then
  echo "error: $bundle does not exist" >&2
  exit 2
fi

# The guest boots in roughly 30s under KVM. The TCG fallback CI runners use is
# several times slower, hence the generous defaults.
port="${SMOKE_SSH_PORT:-2222}"
boot_timeout="${SMOKE_TIMEOUT:-900}"
ssh_wait="${SMOKE_SSH_WAIT:-600}"

work="$(mktemp -d)"
vm_pid=""
cleanup() {
  if [ -n "$vm_pid" ]; then
    kill "$vm_pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$vm_pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$vm_pid" 2>/dev/null || true
  fi
  # QEMU runs under `timeout` in a subshell, so the launcher being gone is not
  # proof the machine is: match the machine by the scratch rootfs path instead.
  pkill -f "$work/bundle/rootfs.ext2" 2>/dev/null || true
  # SMOKE_ARTIFACTS keeps the transcripts around for a CI failure: a smoke test
  # that only says "it did not boot" is not much use from another machine.
  if [ -n "${SMOKE_ARTIFACTS:-}" ] && [ -d "$work" ]; then
    mkdir -p "$SMOKE_ARTIFACTS"
    cp -a "$work"/console.log "$SMOKE_ARTIFACTS"/ 2>/dev/null || true
    for f in "$work/bundle/serial.log" "$work/bundle/serial-boot2.log" \
             "$work/bundle/serial.host.log"; do
      [ -f "$f" ] && cp -a "$f" "$SMOKE_ARTIFACTS"/ || true
    done
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

case "$bundle" in
*.tar.zst)
  mkdir -p "$work/bundle"
  tar -C "$work/bundle" --strip-components=1 -I zstd -xf "$bundle"
  ;;
*.tar.gz | *.tgz)
  mkdir -p "$work/bundle"
  tar -C "$work/bundle" --strip-components=1 -xzf "$bundle"
  ;;
*)
  mkdir -p "$work/bundle"
  cp -a "$bundle"/. "$work/bundle"/
  ;;
esac

bundle_dir="$work/bundle"
for f in start.sh asterinas-osdk-bin.elf initramfs.cpio.gz rootfs.ext2 kernel-params; do
  if [ ! -s "$bundle_dir/$f" ]; then
    echo "error: $bundle is missing $f" >&2
    exit 1
  fi
done
echo "==> smoking $bundle"

# Ninja the state disk and the console transcript into the scratch directory.
# EPHEMERAL=1 keeps a leftover disk from an earlier run from deciding what
# boots, which is what a first-time downloader would see anyway.
console="$work/console.log"
(
  cd "$bundle_dir"
  EPHEMERAL=1 NET=1 TIMEOUT="$boot_timeout" SSH_PORT="$port" ./start.sh
) < /dev/null > "$console" 2>&1 &
vm_pid=$!

fail() {
  echo "==> smoke FAILED: $1" >&2
  echo "---- console (tail) ----" >&2
  tail -40 "$console" >&2 || true
  exit 1
}

ssh_opts=(-i "$bundle_dir/.dictyonos-vm/id_ed25519" -p "$port"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o BatchMode=yes -o ConnectTimeout=3 -o LogLevel=ERROR)
deadline=$((SECONDS + ssh_wait))
while :; do
  if ! kill -0 "$vm_pid" 2>/dev/null; then
    rc=0
    wait "$vm_pid" || rc=$?
    vm_pid=""
    fail "the launcher exited ($rc) before ssh came up"
  fi
  if [ -f "$bundle_dir/.dictyonos-vm/id_ed25519" ] \
     && ssh "${ssh_opts[@]}" root@127.0.0.1 true 2>/dev/null; then
    break
  fi
  [ "$SECONDS" -lt "$deadline" ] || fail "ssh did not answer within ${ssh_wait}s"
  sleep 2
done
echo "==> ssh answers on 127.0.0.1:$port"

remote="$(ssh "${ssh_opts[@]}" root@127.0.0.1 \
  'uname -a; cat /proc/1/comm; echo BUNDLE-SMOKE-OK' 2>&1)" \
  || fail "the command run over ssh failed"
printf '%s\n' "$remote"
grep -q '^Linux dictyonos ' <<<"$remote" || fail "uname -a does not name the dictyonos guest"
grep -qx 's6-svscan' <<<"$remote" || fail "PID 1 is not s6-svscan"
grep -qx 'BUNDLE-SMOKE-OK' <<<"$remote" || fail "the guest did not echo the smoke marker"

# The guest powers itself off, so the launcher's own exit status is the thing
# under test: it has to translate QEMU's 33 into success.
ssh "${ssh_opts[@]}" root@127.0.0.1 'poweroff -f' >/dev/null 2>&1 || true
# The launcher's own TIMEOUT bounds this wait, so no second one is needed.
rc=0
wait "$vm_pid" || rc=$?
vm_pid=""
[ "$rc" = "0" ] || fail "the launcher exited $rc after the guest powered off"
grep -q 'powered the machine off' "$console" \
  || fail "the launcher did not report the guest powering off"

echo "==> the bundle boots, answers ssh and powers off by itself"
echo "==> smoke passed"
