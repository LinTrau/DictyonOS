#!/usr/bin/env bash
#
# dictyonos/scripts/build-kernel.sh -- produce the Asterinas kernel payload.
#
# Two upstream quirks shape this script:
#
#   1. cargo-osdk turns the workspace path into a percent-encoded string and then
#      chdir()s into it, so a workspace under a directory with non-ASCII
#      characters aborts with ENOENT. When that is detected the source is
#      mirrored into an ASCII cache directory and built there.
#
#   2. OSDK_LOCAL_DEV bakes CARGO_MANIFEST_DIR into the cargo-osdk binary at
#      compile time. The tool is therefore always (re)installed from the same
#      tree it will build in, into a private CARGO_HOME, so a stale binary can
#      never mix two paths (which cargo reports as a lockfile package
#      collision).
#
# Usage:
#   ./scripts/build-kernel.sh
#
# Environment:
#   DICTYONOS_KERNEL_OUT   where to drop the payload (default ./kernel/)
#   DICTYONOS_CACHE        cache root (default XDG_CACHE_HOME/dictyonos-build-mirror)
#   DICTYONOS_BUILD_USER   /proc/version "compile by" field (default dictyonos)
#   DICTYONOS_BUILD_HOST   /proc/version "compile host" field (default builder)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

CACHE_ROOT="${DICTYONOS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/dictyonos-build-mirror}"
MIRROR="$CACHE_ROOT/asterinas"
SHIM_DIR="$CACHE_ROOT/shim"
OUT_ELF="${DICTYONOS_KERNEL_OUT:-$ROOT/kernel/asterinas-osdk-bin.elf}"

export CARGO_HOME="${CARGO_HOME:-$CACHE_ROOT/cargo-home}"
export OSDK_BUILD_USERNAME="${DICTYONOS_BUILD_USER:-dictyonos}"
export OSDK_BUILD_HOSTNAME="${DICTYONOS_BUILD_HOST:-builder}"
export KBUILD_BUILD_USER="$OSDK_BUILD_USERNAME"
export KBUILD_BUILD_HOST="$OSDK_BUILD_HOSTNAME"

log() { printf '==> %s\n' "$*"; }

# Percent-encoding of a non-ASCII path is what breaks cargo-osdk.
has_non_ascii() { printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]'; }

mirror_source() {
  log "mirroring $1 -> $2"
  mkdir -p "$CACHE_ROOT"
  rm -rf "$2"
  cp -a "$1" "$2"
  chmod -R u+w "$2"
  rm -rf "$2/target"
}

# ---------------------------------------------------------------- locate source
if [ -f "$ROOT/../asterinas/flake.nix" ]; then
  SRC="$(cd "$ROOT/../asterinas" && pwd)"
  log "using the sibling Asterinas checkout at $SRC"
else
  log "resolving the pinned Asterinas source from the flake input"
  SRC="$(nix build --no-link --print-out-paths "$ROOT#asterinas-source")"
fi

# ------------------------------------------------------------- choose build dir
if has_non_ascii "$SRC"; then
  log "non-ASCII characters detected in $SRC"
  WORK="$MIRROR"
  mirror_source "$SRC" "$WORK"
elif [ -w "$SRC" ]; then
  log "path is pure ASCII and writable; building in place"
  WORK="$SRC"
else
  log "source tree is read-only; mirroring it into the cache"
  WORK="$MIRROR"
  mirror_source "$SRC" "$WORK"
fi

# --------------------------------------------------------------- cargo shim
# cargo-osdk overwrites OSDK_BUILD_USERNAME / OSDK_BUILD_HOSTNAME with whoami(1)
# output for the cargo child it spawns. Sitting in front of cargo on PATH is the
# only way to redact them without patching upstream.
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/cargo" <<'SHIM'
#!/bin/sh
# Replace the build metadata cargo-osdk is about to inject, then hand over to
# the real cargo (with this directory removed from PATH).
self_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
new_path=""
old_ifs="$IFS"
IFS=:
for d in $PATH; do
  [ "$d" = "$self_dir" ] && continue
  new_path="${new_path:+$new_path:}$d"
done
IFS="$old_ifs"
PATH="$new_path"
export PATH
export OSDK_BUILD_USERNAME="${OSDK_BUILD_USERNAME:-dictyonos}"
export OSDK_BUILD_HOSTNAME="${OSDK_BUILD_HOSTNAME:-builder}"
export KBUILD_BUILD_USER="$OSDK_BUILD_USERNAME"
export KBUILD_BUILD_HOST="$OSDK_BUILD_HOSTNAME"
exec cargo "$@"
SHIM
chmod +x "$SHIM_DIR/cargo"
export PATH="$SHIM_DIR:$PATH"

log "work directory: $WORK"
log "cargo home:     $CARGO_HOME"
log "building; this takes a few minutes"

export WORK
nix develop "$ROOT#kernel" -c bash -euo pipefail -c '
  cd "$WORK"

  stamp="$CARGO_HOME/.osdk-source-path"
  if [ ! -x "$CARGO_HOME/bin/cargo-osdk" ] || [ "$(cat "$stamp" 2>/dev/null || true)" != "$WORK" ]; then
    echo "==> installing cargo-osdk (OSDK_LOCAL_DEV=1)"
    OSDK_LOCAL_DEV=1 cargo install cargo-osdk --path osdk --root "$CARGO_HOME" --locked
    printf "%s" "$WORK" > "$stamp"
  fi

  echo "==> cargo osdk build"
  cd kernel
  cargo osdk build --boot-method vmm-direct \
    --kcmd-args="loglevel=warn" \
    --kcmd-args="earlycon" \
    --kcmd-args="console=ttyS0"
'

# ------------------------------------------------------------------- install
ELF="$WORK/target/osdk/asterinas-osdk-bin.elf"
if [ ! -f "$ELF" ]; then
  ELF="$(find "$WORK/target/osdk" -maxdepth 1 -name '*.elf' -print -quit)"
fi
if [ ! -f "$ELF" ]; then
  echo "error: no kernel ELF was produced under $WORK/target/osdk" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_ELF")"
cp -f "$ELF" "$OUT_ELF"
log "kernel payload: $OUT_ELF"
ls -l "$OUT_ELF"

cat <<EOF

Next:
  nix build .#rootfs     # assemble the ext2 image
  nix run                # boot it under QEMU

If Nix keeps using an older kernel input, refresh it with:
  nix flake update kernel
EOF
