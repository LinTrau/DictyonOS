# dictyonos

[**English**](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="assets/logo.png" alt="" width="200">
</p>

这是一个能启动的 QEMU 虚拟机，把三个上游项目拼在一起：

| 层 | 上游 | 作用 |
| --- | --- | --- |
| 内核 | [Asterinas](https://github.com/asterinas/asterinas) | Safe-Rust 框架内核，兼容 Linux ABI |
| init 与用户空间 | [sixos](https://codeberg.org/amjoseph/sixos) + [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | 用 `s6` / `s6-rc` 代替 systemd，用 infuse 组合子代替 NixOS 模块系统 |
| 包管理器 | [Lix](https://lix.systems/) | 系统默认的 `nix` |

`nix run` 会把上面这些从源码构建出来并启动。你会拿到串口控制台上的 root shell、
作为 PID 1 的 `s6-svscan`，以及监听 22 端口的 dropbear。虚拟机里的 `nix` 就是 Lix，
而且 `/nix/store` 可写：可以构建，可以往里加 store path，重启之后它们还在。

三个上游仓库都没有被改动。这个仓库只是胶水：一些 Nix 表达式、一个早期启动的 shell
脚本、一个启动脚本。

## 为什么是这套组合

**这是一个概念验证，不是发行版。** 它只想回答一个很窄的问题：三个各自独立演化的项目，
能不能在不 fork 任何一个的前提下拼成一台能启动的系统？目前的答案是「在 QEMU 里可以」。
这里没有安装器、没有升级路径、没有安全响应流程，也不声称可以上生产。少数代码只是因为
上游还没长出对应功能才存在，每一处都在原地写了注释；下面的「踩过的上游坑」实际上就是
给这些上游的待办清单。

让这个实验保持在可控范围内的办法，是把胶水做薄：Asterinas、sixos、infuse.nix、Lix 都按
固定 revision 使用，一处也不打补丁。那为什么是这三个？不是因为它们各自有趣，而是因为
它们能互相补位。

### 可信基足够小，关键位置有内存安全

传统 Linux 系统把大量代码放进了危险位置：几千万行的 C 内核，再加上 `systemd`、`udev`、
原始 `nix-daemon` 这类特权守护进程。这里的内核是 Asterinas 的 framekernel，它把 `unsafe`
限制在一小块 OSTD 里，于是驱动和内核服务都用 Safe Rust 写；内核之上，`s6-svscan` 只用
`fork`/`exec`、管道和信号来管进程，`s6-rc` 读的是构建期编译好的数据库，运行时不解析配置、
也不跟谁走总线。

说「内存安全的发行版」就过头了：busybox、`s6`、dropbear、Lix 都不是内存安全的，而且以
root 运行。准确一点的说法是：最庞大的那个特权组件，也就是内核，恰好是内存安全的。给个
量级：内核体积 19.9 MB，Nix closure 就是它自己；用户空间 closure 985.3 MB，装进 596 MiB
的镜像。

### 从包到服务只有一套心智模型

NixOS 身上有一道缝。包是普通函数，`callPackage`、overlay、`overrideAttrs` 都在这一侧；
服务却在另一侧，走一套自己的求值模型，最后变成状态机各异的 systemd unit。一套系统里
两套心智模型，代价是每次 rebuild 都要算的那棵全局选项树。

sixos 把这道缝去掉了：服务*就是*一个 derivation，target*就是*一个 bundle，两者都用普通
Nix 加 `infuse.nix` 组合子拼起来，整张图在构建期编译成 `s6-rc` 数据库。这个仓库的
`default.nix` 不到五百行，机器上跑的所有服务、包括它们之间的顺序，全在里面，没有模块系统，
也没有 `config`/`mkIf` 那层绕。项目做到这个体量，整个系统放在一个文件里还端得住，而且
构建要么产出一张自洽的图，要么直接失败。

### 年轻内核和它的用户空间之间阻抗很低

systemd 的问题不只是大，它和 Linux 特有的行为缠在一起：cgroup 层级、mount 传播、netlink
和 udev 事件、一长串系统调用和伪文件系统。要把这些补到能让 systemd 跑起来，对一个 Linux
ABI 还在生长中的内核来说是沉重的负担，而这恰恰是 Asterinas 本来就得背的负担。

`s6` 要的东西很少：`fork`、`exec`、信号、管道、文件描述符。它的监督树自上而下都由正交的
POSIX 原语搭成。契合程度还不错：在一个没有 `rseq`、没有 netlink、没有 ACPI（关机是靠写
QEMU 的 `isa-debug-exit` 端口实现的）、`kexec` 也用不了的内核上，这里的服务集在虚拟机
时间里大约一秒内就全部起来了。Asterinas 确实有
缺口，但缺口很浅、也能数得清，比如它绑不了 IPv4 通配地址（坑 8），这比一个走到启动中途
就卡住的服务管理器要好得多。

### 作为 microVM 与机密计算的基底是说得通的

这个方向上的东西这里一样都没实现，所以请把它当作「为什么值得关心这套栈的形状」的理由，
而不是功能。一个 `unsafe` 面小到可以审计、将来也许可以形式化验证的内核，正是机密计算
客户机（Intel TDX、AMD SEV-SNP）该有的可信基，因为客户机内核本身也是被度量和证明的一部分。
一棵由 `fork`/`exec` 和信号搭起来、没有守护进程总线、也没有解释型配置的监督树，给的正是
serverless microVM 被评判时看的那个短而确定的冷启动。而内容寻址的 closure，就是一台
不可变节点说明自己正在跑什么的方式。把这些和只读系统镜像、一小块可写状态盘放在一起，
一台用完即弃、可度量的客户机的形状已经能看见了。

## 启动流程

```
QEMU  -kernel + -initrd + -drive(readonly vda) + -drive(rw vdb)     直接内核启动：不用 GRUB，不用 kexec
  |
  v
Asterinas 内核
  |  解开 initramfs.cpio.gz，以 PID 1 运行 /init
  v
[dictyonos-init]                                 initramfs.nix + stage1-init.sh
  |  mount proc / sys / devtmpfs，链接 /dev/ptmx
  |  mount -t ext2 -o ro /dev/vda -> /sysroot    系统镜像：configuration + store
  |  mount -t ext2 -o rw /dev/vdb -> /var        可写状态盘
  |  bind /var/nix-var 到 /nix/var               nextboot/prevboot 就住在这里
  |  overlay /nix/store：lower = vda，upper = /var/nix-store-upper
  |  选一个 configuration：先看 prevboot（若 dictyonos.rollback=1），
  |                       再看 nextboot，最后才是 /proc/cmdline 的 configuration=
  |  mount --move /proc /sys /dev 进 /sysroot
  |  switch_root /sysroot <选中的>/boot/init
  v
s6-linux-init                                    挂载 tmpfs /run，解开自己的 cpio，
  |                                              把内核环境导出到 /run/boot
  v
s6-svscan                                        长期存活的 PID 1
  |  rc.init -> <configuration>/bin/activate -> s6-rc-init + s6-rc change default
  v
s6-rc 服务：set-hostname、mounts.{proc,sys,dev.pts,dev.shm,tmp,""}、net-dhcp、
            state-sync、lix-daemon(+log)、ssh(+log)
  + ttyS0 上的 s6-linux-init-early-getty          交互式 root shell
```

### 为什么不用 ownerboot / kexec？

sixos 平时通过 `ownerboot` 启动，用 `kexec` 把新系统交给内核。Asterinas 没实现 `kexec`，
这条路走不通。这里的做法是把 sixos 的 *configuration closure*（也就是 `mkConfiguration`
产出、平时喂给 kexec 的那个 derivation）直接当作根文件系统，用 QEMU 的直接内核启动来
引导。sixos 本身没有动：它自己的 `boot/kernel-params` 文件本来就提供 `configuration=`
参数，`rc.init` 认识它。

## 目录结构

```
flake.nix                      inputs、packages、apps
default.nix                    sixos site + Lix 系统 profile + 内核/initramfs 接线
kernel.nix                     Asterinas 内核，做成纯 derivation
vendor.nix                     cargo vendor 这个 FOD，以及离线的 .cargo/config.toml
initramfs.nix                  构建 stage-1 cpio.gz（静态 busybox + /init）
stage1-init.sh                 stage-1 的 /init 本体
rootfs.nix                     产出 rootfs.ext2 的纯 derivation
scripts/run-vm.sh              在 QEMU 里启动产物
scripts/dictyonos-switch       记录下一次启动用哪一份 configuration
scripts/merge-cargo-locks.py   合并构建需要的三个 Cargo.lock
scripts/vendor-git-deps.py     把 asterinas 的 git 依赖改写成 path 依赖
```

## 快速开始

```sh
git clone https://github.com/LinTrau/dictyonos
cd dictyonos
nix run                       # 构建内核 + initramfs + rootfs，然后启动 QEMU
```

安装、升级、回滚和救援的完整说明见 [docs/INSTALL.md](docs/INSTALL.md)。

没有缓存时，第一次构建会编译 Asterinas 内核、从源码构建 Lix（坑 13），再打包出 596 MiB
的 ext2 镜像，全都发生在 Nix sandbox 里，给它几分钟。CI 会把这些产物推到
[`dictyonos.cachix.org`](https://dictyonos.cachix.org)，flake 在 `nixConfig` 里声明了它，
所以信任 flake 配置的机器直接 substitute：

```sh
nix run --accept-flake-config
```

不在 `accept-flake-config` 打开时 Nix 会忽略 flake 的 `nixConfig`（会有提示），所以缓存
是「你同意才用」，而不是 flake 能强塞给你。多用户安装且你不是 trusted user 时，Nix 还不肯
从 flake 里接收签名公钥，那就用 root 把
`dictyonos.cachix.org-1:IRpGeZZJpVtQ7uPSCYKHbhz012v62JVyFwFH5ZSbSh8=` 加进
`/etc/nix/nix.conf` 的 `trusted-public-keys`。

之后：

```sh
ssh -i .dictyonos-vm/id_ed25519 -p 2222 root@127.0.0.1    # 密钥由启动脚本生成
```

虚拟机里的 store 可写，所以可以直接在里面构建：

```sh
nix build --no-link --print-out-paths --expr 'derivation { name = "hi";
  system = "x86_64-linux"; builder = "/bin/sh"; args = [ "-c" "echo hi > $out" ]; }'
```

### Flake 输出（`x86_64-linux`）

| 输出 | 内容 |
| --- | --- |
| `packages.default` / `packages.rootfs` | ext2 根文件系统镜像 |
| `packages.kernel` | Asterinas 内核 ELF（`asterinas-osdk-bin.elf`） |
| `packages.system` | sixos 顶层 configuration derivation |
| `packages.initramfs` | stage-1 `initramfs.cpio.gz` |
| `apps.default` | 一次性 QEMU 启动脚本 |
| `devShells.kernel` | Asterinas 工具链（Rust nightly + OSDK 前置依赖） |

### 运行虚拟机

```sh
nix run                                  # 交互式串口控制台
AUTO=1 nix run                           # 跑验收：启动两次，然后退出
AUTO=1 BOOT2=0 nix run                   # 只跑两次启动里的第一次
EPHEMERAL=1 nix run                      # 先把状态盘丢掉
NET=0 nix run                            # 不带网卡启动（也没有 ssh）
SSH_PORT=2200 nix run                    # 转发到别的宿主端口
TIMEOUT=300 nix run                      # N 秒后放弃
MEM=16G SMP=4 nix run                    # 给更多资源
```

常用的环境变量：`DICTYONOS_KERNEL_ELF`、`DICTYONOS_ROOTFS`、`DICTYONOS_INITRAMFS`、
`DICTYONOS_CONFIG`、`DICTYONOS_STATE`、`DICTYONOS_WORKDIR`、`CMDLINE`、`NET`、`MEM`、
`SMP`、`CPU`、`TIMEOUT`、`QEMU_BIN`、`ENABLE_KVM`、`AUTO`、`AUTO_WAIT`、`BOOT2`、
`STEP_WAIT`、`HALT_WAIT`、`SERIAL_LOG`、`SERIAL_LOG_BOOT2`、`SERIAL_LOG_HOST`、`SSH_KEY`、
`SSH_PORT`、`SSH_WAIT`。

调试时 `CMDLINE` 很好用：往里追加 `loglevel=info` 就能恢复 Asterinas 的逐系统调用日志。

### 两块盘

`/dev/vda` 是系统镜像，以 `readonly=on` 挂上。它是内容寻址、可以共享的产物，理想情况下
谁都不该往里写。但有一个目录绕不开：`/nix/store` 是 Lix 存放一切构建和下载结果的地方，
一个不能写的 store 会让虚拟机退化成只读电器。所以 stage1 在那里挂了一层 overlayfs：
`/dev/vda` 里的 store 是下层，`/var/nix-store-upper`（位于下面说的状态盘上）是上层。
虚拟机里的 `nix store add-file` 和 `nix build` 都落在上层，`/dev/vda` 上的其他东西保持
只读。如果这层挂载失败，stage1 退回只读 bind mount，在控制台上说一声，然后照常启动。

`/dev/vdb` 是一块 512 MiB 的 ext2 状态盘，第一次运行时创建在
`${DICTYONOS_WORKDIR:-$PWD/.dictyonos-vm}/state.ext2`，之后重复使用；`EPHEMERAL=1` 会把它
换成一块全新的。stage1 把它接到 `/var` 上，再把 `/var/nix-var` bind 到 `/nix/var`，这样
Lix 的数据库、profile 和守护进程 socket 才有地方住。store 的上层和它共用这块盘，这也是
虚拟机里能构建多少东西的实际上限。`.dictyonos-vm/` 之外什么都不碰。

Asterinas 自己从不回写脏页（坑 11），所以有一个小小的 `state-sync` 服务每 30 秒用 `sync -f`
把 `/var` 落盘。状态盘能重复使用就是靠它：没有它，虚拟机一死盘上的内容就没了。

### 切换代际

镜像里只带一份 configuration，stage1 靠内核命令行上的 `configuration=` 找到它。状态盘
可以另存一个选择：stage1 在退回命令行之前，会先读 `/nix/var/nix/profiles/nextboot`（它
在 `/dev/vdb` 上），所以记在那里的 configuration 决定下一次启动。

`dictyonos-switch` 就是用来记它的，同时把之前选中的那份留作 `prevboot`：

```sh
dictyonos-switch /nix/store/<新的-configuration>
# next boot: /nix/store/<新的-configuration>
# go back : boot with dictyonos.rollback=1 (/nix/store/<之前那份>)
```

在内核命令行上加 `dictyonos.rollback=1` 启动，就会改从 `prevboot` 起。实际做法是把
整条命令行交给启动器，因为命令行是启动器写进去的：

```sh
CONFIG="$(nix build --no-link --print-out-paths .#system)"
CMDLINE="$(cat "$CONFIG/boot/kernel-params") dictyonos.rollback=1" nix run
```

只有当路径确实存在于 `/nix/store` 下时，候选才会被采用；别的镜像留下的 profile 会被
跳过、退回命令行，而不是把启动卡死。切换不是热切换：现在什么都不会重启，虚拟机会一直
跑着它启动时的那一代，直到下次重启。

### 不用 flakes

`default.nix` 和 `rootfs.nix` 的每一个来源都是显式参数，所以 `nix-build` 也能用。实际上
flake 才是被支持的入口。

## 内核推导式

`cargo osdk build` 平时是要联网的：它在构建期解析 crates.io 和 `git` 依赖。
`packages.kernel`（`kernel.nix`）把整套东西变成纯 derivation，所以一份全新的 checkout
真的只需要一次 `nix build`：

* **所有依赖都提前 vendor 好。** Asterinas 用 `-Zbuild-std` 构建，所以有三个 lock 文件
  要管：Asterinas 树里的 `Cargo.lock`、`osdk/Cargo.lock`，以及 rust-src 自带的
  `library/Cargo.lock`。`scripts/merge-cargo-locks.py` 把它们合成一个 lock 文件，
  `rustPlatform.fetchCargoVendor` 再把它变成固定输出 derivation（`vendor.nix`），离线用的
  `.cargo/config.toml` 也一并生成。
* **Asterinas 自己的 git 依赖改成了 path 依赖。** `scripts/vendor-git-deps.py` 把指向
  `asterinas` 组织下 crate 的 `git = ...` 条目改写为 vendor 树里的 `path = ...`：cargo 在
  没有 lock 文件时拒绝解析被替换过的 git source，而 `cargo-osdk` 每次构建都会重新生成它的
  基础 crate（全新的 workspace，没有 lock）。也正是这些 crate 带来了一句 `sed`：cargo 只对
  非 path 依赖传 `--cap-lints=allow`，所以 `smoltcp` 里那句
  `#![deny(missing_docs)]` 只能手工放宽。
* **构建跑在 Asterinas 自己的包集里**，并且应用了它的 overlay：配套的 Rust nightly、以及
  内核要嵌入的预编译 Linux vDSO（`VDSO_LIBRARY_DIR`）都从那里来。构建时打开了
  `OSDK_LOCAL_DEV=1`，这样 `cargo-osdk` 在同一棵树里构建并使用，吐出的路径对这个构建
  仍然有效。

**只要改了任何一个 lock 文件，就必须重新固定 vendor hash。** 固定输出 derivation 的
store path 只由 hash 和名字决定，所以 `vendor.nix` 里过期的 `vendorHash` 会静默复用旧的
vendor 树。重新取值的方法：把 hash 改成 `sha256-AAAA...` 然后构建，从报错里的 `got:`
抄回真值。

### 隐私：脱敏过的构建元数据

Asterinas 会把编译时的用户名和主机名写进 `/proc/version`。`cargo-osdk` 为它拉起的 `cargo`
子进程用 `whoami` 设置 `OSDK_BUILD_USERNAME` / `OSDK_BUILD_HOSTNAME`，所以不改上游的唯一
办法是放一个更早出现在 `PATH` 上的 `cargo` shim。`kernel.nix` 就装了这么一个，产物永远
是这样的：

```
Linux version 5.13.0 (dictyonos@builder) (rustc ...) #1 SMP ...
```

如果编译用户或主机名漏了出来，构建会直接失败。这个 shim 还把工具链和 vendor 的 store path
从 ELF 的调试信息里重映射出去：不然 Nix 的引用扫描器会顺着它们把 4 GiB 的 closure 拖进
镜像，而不是 20 MB。

## 关键配置取舍

* **Nix sandbox 是关的。** Asterinas 没实现严格 sandbox 需要的那整套 namespace，也还没有
  页缓存压力回收，所以生成的 `/etc/nix/nix.conf` 里是 `sandbox = false`。Lix 仍然想给每个
  构建套一层 seccomp 过滤器，这是 Asterinas 给不了的，所以镜像里的 Lix 是用
  `-Dseccomp-sandboxing=disabled` 构建的（坑 13）。
* **没有 `mdevd` / `udev`。** Asterinas 提供 `devtmpfs`，`/dev` 由内核填充，没有任何东西
  在等 netlink 热插拔事件。
* **`mounts.proc`、`mounts.sys` 和 `mounts.""` 是空 bundle。** initramfs 已经把活的 `/proc`
  和 `/sys` 挪进了新根，再挂一次会 `EBUSY`；`/` 也不能重新挂成可写，因为系统盘本来就是
  故意只读的。这几个 bundle 存在只是为了让别的 target 的 after 引用能解析。
* **首次启动那条 activation 分支被提前满足了。** `rootfs.nix` 预先建好 activation 会建的
  那些 `/etc`、`/bin/sh`、`/usr/bin/env` 链接，目标字符串和它 `readlink` 比较时测的完全
  一致，于是在只读根上整趟 linkify 都被跳过。为什么这件事这么要紧，见坑 1。
* **没有 getty target。** `s6-linux-init-maker -G`（由 sixos 从 `boot.kernel.console` 推出）
  已经在 `ttyS0` 上监督一个 getty 了。第二个拿不到控制终端，会以
  `TIOCSCTTY: Operation not permitted` 失败。
* **`net-dhcp` 尽力而为。** 它把所有非 `lo` 接口拉起来，在超时限制下跑 `udhcpc`，但每一步
  都有保护，而且永远退出 0，所以网卡缺失或不受支持都不会卡住启动。它还往
  `/etc/resolv.conf`（指向 tmpfs 上的 `/run` 的符号链接，因为 `/etc` 本身只读）里写入
  QEMU 用户态网络用的解析器地址。
* **`ssh` 只认公钥。** 启动脚本生成一次性的密钥对，把公钥那一半放进内核命令行，服务把它
  写进状态盘上的 `/root/.ssh/authorized_keys`。dropbear 带 `-s` 运行，所以密码登录从结构上
  就是关的；它绑定自己发现的接口地址（坑 8），而不是通配地址。
* **`has-hwclock` 是开的。** Asterinas 没有 RTC，这个标签字面上不成立，但它让 sixos 装
  真正的 `hwclock` oneshot（脚本结尾是 `|| true`），而不是那套*文件驱动*的假 hwclock——
  后者会把状态 `redirfd` 到 `/etc`，在只读根上只能反复挂掉重来。

## 踩过的上游坑

1. **sixos 的 `activate` 会静默中断，然后什么都不工作。** 它在 `set -e` 下运行，而
   `linkify` 阶段往 `$RWMOUNT/<path>` 写，`$RWMOUNT` *只*由首次启动分支设置，于是在只读根上
   任何一个 `ln -sfT` 失败都会在 `s6-rc-init` 跑之前干掉 activation。机器仍然会启动到
   `s6-linux-init` 的*early getty*，看起来就像一台串口控制台正常但什么都没有的机器。
   activation 碰到的每个链接要么已经存在，要么能解析；`rootfs.nix` 只要自己的链接有一条
   悬空就让构建失败。
2. **Lix 拒绝在不是挂载点的 store 上运行。** 只要 `statvfs` 报 `ST_RDONLY`，
   `LocalStore::makeStoreWritable` 就会发出
   `mount(NULL, /nix/store, none, MS_REMOUNT | MS_BIND, 0)`，而内核在目标不是挂载点根时
   回答 `EINVAL`。走 overlay 时这个问题顺带解决了；只读回退路径保留了旧的自 bind mount。
   `/nix/store/.links` 也必须存在，因为 `LocalStore` 的构造函数无条件创建它，哪怕只是跑
   一句 `nix eval`。
3. **没有激活的 tag 时 sixos 的 `apply-tags` 会把 host 抹掉。**
   `lib.composeManyExtensions []` 求值成 `(_: _: {})`，于是 tag 集为空时 host 只剩
   `tags`/`canonical`/`name`。这个仓库只声明了一个恒真的身份 tag（`dictyonos`）来让 host
   活着；所有真实的上游 tag 都是故意关掉的，因为它们每一个都会拖进 Asterinas 用不了的
   kexec/ownerboot/initrd 机械。
4. **sixos 的 s6-rc 补丁系列只适用于 nixpkgs 24.05。** 拿更新的 nixpkgs 构建 sixos 会在
   `0009-add-OLDSTATE_UNPROPAGATED_RESTART.patch` 上报 `2 out of 7 hunks FAILED`。所以
   `nixpkgs-sixos` 固定在 `nixos-24.05`，Lix 另取一个（`nixos-26.05`）input。
5. **longrun 必须用 `six.mkFunnel`。** `six.mkService { type = "longrun"; ... }` 产出的是
   `up`/`down`，而 `s6-rc-compile` 要的是 `run`；只有 `mkFunnel`/`mkLogger` 会产出它。
6. **Asterinas 不解析 `console=` 上的波特率后缀。** `console=ttyS0,115200n8` 会被拒绝
   （`console not found, falling back to tty0`），于是所有用户空间输出被静默送进一个并不
   存在的 framebuffer。必须写光秃秃的 `console=ttyS0`。
7. **`fs.protected_hardlinks` 会挡掉 store 的硬链接。** 手工用 `cp -al` 拼镜像的人会撞上
   `EPERM`。在 sandbox 里构建（`rootfs.nix` 的做法）则完全绕开这个问题。
8. **Asterinas 绑不了 IPv4 通配地址。** `bind()` 会在本地路由表里解析参数
   （`kernel/core/src/net/route/mod.rs:lookup_local_iface`），对任何不是本地地址的东西
   回答 `EADDRNOTAVAIL`，`0.0.0.0` 和 `::` 都在此列，所以常见的
   `listen(0.0.0.0:22)` 根本不可能工作。光给 dropbear 一个 `-p 22` 更糟：它从 getaddrinfo
   拿到 IPv6 通配地址，在 `IPV6_V6ONLY` 和 `bind(::)` 上失败，然后以「No listening ports
   available」退出，根本不试 IPv4。所以 `ssh` 服务会等网卡拿到可路由地址，再绑定那个
   地址。
9. **dropbear 通过 `/etc/shells` 校验登录 shell。** 文件不存在时 glibc 的 `getusershell(3)`
   回退到 `/bin/sh,/bin/csh`，而 sixos 生成的 `passwd` 里 root 的 shell 是一个 store path，
   于是每次登录都被拒：「User 'root' has invalid shell, rejected」，尽管密钥已经被接受。
   `rootfs.nix` 从 `passwd` 本身生成 `/etc/shells`。
10. **sixos 生成的 `finish.user` 脚本带着 `-Ws4`。** `execlineb -W -s 4` 要求四个位置参数，
    所以每次重启一个反复挂掉的服务，控制台上都会打印
    `execlineb: fatal: too few arguments: expecting at least 4 but got 3`。这是症状不是病因：
    把那个一直挂的服务修好，噪声就停了。
11. **Asterinas 不做后台回写，`sync(2)` 在这里没法用。** 脏页只有在有人对拥有它们的文件
    系统调用 `syncfs()` 时才离开虚拟机。系统级的 `sync` 会对着只读系统盘打印
    `block: failed to do Write on the device with error status: IoError`，而且不一定能触到
    状态盘；`sync` 这个*挂载选项*会被直接丢掉，因为 Asterinas 的 `PerMountFlags` 里没有
    `SYNCHRONOUS` 位。`sync -f /var`（对状态盘做 syncfs）能用并返回 0，`state-sync` 用的
    就是它。
12. **没有任何东西创建 `/dev/ptmx`。** Asterinas 的 devpts 把多路复用主设备留在
    `/dev/pts/ptmx`，并且期望有个符号链接指向它（它自己的源码就是这么写的），所以在
    `/dev/ptmx` 出现之前 `posix_openpt()` 一律回答 `ENOENT`。initramfs 会把这条链接建好，
    否则每次 Lix 构建都会死在
    `opening pseudoterminal master: No such file or directory`。
13. **Lix 2.94 没法在运行时关掉它的 seccomp 过滤器。** `filter-syscalls` 选项在 2.90 被
    移除，而 `setupSyscallFilter()` 会在每个本地构建前无条件运行，于是在一个没有
    `seccomp(2)` 的内核上，虚拟机里的构建会死在 `unable to load seccomp BPF program:
    Function not implemented`。出路是这个库自己的 meson 开关
    `-Dseccomp-sandboxing=disabled`，代价是 Lix 得从源码构建，不能直接 substitution。
    `default.nix` 就是这么做的。
14. **Asterinas 写的 ext2 xattr 会被 `e2fsck` 拒绝。** 虚拟机里构建完之后，用 `debugfs` 检查
    状态盘会报 `Extended attribute in inode 15 has a hash (0) which is invalid`、
    `i_blocks is 8, should be 16` 和 `Block bitmap differences`，全都出在 overlayfs 当作上层
    的那个目录里。虚拟机里没人察觉，文件读回来也正确，而且这块盘本来就是一次性的，但
    不要对你在意的状态盘跑*会修复*的 `e2fsck`。

## 验收

```sh
AUTO=1 nix run
```

会把机器启动**两次**。第一次启动在串口控制台上依次跑这些检查：`uname -a`、
`cat /proc/version`、`readlink /proc/1/exe`、完整的 `ps aux`、sixos 的 activation 有没有
跑到最后、每个 longrun 的 `s6-svstat` 和它们在 `/var/log` 下的日志尾巴、两块盘和网络
配置、`nix --version` 和 `nix eval --expr` 的 `1 + 1`、在状态盘上写一次再 `sync -f` 再读回，
以及一次真实构建和一次 `nix store add-file`，用来证明 `/nix/store` 可写。与此同时宿主机
检查一次真实的 ssh 握手，并通过它跑一条命令。

第二次启动在*同一块*状态盘上开一台新机器，必须还能找到 `/var/persist-early`、
`/var/persist-late` 和两个 store path，内容不变，而且必须给出同一个 dropbear 主机密钥。
宿主这边也会给出自己的证据：在镜像上跑 `e2fsck -fn`，不挂载直接用 `debugfs` 读
（Asterinas 关机前不卸载任何文件系统，所以镜像退出时从未被同步），以及 `ssh-keyscan` 看到的
客户端侧主机密钥，并跨两次启动比较。只有这些都成立，运行才会打印 `REBOOT-PERSISTENCE-OK`。

每次启动都以 `poweroff -f` 收尾，于是机器是自己消失的：内核往 `isa-debug-exit` 端口写
0x10，QEMU 以状态 33 退出，启动脚本把它当作关机成功，而不是一直等到 `TIMEOUT`。

一次运行会产出三份转录：`./serial.log`（第一次启动）、`./serial-boot2.log`（第二次启动）、
`./serial.host.log`（ssh、`e2fsck`、`debugfs`），完整的一次抓取在
[ACCEPTANCE.md](ACCEPTANCE.md)。[.github/workflows/ci.yml](.github/workflows/ci.yml) 在每次
push 和 pull request 上跑同一套验收，然后**在同一块状态盘上再启动一次**（`ROLLBACK=1`，
必须从 `prevboot` 起来，转录是 `./serial-rollback.log`），并且无论成败都上传这四份转录。

发版还多一道：`./scripts/smoke-bundle.sh` 把要附在 release 上的压缩包解开、直接启动
包里的那份产物，等 ssh 通了在客机里跑一条命令，再要求机器自己关机；
[.github/workflows/release.yml](.github/workflows/release.yml) 在发布之前跑它，起不来的
bundle 不会挂到 tag 上。

## 已知限制

* 虚拟机确实能构建，但它自己没有工具链：需要编译器的构建得先从二进制缓存拉一个，而且
  store 的上层和 `/var` 挤在同一块 512 MiB 状态盘上。
* `uname -a` 报的是 `Linux 5.13.0`，这是故意的，Asterinas 对外声称 Linux ABI。想看真话
  看 `/proc/version`：它写的是 Rust 编译器，不是 C 编译器。
* 系统调用 334（`rseq`）没有实现，每个进程启动时记一条日志；glibc 能正确处理 `ENOSYS`。
* **不能绑 INET 通配地址**（坑 8）：想要「所有接口」的服务只能自己把实际拥有的地址列出来。
* **状态盘的持久化以 30 秒为周期。** Asterinas 不做后台回写（坑 11），所以 `/var` 是由
  `state-sync` 服务而不是内核提交的：虚拟机死之前最后半分钟写进去的东西会丢，包括你刚
  构建出来的 store path。
* **会修复的 `e2fsck` 会弄坏状态盘**（坑 14）。验收只跑 `e2fsck -fn`。
* **回滚是手动的。** `dictyonos.rollback=1` 只把 `prevboot` 顶到前面启动一次，没有任何
  东西会自己发现新一代没起来，也不会让这个选择固定下来。一代如果在 s6 起来之前就坏了，
  仍然得有人手动加上 `dictyonos.rollback=1`。

## 许可与上游致谢

这个仓库里的胶水层，包括 `flake.nix`、`default.nix`、`kernel.nix`、`vendor.nix`、
`initramfs.nix`、`rootfs.nix`、`stage1-init.sh` 和 `scripts/`，采用 **Mozilla Public License
2.0**（`LICENSE`），与 Asterinas 一致。

它使用但不修改、也不重新分发以下上游项目。它们的许可适用于它们自己，而不是这个仓库：

| 上游 | 许可 | 说明 |
| --- | --- | --- |
| [Asterinas](https://github.com/asterinas/asterinas) | MPL-2.0 | 内核；通过 `asterinas` input 按 revision 引用，由 `kernel.nix` 本地构建 |
| [sixos](https://codeberg.org/amjoseph/sixos) | GPL-3.0-only（见其 `COPYING.GPL3-ONLY`） | 基于 s6 的服务层 |
| [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | GPL-3.0（按其仓库） | sixos 赖以构建的属性集组合子 |
| [Lix](https://lix.systems/) | LGPL-2.1 | 包管理器；从源码构建，不带 seccomp 支持（坑 13） |
| [dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html) | MIT | ssh 服务端 |
| [nixpkgs](https://github.com/NixOS/nixpkgs) | MIT | 包定义 |
| [skarnet s6 / s6-rc / s6-linux-init](https://skarnet.org/software/) | ISC | 进程监督，经 sixos 引入 |

因为 sixos 和 infuse.nix 是以各自 revision 作为构建输入拉取的，任何重新分发*构建产物*
（dictyonos 镜像）的人都在分发 GPL-3.0 二进制，必须遵守相应条款。
