# dictyonos

A bootable QEMU machine that fuses three independent upstream projects:

| layer | upstream | role |
| --- | --- | --- |
| kernel | [Asterinas](https://github.com/asterinas/asterinas) | Safe-Rust framekernel, Linux-ABI compatible |
| init + userland | [sixos](https://codeberg.org/amjoseph/sixos) + [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | `s6` / `s6-rc` instead of systemd; infuse combinators instead of the NixOS module system |
| package manager | [Lix](https://lix.systems/) | the system-default `nix` |

The result boots to a serial root shell with `s6-svscan` as PID 1, Lix on
`PATH`, and a dropbear sshd on port 22. None of the three upstream trees is
modified: this repository is a pure glue layer (Nix expressions, one early-boot
shell script, one launcher script).

Everything -- including the Asterinas kernel -- is built from source by
`nix build`. A `git clone` followed by a single `nix run` is the whole
workflow: there is no prebuilt artifact in the tree and no manual kernel step.

## Boot flow

``````````
QEMU  -kernel + -initrd + -drive(readonly vda) + -drive(rw vdb)     direct kernel boot: no GRUB, no kexec
  |
  v
Asterinas kernel
  |  unpacks initramfs.cpio.gz, runs /init as PID 1
  v
[dictyonos-init]                                 initramfs.nix + stage1-init.sh
  |  mount proc / sys / devtmpfs
  |  mount -t ext2 -o ro /dev/vda -> /sysroot    holds /nix/store + the configuration
  |  read configuration=<store-path> from /proc/cmdline
  |  mount -t ext2 -o rw /dev/vdb -> /var        the writable state disk
  |  bind /var/nix-var over /nix/var, and /nix/store onto itself
  |  mount --move /proc /sys /dev into /sysroot
  |  switch_root /sysroot <configuration>/boot/init
  v
s6-linux-init                                    mounts tmpfs /run, unpacks its cpio,
  |                                              dumps the kernel environment
  |                                              (configuration=, init=) into /run/boot
  v
s6-svscan                                        long-lived PID 1
  |  rc.init -> <configuration>/bin/activate -> s6-rc-init + s6-rc change default
  v
s6-rc services: set-hostname, mounts.{proc,sys,dev.pts,dev.shm,tmp,""}, net-dhcp,
                lix-daemon(+log), ssh(+log)
  + s6-linux-init-early-getty on ttyS0            interactive root shell
``````````

### Why not ownerboot / kexec?

sixos normally boots through `ownerboot`, which hands the new system to the
kernel with `kexec`. Asterinas does not implement `kexec`, so that path is
unusable here. Instead the sixos *configuration closure* -- the same derivation
`mkConfiguration` produces and normally feeds to kexec -- is shipped as the
root filesystem and booted with QEMU direct kernel boot. sixos itself is
untouched: its own `boot/kernel-params` file already supplies the
`configuration=` parameter that `rc.init` knows how to consume.

## Layout

``````````
flake.nix                      inputs, packages, apps
default.nix                    the sixos site + Lix system profile + kernel/initramfs wiring
kernel.nix                     the Asterinas kernel, as a pure derivation
vendor.nix                     the cargo vendor FOD + the offline .cargo/config.toml
initramfs.nix                  builds the stage-1 cpio.gz (static busybox + /init)
stage1-init.sh                 the stage-1 /init itself
rootfs.nix                     pure derivation that emits rootfs.ext2
scripts/run-vm.sh              boots the result under QEMU
scripts/merge-cargo-locks.py   merges the three Cargo.lock files the build needs
scripts/vendor-git-deps.py     rewrites asterinas git dependencies into path deps
``````````

## Quick start

``````````sh
git clone https://github.com/LinTrau/dictyonos
cd dictyonos
nix run                       # builds kernel + initramfs + rootfs, then boots QEMU
``````````

The first run builds the Asterinas kernel and a ~640 MiB ext2 image inside the
Nix sandbox, so give it a few minutes. Afterwards:

``````````sh
ssh -p 2222 root@127.0.0.1    # the launcher generates a throwaway key and injects it
``````````

### Flake outputs (`x86_64-linux`)

| output | what |
| --- | --- |
| `packages.default` / `packages.rootfs` | the ext2 root filesystem image |
| `packages.kernel` | the Asterinas kernel ELF (`asterinas-osdk-bin.elf`) |
| `packages.system` | the sixos top-level configuration derivation |
| `packages.initramfs` | the stage-1 `initramfs.cpio.gz` |
| `apps.default` | one-shot QEMU launcher |
| `devShells.kernel` | the Asterinas toolchain (Rust nightly + OSDK prerequisites) |

### Running the VM

``````````sh
nix run                                  # interactive serial console
AUTO=1 nix run                           # boot, run the acceptance checks, exit
EPHEMERAL=1 nix run                      # throw the state disk away first
NET=0 nix run                            # boot without a NIC (and without ssh)
SSH_PORT=2200 nix run                    # forward a different host port
TIMEOUT=300 nix run                      # give up after N seconds
MEM=16G SMP=4 nix run                    # more resources
``````````

Useful environment variables: `DICTYONOS_KERNEL_ELF`, `DICTYONOS_ROOTFS`,
`DICTYONOS_INITRAMFS`, `DICTYONOS_CONFIG`, `DICTYONOS_STATE`,
`DICTYONOS_WORKDIR`, `CMDLINE`, `NET`, `MEM`, `SMP`, `CPU`, `TIMEOUT`,
`QEMU_BIN`, `ENABLE_KVM`, `AUTO`, `AUTO_WAIT`, `SERIAL_LOG`, `SSH_KEY`,
`SSH_PORT`, `SSH_WAIT`.

`CMDLINE` is handy for debugging: appending `loglevel=info` to it restores
Asterinas' per-syscall trace.

### The two disks

`/dev/vda` is the system image, attached with `readonly=on`. It is a
content-addressed, shareable artifact, so nothing ever writes to it: `/etc`,
`/bin` and `/nix/store` are all read-only.

`/dev/vdb` is a 512 MiB ext2 state disk, created on first run under
`${DICTYONOS_WORKDIR:-$PWD/.dictyonos-vm}/state.ext2` and reused afterwards.
`EPHEMERAL=1` replaces it with a blank one. stage1 grafts it over `/var` and
binds `/var/nix-var` over `/nix/var`, so the Lix database, profiles and the
daemon socket have somewhere to live. Nothing outside `.dictyonos-vm/` is
touched.

Asterinas never writes dirty pages back on its own (gotcha 11), so a small
`state-sync` service commits `/var` with `sync -f` every 30 seconds. That is
what makes the disk reusable; without it its contents would evaporate when the
VM dies.

### Without flakes

`default.nix` and `rootfs.nix` take every source as an explicit argument, so
they work with `nix-build` too. In practice the flake is the supported entry
point.

## The kernel derivation

`cargo osdk build` normally wants a network: it resolves crates.io and `git`
dependencies at build time. `packages.kernel` (`kernel.nix`) makes the whole
thing a pure derivation, so a fresh checkout really does build with one
`nix build`:

* **Every dependency is vendored up front.** Asterinas builds itself with
  `-Zbuild-std`, so three lock files matter: `Cargo.lock` from the Asterinas
  tree, `osdk/Cargo.lock`, and rust-src's own `library/Cargo.lock`.
  `scripts/merge-cargo-locks.py` merges them into one lock file, which
  `rustPlatform.fetchCargoVendor` turns into a fixed-output derivation
  (`vendor.nix`) -- offline `.cargo/config.toml` included.
* **Asterinas' own git dependencies become path dependencies.**
  `scripts/vendor-git-deps.py` rewrites the `git = ...` entries that point at
  `asterinas`-hosted crates into `path = ...` entries inside the vendor tree:
  cargo refuses to resolve a replaced git source without a lock file, and
  `cargo-osdk` regenerates its base crate (a fresh workspace, no lock) on every
  build. Those crates are also the reason for a small `sed`: cargo only passes
  `--cap-lints=allow` to non-path dependencies, so one
  `#![deny(missing_docs)]` in `smoltcp` has to be relaxed by hand.
* **The build runs in Asterinas' own package set**, with its overlay applied:
  that is what supplies the matching Rust nightly and the prebuilt Linux vDSOs
  the kernel embeds (`VDSO_LIBRARY_DIR`).
* `OSDK_LOCAL_DEV=1` is set, so `cargo-osdk` is built and used from the same
  tree and emits paths that are still valid for the build.

**If you change any lock file, you must re-pin the vendor hash.** A
fixed-output derivation's store path is a function of its hash and name only,
so a stale `vendorHash` in `vendor.nix` silently reuses the old vendor tree. To
re-capture it, set the hash to `sha256-AAAA...`, build, and copy the `got:`
value out of the error.

### Privacy: redacted build metadata

Asterinas bakes the compiling user and host into `/proc/version`.
`cargo-osdk` sets `OSDK_BUILD_USERNAME` / `OSDK_BUILD_HOSTNAME` from `whoami`
for the `cargo` child it spawns, so the only way to override them without
patching upstream is a `cargo` shim earlier on `PATH`. `kernel.nix` installs
one, so the result always reads:

``````````
Linux version 5.13.0 (dictyonos@builder) (rustc ...) #1 SMP ...
``````````

and the build fails outright if the compiling user or host leaks through. The
shim also remaps the toolchain and vendor store paths out of the ELF's debug
info: without that, Nix's reference scanner follows them and drags a 4 GiB
closure into the image instead of a 20 MB one.

## Configuration choices that matter

* **The Nix sandbox is off.** Asterinas does not implement the full namespace
  set a strict sandbox needs, and it has no page-cache pressure reclaim yet, so
  the generated `/etc/nix/nix.conf` contains `sandbox = false`. (Lix 2.94
  removed `filter-syscalls` entirely, so that setting no longer exists and is
  deliberately not written.)
* **No `mdevd` / `udev`.** Asterinas provides `devtmpfs`, so `/dev` is
  populated by the kernel. The default sixos target set is replaced by a
  minimal one; nothing waits on netlink hotplug events.
* **`mounts.proc`, `mounts.sys` and `mounts.""` are empty bundles.** The
  initramfs already moved a live `/proc` and `/sys` into the new root, so
  re-mounting them would fail with `EBUSY`; `/` cannot be remounted read-write
  either, because the system disk is read-only on purpose. The bundles exist
  only so the after-references other targets make still resolve.
* **The first-boot activation branch is pre-empted.** sixos' first-boot branch
  bind-mounts `/` read-write and calls `chattr +i`, which a read-only ext2 on a
  read-only QEMU drive cannot do. `rootfs.nix` pre-creates the same `/etc`,
  `/bin/sh` and `/usr/bin/env` links that activation would create, using the
  exact targets its `readlink` comparisons test for, so the whole linkify pass
  is skipped -- see gotcha 1 for why that matters so much.
* **There is no getty target.** `s6-linux-init-maker -G` (derived by sixos from
  `boot.kernel.console`) already supervises a getty on `ttyS0`. A second one
  cannot take the controlling terminal and fails with
  `TIOCSCTTY: Operation not permitted`.
* **`net-dhcp` is best-effort.** It brings every non-`lo` interface up and runs
  `udhcpc` under a timeout, but every step is guarded and it always exits 0, so
  a missing or unsupported NIC can never stall the boot. It also seeds
  `/etc/resolv.conf` -- a symlink into the tmpfs-backed `/run`, because `/etc`
  itself is read-only -- with the QEMU user-mode resolver.
* **`ssh` is public-key only.** The launcher generates a throwaway keypair,
  passes the public half on the kernel command line, and the service writes it
  to `/root/.ssh/authorized_keys` (which lives on the state disk). dropbear
  runs with `-s`, so password logins are off by construction, and it listens on
  the interface address it discovers (see gotcha 8) rather than the wildcard.
* **`has-hwclock` is on.** Asterinas has no RTC driver, so the tag is not
  literally true -- but it is what stops sixos from installing its
  *file-backed* fake hwclock (`hwclock-fake` + `hwclock-fake-updater`, which
  `redirfd` a state file into `/etc` and therefore die and get restarted about
  once a second on a read-only root). With the tag on, sixos installs its real
  `hwclock` oneshot instead, whose scripts end in `|| true` and cannot fail or
  spin.

## Upstream gotchas found the hard way

1. **sixos' `activate` can abort silently, and then nothing works.** It runs
   under `set -e`, and its `linkify` pass writes to `$RWMOUNT/<path>`, where
   `$RWMOUNT` is set *only* by the first-boot branch above -- so on a read-only
   root any failed `ln -sfT` kills activation before `s6-rc-init` ever runs.
   The machine still boots into the `s6-linux-init` *early getty*, which looks
   like a working serial console with no services: no `/run/s6-rc`, no ssh, no
   DHCP, and no error on the console (the output goes to the catch-all logger).
   Every link activation touches has to either already exist or resolve.
   `rootfs.nix` fails the build if one of its own links dangles.
2. **Lix refuses to run on a store that is not a mount point.**
   `LocalStore::makeStoreWritable` issues
   `mount(NULL, /nix/store, none, MS_REMOUNT | MS_BIND, 0)` whenever `statvfs`
   reports `ST_RDONLY`, and the kernel answers `EINVAL` unless the target is
   the root of a mount. `stage1-init.sh` therefore bind-mounts `/nix/store`
   onto itself; the superblock stays read-only, so nothing can actually be
   written there. `/nix/store/.links` also has to exist, because
   `LocalStore`'s constructor creates it unconditionally -- even for a pure
   `nix eval`.
3. **sixos `apply-tags` erases the host when no tag is active.**
   `lib.composeManyExtensions []` evaluates to `(_: _: {})`, so with an empty
   tag set the host collapses to just `tags`/`canonical`/`name`. This
   repository declares one always-true identity tag (`dictyonos`) purely to keep
   the host alive; every real upstream tag is deliberately left off because
   each one drags in kexec/ownerboot/initrd machinery Asterinas cannot use.
4. **sixos' s6-rc patch series only applies to nixpkgs 24.05.** Building sixos
   against a newer nixpkgs fails with `2 out of 7 hunks FAILED` in
   `0009-add-OLDSTATE_UNPROPAGATED_RESTART.patch`. The `nixpkgs-sixos` input is
   therefore pinned to the `nixos-24.05` branch, and Lix comes from a second
   (`nixos-26.05`) input. The second input is a release branch rather than
   `nixos-unstable` because the unstable revision current at the time of writing
   ships a Lix whose meson options no longer match its own build script
   (`ERROR: Unknown option: mimalloc`); 26.05 is also the channel Asterinas' own
   NixOS distro targets.
5. **Longruns must use `six.mkFunnel`.** `six.mkService { type = "longrun"; ... }`
   emits `up`/`down`, but `s6-rc-compile` wants `run`; only `mkFunnel`/
   `mkLogger` produce it.
6. **Asterinas does not parse the baud suffix on `console=`.**
   `console=ttyS0,115200n8` is rejected (`console not found, falling back to
   tty0`), which silently sends all userspace output to a framebuffer that does
   not exist. Plain `console=ttyS0` is required.
7. **`fs.protected_hardlinks` blocks hardlinking the store.** Anyone assembling
   the image by hand with `cp -al` hits `EPERM`. Building it inside the sandbox
   (as `rootfs.nix` does) sidesteps this entirely.
8. **Asterinas cannot bind an IPv4 wildcard address.** `bind()` resolves its
   argument in a local routing table
   (`kernel/core/src/net/route/mod.rs:lookup_local_iface`) and answers
   `EADDRNOTAVAIL` for anything that is not a local address -- `0.0.0.0` and
   `::` included, so the usual `listen(0.0.0.0:22)` cannot work at all. A plain
   dropbear `-p 22` is worse: it takes the IPv6 wildcard from getaddrinfo,
   fails on `IPV6_V6ONLY` and `bind(::)`, and exits with "No listening ports
   available" without ever trying IPv4. The `ssh` service therefore waits for
   the NIC to have a routable address and binds that address.
9. **dropbear validates the login shell through `/etc/shells`.** With the file
   absent glibc's `getusershell(3)` falls back to "/bin/sh,/bin/csh", and
   root's shell in a sixos-generated `passwd` is a store path -- so every login
   is refused with "User 'root' has invalid shell, rejected" even though the
   key was accepted. `rootfs.nix` writes `/etc/shells` from `passwd` itself.
10. **sixos' generated `finish.user` scripts carry `-Ws4`.** `execlineb -W -s 4`
    demands four positional parameters, so every restart of a dying service
    prints `execlineb: fatal: too few arguments: expecting at least 4 but got 3`
    on the console. It is a symptom, not a cause: fix the service that keeps
    dying and the noise stops.
11. **Asterinas does no background writeback, and `sync(2)` is unusable here.**
    Dirty pages leave the guest only when something calls `syncfs()` on the
    filesystem that owns them. The system-wide `sync` logs
    `block: failed to do Write on the device with error status: IoError`
    against the read-only system disk and does not reliably reach the state
    disk; the `sync` *mount option* is dropped on the floor, because Asterinas'
    `PerMountFlags` has no `SYNCHRONOUS` bit. `sync -f /var` (syncfs on the
    state disk) works and returns 0, which is what `state-sync` uses.

## Verifying

``````````sh
AUTO=1 nix run
``````````

boots the machine and, on the serial console, runs `uname -a`,
`cat /proc/version`, `readlink /proc/1/exe`, the full `ps aux`, checks that
sixos' activation reached the end, reports `s6-svstat` for every longrun and
tails their logs under `/var/log`, shows both disks and the network
configuration, runs `nix --version` and `nix eval --expr '1 + 1'`, and does a
write/`sync -f`/read-back round-trip on the state disk. In parallel it checks a
real ssh handshake from the host and runs a command through it. Everything is
written to `./serial.log`. A captured run is in [ACCEPTANCE.md](ACCEPTANCE.md),
and the host-side half of the state-disk check is a `debugfs` read of
`.dictyonos-vm/state.ext2`.

## Known limitations

* `poweroff -f` reports `Failed to power off the system` and leaves QEMU
  running; Asterinas does not implement ACPI power-off. The launcher's
  `TIMEOUT` ends the run.
* **The guest cannot build.** `/nix/store` is read-only by design, so
  `nix eval` and everything that only reads the store work, but `nix build`
  would have nowhere to put its output.
* `uname -a` reports `Linux 5.13.0` on purpose -- Asterinas advertises a Linux
  ABI. `/proc/version` is the honest tell: it names the Rust compiler, not a C
  one.
* Syscall 334 (`rseq`) is unimplemented and logged once per process start;
  glibc handles `ENOSYS` gracefully.
* **No INET wildcard bind** (gotcha 8): a service that wants "all interfaces"
  has to enumerate the addresses it actually has.
* **State-disk durability runs on a 30-second timer.** Asterinas does no
  background writeback (gotcha 11), so `/var` is committed by the `state-sync`
  service rather than by the kernel, and anything written in the last half
  minute before the VM dies is lost. The acceptance proves the mechanism both
  ways: the guest writes, `sync -f`s and reads back `/var/persist-early`, and
  the host then finds that file inside `state.ext2`.

## License & Upstream Credits

The glue layer in this repository -- `flake.nix`, `default.nix`, `kernel.nix`,
`vendor.nix`, `initramfs.nix`, `rootfs.nix`, `stage1-init.sh` and `scripts/` --
is licensed under the **Mozilla Public License 2.0** (`LICENSE`), matching
Asterinas.

It consumes, but does not modify or redistribute, the following upstream
projects. Their licenses apply to them, not to this repository:

| upstream | license | notes |
| --- | --- | --- |
| [Asterinas](https://github.com/asterinas/asterinas) | MPL-2.0 | kernel; referenced by revision via the `asterinas` input and built locally by `kernel.nix` |
| [sixos](https://codeberg.org/amjoseph/sixos) | GPL-3.0-only (see its `COPYING.GPL3-ONLY`) | s6-based service layer |
| [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | GPL-3.0 (per its repository) | attribute-set combinators sixos is built on |
| [Lix](https://lix.systems/) | LGPL-2.1 | package manager; taken prebuilt from nixpkgs |
| [dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html) | MIT | ssh server |
| [nixpkgs](https://github.com/NixOS/nixpkgs) | MIT | package definitions |
| [skarnet s6 / s6-rc / s6-linux-init](https://skarnet.org/software/) | ISC | process supervision, pulled in through sixos |

Because sixos and infuse.nix are fetched as build inputs at their own
revisions, anyone redistributing a *built* dictyonos image is redistributing
GPL-3.0 binaries and must honour those terms.

