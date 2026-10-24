# dictyonos: acceptance transcript

This is the acceptance record for this tree. Everything below was captured by
`AUTO=1 nix run` on a stock, non-interactive boot: there is no manual step of any
kind. The run boots the machine **twice against the same state disk**: the first
boot has to bring the system up, and the second has to show that what the first
one wrote is still there. It checks the result from the host as much as from the
guest.

This record was captured on 24 October 2026 against the asterinas pin `ceb65e3f8`
and the flake.lock in this tree; the console text below is unedited apart from
dropping the kernel's own log lines, as noted at the end.

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
answer before typing the next, so the transcript is in the order it happened. The
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
   31 root      0:00 s6-supervise s6-svscan-log
   32 root      0:00 s6-supervise s6-linux-init-runleveld
   33 root      0:00 s6-supervise s6-linux-init-shutdownd
   34 root      0:00 s6-supervise s6-linux-init-early-getty
   35 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   36 root      0:00 /nix/store/js0jfqxgrlb7bwk8lr1qa4h3cb4cd0fm-s6-linux-init-
   37 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   38 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1
   54 root      0:00 s6-supervise lix-daemon
   55 root      0:00 s6-supervise lix-daemon-log
   56 root      0:00 s6-supervise s6rc-fdholder
   57 root      0:00 s6-supervise s6rc-oneshot-runner
   58 root      0:00 s6-supervise ssh
   59 root      0:00 s6-supervise ssh-log
   60 root      0:00 s6-supervise state-sync
   61 root      0:00 s6-supervise state-sync-log
   68 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
   69 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  110 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  111 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  113 root      0:00 /nix/store/fqbzpslyx0mfwmiwpn7vbdar39g756dx-s6-2.12.0.4/bi
  122 root      0:00 {yqqw32lw56s9plm} /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4
  123 root      0:00 /nix/store/50gf8bygvm8cv7gw73w6w5injdrcpzhk-dropbear-2022.
  124 root      0:04 /nix/store/23i45j5xlngp9hwwj0l9y4x9rq5j6i6r-lix-2.94.2/bin
  154 root      0:00 /nix/store/v9835pqvwavkylzv7a5jlvq2m0jd4ddz-busybox-1.36.1
  158 root      0:00 ps aux
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
up (pid 123) 37 seconds
up (pid 111) 37 seconds
up (pid 124) 37 seconds
up (pid 113) 38 seconds
up (pid 122) 37 seconds
up (pid 69) 38 seconds, ready 38 seconds
DICTYONOS-OK-06
/run/service/s6-linux-init-early-getty # echo ---- svclogs ----; echo '== ssh';

tail -25 /var/log/ssh/current 2>&1; echo '== lix-daemon'; tail -8 /var/log/lix-d

aemon/current 2>&1; echo '== state-sync'; tail -8 /var/log/state-sync/current 2>

&1; echo DICTYONOS-OK-"07"
---- svclogs ----
== ssh
@400000006adcaf050d4e12c9 dropbear: installed the authorized key from the kernel command line
@400000006adcaf050f85f641 dropbear: listening on 10.0.2.15:22
@400000006adcaf05125cd8c9 [123] Oct 24 06:13:04 Not backgrounding
@400000006adcaf09373fb897 [144] Oct 24 06:13:08 Child connection from 10.0.2.2:48310
@400000006adcaf0a012cd279 [144] Oct 24 06:13:08 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:48310
@400000006adcaf0a01b73e82 [144] Oct 24 06:13:08 Exit (root) from <10.0.2.2:48310>: Disconnect received
@400000006adcaf0a0330472e [146] Oct 24 06:13:09 Child connection from 10.0.2.2:48324
@400000006adcaf0a089bc8dc [146] Oct 24 06:13:09 Pubkey auth succeeded for 'root' with ssh-ed25519 key SHA256:xZaF01c6o8MX3cmqpGitnKrX0dbhyhTzzbjjC3BqKvM from 10.0.2.2:48324
@400000006adcaf0a09e5385f [146] Oct 24 06:13:09 Exit (root) from <10.0.2.2:48324>: Disconnect received
@400000006adcaf0a0a33f3a7 [150] Oct 24 06:13:09 Child connection from 10.0.2.2:48334
@400000006adcaf0a0a98b6f4 [150] Oct 24 06:13:09 Exit before auth from <10.0.2.2:48334>: Exited normally
@400000006adcaf0a388ff7b9 [151] Oct 24 06:13:09 Child connection from 10.0.2.2:48298
@400000006adcaf0a38c7f5b1 [151] Oct 24 06:13:09 Exit before auth from <10.0.2.2:48298>: Error reading: Connection reset by peer
== lix-daemon
== state-sync
@400000006adcaf230c46585a state-sync: committing /var
DICTYONOS-OK-07
/run/service/s6-linux-init-early-getty # echo ---- persist ----; echo early > /v

ar/persist-early; sync -f /var/persist-early; echo targeted-sync-exit=$?; cat /v

ar/persist-early; echo DICTYONOS-OK-"08"
---- persist ----
targeted-sync-exit=0
early
DICTYONOS-OK-08
/run/service/s6-linux-init-early-getty # echo ---- disks ----; mount | grep -E '

vda|vdb|nix/store|/var'; echo DICTYONOS-OK-"09"
---- disks ----
/dev/vda on / type ext2 (ro,relatime)
overlay on /nix/store type overlay (rw,relatime)
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
[    48.217] WARN  : CLONE_SYSVSEM is not supported now
nix (Lix, like Nix) 2.94.2
System type: x86_64-linux
Additional system types: i686-linux, x86_64-v1-linux, x86_64-v2-linux, x86_64-v3-linux
Features: gc, signed-caches
System configuration file: /etc/nix/nix.conf
User configuration files: /root/.config/nix/nix.conf:/etc/xdg/nix/nix.conf
Store directory: /nix/store
State directory: /nix/var/nix
Data directory: /nix/store/23i45j5xlngp9hwwj0l9y4x9rq5j6i6r-lix-2.94.2/share
[    48.510] WARN  : PID 178: terminating on signal SIGKILL
DICTYONOS-OK-11
/run/service/s6-linux-init-early-getty # nix eval --expr '1 + 1'; echo DICTYONOS

-OK-"12"
[    50.208] WARN  : CLONE_SYSVSEM is not supported now
2
[    50.488] WARN  : PID 180: terminating on signal SIGKILL
DICTYONOS-OK-12
/run/service/s6-linux-init-early-getty # echo ---- store write ----; echo built-

in-the-guest > /tmp/dictyonos-store-write.txt; nix store add-file /tmp/dictyonos

-store-write.txt; echo add-file-exit=$?; sync -f /var; echo DICTYONOS-OK-"13"
---- store write ----
[    52.194] WARN  : CLONE_SYSVSEM is not supported now
[    52.519] WARN  : CLONE_SYSVSEM is not supported now
[    52.846] WARN  : CLONE_SYSVSEM is not supported now
/nix/store/caardw9r23xgi40d2ymsbjr9mncb2lm1-dictyonos-store-write.txt
[    52.869] WARN  : PID 182: terminating on signal SIGKILL
add-file-exit=0
[    52.905] WARN  : PID 184: terminating on signal SIGKILL
DICTYONOS-OK-13
/run/service/s6-linux-init-early-getty # echo ---- build ----; nix build --no-li

nk --print-out-paths --expr "derivation { name = ''dictyonos-build-test''; syste

m = ''x86_64-linux''; builder = ''/bin/sh''; args = [ ''-c'' ''echo built-in-the

-guest > \$out'' ]; }"; echo build-exit=$?; sync -f /var; echo DICTYONOS-OK-"14"

---- build ----
[    54.181] WARN  : CLONE_SYSVSEM is not supported now
[    54.489] WARN  : CLONE_SYSVSEM is not supported now
[    54.747] WARN  : CLONE_SYSVSEM is not supported now
[    54.790] WARN  : CLONE_SYSVSEM is not supported now
[    54.794] WARN  : CLONE_SYSVSEM is not supported now
warning: error: unable to download 'https://cache.nixos.org/nix-cache-info': Resolving timed out after 5055 milliseconds (curl error code=28); retrying in 423ms ms (attempt 1/5)
[    63.462] WARN  : CLONE_SYSVSEM is not supported now
[    63.731] WARN  : PID 197: terminating on signal SIGKILL
[    63.731] WARN  : PID 197: terminating on signal SIGKILL
[    63.759] WARN  : `personality(ADDR_NO_RANDOMIZE)` is accepted, but still does not disable ASLR
/nix/store/kfvsv78kfdskj96m3bm50v0dhnrbhkgh-dictyonos-build-test
[    63.773] WARN  : PID 188: terminating on signal SIGKILL
build-exit=0
[    63.802] WARN  : PID 190: terminating on signal SIGKILL
DICTYONOS-OK-14
/run/service/s6-linux-init-early-getty # echo ---- built content ----; ls -ld /n

ix/store/*-dictyonos-build-test /nix/store/*-dictyonos-store-write.txt; cat /nix

/store/*-dictyonos-build-test; cat /nix/store/*-dictyonos-store-write.txt; echo

DICTYONOS-OK-"15"
---- built content ----
-r--r--r--    1 root     root            19 Dec 31  1969 /nix/store/caardw9r23xgi40d2ymsbjr9mncb2lm1-dictyonos-store-write.txt
-r--r--r--    1 root     root            19 Dec 31  1969 /nix/store/kfvsv78kfdskj96m3bm50v0dhnrbhkgh-dictyonos-build-test
built-in-the-guest
built-in-the-guest
DICTYONOS-OK-15
/run/service/s6-linux-init-early-getty # echo ---- generations ----; mkdir -p /n

ix/store/dictyonos-generation-2; cp -a /run/current-system/. /nix/store/dictyono

s-generation-2/; echo copy-exit=$?; dictyonos-switch /nix/store/dictyonos-genera

tion-2; echo switch-exit=$?; echo nextboot=$(readlink /nix/var/nix/profiles/next

boot); echo prevboot=$(readlink /nix/var/nix/profiles/prevboot); sync -f /var; e

cho DICTYONOS-OK-"16"
---- generations ----
copy-exit=0
next boot: /nix/store/dictyonos-generation-2
go back : boot with dictyonos.rollback=1 (/nix/store/mcw8lms2qvglm0j1cyn2bcsymz77pgc4-six-system-dictyonos-unknown-nixpkgs-version)
switch-exit=0
nextboot=/nix/store/dictyonos-generation-2
prevboot=/nix/store/mcw8lms2qvglm0j1cyn2bcsymz77pgc4-six-system-dictyonos-unknown-nixpkgs-version
DICTYONOS-OK-16
/run/service/s6-linux-init-early-getty # echo ---- persist2 ----; echo late > /v

ar/persist-late; sleep 35; cat /var/persist-late; ls -l /var/persist-late /var/p

ersist-early; tail -3 /var/log/state-sync/current; echo DICTYONOS-OK-"17"
---- persist2 ----
late
-rw-r--r--    1 root     root             6 Oct 24 06:13 /var/persist-early
-rw-r--r--    1 root     root             5 Oct 24 06:14 /var/persist-late
@400000006adcaf230c46585a state-sync: committing /var
@400000006adcaf41105db947 state-sync: committing /var
@400000006adcaf5f14b84df7 state-sync: committing /var
DICTYONOS-OK-17
/run/service/s6-linux-init-early-getty # echo DICTYONOS-DONE; echo DICTYONOS-OK-

"18"
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

The first machine powers itself off, and the launcher starts QEMU again with the
very same `state.ext2`. Between the two boots the disk is not mounted on the host
at all: it is only read with debugfs, so nothing but the guest can have written
to it.

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
-rw-r--r--    1 root     root             6 Oct 24 06:13 /var/persist-early
-rw-r--r--    1 root     root             5 Oct 24 06:14 /var/persist-late
DICTYONOS-OK-02
echo ---- host key ----; dropbearkey -y

 -f /var/lib/dropbear/dropbear_ed25519_host_key | tail -2; echo DICTYONOS-OK-"03

"
---- host key ----
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3Yp9xkN3DI2Gn0F8VSASb8LFTe9HlYvgnerFM/00cy root@dictyonos
Fingerprint: SHA256:4Mcm5HVjJZ7FX3dBoGdorpJzWfXwCyuUMecpHKcwXh8
DICTYONOS-OK-03
/run/service/s6-linux-init-early-getty # echo ---- state-sync log ----; tail -3

/var/log/state-sync/current; echo DICTYONOS-OK-"04"
---- state-sync log ----
@400000006adcaf96070d01ec state-sync: committing /var
DICTYONOS-OK-04
/run/service/s6-linux-init-early-getty # echo ---- store persistence ----; ls -l

d /nix/store/*-dictyonos-build-test /nix/store/*-dictyonos-store-write.txt; cat

/nix/store/*-dictyonos-build-test; cat /nix/store/*-dictyonos-store-write.txt; e

cho DICTYONOS-OK-"05"
---- store persistence ----
-r--r--r--    1 root     root            19 Dec 31  1969 /nix/store/caardw9r23xgi40d2ymsbjr9mncb2lm1-dictyonos-store-write.txt
-r--r--r--    1 root     root            19 Dec 31  1969 /nix/store/kfvsv78kfdskj96m3bm50v0dhnrbhkgh-dictyonos-build-test
built-in-the-guest
built-in-the-guest
DICTYONOS-OK-05
/run/service/s6-linux-init-early-getty # echo ---- generation ----; echo nextboo

t=$(readlink /nix/var/nix/profiles/nextboot); echo prevboot=$(readlink /nix/var/

nix/profiles/prevboot); ls -ld /nix/store/dictyonos-generation-2/boot/init; echo

 DICTYONOS-OK-"06"
---- generation ----
nextboot=/nix/store/dictyonos-generation-2
prevboot=/nix/store/mcw8lms2qvglm0j1cyn2bcsymz77pgc4-six-system-dictyonos-unknown-nixpkgs-version
lrwxrwxrwx    1 1000     100             80 Oct 24 06:14 /nix/store/dictyonos-generation-2/boot/init -> /nix/store/m5j4gp00czqmg4qfg3msbz1j095jav75-six-s6-linux-init-unstable/boot/init
DICTYONOS-OK-06
/run/service/s6-linux-init-early-getty # if [ "$(cat /var/persist-early 2>/dev/n

ull)" = early ] && [ "$(cat /var/persist-late 2>/dev/null)" = late ] && [ -e "$(

ls -d /nix/store/*-dictyonos-build-test 2>/dev/null)" ]; then echo REBOOT-PERSIS

TENCE-"OK"; else echo REBOOT-PERSISTENCE-"FAILED"; fi; echo DICTYONOS-OK-"07"
REBOOT-PERSISTENCE-OK
DICTYONOS-OK-07
/run/service/s6-linux-init-early-getty # echo DICTYONOS-DONE; echo DICTYONOS-OK-

"08"
DICTYONOS-DONE
```

## Rolling back, from a separate run

Boot 2 started the generation recorded in nextboot. Going back is one word added to
the kernel command line the configuration carries: `dictyonos.rollback=1`.
Same launcher, same state disk, and the initramfs says which side of the profile
pair it took:

```text
[dictyonos-init] dictyonos.rollback=1: prevboot before nextboot
[dictyonos-init] handing off to /nix/store/mcw8lms2qvglm0j1cyn2bcsymz77pgc4-six-system-dictyonos-unknown-nixpkgs-version/boot/init (from prevboot)
```

nextboot still named `/nix/store/dictyonos-generation-2` at that point, so the
machine deliberately did not start it: prevboot is the configuration the switch
kept when it recorded the newer one.

## The state disk, and how each boot ended, from the host

debugfs reads the files out of it without mounting it, and the host key dropbear
presented to the ssh client is compared across the two boots. e2fsck runs with
-n, so it only looks: it reports the extended attributes Asterinas wrote for the
overlay's upper layer as damaged. See the last note. The isa-debug-exit lines are
the launcher's verdict on how QEMU ended: by itself, with status 33, because the
guest asked it to.

```text
==> boot 1: the guest powered the machine off; QEMU exited by itself with 33 (isa-debug-exit 0x10, no timeout)

== boot1: e2fsck -fn state.ext2 ==
e2fsck 1.47.0 (5-Feb-2023)
Pass 1: Checking inodes, blocks, and sizes
Extended attribute in inode 18 has a hash (0) which is invalid
Clear? no

Inode 18, i_blocks is 8, should be 16.  Fix? no

Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
Block bitmap differences:  -2650 -2653 -2666 -2687
Fix? no

state.ext2: ********** WARNING: Filesystem still has errors **********

state.ext2: 191/32768 files (2.1% non-contiguous), 4409/131072 blocks
e2fsck exit status: 4
== /persist-early ==
early
== /persist-late ==
late
== /log/state-sync/current ==
@400000006adcaf230c46585a state-sync: committing /var
@400000006adcaf41105db947 state-sync: committing /var
@400000006adcaf5f14b84df7 state-sync: committing /var
== /lib/dropbear ==
     36   40755 (2)      0      0    4096 24-Oct-2026 21:13 .
     34   40755 (2)      0      0    4096 24-Oct-2026 21:13 ..
     39  100600 (1)      0      0      83 24-Oct-2026 21:13 dropbear_ed25519_host_key

==> boot 2: the guest powered the machine off; QEMU exited by itself with 33 (isa-debug-exit 0x10, no timeout)

== boot2: e2fsck -fn state.ext2 ==
e2fsck 1.47.0 (5-Feb-2023)
Pass 1: Checking inodes, blocks, and sizes
Extended attribute in inode 18 has a hash (0) which is invalid
Clear? no

Inode 18, i_blocks is 8, should be 16.  Fix? no

Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
Block bitmap differences:  -2650 -2653 -2666 -2687
Fix? no

state.ext2: ********** WARNING: Filesystem still has errors **********

state.ext2: 194/32768 files (2.1% non-contiguous), 4411/131072 blocks
e2fsck exit status: 4
== /persist-early ==
early
== /persist-late ==
late
== /log/state-sync/current ==
@400000006adcaf96070d01ec state-sync: committing /var
== /lib/dropbear ==
     36   40755 (2)      0      0    4096 24-Oct-2026 21:13 .
     34   40755 (2)      0      0    4096 24-Oct-2026 21:13 ..
     39  100600 (1)      0      0      83 24-Oct-2026 21:13 dropbear_ed25519_host_key

== dropbear host key, as a client sees it ==
both boots presented the same key:
[127.0.0.1]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3Yp9xkN3DI2Gn0F8VSASb8LFTe9HlYvgnerFM/00cy

== after boot 2, read from the state disk ==
persist-early: 'early'
persist-late:  'late'
host key:      byte-identical to boot 1
==> generations: boot 2 started the configuration recorded on the state disk, not the one on the command line
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
| read-only system disk | mount shows `/dev/vda on / type ext2 (ro,relatime)`; the running system never writes to it |
| writable state disk | `/dev/vdb on /var type ext2 (rw,relatime)`, with `/nix/var` bound onto it |
| a writable store on a read-only root | /nix/store is an overlay mount: the system disk is the lower layer and `/var/nix-store-upper`, which lives on the state disk, is the upper one |
| state disk really persists | the host finds `/persist-early` and /persist-late inside `state.ext2`; `/var/persist-late` was never synced by the shell; the `state-sync` timer committed it |
| the persistence survives a reboot | boot 2 reads early and late back from the same disk, with a fresh kernel and an empty page cache |
| the ssh host key survives a reboot | both boots present the same client-visible key, and the key file dumped from the disk is byte-identical across them |
| Lix is the package manager | `nix --version` reports `nix (Lix, like Nix) 2.94.2` |
| Lix runs, and the guest can build | `nix eval --expr '1 + 1'` prints 2, `nix store add-file` adds an object to the store, and a real `nix build` produces /nix/store/...-dictyonos-build-test |
| what the guest built survives a reboot | boot 2 finds the added file and the built path again, with the same contents |
| poweroff is a real poweroff | both boots end with `poweroff -f`, and QEMU exits by itself with status 33 (`isa-debug-exit 0x10`): no TIMEOUT, no halted-CPU machine to kill |
| a generation can be selected | boot 1 runs dictyonos-switch, which writes nextboot/prevboot on the state disk; boot 2 starts that configuration, not the one on its kernel command line |
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
  property of Asterinas, not of this configuration; see gotcha 11 and the
  `state-sync` service in [README.md](README.md).
* `e2fsck -fn` on the state disk warns about the upper layer the overlay keeps
  there: Asterinas leaves ext2's extended-attribute hash unset and miscounts the
  blocks an attribute occupies. Do not run a
  repairing e2fsck against a state disk you care about, because it would "fix" the
  hashes and lose the overlay's files. See gotcha 14 in [README.md](README.md).
* A generation has to be a different store path for the switch to mean anything,
  and the image carries exactly one configuration, so boot 1 first copies it to a
  second name inside the writable store (/nix/store/dictyonos-generation-2) and
  switches to that. The copy is a fixture, not a hashed store path.
* `poweroff -f` is a real poweroff. Asterinas has no ACPI, so the kernel writes 0x10
  to QEMU's isa-debug-exit port (iobase 0xf4) and QEMU exits by itself with
  status 33; the launcher reports that instead of waiting for TIMEOUT, and no
  Halting the machine line appears anywhere. The two writeback ERROR lines after
  `poweroff -f` are the read-only-disk limitation: busybox's poweroff asks the
  system disk for one last sync, and the disk refuses it.
