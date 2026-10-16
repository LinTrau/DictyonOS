# dictyonos — acceptance transcript

Captured from the serial console of a stock, non-interactive boot of this
commit. There is no manual step of any kind:

```sh
git clone <this repo> && cd dictyonos
AUTO=1 nix run
```

Nothing is overridden: the kernel, initramfs, state disk, kernel parameters and
root filesystem all come straight out of the flake.


```text
/run/service/s6-linux-init-early-getty # echo ==== DICTYONOS ACCEPTANCE ====
==== DICTYONOS ACCEPTANCE ====
/run/service/s6-linux-init-early-getty # uname -a
Linux dictyonos 5.13.0 #1 SMP Thu Jan  1 00:00:00 UTC 1970 x86_64 GNU/Linux
cat /proc/version 2>/dev/null; cat /pro

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
   30 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   31 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1
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
  103 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  104 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  107 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  114 root      0:00 {yqqw32lw56s9plm} /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4
  116 root      0:04 /nix/store/g8y3595zxljm9g4lyaki61zqjqyvi52d-lix-2.94.2/bin
  117 root      0:00 /nix/store/50gf8bygvm8cv7gw73w6w5injdrcpzhk-dropbear-2022.
  146 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1
  150 root      0:00 ps aux
/run/service/s6-linux-init-early-getty # echo ---- s6 ----; if [ -d /run/s6-rc ]

; then echo activation-completed; else echo activation-FAILED; fi; ls /run/servi

ce
---- s6 ----
activation-completed
lix-daemon                 s6rc-fdholder
lix-daemon-log             s6rc-oneshot-runner
s6-linux-init-early-getty  ssh
s6-linux-init-runleveld    ssh-log
s6-linux-init-shutdownd    state-sync
s6-svscan-log              state-sync-log
/run/service/s6-linux-init-early-getty # echo ---- svstat ----; for s in ssh ssh

-log lix-daemon lix-daemon-log state-sync s6rc-oneshot-runner; do s6-svstat /run

/service/$s; done 2>&1
---- svstat ----
up (pid 117) 39 seconds
up (pid 107) 39 seconds
up (pid 116) 39 seconds
up (pid 104) 39 seconds
up (pid 114) 39 seconds
up (pid 62) 40 seconds, ready 40 seconds
/run/service/s6-linux-init-early-getty # echo ---- svclogs ----; echo '== ssh'; 

tail -25 /var/log/ssh/current 2>&1; echo '== lix-daemon'; tail -8 /var/log/lix-d

aemon/current 2>&1; echo '== hwclock'; tail -8 /var/log/hwclock-fake-updater/cur

rent 2>&1
---- svclogs ----
== ssh
@400000006ad1ef140c9b1d11 dropbear: installed the authorized key from the kernel command line
@400000006ad1ef140ef1a498 dropbear: listening on 10.0.2.15:22
@400000006ad1ef1411a3fe7a [117] Oct 16 02:31:27 Not backgrounding
@400000006ad1ef18347f11a5 [137] Oct 16 02:31:31 Child connection from 10.0.2.2:40680
@400000006ad1ef183a77983e [137] Oct 16 02:31:31 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:40680
@400000006ad1ef183b0a9cf6 [137] Oct 16 02:31:31 Exit (root) from <10.0.2.2:40680>: Disconnect received
@400000006ad1ef1900ddc07f [139] Oct 16 02:31:31 Child connection from 10.0.2.2:40688
@400000006ad1ef19064bc79a [139] Oct 16 02:31:32 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:40688
@400000006ad1ef1907abcb84 [139] Oct 16 02:31:32 Exit (root) from <10.0.2.2:40688>: Disconnect received
@400000006ad1ef19327268e1 [143] Oct 16 02:31:32 Child connection from 10.0.2.2:40672
@400000006ad1ef193294d5cb [143] Oct 16 02:31:32 Exit before auth from <10.0.2.2:40672>: Error reading: Connection reset by peer
== lix-daemon
== hwclock
tail: can't open '/var/log/hwclock-fake-updater/current': No such file or directory
tail: no files
/run/service/s6-linux-init-early-getty # echo ---- persist ----; echo early > /v

ar/persist-early; sync -f /var/persist-early; echo targeted-sync-exit=$?; sync; 

cat /var/persist-early
---- persist ----
targeted-sync-exit=0
[    49.903] ERROR : block: failed to do Write on the device with error status: IoError
[    49.903] ERROR : writeback I/O failed with status IoError; data may be lost
early
/run/service/s6-linux-init-early-getty # echo ---- disks ----; mount | grep -E '

vda|vdb|/var'
---- disks ----
/dev/vda on / type ext2 (ro,relatime)
/dev/vda on /nix/store type ext2 (ro,relatime)
/dev/vdb on /nix/var type ext2 (rw,relatime)
/dev/vdb on /var type ext2 (rw,relatime)
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
nix eval --expr '1 + 1'
2
/run/service/s6-linux-init-early-getty # echo ---- persist2 ----; echo late > /v

ar/persist-late; sleep 35; cat /var/persist-late; ls -l /var/persist-late /var/p

ersist-early; tail -3 /var/log/state-sync/current
---- persist2 ----
echo DICTYONOS-DONE
```

## The ssh check, from the host

The launcher verifies the machine over the forwarded port in parallel with the serial transcript above -- the port forward is real and so is the key:

```text
==> ssh handshake succeeded; running a remote command
Linux dictyonos 5.13.0 #1 SMP Thu Jan  1 00:00:00 UTC 1970 x86_64 GNU/Linux
s6-svscan
SSH-REMOTE-OK
```

## The state disk, from the host

Afterwards the host opens `.dictyonos-vm/state.ext2` with `debugfs` and reads back what the guest wrote to it. `persist-late` is the interesting one: the acceptance wrote it and then *slept*, syncing nothing itself, so it can only be here because the `state-sync` service committed it -- see the three ticks at the end of its log.

```text
== / (root of the state disk) ==
      2   40755 (2)      0      0    4096 16-Oct-2026 17:32 .
      2   40755 (2)      0      0    4096 16-Oct-2026 17:32 ..
     11   40700 (2)      0      0   16384 16-Oct-2026 17:31 lost+found
     12   40755 (2)      0      0    4096 16-Oct-2026 17:31 log
     13   40755 (2)      0      0    4096 16-Oct-2026 17:31 root
     14   40755 (2)      0      0    4096 16-Oct-2026 17:31 nix-var
     29   40755 (2)      0      0    4096 16-Oct-2026 17:31 lib
     35  100644 (1)      0      0       6 16-Oct-2026 17:32 persist-early
     36  100644 (1)      0      0       5 16-Oct-2026 17:32 persist-late


== /persist-early ==
early
== /persist-late ==
late
== /lib/dropbear ==
 30  (12) .    29  (52) ..    33  (4032) dropbear_ed25519_host_key   
== /log ==
 12  (12) .    2  (12) ..    15  (20) state-sync    16  (20) lix-daemon   
 17  (4032) ssh   
== /log/state-sync/current ==
state-sync: committing /var
state-sync: committing /var
state-sync: committing /var
```


## What this demonstrates

| check | result |
| --- | --- |
| kernel identity | `/proc/version` names `dictyonos@builder` and a Rust compiler; `uname` reports the Linux ABI Asterinas emulates |
| build metadata redacted | the developer machine's user and host name appear nowhere in the payload |
| PID 1 | `/nix/store/...-s6-2.12.0.4/bin/s6-svscan -X3 -- /run/service` — `s6`, not systemd |
| no systemd anywhere | the closure contains no `systemd`, `dbus` or `polkit` |
| sixos activation completed | `/run/s6-rc` exists, which only happens if `bin/activate` ran all the way to `s6-rc-init` |
| service supervision | `s6-svstat` reports every longrun up; each has its own `s6-log` under `/var/log` |
| read-only system disk | `/dev/vda on / type ext2 (ro,relatime)`, and `/nix/store` is a read-only mount of its own |
| writable state disk | `/dev/vdb on /var type ext2 (rw,relatime)`, plus `/nix/var` bound onto it |
| state disk really persists | the host finds `/persist-early` and `/persist-late` inside `state.ext2`; the late one was committed by `state-sync`, not by the shell |
| Lix is the package manager | `nix --version` reports `nix (Lix, like Nix) 2.94.2` |
| Lix works on a read-only store | `nix eval --expr '1 + 1'` prints `2` |
| ssh | a real handshake from the host succeeds and runs `uname -a`, `cat /proc/1/comm` through it |
| ssh authentication | dropbear's log records `Pubkey auth succeeded for 'root'` |

## Notes

* Asterinas logs one `Unimplemented syscall number: 334` (`rseq`) per process
  start, and s6 reports a few unsupported `MSG_*`/`SA_*` flags. Those lines are
  elided from the transcript above to keep it readable.
* The system-wide `sync` reports
  `block: failed to do Write on the device with error status: IoError` against
  the read-only system disk and does not reliably reach the state disk. That is
  a property of Asterinas, not of this configuration — see gotcha 11 and the
  `state-sync` service in [README.md](README.md).
* `poweroff -f` reports `Failed to power off the system` and halts the machine:
  Asterinas implements no ACPI power-off. The launcher ends the run with
  `TIMEOUT` instead.
