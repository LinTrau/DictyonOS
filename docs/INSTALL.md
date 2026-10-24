# Installing, upgrading and rolling back dictyonos

This is the user-facing entry point the README does not have: how to get a
machine up from an empty directory, how to move it to a new generation, how to
get back, and what to do when it does not come up. The README explains *why* the
stack looks the way it does; [ACCEPTANCE.md](../ACCEPTANCE.md) is the transcript
of a run that proves the claims below still hold.

## QEMU is the only supported platform

dictyonos boots as a QEMU virtual machine on an `x86_64-linux` host with Nix.
That is the supported configuration, and the only one the acceptance exercises:

* no bare-metal boot: there is no bootloader, no install media, no ESP. The
  image is handed to QEMU with `-kernel`, and `/dev/vda` is the root filesystem
  with `readonly=on`;
* no installer: nothing partitions a disk for you, nothing writes to a physical
  device, and stage 1 expects to find `/dev/vda` and (optionally) `/dev/vdb`
  already there;
* `x86_64` only: Asterinas' AArch64 support is still early, so no `aarch64-linux`
  output is promised;
* no multi-user story: the guest has a single `root` account, reachable over ssh
  with a key the launcher generates. There is no login prompt, no password and no
  user management.

A minimal install is therefore: a checkout, `nix run`, and a directory the
launcher owns.

## What the host needs

| requirement | why |
| --- | --- |
| Nix with flakes (`experimental-features = nix-command flakes`) | the flake is the supported entry point |
| `x86_64-linux` | the kernel, the image and the toolchain are built for it |
| QEMU (from the flake, or `QEMU_BIN=/usr/bin/qemu-system-x86_64`) | it is the machine |
| `/dev/kvm` (recommended, not required) | `ENABLE_KVM=0` falls back to TCG, which is dramatically slower |
| network (recommended, not required) | a from-scratch build substitutes from the cache; once built, the guest boots with `NET=0` |

Disk space, with the numbers the build actually produces:

* a from-scratch build is the expensive case: the Asterinas Rust toolchain, the
  Lix build, the kernel and the 596 MiB ext2 image all land in the Nix store.
  That is several GiB; the only measured figure in this repository is the 596 MiB
  image itself, so treat the store number as a budget rather than a measurement,
  or let `nixConfig` substitute the cached outputs;
* every state disk is a separate `512 MiB` ext2 file under the working
  directory — sparse, so it only costs what was actually written. Delete it and
  it comes back on the next run;
* nothing outside the working directory is written. The launcher does not touch
  `/etc`, does not register services, and does not need root.

Memory and CPU count default to `MEM=8G SMP=1`; the acceptance steps fit in that.
The QEMU CPU model is `host` when KVM is in use and
`Icelake-Server,+x2apic,+vmx` under TCG. KVM is the default and needs `/dev/kvm`;
`ENABLE_KVM=0` forces the TCG path, and `CPU=<model>` overrides either choice.
`TIMEOUT=240` is a hard wall-clock limit on **every** QEMU run, not a
"nothing answered" threshold: the launcher `exec`s `timeout --foreground
$TIMEOUT` around QEMU, so an interactive session is killed after four minutes
too. Raise it for anything longer than a smoke test; CI runs the acceptance with
`TIMEOUT=900` and larger `STEP_WAIT`/`HALT_WAIT`.

## First run, from an empty directory

```sh
git clone https://github.com/LinTrau/dictyonos
cd dictyonos
nix run                      # builds kernel + initramfs + rootfs, then boots QEMU
```

With a cache trusted (`nix run --accept-flake-config`) the artifacts are
substituted instead of built. What happens on the first run, in order:

1. the flake builds or substitutes `packages.kernel` (the Asterinas ELF),
   `packages.initramfs` (stage 1) and `packages.rootfs` (the 596 MiB ext2
   image), plus `packages.system`, the sixos configuration they boot;
2. the launcher creates `${DICTYONOS_WORKDIR:-$PWD/.dictyonos-vm}/` and, because
   no state disk exists yet, a fresh `512 MiB` ext2 disk at `state.ext2` inside
   it;
3. it generates a throwaway ed25519 keypair there and hands the public half to
   the guest on the kernel command line, so `ssh` works on the first boot
   without any provisioning step;
4. QEMU starts with `/dev/vda` set to the image (`readonly=on`) and `/dev/vdb`
   set to the state disk, and the serial console is attached to your terminal;
5. `ssh -i .dictyonos-vm/id_ed25519 -p 2222 root@127.0.0.1` works as soon as
   dropbear is up — the key matters, because dropbear only receives the public
   half and there is no password login. Stop the
   machine from inside with `poweroff -f`; from the host, interrupt the
   launcher. QEMU runs with `-nographic -display none -monitor none -serial
   stdio`, so the serial console is plain stdio and there is no `Ctrl-A` monitor
   escape to fall out of.

The directory the launcher owns:

```
.dictyonos-vm/
├── state.ext2                 the 512 MiB state disk (keep it: /var and the store upper layer live here)
├── id_ed25519{,.pub}          the throwaway ssh key
└── hostkey.{scan,file}.bootN  the host key each boot presented and carried (acceptance runs only)
```

Transcripts are written next to your shell, not in the workdir. An interactive
run writes `./serial.log`; an `AUTO=1` run adds `./serial.host.log` (host-side
ssh, `e2fsck` and `debugfs` evidence) and, when it runs the second boot,
`./serial-boot2.log`. `ROLLBACK=1` boots once only, so it writes no boot-2 log.
All of them match the `*.log` ignore rule.

## The state disk: what persists, and what does not

`/dev/vda` is a content-addressed artifact and stays read-only. Two things need
to be writable, so both live on the state disk:

* `/var` is grafted onto `/dev/vdb`, with `/var/nix-var` bind-mounted over
  `/nix/var` — that is where the Lix database, the profiles and the daemon
  socket live;
* `/nix/store` is an overlayfs whose lower layer is the image and whose upper
  layer is `/var/nix-store-upper`, also on the state disk. Lix can therefore
  write into the store from inside the guest.

That single 512 MiB file is also the ceiling: it holds `/var`, the store's upper
layer and everything you build in the guest, together.

Asterinas never writes dirty pages back on its own (README gotcha 11) and
`poweroff` does not unmount anything, so durability is a timer, not a syscall:
the `state-sync` service commits `/var` with `sync -f` every 30 seconds.
**Anything written in the last half minute before the machine dies is lost**,
including a store path you just built. `nix run`'s own boot sequence powers off
the same way; the acceptance run's second boot is what proves the timer worked.

To throw the disk away, so the next boot starts from the image's own state:

```sh
EPHEMERAL=1 nix run          # replaces .dictyonos-vm/state.ext2 with a blank one
```

Deleting the file has the same effect. Never run a *repairing* `e2fsck` on a
state disk (README gotcha 14): read-only checks (`e2fsck -fn`) are what the
acceptance uses, and a repair damages the overlay's upper layer.

## Upgrading to a new generation

Two different things get called "upgrading" here, and they cover different
halves of the system. The switch is never hot: nothing restarts now, the machine
keeps running what it booted, and only the next boot reads a recorded choice.

* **a new image** — `nix run` from a newer checkout — replaces the kernel, stage
  1 and the userspace the image carries. The kernel arrives through `-kernel`,
  so only a new QEMU invocation can change it;
* **a new generation** — `dictyonos-switch` — changes which configuration's
  `boot/init` stage 1 hands off to. That is userspace only:
  `<configuration>/boot/kernel` is a placeholder the boot path never reads
  (`default.nix:93-102`).

Nothing in this repository has ever booted two genuinely different
configurations: CI builds one image, boots it, then rolls that same image back
(`.github/workflows/ci.yml:125-136`), and the "new generation" the acceptance
switches to is a copy of the running closure (`scripts/run-vm.sh:439-445`). Treat
the cross-image cases below as documented behaviour of stage 1, not as tested
procedures.

### Boot a new image

Clear the recorded choice first, from inside the running guest, or the old one
wins over the new image:

```sh
rm -f /nix/var/nix/profiles/nextboot /nix/var/nix/profiles/prevboot
sync -f /var
```

then boot as usual against the same state disk:

```sh
nix run
```

Skipping that step does not upgrade: stage 1 reads `nextboot` before
`configuration=` on the command line, and a path recorded by an earlier switch
is still present, because guest-built store paths live in the state disk's upper
layer and survive the image change. You get the old userspace under the new
kernel. An earlier `AUTO=1` run is enough to leave such a profile behind.

### Record a generation

With the new closure already under `/nix/store` in the guest:

```sh
dictyonos-switch /nix/store/<new-configuration>
# next boot: /nix/store/<new-configuration>
# go back : boot with dictyonos.rollback=1 (/nix/store/<previous>)
```

Getting a closure built on the host into the guest is still manual:

```sh
NEW="$(nix build --no-link --print-out-paths .#system)"   # on the host
NIX_SSHOPTS="-i .dictyonos-vm/id_ed25519 -p 2222" \
  nix copy --to ssh://root@127.0.0.1 "$NEW"              # while the VM is up
# inside the guest:
dictyonos-switch "$NEW"
```

`dictyonos-switch` writes `/nix/var/nix/profiles/nextboot` (on the state disk),
keeps whatever was selected before as `prevboot`, and commits with `sync -f
/var` itself, so the choice survives even if the machine goes away before the
next `state-sync` tick. It refuses anything that is not a sixos configuration
(no `boot/init`) or outside `/nix/store`, because a path that will not exist on
the next boot is not a choice.

Boot order, from `stage1-init.sh:173-178`: `prevboot` when the command line
carries `dictyonos.rollback=1`, then `nextboot`, then `configuration=` from the
command line. A candidate whose directory is really gone from the merged
`/nix/store` is skipped with a message instead of stopping the boot — but a path
kept in the state disk's upper layer is not gone, which is why clearing
`nextboot` matters when what you want is the new image.

## Rolling back

The rollback is one kernel command line argument, and the launcher is what
writes the command line, so you pass it through `CMDLINE`:

```sh
CONFIG="$(nix build --no-link --print-out-paths .#system)"
CMDLINE="$(cat "$CONFIG/boot/kernel-params") dictyonos.rollback=1" nix run
```

with `ROLLBACK=1` as the shorthand the CI job uses:

```sh
ROLLBACK=1 nix run
```

`dictyonos.rollback=1` makes stage 1 try `prevboot` first, then `nextboot`, then
the command line's `configuration=`. `prevboot` is the `nextboot` that
`dictyonos-switch` recorded last time, so exactly one step back is kept — and it
only exists after a switch. On a fresh state disk stage 1 seeds `nextboot` from
the image and leaves `prevboot` alone, so `ROLLBACK=1` there is a no-op that
simply boots `nextboot`.

The rollback is not sticky: `nextboot` is still recorded on the state disk, so
the boot after the rolled-back one goes forward again unless you keep passing
`dictyonos.rollback=1` or remove the profile.

What it does not do: notice a failure. Nothing watches the machine come up and
reverts by itself; a generation that breaks before s6 starts needs the boot
argument typed by hand. That is a known limitation, not oversight — automatic
reversion is future work.

## When it does not boot

The failure modes are specific, and so are the ways out.

| symptom | what it means | what to do |
| --- | --- | --- |
| `FATAL: could not mount the system image`, then a shell | `/dev/vda` was not attached, or is not the ext2 image | run through `nix run`; do not start QEMU by hand without the `-drive` for vda |
| `no state disk; /var will be a tmpfs` | `/dev/vdb` is absent or unreadable | the machine boots but nothing persists; check the state disk path and permissions |
| `warning: could not mount an overlay on /nix/store; the store stays read-only` | the overlay's upper layer could not be set up | the machine boots as a read-only appliance; rebuild the state disk with `EPHEMERAL=1` |
| the next boot does not reach s6 after a switch | the recorded generation does not start | `ROLLBACK=1 nix run`, i.e. `dictyonos.rollback=1` on the command line |
| `127.0.0.1:2222 is already in use` | another VM still holds the port | stop it, or `SSH_PORT=2200 nix run` |
| ssh is refused, but the serial console works | dropbear is up but bound to loopback only, or the key is not the generated one | pass `-i .dictyonos-vm/id_ed25519`; `NET=0` skips the host-side port forward and key injection |
| the run stops at `TIMEOUT` | the wall clock ran out — it is not a hang detector | `TIMEOUT=1800` for interactive work, `loglevel=info` in `CMDLINE` for Asterinas' per-syscall trace |

There is **no dedicated rescue mode** — no single-user target, no boot menu, no
installer to fall back to — but the machine does not go dark either. Stage 1's
`die()` prints `[dictyonos-init] FATAL: ...` and drops to a busybox shell on the
console (`stage1-init.sh:20`), and sixos runs `s6-linux-init-early-getty` on
`ttyS0`, so an activation that aborts leaves a root shell as well. Those shells
are the rescue entry, they are where the messages above appear, and the tools
available in them are the busybox the initramfs carries.

The state disk is disposable enough that `EPHEMERAL=1` is a legitimate recovery
action when you do not care about `/var` or the paths you built in the guest.

Every boot leaves a transcript on the host (`./serial.log`, and
`./serial-boot2.log` for the second boot of an acceptance run), which is the
first thing to attach to a bug report.

## Checking that the install works

```sh
AUTO=1 nix run
```

boots the machine twice against the same state disk and fails unless all of the
following hold:

* both boots answer `ssh`, and the machine goes away afterwards: normally the
  guest powers off, and a guest that only halts counts too because the launcher
  then stops QEMU itself;
* on boot 2 the guest finds `/var/persist-early` = `early`, `/var/persist-late`
  = `late` and the store path it built on boot 1, and prints
  `REBOOT-PERSISTENCE-OK` (`scripts/run-vm.sh:468`);
* the host reads the same two files back out of the image with `debugfs`, and the
  dropbear host key it dumped on boot 2 is byte-identical to boot 1's;
* boot 2 reports `handing off to /nix/store/dictyonos-generation-2/boot/init
  (from nextboot)` — the state disk's profile, not the command line, chose the
  configuration.

The `e2fsck -fn` output in `serial.host.log` is *recorded*, not asserted: per
gotcha 14 it reports xattr and bitmap damage on every run, which is expected and
is not a failure. [ACCEPTANCE.md](../ACCEPTANCE.md) records a full run;
[.github/workflows/ci.yml](../.github/workflows/ci.yml) runs the same thing on
pushes to `main` and on pull requests, plus a `ROLLBACK=1` boot that has to come
up on `prevboot`.

## Deliberately not supported

* an installer, partitioning, or writing to a physical disk;
* bare metal, UEFI, PXE, or any bootloader (see README "Why not ownerboot / kexec?");
* `aarch64`, and any platform the acceptance does not exercise;
* multi-user, passwords, or account management;
* hot switching, automatic rollback after a failed boot, and rescue tooling
  beyond the shells on the serial console;
* repairing the state disk with `e2fsck` (see gotcha 14).

Where the behaviour above is implemented, for when the document and the code
disagree — the code wins:

* state disk creation, key generation, port checks: `scripts/run-vm.sh`;
* generation order, overlayfs, `state-sync`, fallbacks: `stage1-init.sh`;
* profiles and the `prevboot` handover: `scripts/dictyonos-switch`;
* the acceptance the claims above come from: `ACCEPTANCE.md`.
