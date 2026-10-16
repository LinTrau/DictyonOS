# dictyonos/kernel.nix
#
# Builds the Asterinas kernel payload (asterinas-osdk-bin.elf) as a pure Nix
# derivation: no network, no host-local helper script, no untracked artifact in
# the tree.
#
# Three upstream details drive the shape of this expression; all of them were
# read out of the Asterinas sources rather than guessed:
#
#   * cargo-osdk is built with OSDK_LOCAL_DEV=1. That flag makes it emit
#     *absolute* paths (derived from its own CARGO_MANIFEST_DIR at compile
#     time) for the ostd / frame-allocator / heap-allocator dependencies of the
#     base crate it generates. Without the flag those become crates.io version
#     requirements that are not in the vendor tree, so an offline build fails.
#     Both the install and the kernel build therefore run inside the same
#     copied source tree, which keeps those baked-in paths valid.
#
#   * kernel/core/src/vdso.rs embeds the Linux vDSOs with env!(), so
#     VDSO_LIBRARY_DIR has to be set at compile time.
#
#   * cargo-osdk overwrites OSDK_BUILD_USERNAME / OSDK_BUILD_HOSTNAME with
#     whoami(1) output for the cargo child it spawns. A cargo shim earlier on
#     PATH is the only way to keep those -- and therefore /proc/version -- free
#     of the build machine identity.
{ lib, pkgs, asterinas, cargoConfig, vendor }:

let
  buildUser = "dictyonos";
  buildHost = "builder";

  # Sits in front of the real cargo. See the header comment.
  cargoShim = pkgs.writeShellScript "cargo" ''
    self_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    real_cargo=""
    old_ifs="$IFS"
    IFS=:
    for d in $PATH; do
      [ "$d" = "$self_dir" ] && continue
      if [ -x "$d/cargo" ]; then real_cargo="$d/cargo"; break; fi
    done
    IFS="$old_ifs"
    if [ -z "$real_cargo" ]; then
      echo "cargo shim: could not find the real cargo on PATH" >&2
      exit 127
    fi
    # PATH deliberately keeps pointing at this shim: cargo-osdk spawns cargo
    # again deeper down, and that invocation has to be intercepted as well.
    export OSDK_BUILD_USERNAME="${buildUser}"
    export OSDK_BUILD_HOSTNAME="${buildHost}"
    export KBUILD_BUILD_USER="$OSDK_BUILD_USERNAME"
    export KBUILD_BUILD_HOST="$OSDK_BUILD_HOSTNAME"

    # Keep absolute store paths out of the payload. rustc records the source path
    # of every compilation unit in panic messages, Nix's reference scanner then
    # treats the kernel as depending on its entire build toolchain (a 3.6 GiB
    # closure for a 21 MiB artifact). Remapping the two roots that leak keeps the
    # closure honest. OSDK sets RUSTFLAGS itself, hence appending rather than
    # overriding.
    export RUSTFLAGS="''${RUSTFLAGS:+$RUSTFLAGS }--remap-path-prefix=${pkgs.asterinas-rust-toolchain}=/rust --remap-path-prefix=${vendor}=/vendor"
    export RUSTFLAGS
    exec "$real_cargo" "$@"
  '';

  shimDir = pkgs.linkFarm "dictyonos-cargo-shim" [
    { name = "cargo"; path = cargoShim; }
  ];
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "asterinas-kernel";
  version = "0.19.0";

  dontUnpack = true;
  dontConfigure = true;
  dontFixup = true;
  dontStrip = true;

  nativeBuildInputs = [
    pkgs.asterinas-rust-toolchain
    # The microvm scheme asks cargo-osdk to strip the payload, which it does by
    # invoking rust-strip from cargo-binutils.
    pkgs.cargo-binutils
    # scripts/vendor-git-deps.py
    pkgs.python3
  ];

  # kernel/core/src/vdso.rs reads this with env!() at compile time.
  VDSO_LIBRARY_DIR = "${pkgs.asterinas-vdso}";

  buildPhase = ''
    runHook preBuild

    export HOME="$NIX_BUILD_TOP/home"
    mkdir -p "$HOME"

    # An offline .cargo/config.toml built from the vendor tree: crates.io and
    # both git dependencies resolve to local directories.
    export CARGO_HOME="$NIX_BUILD_TOP/cargo-home"
    mkdir -p "$CARGO_HOME"
    cp ${cargoConfig} "$CARGO_HOME/config.toml"

    export PATH="${shimDir}:$PATH"

    # A writable copy of the pinned Asterinas tree. The sandbox path is always
    # ASCII, so the percent-encoding workaround the old host script needed is
    # not required here.
    cp -a --no-preserve=mode ${asterinas.outPath} source
    chmod -R u+w source
    rm -rf source/.git source/target

    # The two workspace-level dependencies that live in git repositories are
    # handed to cargo as path dependencies (scripts/vendor-git-deps.py). That is
    # what makes the build lockfile-free -- cargo refuses to resolve a *replaced*
    # git source without a pre-existing lock, and cargo-osdk regenerates its base
    # crate (a fresh workspace with no lock) on every build.
    #
    # The catch: cargo passes --cap-lints=allow to non-path dependencies only,
    # and both crates gate their build on #![deny(missing_docs)]. So take a
    # private copy of each and relax that single documentation lint; nothing else
    # in them is touched.
    mkdir -p vendored
    for crate in ${vendor}/source-git-*/*/; do
      name="$(basename "$crate")"
      cp -a --no-preserve=mode "$crate" "vendored/$name"
      chmod -R u+w "vendored/$name"
      # "|| true" matters: grep exits 1 when a crate has no such lint, and
      # stdenv runs the phase under errexit + pipefail, which would abort the
      # whole build without a word.
      for f in $(grep -rl 'deny(missing_docs)' "vendored/$name" || true); do
        sed -i 's/deny(missing_docs)/allow(missing_docs)/g' "$f"
      done
    done
    python3 ${./scripts/vendor-git-deps.py} source/Cargo.toml ${vendor} "$PWD/vendored"

    echo "==> installing cargo-osdk"
    (
      cd source/osdk
      OSDK_LOCAL_DEV=1 cargo install cargo-osdk \
        --path . \
        --root "$CARGO_HOME" \
        --locked \
        --offline
    )

    # The microvm scheme is vmm-direct -- the bare multiboot2 ELF QEMU wants for
    # -kernel -- and additionally asks cargo-osdk to strip the payload, which is
    # what the upstream project does for this boot protocol. Stripping matters
    # beyond size: unstripped DWARF names every store path it was built from, and
    # Nix's reference scanner would follow them.
    echo "==> cargo osdk build"
    (
      cd source/kernel
      "$CARGO_HOME/bin/cargo-osdk" osdk build \
        --scheme microvm \
        --target-arch x86_64 \
        --kcmd-args="loglevel=warn" \
        --kcmd-args="earlycon" \
        --kcmd-args="console=ttyS0"
    )

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    elf="$(find source/target/osdk -maxdepth 1 -name '*.elf' -print -quit)"
    if [ -z "$elf" ]; then
      echo "asterinas-kernel: cargo osdk produced no ELF under source/target/osdk" >&2
      ls -la source/target/osdk >&2 || true
      exit 1
    fi

    # /proc/version is assembled from the two OSDK_BUILD_* values at compile
    # time, so both end up in the payload as string literals. Verify that the
    # shim did its job:
    #
    #   * the *build user* is a precise signal -- in a Nix sandbox it is nixbldN,
    #     a string that has no business appearing anywhere in the kernel;
    #   * the *build host* only matters when the build is not sandboxed, because
    #     a sandboxed build always reports a generic name. Generic names are
    #     skipped so that a legitimate occurrence of e.g. "localhost" in a
    #     dependency cannot fail the build.
    build_user="$(id -un 2>/dev/null || true)"
    if [ -n "$build_user" ] && grep -a -q "$build_user" "$elf"; then
      echo "asterinas-kernel: build user ($build_user) leaked into the payload" >&2
      exit 1
    fi

    build_host="$(cat /proc/sys/kernel/hostname 2>/dev/null || true)"
    case "$build_host" in
      "" | localhost | builder | nixos) : ;;
      *)
        if grep -a -q "$build_host" "$elf"; then
          echo "asterinas-kernel: build host ($build_host) leaked into the payload" >&2
          exit 1
        fi
        ;;
    esac

    mkdir -p $out
    cp -f "$elf" "$out/asterinas-osdk-bin.elf"
    runHook postInstall
  '';

  passthru = {
    inherit buildUser buildHost;
  };

  meta = {
    description = "Asterinas framekernel payload (multiboot2 ELF) for dictyonos";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mpl20;
  };
})
