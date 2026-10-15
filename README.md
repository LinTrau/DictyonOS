# dictyonos

A bootable QEMU machine that fuses three independent upstream projects:

| layer | upstream | role |
| --- | --- | --- |
| kernel | [Asterinas](https://github.com/asterinas/asterinas) | Safe-Rust framekernel, Linux-ABI compatible |
| init + userland | [sixos](https://codeberg.org/amjoseph/sixos) + [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | `s6` / `s6-rc` instead of systemd; infuse combinators instead of the NixOS module system |
| package manager | [Lix](https://lix.systems/) | the system-default `nix` |

The result boots to a serial root shell with `s6-svscan` as PID 1 and Lix on
`PATH`. None of the three upstream trees is modified: this repository is a pure
glue layer (Nix expressions, one early-boot shell script, two driver scripts).

## Boot flow

`````````
QEMU  -kernel + -initrd + -drive(ext2)          direct kernel boot: no GRUB, no kexec
  |
  v
Asterinas kernel
  |  unpacks initramfs.cpio.gz, runs /init as PID 1
  v
[dictyonos-init]                                 initramfs.nix + stage1-init.sh
  |  mount proc / sys / devtmpfs
  |  mount -t ext2 /dev/vda -> /sysroot          holds /nix/store + the configuration
  |  read configuration=<store-path> from /proc/cmdline
  |  mount --move /proc /sys /dev into /sysroot
  |  switch_root /sysroot <configuration>/boot/init
  v
s6-linux-init                                    mounts tmpfs /run, unpacks its cpio
  |  writes the kernel command line into /run/boot
  v
s6-svscan                                        long-lived PID 1
  |  rc.init -> <configuration>/bin/activate -> s6-rc-init + s6-rc change default
  v
s6-rc services: set-hostname, mounts.*, net-dhcp,
                lix-daemon(+log), hwclock-fake-updater(+log)
  + s6-linux-init-early-getty on ttyS0            interactive root shell
`````````

### Why not ownerboot / kexec?

sixos normally boots through `ownerboot`, which hands the new system to the kernel
with `kexec`. Asterinas does not implement `kexec`, so that path is unusable
here. Instead the sixos *configuration closure* -- the same derivation
`mkConfiguration` produces and normally feeds to kexec -- is shipped as the root
filesystem and booted with QEMU direct kernel boot. sixos itself is untouched:
its own `boot/kernel-params` file already supplies the `configuration=`
parameter that `rc.init` knows how to consume.

## Layout

`````````
flake.nix              inputs, packages, apps
default.nix            the sixos site + Lix system profile + kernel/initramfs wiring
initramfs.nix          builds the stage-1 cpio.gz (static busybox + /init)
stage1-init.sh         the stage-1 /init itself
rootfs.nix             pure derivation that emits rootfs.ext2
scripts/build-kernel.sh  builds the Asterinas kernel payload
scripts/run-vm.sh        boots the result under QEMU
`````````

## Quick start

`````````sh
git clone https://github.com/LinTrau/dictyonos
cd dictyonos

./scripts/build-kernel.sh     # ~5 min; needs network for crates.io
nix build .#rootfs            # assembles rootfs.ext2 inside the Nix sandbox
nix run                       # boots it under QEMU (serial console)
`````````

`nix run` is the packaged launcher: it bakes the kernel, initramfs and rootfs
paths in and defers to `scripts/run-vm.sh`, which still accepts overrides.

### Flake outputs (`x86_64-linux`)

| output | what |
| --- | --- |
| `packages.default` / `packages.rootfs` | the ext2 root filesystem image |
| `packages.system` | the sixos top-level configuration derivation |
| `packages.initramfs` | the stage-1 `initramfs.cpio.gz` (pure; needs no kernel) |
| `packages.asterinas-source` | the pinned Asterinas source tree |
| `apps.default` | one-shot QEMU launcher |
| `devShells.kernel` | the Asterinas toolchain (Rust nightly + OSDK prerequisites) |

### Running the VM

`````````sh
nix run                                  # interactive serial console
AUTO=1 nix run                           # boot, run the acceptance checks, exit
NET=0 nix run                            # boot without a NIC
TIMEOUT=300 nix run                      # give up after N seconds
MEM=16G SMP=4 nix run                    # more resources
`````````

Useful environment variables: `DICTYONOS_KERNEL_ELF`, `DICTYONOS_ROOTFS`,
`DICTYONOS_INITRAMFS`, `DICTYONOS_CONFIG`, `CMDLINE`, `NET`,
`MEM`, `SMP`, `CPU`, `TIMEOUT`, `QEMU_BIN`,
`ENABLE_KVM`, `AUTO`, `AUTO_WAIT`, `SERIAL_LOG`.

`CMDLINE` is handy for debugging: for example
`CMDLINE="$(cat build/result/boot/kernel-params) loglevel=info"` restores
Asterinas' per-syscall trace.

### Local development against sibling checkouts

The flake consumes published revisions, so an ordinary `git clone` works
standalone. If you have the upstream trees checked out next to this one, point the
inputs at them for a fast edit-test loop -- no changes to `flake.nix` needed:

`````````sh
nix build .#rootfs \
  --override-input asterinas path:../asterinas \
  --override-input sixos     path:../sixos \
  --override-input infuse    path:../infuse.nix
`````````

(the names assume `../asterinas`, `../sixos` and `../infuse.nix`; adjust
the paths to taste).

### Without flakes

`default.nix` and `rootfs.nix` take every source as an explicit argument, so
they work with `nix-build` too:

`````````sh
nix-build --argstr system x86_64-linux \
  --arg nixpkgs-src     /path/to/nixpkgs-24.05 \
  --arg lixPkgs         '(import /path/to/nixpkgs-unstable { system = "x86_64-linux"; })' \
  --arg sixos-src       /path/to/sixos \
  --arg infuse-src      /path/to/infuse.nix \
  --arg kernelElf       /path/to/asterinas-osdk-bin.elf \
  --arg configuration   ... # see default.nix
`````````

In practice the flake is the supported entry point.

## The kernel payload

The Asterinas kernel cannot be built by a normal Nix derivation: `cargo osdk
build` needs crates.io, which the build sandbox does not have. It is therefore a
*prebuilt artifact*, produced by `scripts/build-kernel.sh` into `./kernel/` and
consumed through the `kernel` flake input (declared as `path:./kernel`, so the
lock file stores the relative path `./kernel` and nothing host-specific).

After (re)building the payload, refresh the input if Nix still sees the old one:

`````````sh
nix flake update kernel
`````````

### Privacy: redacted build metadata

Asterinas bakes the compiling user and host into `/proc/version`. `cargo-osdk`
sets `OSDK_BUILD_USERNAME` / `OSDK_BUILD_HOSTNAME` from `whoami` for the
`cargo` child it spawns, so the only way to override them without patching
upstream is a `cargo` shim earlier on `PATH`.
`scripts/build-kernel.sh` installs one, and the result reads:

`````````
Linux version 5.13.0 (dictyonos@builder) (rustc ...) #1 SMP ...
`````````

The shim also exports `KBUILD_BUILD_USER` / `KBUILD_BUILD_HOST` for good
measure.

### Non-ASCII workspace paths

`cargo-osdk` percent-encodes the workspace path and then `chdir`s into the
encoded string, so a checkout under a directory with non-ASCII characters aborts
with `ENOENT`. `scripts/build-kernel.sh` detects that with a regex
(`LC_ALL=C grep -q '[^ -~]'`) and mirrors the source to
`${XDG_CACHE_HOME:-$HOME/.cache}/dictyonos-build-mirror` before building. A pure
ASCII checkout is built in place instead. Because `OSDK_LOCAL_DEV` bakes
`CARGO_MANIFEST_DIR` into the `cargo-osdk` binary, the script always
(re)installs the tool from the tree it is about to build, into a private
`CARGO_HOME` under the same cache root -- a stale binary would otherwise mix
two paths and cargo would report a lockfile package collision.

## Configuration choices that matter

* **The Nix sandbox is off.** Asterinas does not implement the full namespace set
  a strict sandbox needs, and it has no page-cache pressure reclaim yet, so the
  generated `/etc/nix/nix.conf` contains `sandbox = false`.
  (Lix 2.94 removed `filter-syscalls` entirely, so that setting no longer
  exists and is deliberately not written.)
* **No `mdevd` / `udev`.** Asterinas provides `devtmpfs`, so `/dev` is
  populated by the kernel. The default sixos target set is replaced by a minimal
  one; nothing waits on netlink hotplug events.
* **`mounts.proc` and `mounts.sys` are empty bundles.** The initramfs already
  moved a live `/proc` and `/sys` into the new root, so re-mounting them
  would fail with `EBUSY`.
* **First-boot activation is pre-empted.** sixos' first-boot branch calls
  `chattr +i`, which Asterinas' ext2 does not implement. `rootfs.nix`
  pre-creates `/etc/*`, `/bin/sh` and `/usr/bin/env` pointing straight at
  the configuration, so that branch is skipped.
* **There is no getty target.** `s6-linux-init-maker -G` (derived by sixos from
  `boot.kernel.console`) already supervises a getty on `ttyS0`. A second one
  cannot take the controlling terminal and fails with
  `TIOCSCTTY: Operation not permitted`.
* **`net-dhcp` is best-effort.** It brings every non-`lo` interface up and
  runs `udhcpc` under a timeout, but every step is guarded and it always exits
  0, so a missing or unsupported NIC can never stall the boot.

## Upstream gotchas found the hard way

1. **sixos `apply-tags` erases the host when no tag is active.**
   `lib.composeManyExtensions []` evaluates to `(_: _: {})`, so with an empty
   tag set the host collapses to just `tags`/`canonical`/`name`. This
   repository declares one always-true identity tag (`dictyonos`) purely to keep
   the host alive; every real upstream tag is deliberately left off because each
   one drags in kexec/ownerboot/initrd machinery Asterinas cannot use.
2. **sixos' s6-rc patch series only applies to nixpkgs 24.05.** Building sixos
   against a newer nixpkgs fails with `2 out of 7 hunks FAILED` in
   `0009-add-OLDSTATE_UNPROPAGATED_RESTART.patch`. The `nixpkgs-sixos` input is
   therefore pinned to the `nixos-24.05` branch, and Lix comes from a second
   (`nixos-26.05`) input. The second input is a release branch rather than
   `nixos-unstable` because the unstable revision current at the time of writing
   ships a Lix whose meson options no longer match its own build script
   (`ERROR: Unknown option: mimalloc`); 26.05 is also the channel Asterinas
   own NixOS distro targets.
3. **Longruns must use `six.mkFunnel`.** `six.mkService { type = "longrun"; ... }`
   emits `up`/`down`, but `s6-rc-compile` wants `run`; only
   `mkFunnel`/`mkLogger` produce it.
4. **Asterinas does not parse the baud suffix on `console=`.**
   `console=ttyS0,115200n8` is rejected (`console not found, falling back to
   tty0`), which silently sends all userspace output to a framebuffer that does
   not exist. Plain `console=ttyS0` is required.
5. **`fs.protected_hardlinks` blocks hardlinking the store.** Anyone assembling
   the image by hand with `cp -al` hits EPERM. Building it inside the sandbox
   (as `rootfs.nix` does) sidesteps this entirely.

## Verifying

`````````sh
AUTO=1 nix run
`````````

boots the machine, runs `uname -a`, `cat /proc/version`, `readlink
/proc/1/exe`, `ps aux`, `ls /run/s6-rc /run/service`, `ip -o addr`,
`nix --version` and `nix eval --expr '1 + 1'` on the serial console, and
writes the transcript to `build/serial.log`. A captured run is in
[ACCEPTANCE.md](ACCEPTANCE.md).

## Known limitations

* `poweroff -f` reports `Failed to power off the system` and leaves QEMU
  running; Asterinas does not implement ACPI power-off. The launcher's `TIMEOUT`
  ends the run.
* `uname -a` reports `Linux 5.13.0` on purpose -- Asterinas advertises a
  Linux ABI. `/proc/version` is the honest tell: it names the Rust compiler,
  not a C one.
* Syscall 334 (`rseq`) is unimplemented and logged once per process start;
  glibc handles `ENOSYS` gracefully.
* `ssh` and a writable network configuration are not included; the guest gets
  a DHCP lease on the QEMU user-mode NIC and nothing else.

## License & Upstream Credits

The glue layer in this repository -- `flake.nix`, `default.nix`,
`initramfs.nix`, `rootfs.nix`, `stage1-init.sh` and
`scripts/` -- is licensed under the **Mozilla Public License 2.0**
(`LICENSE`), matching Asterinas.

It consumes, but does not modify or redistribute, the following upstream projects.
Their licenses apply to them, not to this repository:

| upstream | license | notes |
| --- | --- | --- |
| [Asterinas](https://github.com/asterinas/asterinas) | MPL-2.0 | kernel; referenced by revision via the `asterinas` input, built locally by `scripts/build-kernel.sh` |
| [sixos](https://codeberg.org/amjoseph/sixos) | GPL-3.0-only (see its `COPYING.GPL3-ONLY`) | s6-based service layer |
| [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | GPL-3.0 (per its repository) | attribute-set combinators sixos is built on |
| [Lix](https://lix.systems/) | LGPL-2.1 | package manager; taken prebuilt from nixpkgs |
| [nixpkgs](https://github.com/NixOS/nixpkgs) | MIT | package definitions |
| [skarnet s6 / s6-rc / s6-linux-init](https://skarnet.org/software/) | ISC | process supervision, pulled in through sixos |

Because sixos and infuse.nix are fetched as build inputs at their own revisions,
anyone redistributing a *built* dictyonos image is redistributing GPL-3.0 binaries
and must honour those terms.
