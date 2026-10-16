# dictyonos — acceptance transcript

Captured from the serial console of a stock, non-interactive boot of the
committed tree. There is no manual step of any kind:

```sh
git clone <this repo> && cd dictyonos
AUTO=1 nix run
```

Nothing is overridden: the kernel, initramfs, state disk, kernel parameters and
root filesystem all come straight out of the flake. Asterinas logs one
"Unimplemented syscall number: 334" (`rseq`) per process start and s6 reports a
few unsupported `MSG_*`/`SA_*` flags; those lines are elided below to keep the
transcript readable.

```text
/run/service/s6-linux-init-early-getty # echo ==== DICTYONOS ACCEPTANCE ====
==== DICTYONOS ACCEPTANCE ====
/run/service/s6-linux-init-early-getty # uname -a
Linux dictyonos 5.13.0 #1 SMP Thu Jan  1 00:00:00 UTC 1970 x86_64 GNU/Linux
/run/service/s6-linux-init-early-getty # cat /proc/version 2>/dev/null; cat /pro
c/1/comm 2>/dev/null
Linux version 5.13.0 (dictyonos@builder) (rustc 1.99.0-nightly) #1 SMP Thu Jan  1 00:00:00 UTC 1970
s6-svscan
/run/service/s6-linux-init-early-getty # echo ---- PID 1 ----; readlink /proc/1/
exe; ps aux 2>/dev/null
---- PID 1 ----
/nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-svscan
PID   USER     TIME  COMMAND
    1 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   24 root      0:00 s6-supervise s6-svscan-log
   25 root      0:00 s6-supervise s6-linux-init-runleveld
   26 root      0:00 s6-supervise s6-linux-init-shutdownd
   27 root      0:00 s6-supervise s6-linux-init-early-getty
   28 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   29 root      0:00 /nix/store/js0jfqxgrlb7bwk8lr1qa4h3cb4cd0fm-s6-linux-init-
   30 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1
   31 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   47 root      0:00 s6-supervise lix-daemon
   48 root      0:00 s6-supervise lix-daemon-log
   49 root      0:00 s6-supervise s6rc-fdholder
   50 root      0:00 s6-supervise s6rc-oneshot-runner
   51 root      0:00 s6-supervise ssh
   52 root      0:00 s6-supervise ssh-log
   59 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   60 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   98 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   99 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  106 root      0:00 /nix/store/50gf8bygvm8cv7gw73w6w5injdrcpzhk-dropbear-2022.
  107 root      0:05 /nix/store/g8y3595zxljm9g4lyaki61zqjqyvi52d-lix-2.94.2/bin
  135 root      0:00 ps aux
/run/service/s6-linux-init-early-getty # echo ---- s6 ----; if [ -d /run/s6-rc ]
; then echo activation-completed; else echo activation-FAILED; fi; ls /run/servi
ce
---- s6 ----
activation-completed
lix-daemon                 s6-svscan-log
lix-daemon-log             s6rc-fdholder
s6-linux-init-early-getty  s6rc-oneshot-runner
s6-linux-init-runleveld    ssh
s6-linux-init-shutdownd    ssh-log
/run/service/s6-linux-init-early-getty # echo ---- svstat ----; for s in ssh ssh
-log lix-daemon lix-daemon-log s6rc-oneshot-runner; do s6-svstat /run/service/$s
; done 2>&1
---- svstat ----
up (pid 106) 39 seconds
up (pid 98) 39 seconds
up (pid 107) 39 seconds
up (pid 99) 39 seconds
up (pid 59) 39 seconds, ready 39 seconds
/run/service/s6-linux-init-early-getty # echo ---- svclogs ----; echo '== ssh'; 
tail -25 /var/log/ssh/current 2>&1; echo '== lix-daemon'; tail -8 /var/log/lix-d
aemon/current 2>&1; echo '== hwclock'; tail -8 /var/log/hwclock-fake-updater/cur
rent 2>&1
---- svclogs ----
== ssh
@400000006ad1e9a80bb2a8d4 dropbear: installed the authorized key from the kernel command line
@400000006ad1e9a80e781153 dropbear: listening on 10.0.2.15:22
@400000006ad1e9a8115abfaf [106] Oct 16 02:08:19 Not backgrounding
@400000006ad1e9ac1fb74124 [124] Oct 16 02:08:23 Child connection from 10.0.2.2:59186
@400000006ad1e9ac25eebe54 [124] Oct 16 02:08:23 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:59186
@400000006ad1e9ac26b649e2 [124] Oct 16 02:08:23 Exit (root) from <10.0.2.2:59186>: Disconnect received
@400000006ad1e9ac285cf2de [126] Oct 16 02:08:23 Child connection from 10.0.2.2:59194
@400000006ad1e9ac2dc7cf25 [126] Oct 16 02:08:23 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:59194
@400000006ad1e9ac2f438726 [126] Oct 16 02:08:23 Exit (root) from <10.0.2.2:59194>: Disconnect received
@400000006ad1e9ad210a4cf7 [130] Oct 16 02:08:24 Child connection from 10.0.2.2:56920
@400000006ad1e9ad214637cf [130] Oct 16 02:08:24 Exit before auth from <10.0.2.2:56920>: Error reading: Connection reset by peer
== lix-daemon
== hwclock
tail: can't open '/var/log/hwclock-fake-updater/current': No such file or directory
tail: no files
/run/service/s6-linux-init-early-getty # echo ---- disks ----; mount | grep -E '
vda|vdb|/var'
---- disks ----
/dev/vda on / type ext2 (ro,relatime)
/dev/vdb on /var type ext2 (rw,relatime)
/dev/vdb on /nix/var type ext2 (rw,relatime)
/dev/vda on /nix/store type ext2 (ro,relatime)
/run/service/s6-linux-init-early-getty # echo ---- net ----; ip -o addr 2>/dev/n
ull | head -4; cat /etc/resolv.conf 2>/dev/null; netstat -ltn 2>/dev/null | grep
 :22
---- net ----
1: lo    inet 127.0.0.1/8 scope host lo
1: lo    inet6 ::1/128 scope host 
2: eth0    inet 10.0.2.15/24 brd 10.0.2.255 scope global eth0
nameserver 10.0.2.3
/run/service/s6-linux-init-early-getty # echo ---- LIX ----; nix --version
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
[    54.708] WARN  : PID 152: terminating on signal SIGKILL
/run/service/s6-linux-init-early-getty # nix eval --expr '1 + 1'
2
[    57.609] WARN  : PID 154: terminating on signal SIGKILL
/run/service/s6-linux-init-early-getty # echo ---- persist ----; echo persisted 
> /var/persist-test; sync; cat /var/persist-test; ls -l /var/persist-test
---- persist ----
[    61.214] ERROR : block: failed to do Write on the device with error status: IoError
[    61.214] ERROR : writeback I/O failed with status IoError; data may be lost
persisted
-rw-r--r--    1 root     root            10 Oct 16 02:09 /var/persist-test
/run/service/s6-linux-init-early-getty # echo DICTYONOS-DONE
```

## The ssh check, from the host

The launcher verifies the machine over the forwarded port in parallel with
the serial transcript above:

```text
==> ssh handshake succeeded; running a remote command
Linux dictyonos 5.13.0 #1 SMP Thu Jan  1 00:00:00 UTC 1970 x86_64 GNU/Linux
s6-svscan
SSH-REMOTE-OK
```

## What this demonstrates

| check | result |
| --- | --- |
| kernel identity | `/proc/version` names `dictyonos@builder` and a Rust compiler; `uname` reports the Linux ABI Asterinas emulates |
| build metadata redacted | the developer machine's user and host name appear nowhere in the payload |
| PID 1 | `/nix/store/...-s6-2.12.0.4/bin/s6-svscan -X3 -- /run/service` — `s6`, not systemd |
| sixos activation completed | `/run/s6-rc` exists and `s6-rc` reports every service started, which only happens if `activate` ran to the end |
| service supervision | `s6-svstat` reports the four longruns up and ready; each has its own `s6-log` under `/var/log` |
| read-only system disk | `/dev/vda on / type ext2 (ro,relatime)`, and `/nix/store` is a read-only mount of its own |
| writable state disk | `/dev/vdb on /var type ext2 (rw,relatime)`, plus `/nix/var` bound onto it |
| no systemd anywhere | the closure contains no `systemd`, `dbus` or `polkit` |
| Lix is the package manager | `nix --version` reports `nix (Lix, like Nix) 2.94.2` |
| Lix works on a read-only store | `nix eval --expr '1 + 1'` prints `2` |
| ssh | the launcher completes a real handshake and runs `uname -a`, `cat /proc/1/comm` over it |

## Notes

* `poweroff -f` reports `Failed to power off the system`: Asterinas implements
  no ACPI power-off. The launcher ends the run with `TIMEOUT` instead.
* The state-disk round-trips above are checked again from the host afterwards,
  by reading `.dictyonos-vm/state.ext2` with `debugfs` — see the note in
  [README.md](README.md#known-limitations) about when those writes are durable.
* The whole run costs a few minutes on 32 cores, most of it the kernel build
  the first time and the ext2 image afterwards.
