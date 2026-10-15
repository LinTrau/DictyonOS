# dictyonos

A bootable QEMU machine that fuses three independent upstream projects:

| layer | source | role |
| --- | --- | --- |
| kernel | `../asterinas` | Safe-Rust framekernel, Linux-ABI compatible |
| userland / init | `../sixos` + `../infuse.nix` | `s6` / `s6-rc` instead of systemd; infuse.nix instead of the NixOS module system |
| package manager | nixpkgs `lixPackageSets` (or `../lix`) | Lix is the system-default `nix` |

Nothing under `../asterinas`, `../sixos` or `../lix` is edited. This directory is a
pure glue layer: Nix expressions, one early-boot shell script, and three driver
scripts.

## Boot flow

```
QEMU  -kernel + -initrd + -drive(ext2)         <- direct kernel boot, no GRUB, no kexec
  |
  v
Asterinas kernel
  |  unpacks initramfs.cpio.gz, runs /init as PID 1
  v
[dictyonos-init]  (static busybox, glue/initramfs.nix + glue/stage1-init.sh)
  |  mount proc / sys / devtmpfs
  |  mount -t ext2 /dev/vda  ->  /sysroot        (holds /nix/store + the configuration)
  |  read configuration=<store-path> from /proc/cmdline
  |  mount --move /proc /sys /dev into /sysroot
  |  switch_root /sysroot <configuration>/boot/init
  v
s6-linux-init  (mounts tmpfs /run, unpacks its cpio, execs /run/init/bin/init)
  |  writes the kernel command line into /run/boot
  v
s6-svscan                                      <- long-lived PID 1
  |  rc.init -> <configuration>/bin/activate -> s6-rc-init + s6-rc change default
  v
s6-rc services: set-hostname, mounts.*, lix-daemon(+log), hwclock-fake-updater(+log)
  + s6-linux-init-early-getty on ttyS0          <- interactive root shell
```

### Why not ownerboot / kexec?

sixos normally boots through `ownerboot`, which hands the new system to the kernel
with `kexec`. Asterinas does not implement `kexec`, so that path is unusable here.
Instead the sixos *configuration closure* (the same `configuration` derivation
`mkConfiguration` produces, normally fed to kexec) is shipped as the root
filesystem and booted with QEMU direct kernel boot. sixos itself is untouched:
its own `boot/kernel-params` file supplies the `configuration=` parameter that
`rc.init` already knows how to consume.

### Files

| file | purpose |
| --- | --- |
| `default.nix` | the sixos site + the Lix-carrying system profile + the initramfs/kernel wiring |
| `initramfs.nix` | builds the stage-1 cpio.gz (static busybox + `/init`) |
| `stage1-init.sh` | the stage-1 `/init` itself |
| `build-kernel.sh` | builds the Asterinas kernel payload |
| `build-images.sh` | realises the configuration and produces `rootfs.ext2` |
| `run-vm.sh` | boots the result under QEMU (serial console only) |

## Building

```sh
./dictyonos/build-kernel.sh     # ~5 min, needs a dev shell (nix develop)
./dictyonos/build-images.sh     # ~5 min, produces dictyonos/build/rootfs.ext2
```

## Running

```sh
./dictyonos/run-vm.sh                    # interactive serial console (Ctrl-A X to quit)
AUTO=1 ./dictyonos/run-vm.sh             # boot, run the acceptance checks, print a transcript
CMDLINE="... loglevel=info ..." TIMEOUT=120 ./dictyonos/run-vm.sh   # debugging
```

## Configuration choices that matter

* **`/etc/nix/nix.conf` disables the sandbox.** Asterinas does not yet implement the
  full set of Linux namespaces a strict Nix sandbox needs, and it has no page-cache
  pressure reclaim, so the generated configuration contains

  ```ini
  sandbox = false
  filter-syscalls = false
  ```

  (Lix 2.94 dropped `filter-syscalls`, so it reports `unknown setting` and ignores it --
  the syscall filter no longer exists to be enabled in the first place.)

* **No `mdevd` / `udev`.** Asterinas provides `devtmpfs`, so `/dev` is fully populated
  by the kernel. The default sixos target set was replaced by a minimal one; nothing
  waits on netlink hotplug events.
* **`mounts.proc` and `mounts.sys` are empty bundles.** The initramfs already moved a
  live `/proc` and `/sys` into the new root, so re-mounting them would fail with EBUSY.
* **First-boot activation is pre-empted.** sixos' first-boot branch calls
  `chattr +i`, which Asterinas' ext2 does not implement. `build-images.sh` therefore
  pre-creates `/etc/*`, `/bin/sh` and `/usr/bin/env` pointing straight at the
  configuration, so that branch is skipped.
* **There is no getty target.** `s6-linux-init-maker -G` (derived by sixos from
  `boot.kernel.console`) already supervises a getty on `ttyS0`. A second one cannot
  take the controlling terminal and fails with `TIOCSCTTY: Operation not permitted`.

## Upstream gotchas found the hard way

1. **OSDK percent-encodes non-ASCII workspace paths.** `cargo osdk` turned
   `/home/user/项目/...` into `/home/user/%E9%A1%B9%E7%9B%AE/...` and then `chdir`ed
   into it, aborting with `ENOENT`. `build-kernel.sh` therefore mirrors `asterinas`
   to an ASCII path first. Because `OSDK_LOCAL_DEV=1` bakes `CARGO_MANIFEST_DIR` into
   the `cargo-osdk` binary at compile time, the tool has to be *reinstalled* from that
   same mirror, otherwise the generated base crate mixes both paths and cargo reports
   a lockfile package collision.
2. **sixos `apply-tags` erases the host when no tag is active.**
   `lib.composeManyExtensions []` evaluates to `(_: _: {})`, so with an empty tag set
   the host collapses to just `tags`/`canonical`/`name`. This glue layer declares one
   always-true identity tag (`dictyonos`) purely to keep the host alive; every real
   upstream tag is deliberately left off because each one drags in kexec/ownerboot/
   initrd machinery Asterinas cannot use.
3. **sixos' s6-rc patch series only applies to nixpkgs 24.05.** Building sixos against
   nixpkgs 26.05 fails with `2 out of 7 hunks FAILED` in
   `0009-add-OLDSTATE_UNPROPAGATED_RESTART.patch`. `default.nix` keeps sixos on its own
   24.05 pin and imports a second, newer nixpkgs *only* to pull a prebuilt Lix.
4. **Longruns must use `six.mkFunnel`.** `six.mkService { type = "longrun"; ... }`
   emits `up`/`down`, but `s6-rc-compile` wants `run`; only `mkFunnel`/`mkLogger`
   produce it.
5. **Asterinas does not parse the baud suffix on `console=`.**
   `console=ttyS0,115200n8` is rejected (`console not found, falling back to tty0`),
   which silently sends all userspace output to a framebuffer that does not exist.
   Plain `console=ttyS0` is required.
6. **`fs.protected_hardlinks` blocks hardlinking the store.** `cp -al` of `/nix/store`
   into the staging tree fails with EPERM; `build-images.sh` uses a plain recursive copy.

## Known limitations

* `poweroff -f` reports `Failed to power off the system` and leaves QEMU running;
  Asterinas does not implement ACPI power-off. Kill QEMU or let the run timeout expire.
* `uname -a` reports `Linux 5.13.0` on purpose -- Asterinas advertises a Linux ABI.
  `/proc/version` shows `(rustc 1.99.0-nightly)`, which is the real tell.
* Syscall 334 (`rseq`) is unimplemented and logged once per process start; glibc
  handles `ENOSYS` gracefully.
* Networking is not configured; the guest has no NIC in this configuration.
