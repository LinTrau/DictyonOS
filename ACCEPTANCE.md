# dictyonos — acceptance transcript

Captured from the serial console of a stock, non-interactive boot of the
committed tree:

```sh
git clone <this repo> && cd dictyonos
./scripts/build-kernel.sh
nix build .#rootfs
AUTO=1 nix run
```

Nothing was overridden: the launcher, the kernel parameters and the root
filesystem all come straight out of the flake.

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
exe; ps aux 2>/dev/null | head -20
---- PID 1 ----
/nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-svscan
PID   USER     TIME  COMMAND
    1 root      0:01 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-svscan -X3 -- /run/service
   21 root      0:00 s6-supervise s6-svscan-log
   22 root      0:00 s6-supervise s6-linux-init-runleveld
   23 root      0:00 s6-supervise s6-linux-init-shutdownd
   24 root      0:00 s6-supervise s6-linux-init-early-getty
   25 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-log -bpd3 -- 1 t /run/uncaught-logs
   26 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-ipcserverd -1 -c 1 -- /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-sudod -dt30000 -- /run/init/scripts/runlevel
   27 root      0:00 /nix/store/js0jfqxgrlb7bwk8lr1qa4h3cb4cd0fm-s6-linux-init-1.1.2.0-bin/bin/s6-linux-init-shutdownd -d3 -c /run/init -g 3000
   28 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1/bin/sh --
   47 root      0:00 s6-supervise hwclock-fake-updater
   48 root      0:00 s6-supervise hwclock-fake-updater-log
   49 root      0:00 s6-supervise lix-daemon
   50 root      0:00 s6-supervise lix-daemon-log
   51 root      0:00 s6-supervise s6rc-fdholder
   52 root      0:00 s6-supervise s6rc-oneshot-runner
   59 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-fdholderd -1 -i data/rules
   60 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-ipcserverd -1 -- /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-ipcserver-access -v0 -E -l0 -i data/rules -- /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-sudod -t 30000 -- /nix/store/ndg34k9kn84m6av0rgg1dwdziqmh36h8-s6-rc-0.5.4.2-lib/libexec/s6-rc-oneshot-run -l ../.. --
   99 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-log s1000000 n20 t /var/log/hwclock-fake-updater/
  100 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bin/s6-log s1000000 n20 t /var/log/lix-daemon/
/run/service/s6-linux-init-early-getty # echo ---- s6 ----; ls /run/s6-rc /run/s
ervice 2>/dev/null
---- s6 ----
/run/s6-rc:
compiled     lock         prefix       scandir      servicedirs  state

/run/service:
hwclock-fake-updater       s6-linux-init-runleveld
hwclock-fake-updater-log   s6-linux-init-shutdownd
lix-daemon                 s6-svscan-log
lix-daemon-log             s6rc-fdholder
s6-linux-init-early-getty  s6rc-oneshot-runner
/run/service/s6-linux-init-early-getty # echo ---- net ----; ip -o addr 2>/dev/n
ull; cat /etc/resolv.conf 2>/dev/null
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
/run/service/s6-linux-init-early-getty # nix eval --expr '1 + 1'
2
/run/service/s6-linux-init-early-getty # echo DICTYONOS-DONE
```

## What this demonstrates

| check | result |
| --- | --- |
| kernel identity | `/proc/version` names `dictyonos@builder` and a Rust compiler; `uname` reports the Linux ABI Asterinas emulates |
| build metadata redacted | the developer machine's user and host name appear nowhere in the payload |
| PID 1 | `/nix/store/...-s6-2.12.0.4/bin/s6-svscan -X3 -- /run/service` |
| no systemd | `ps aux` lists only s6-supervise and s6-log processes |
| s6-rc operational | `/run/s6-rc` holds the compiled database; `/run/service` holds the live scandir |
| default package manager | `nix (Lix, like Nix) 2.94.2` |
| evaluation works | `nix eval --expr '1 + 1'` prints `2` |
| no sandbox warning | `filter-syscalls` is not written to `/etc/nix/nix.conf`, so no "unknown setting" warning is emitted |
| networking | `eth0` got `10.0.2.15/24` over DHCP from the QEMU user-mode NIC, and `/etc/resolv.conf` points at `10.0.2.3` |

Raw logs: `serial.log` (with ANSI colours) and `serial.clean.log`.

## Known noise in the log

* `Unimplemented syscall number: 334` — `rseq`, logged once per process start; glibc handles `ENOSYS` gracefully.
* `Failed to power off the system` / `Halting the machine...` — Asterinas does not implement ACPI power-off, so the launcher's `TIMEOUT` ends the run instead.
* `getty: ttyS0: TIOCSCTTY: Operation not permitted` may appear if a second getty races the early getty; it does not affect the console shell.
