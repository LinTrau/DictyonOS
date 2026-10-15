# dictyonos — acceptance transcript

Produced with the standard boot path (no environment overrides):

```sh
AUTO=1 ./dictyonos/run-vm.sh
```

Serial console capture:

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
/nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-svscan
PID   USER     TIME  COMMAND
    1 root      0:00 /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-svscan -X3 -- /run/service
   21 root      0:00 s6-supervise s6-svscan-log
   22 root      0:00 s6-supervise s6-linux-init-runleveld
   23 root      0:00 s6-supervise s6-linux-init-shutdownd
   24 root      0:00 s6-supervise s6-linux-init-early-getty
   25 root      0:00 /nix/store/h6qc93hhsji3k22a85yq98n48d97vh91-s6-linux-init-1.1.2.0-bin/bin/s6-linux-init-shutdownd -d3 -c /run/init -g 3000
   26 root      0:00 /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-log -bpd3 -- 1 t /run/uncaught-logs
   27 root      0:00 /nix/store/2d3xzhklq3z7pkl0lzh6bma4fcnqmk68-busybox-1.36.1/bin/sh --
   28 root      0:00 /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-ipcserverd -1 -c 1 -- /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-sudod -dt30000 -- /run/init/scripts/runlevel
   47 root      0:00 s6-supervise hwclock-fake-updater
   48 root      0:00 s6-supervise hwclock-fake-updater-log
   49 root      0:00 s6-supervise lix-daemon
   50 root      0:00 s6-supervise lix-daemon-log
   51 root      0:00 s6-supervise s6rc-fdholder
   52 root      0:00 s6-supervise s6rc-oneshot-runner
   59 root      0:00 /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-fdholderd -1 -i data/rules
   60 root      0:00 /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-ipcserverd -1 -- /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-ipcserver-access -v0 -E -l0 -i data/rules -- /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-sudod -t 30000 -- /nix/store/bpzycbs47r79nqlyrsxy3ipc4f3azrb7-s6-rc-0.5.4.2-lib/libexec/s6-rc-oneshot-run -l ../.. --
   96 root      0:00 /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-log s1000000 n20 t /var/log/lix-daemon/
   99 root      0:00 /nix/store/fw6vy4zpkb42sy6caqx8yyr426qkx8ci-s6-2.12.0.4/bin/s6-log s1000000 n20 t /var/log/hwclock-fake-updater/
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
/run/service/s6-linux-init-early-getty # echo ---- LIX ----; nix --version
---- LIX ----
warning: unknown setting 'filter-syscalls'
nix (Lix, like Nix) 2.94.2
System type: x86_64-linux
Additional system types: i686-linux, x86_64-v1-linux, x86_64-v2-linux, x86_64-v3-linux
Features: gc, signed-caches
System configuration file: /etc/nix/nix.conf
User configuration files: /root/.config/nix/nix.conf:/etc/xdg/nix/nix.conf
Store directory: /nix/store
State directory: /nix/var/nix
Data directory: /nix/store/ly6x54s87cz4x912sbq24pyxm30iffgh-lix-2.94.2/share
/run/service/s6-linux-init-early-getty # nix eval --expr '1 + 1'
warning: unknown setting 'filter-syscalls'
warning: you don't have Internet access; disabling some network-dependent features
2
/run/service/s6-linux-init-early-getty # echo DICTYONOS-DONE
```

Raw logs: `dictyonos/build/serial.log` (with ANSI colours) and `dictyonos/build/serial.clean.log`.
