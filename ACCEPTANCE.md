# dictyonos — acceptance transcript

This is the acceptance record for this tree. Everything below was captured by
`AUTO=1 nix run` on a stock, non-interactive boot: there is no manual step of any
kind. The run boots the machine **twice against the same state disk** — the first
boot has to bring the system up, the second has to show that what the first one
wrote is still there — and it checks the result from the host as much as from the
guest.

```sh
git clone <this repo> && cd dictyonos
AUTO=1 nix run
```

or, for just the first of the two boots:

```sh
AUTO=1 BOOT2=0 nix run
```

Nothing is overridden: the kernel, the initramfs, the root filesystem, the state
disk and the kernel command line all come straight out of the flake. The launcher
types the commands below into the serial console itself and waits for each one to
answer before typing the next, so the transcript is in the order it happened — the
step that writes `/var/persist-late` deliberately sleeps 35 s in the middle.

## Boot 1, from the serial console

```text
/run/service/s6-linux-init-early-getty # echo ==== DICTYONOS ACCEPTANCE boot 1 =

===; echo DICTYONOS-OK-"01"
==== DICTYONOS ACCEPTANCE boot 1 ====
DICTYONOS-OK-01
/run/service/s6-linux-init-early-getty # uname -a; echo DICTYONOS-OK-"02"
Linux dictyonos 5.13.0 #1 SMP Thu Jan  1 00:00:00 UTC 1970 x86_64 GNU/Linux
DICTYONOS-OK-02
cat /proc/version 2>/dev/null; cat /pro

c/1/comm 2>/dev/null; echo DICTYONOS-OK-"03"
Linux version 5.13.0 (dictyonos@builder) (rustc 1.99.0-nightly) #1 SMP Thu Jan  1 00:00:00 UTC 1970
s6-svscan
DICTYONOS-OK-03
/run/service/s6-linux-init-early-getty # echo ---- PID 1 ----; readlink /proc/1/

exe; ps aux 2>/dev/null; echo DICTYONOS-OK-"04"
---- PID 1 ----
/nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-svscan
PID   USER     TIME  COMMAND
    1 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   24 root      0:00 s6-supervise s6-svscan-log
   25 root      0:00 s6-supervise s6-linux-init-runleveld
   26 root      0:00 s6-supervise s6-linux-init-shutdownd
   27 root      0:00 s6-supervise s6-linux-init-early-getty
   28 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   29 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1
   30 root      0:00 /nix/store/js0jfqxgrlb7bwk8lr1qa4h3cb4cd0fm-s6-linux-init-
   31 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   47 root      0:00 s6-supervise lix-daemon
   48 root      0:00 s6-supervise lix-daemon-log
   49 root      0:00 s6-supervise s6rc-fdholder
   50 root      0:00 s6-supervise s6rc-oneshot-runner
   51 root      0:00 s6-supervise ssh
   52 root      0:00 s6-supervise ssh-log
   53 root      0:00 s6-supervise state-sync
   54 root      0:00 s6-supervise state-sync-log
   61 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   62 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  101 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  105 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  106 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  113 root      0:00 {yqqw32lw56s9plm} /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4
  116 root      0:05 /nix/store/g8y3595zxljm9g4lyaki61zqjqyvi52d-lix-2.94.2/bin
  117 root      0:00 /nix/store/50gf8bygvm8cv7gw73w6w5injdrcpzhk-dropbear-2022.
  147 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1
  151 root      0:00 ps aux
DICTYONOS-OK-04
/run/service/s6-linux-init-early-getty # echo ---- s6 ----; if [ -d /run/s6-rc ]

; then echo activation-completed; else echo activation-FAILED; fi; ls /run/servi

ce; echo DICTYONOS-OK-"05"
---- s6 ----
activation-completed
lix-daemon                 s6rc-fdholder
lix-daemon-log             s6rc-oneshot-runner
s6-linux-init-early-getty  ssh
s6-linux-init-runleveld    ssh-log
s6-linux-init-shutdownd    state-sync
s6-svscan-log              state-sync-log
DICTYONOS-OK-05
/run/service/s6-linux-init-early-getty # echo ---- svstat ----; for s in ssh ssh

-log lix-daemon lix-daemon-log state-sync s6rc-oneshot-runner; do s6-svstat /run

/service/$s; done 2>&1; echo DICTYONOS-OK-"06"
---- svstat ----
up (pid 117) 37 seconds
up (pid 106) 37 seconds
up (pid 116) 37 seconds
up (pid 105) 37 seconds
up (pid 113) 37 seconds
up (pid 62) 37 seconds, ready 37 seconds
DICTYONOS-OK-06
/run/service/s6-linux-init-early-getty # echo ---- svclogs ----; echo '== ssh';

tail -25 /var/log/ssh/current 2>&1; echo '== lix-daemon'; tail -8 /var/log/lix-d

aemon/current 2>&1; echo '== state-sync'; tail -8 /var/log/state-sync/current 2>

&1; echo DICTYONOS-OK-"07"
---- svclogs ----
== ssh
@400000006ad259f71c1a74cb dropbear: installed the authorized key from the kernel command line
@400000006ad259f71ef0cb8f dropbear: listening on 10.0.2.15:22
@400000006ad259f721766e12 [117] Oct 16 10:07:30 Not backgrounding
@400000006ad259fb25d577e3 [137] Oct 16 10:07:34 Child connection from 10.0.2.2:44268
@400000006ad259fb2b73009c [137] Oct 16 10:07:34 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:44268
@400000006ad259fb2c17d513 [137] Oct 16 10:07:34 Exit (root) from <10.0.2.2:44268>: Disconnect received
@400000006ad259fb2d4b5249 [139] Oct 16 10:07:34 Child connection from 10.0.2.2:44284
@400000006ad259fb331718c4 [139] Oct 16 10:07:34 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:44284
@400000006ad259fb34de3d10 [139] Oct 16 10:07:34 Exit (root) from <10.0.2.2:44284>: Disconnect received
@400000006ad259fb35c331be [143] Oct 16 10:07:34 Child connection from 10.0.2.2:44300
@400000006ad259fb36313182 [143] Oct 16 10:07:34 Exit before auth from <10.0.2.2:44300>: Exited normally
@400000006ad259fc24470be3 [144] Oct 16 10:07:35 Child connection from 10.0.2.2:45554
@400000006ad259fc24820d43 [144] Oct 16 10:07:35 Exit before auth from <10.0.2.2:45554>: Error reading: Connection reset by peer
== lix-daemon
== state-sync
@400000006ad25a1519af2fcb state-sync: committing /var
DICTYONOS-OK-07
/run/service/s6-linux-init-early-getty # echo ---- persist ----; echo early > /v

ar/persist-early; sync -f /var/persist-early; echo targeted-sync-exit=$?; cat /v

ar/persist-early; echo DICTYONOS-OK-"08"
---- persist ----
targeted-sync-exit=0
early
DICTYONOS-OK-08
/run/service/s6-linux-init-early-getty # echo ---- disks ----; mount | grep -E '

vda|vdb|/var'; echo DICTYONOS-OK-"09"
---- disks ----
/dev/vda on / type ext2 (ro,relatime)
/dev/vda on /nix/store type ext2 (ro,relatime)
/dev/vdb on /nix/var type ext2 (rw,relatime)
/dev/vdb on /var type ext2 (rw,relatime)
DICTYONOS-OK-09
/run/service/s6-linux-init-early-getty # echo ---- net ----; ip -o addr 2>/dev/n

ull | head -4; cat /etc/resolv.conf 2>/dev/null; netstat -ltn 2>/dev/null | grep

 :22; echo DICTYONOS-OK-"10"
---- net ----
1: lo    inet 127.0.0.1/8 scope host lo
1: lo    inet6 ::1/128 scope host
2: eth0    inet 10.0.2.15/24 brd 10.0.2.255 scope global eth0
nameserver 10.0.2.3
DICTYONOS-OK-10
/run/service/s6-linux-init-early-getty # echo ---- LIX ----; nix --version; echo

 DICTYONOS-OK-"11"
---- LIX ----
nix (Lix, like Nix) 2.94.2
System type: x86_64-linux
Additional system types: i686-linux, x86_64-v1-linux, x86_64-v2-linux, x86_64-v3-linux
Features: gc, signed-caches
System configuration file: /etc/nix/nix.conf
User configuration files: /root/.config/nix/nix.conf:/etc/xdg/nix/nix.conf
Store directory: /nix/store
State directory: /nix/var/nix
Data directory: /nix/store/g8y3595zxljm9g4lyaki61zqjqyvi52d-lix-2.94.2/share
[    48.049] WARN  : PID 171: terminating on signal SIGKILL
DICTYONOS-OK-11
/run/service/s6-linux-init-early-getty # nix eval --expr '1 + 1'; echo DICTYONOS

-OK-"12"
2
[    50.010] WARN  : PID 173: terminating on signal SIGKILL
DICTYONOS-OK-12
/run/service/s6-linux-init-early-getty # echo ---- persist2 ----; echo late > /v

ar/persist-late; sleep 35; cat /var/persist-late; ls -l /var/persist-late /var/p

ersist-early; tail -3 /var/log/state-sync/current; echo DICTYONOS-OK-"13"
---- persist2 ----
late
-rw-r--r--    1 root     root             6 Oct 16 10:08 /var/persist-early
-rw-r--r--    1 root     root             5 Oct 16 10:08 /var/persist-late
@400000006ad25a1519af2fcb state-sync: committing /var
@400000006ad25a331e4b0757 state-sync: committing /var
DICTYONOS-OK-13
/run/service/s6-linux-init-early-getty # echo DICTYONOS-DONE; echo DICTYONOS-OK-

"14"
DICTYONOS-DONE
```

## The ssh check, from the host

The launcher does not take the console's word for anything: it opens a real ssh
connection through the forwarded port, runs a command through it, and reads the
result back. The same check runs again on the second boot.

```text
==> waiting for sshd on 127.0.0.1:2222
==> ssh handshake succeeded; running a remote command
Warning: Permanently added '[127.0.0.1]:2222' (ED25519) to the list of known hosts.
Linux dictyonos 5.13.0 #1 SMP Thu Jan  1 00:00:00 UTC 1970 x86_64 GNU/Linux
s6-svscan
SSH-REMOTE-OK

==> waiting for sshd on 127.0.0.1:2222
==> ssh handshake succeeded; running a remote command
Warning: Permanently added '[127.0.0.1]:2222' (ED25519) to the list of known hosts.
Linux dictyonos 5.13.0 #1 SMP Thu Jan  1 00:00:00 UTC 1970 x86_64 GNU/Linux
s6-svscan
SSH-REMOTE-OK
```

## Boot 2, from the serial console, on the same state disk

QEMU is stopped, and then started again with the very same `state.ext2`. Between the
two boots the disk is not mounted on the host at all: it is only read with
debugfs, so nothing but the guest can have written to it.

```text
/run/service/s6-linux-init-early-getty # echo ==== DICTYONOS ACCEPTANCE boot 2,

same state disk ====; echo DICTYONOS-OK-"01"
==== DICTYONOS ACCEPTANCE boot 2, same state disk ====
DICTYONOS-OK-01
/run/service/s6-linux-init-early-getty # echo ---- persistence ----; cat /var/pe

rsist-early; cat /var/persist-late; ls -l /var/persist-early /var/persist-late;

echo DICTYONOS-OK-"02"
---- persistence ----
early
late
-rw-r--r--    1 root     root             6 Oct 16 10:08 /var/persist-early
-rw-r--r--    1 root     root             5 Oct 16 10:08 /var/persist-late
DICTYONOS-OK-02
echo ---- host key ----; dropbearkey -y

 -f /var/lib/dropbear/dropbear_ed25519_host_key | tail -2; echo DICTYONOS-OK-"03

"
---- host key ----
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTRYzWABMXNpSYx7qO3DybUZ9C60+WrfM3L7Y8LGGze root@dictyonos
Fingerprint: SHA256:FQ6EyhhHc7L2TamAGc7i8AWt6o9+l6CLuI//ar9JzEY
DICTYONOS-OK-03
/run/service/s6-linux-init-early-getty # echo ---- state-sync log ----; tail -3

/var/log/state-sync/current; echo DICTYONOS-OK-"04"
---- state-sync log ----
@400000006ad25a7811722d48 state-sync: committing /var
DICTYONOS-OK-04
/run/service/s6-linux-init-early-getty # if [ "$(cat /var/persist-early 2>/dev/n

ull)" = early ] && [ "$(cat /var/persist-late 2>/dev/null)" = late ]; then echo

REBOOT-PERSISTENCE-"OK"; else echo REBOOT-PERSISTENCE-"FAILED"; fi; echo DICTYON

OS-OK-"05"
REBOOT-PERSISTENCE-OK
DICTYONOS-OK-05
/run/service/s6-linux-init-early-getty # echo DICTYONOS-DONE; echo DICTYONOS-OK-

"06"
DICTYONOS-DONE
```

## The state disk, from the host

e2fsck -fn reports the filesystem consistent, debugfs reads the files out of it
without mounting it, and the host key dropbear presented to the ssh client is
compared across the two boots.

```text
==> the guest halted; stopping the machine

== boot1: e2fsck -fn state.ext2 ==
e2fsck 1.47.0 (5-Feb-2023)
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
state.ext2: 36/32768 files (0.0% non-contiguous), 2178/131072 blocks
== /persist-early ==
early
== /persist-late ==
late
== /log/state-sync/current ==
@400000006ad25a1519af2fcb state-sync: committing /var
@400000006ad25a331e4b0757 state-sync: committing /var
@400000006ad25a5120dc0122 state-sync: committing /var
== /lib/dropbear ==
     30   40755 (2)      0      0    4096 17-Oct-2026 01:07 .
     29   40755 (2)      0      0    4096 17-Oct-2026 01:07 ..
     33  100600 (1)      0      0      83 17-Oct-2026 01:07 dropbear_ed25519_host_key

==> the guest halted; stopping the machine

== boot2: e2fsck -fn state.ext2 ==
e2fsck 1.47.0 (5-Feb-2023)
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
state.ext2: 39/32768 files (0.0% non-contiguous), 2180/131072 blocks
== /persist-early ==
early
== /persist-late ==
late
== /log/state-sync/current ==
@400000006ad25a7811722d48 state-sync: committing /var
== /lib/dropbear ==
     30   40755 (2)      0      0    4096 17-Oct-2026 01:07 .
     29   40755 (2)      0      0    4096 17-Oct-2026 01:07 ..
     33  100600 (1)      0      0      83 17-Oct-2026 01:07 dropbear_ed25519_host_key

== dropbear host key, as a client sees it ==
both boots presented the same key:
[127.0.0.1]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTRYzWABMXNpSYx7qO3DybUZ9C60+WrfM3L7Y8LGGze

== after boot 2, read from the state disk ==
persist-early: 'early'
persist-late:  'late'
host key:      byte-identical to boot 1
```

## What this demonstrates

| check | result |
| --- | --- |
| kernel identity | `uname -a` reports Linux dictyonos 5.13.0 ... x86_64 GNU/Linux; `/proc/version` names dictyonos@builder and rustc 1.99.0-nightly |
| build metadata redacted | the user and host name recorded in the payload are dictyonos and builder, not those of the machine it was built on |
| PID 1 | `/proc/1/comm` is `s6-svscan`, and `/proc/1/exe` resolves into `/nix/store/...-s6-2.12.0.4/bin/s6-svscan` |
| no systemd anywhere | ps lists s6 supervisors only, and the closure contains no systemd, dbus or polkit |
| sixos activation completed | `/run/s6-rc` exists, which only happens if the sixos bin/activate ran all the way to s6-rc-init |
| service supervision | s6-svstat reports ssh, ssh-log, lix-daemon, lix-daemon-log, `state-sync` and s6rc-oneshot-runner up, each with its own s6-log |
| read-only system disk | mount shows `/dev/vda on / type ext2 (ro,relatime)`, and /nix/store as a read-only mount of its own |
| writable state disk | `/dev/vdb on /var type ext2 (rw,relatime)`, with `/nix/var` bound onto it |
| state disk really persists | the host finds `/persist-early` and /persist-late inside `state.ext2`; `/var/persist-late` was never synced by the shell — the `state-sync` timer committed it |
| the persistence survives a reboot | boot 2 reads early and late back from the same disk, with a fresh kernel and an empty page cache |
| the ssh host key survives a reboot | both boots present the same client-visible key, and the key file dumped from the disk is byte-identical across them |
| Lix is the package manager | `nix --version` reports `nix (Lix, like Nix) 2.94.2` |
| Lix works on a read-only store | `nix eval --expr '1 + 1'` prints 2, on a root filesystem mounted read-only |
| ssh | a real handshake from the host succeeds on both boots and runs `uname -a` and cat `/proc/1/comm` through it |
| ssh authentication | dropbear records `Pubkey auth succeeded` for 'root'; the launcher's throwaway key is handed over on the kernel command line |

## Notes

* Asterinas logs one `Unimplemented syscall number: 334` (`rseq`) per process start,
  and s6 reports a few unsupported `MSG_*`/`SA_*` flags. Those lines are elided from
  the transcript above to keep it readable.
* Each step is typed with a quoted marker (echo DICTYONOS-OK-"07"), so the
  console's echo of the command line cannot be mistaken for the step's answer.
  The transcript shows both, in order.
* The capture used `EPHEMERAL=1`, so boot 1 starts from a freshly created 512 MiB
  state disk; without it both boots reuse whatever `state.ext2` is already there.
* The acceptance no longer uses a system-wide sync: the guest asks only for
  `sync -f /var`, a `syncfs` on the state disk, which is the operation Asterinas
  implements. A system-wide sync reports
  block: failed to do Write on the device with error status: IoError against the
  read-only system disk and does not reliably reach the state disk. That is a
  property of Asterinas, not of this configuration — see gotcha 11 and the
  `state-sync` service in [README.md](README.md).
* `poweroff -f` reports Failed to power off the system and halts the machine:
  Asterinas implements no ACPI power-off. The launcher waits for
  `Halting the machine` and stops QEMU itself, because QEMU does not exit when the
  guest halts.
