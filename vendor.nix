# dictyonos/vendor.nix
#
# Offline cargo vendor tree for the Asterinas kernel build.
#
# Asterinas has two independent cargo workspaces with their own lockfiles:
#
#   * the kernel workspace   (asterinas/Cargo.lock)
#   * the cargo-osdk utility (asterinas/osdk/Cargo.lock), which is *not* a
#     member of the root workspace
#   * the Rust sysroot crate (the rust-src component's library/Cargo.lock), whose
#     dependencies -Zbuild-std resolves on its own
#
# Both are built in this repository, so the vendor tree has to cover their
# union. rustPlatform.fetchCargoVendor consumes exactly one Cargo.lock, so a
# combined lockfile is synthesised first: the [[package]] blocks are copied
# verbatim and de-duplicated on (name, version). Packages without a `source`
# (workspace-local path dependencies) stay out of the vendor tree -- they are
# shipped in the copied source tree instead.
#
# fetchCargoVendor is a fixed-output derivation pinned by `vendorHash`.
# When any of the lockfiles above changes, rebuild once with a deliberately wrong
# hash and Nix prints the correct one. Do NOT skip that step: Nix keys a
# fixed-output derivation's result purely on the hash, so leaving the old hash in
# place silently reuses the stale vendor tree and the build fails later with a
# confusing "no matching package" error.
{
  pkgs,
  asterinas,
  rustToolchain,
  vendorHash ? "sha256-13M2v4fuD2JsSlu1Qvvd2CK90k4fHCq0u4xovX+JT28=",
}:

let
  kernelLock = asterinas.outPath + "/Cargo.lock";
  osdkLock = asterinas.outPath + "/osdk/Cargo.lock";

  # "cargo osdk build" passes -Zbuild-std, which makes cargo resolve the sysroot
  # crates from the rust-src component's own library workspace. Their
  # dependencies (rustc-literal-escaper et al) are not in either Asterinas
  # lockfile, so that lock has to be part of the vendor tree as well.
  rustLibLock = rustToolchain + "/lib/rustlib/src/rust/library/Cargo.lock";

  mergeTool = pkgs.writeText "merge-cargo-locks.py" (
    builtins.readFile ./scripts/merge-cargo-locks.py
  );

  # A directory whose only content is the merged Cargo.lock; the fetcher reads
  # ./Cargo.lock relative to the unpacked source.
  mergedLockDir = pkgs.runCommand "dictyonos-cargo-locks" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    mkdir -p $out
    python3 ${mergeTool} $out/Cargo.lock ${kernelLock} ${osdkLock} ${rustLibLock}
  '';

  vendor = pkgs.rustPlatform.fetchCargoVendor {
    name = "dictyonos-cargo-vendor";
    src = mergedLockDir;
    hash = vendorHash;
  };
in
{
  inherit mergedLockDir vendor;

  # The fetcher already emits a .cargo/config.toml with an @vendor@ placeholder
  # and correct selectors for every source in the lockfile (crates.io and both
  # git dependencies). Substituting the placeholder is all that is needed; one
  # file serves both cargo and cargo-osdk because the vendor tree holds the
  # union of their dependencies.
  cargoConfig = pkgs.runCommand "dictyonos-cargo-config.toml" { } ''
    substitute ${vendor}/.cargo/config.toml $out \
      --replace-fail "@vendor@" "${vendor}"
    printf '\n[net]\noffline = true\n' >> $out
  '';
}
