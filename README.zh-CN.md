# dictyonos

[English](README.md) | **简体中文**

把三个彼此独立的上游项目缝合成一台可启动的 QEMU 虚拟机:

| 层 | 上游 | 作用 |
| --- | --- | --- |
| 内核 | [Asterinas](https://github.com/asterinas/asterinas) | Safe-Rust 框内核(framekernel),兼容 Linux ABI |
| init + 用户态 | [sixos](https://codeberg.org/amjoseph/sixos) + [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | 用 `s6` / `s6-rc` 取代 systemd;用 infuse 组合子取代 NixOS 模块系统 |
| 包管理器 | [Lix](https://lix.systems/) | 作为系统默认的 `nix` |

启动后进入串口 root shell:PID 1 是 `s6-svscan`,`PATH` 上有 Lix,22 端口上跑着 dropbear。
三个上游源码一行都没有改:本仓库只是一层胶水(Nix 表达式、一个早期引导 shell 脚本、一个启动器脚本)。

包括 Asterinas 内核在内的一切都由 `nix build` 从源码构建:`git clone` 之后一条 `nix run` 就是全部流程,
仓库里既没有预编译产物,也没有任何"先手动编内核"的步骤。

## 现状与设计取舍(为什么是这套组合?)

**现状。** `dictyonos` 是一个实验性的个人兴趣项目,也是一次架构概念验证,不是发行版。
它想回答的问题很窄——能不能在不改任何上游源码的前提下,把三个各自独立演进的项目缝合成一个能启动的系统?
诚实地说答案是"到目前为止可以,在 QEMU 里"。这里没有安装器、没有升级路径、没有安全响应流程,也不声称可用于生产。
树里还有一些脚手架,纯粹是因为某个上游还没长出对应能力;每一处都用注释写清了迫使它存在的限制,
下面《踩过的上游坑》一节本质上就是给上游的待办清单。这些脚手架应当随着上游演进而逐步拆除。

让这个实验保持在可控范围内的一条约束是:本仓库始终是**极薄、零侵入**的胶水层。
Asterinas、sixos、infuse.nix 和 Lix 都按固定 revision 消费、一处补丁都不打;
这里住着的只有 Nix 表达式、一个早期引导脚本和一个启动器脚本。
其中确实有承重的部分而非纯粹的临时物——内核是建立在 vendored cargo registry 之上的纯 Nix 推导,
stage1 则绕开了两处我们踩出来的 Asterinas 缺口——但这些都不需要动上游一行代码。

那为什么偏偏是这三者?把有意思的项目排在一起并不难,真正的问题是它们能否互相增益。有四个理由:

### 更小的可信计算基,内存安全落在真正要紧的地方

传统 Linux 系统把海量代码放进了危险的权限位置:数千万行 C 内核,外加用 C 和 C++ 写的特权守护进程
——作为 PID 1 的 `systemd`、`udev`、原版 `nix-daemon`。这里的内核是 Asterinas 的框内核,
它把所有 `unsafe` 块收敛在很小的 OSTD 框内,驱动与内核服务因此能用 Safe Rust 写;
而其上的用户态则被刻意按相反的取向挑选:`s6-svscan` 只用 `fork`/`exec`、管道和信号来监管整台机器,
`s6-rc` 读取的是构建期编译好的静态数据库,所以运行期没有任何东西需要解析配置或与总线对话。

这里需要说得精确一点,因为"内存安全的发行版"会是一句过度宣称:busybox、`s6` 本身、dropbear 以及 Lix(C++ 实现,
正在逐步引入 Rust)都不是内存安全的,而且都以 root 运行。更窄、也更有用的说法是:**庞大的**那块特权组件——内核——
是内存安全的那一个,而它之上的每一件东西都被刻意做小到可以审计。本仓库的实测数字:内核负载 19.9 MB,
其 Nix closure 恰好等于它自身(零外部引用);用户态 closure 是 1011.8 MB 的 store 路径,打包进 639 MiB 的镜像。

### 从软件包到系统服务,只有一套心智模型

NixOS 里有一道众所周知的缝:软件包是函数——`callPackage`、overlay、`overrideAttrs`;
而系统服务却住在完全另一个世界:NixOS module 系统有自己的一套求值模型,再喂给拥有自身状态机的 `systemd`。
两套心智模型、一个系统,以及一棵全局 option 树,它的求值代价会在每次 rebuild 时显现。

sixos 把这缝抹掉了。在这里,**一个服务就是一个推导式**,**一个 target 就是一个 bundle**;
两者都用普通的 Nix 函数和 `infuse.nix` 组合子拼装,整张图在构建期被编译成 `s6-rc` 数据库。
本仓库的 `default.nix` 不到五百行,却定义了机器上运行的**每一个**服务——包括它们之间的顺序约束——
没有模块系统、没有 `config`/`mkIf` 的层层间接、没有全局 option 树。
正因如此,这么小的项目才敢声称自己能被整体推敲:`nix build .#system` 要么产出一张自洽的服务图,要么直接失败。

### 内核与用户态之间的阻抗更低

`systemd` 的问题不只是大,而是它和 Linux 特有行为深度纠缠——cgroup 层级、挂载传播语义、netlink 与 `udev` 事件,
以及长尾的系统调用和伪文件系统。对一个还在补齐 Linux ABI 的内核来说,复现到足以取悦它的程度是沉重负担,
而这恰恰是 Asterinas 否则必须背上的负担。

`s6` 要的东西少得多:`fork`、`exec`、信号、管道、文件描述符。它的监管树自始至终都是正交的 POSIX 原语,
`s6-rc` 读的是编译好的数据库而不是解释它。契合度好到什么程度?在这台**没有实现 `rseq`、没有 netlink、
没有 ACPI poweroff、`kexec` 也跑不通**的内核上,服务集在约一秒 guest 时间内就全部拉起。
Asterinas 确有缺口时,那些缺口既浅又可枚举——比如它不能绑定 IPv4 通配地址(见第 8 条坑)——
这比"服务管理器在启动中途挂住"要好得多的失效方式。

### 面向微虚机与机密计算的合理底座

这部分本仓库并未实现,而且值得直说:下面讲的是**这套形态为何值得关注**,而不是本仓库的功能。
但有三个性质正指向那个方向。其一,`unsafe` 面积小到可审计(将来也可能可验证)的内核,
正是机密计算 guest(Intel TDX、AMD SEV-SNP)所需要的可信计算基——那里 guest 内核本身就在被度量和证明的范围里。
其二,一棵由 `fork`/`exec` 和信号构成、没有守护进程总线、也没有解释型配置的监管树,带来的是短而确定的冷启动,
而这正是 serverless 微虚机真正被考核的指标。其三,Lix 的内容寻址、可复现闭包,恰好是不可变节点或需要自证
"我在跑什么"的 attested guest 所要的东西。把这三样和只读系统镜像 + 一小块可写状态盘(本仓库就是这么做的)放在一起,
一台一次性、可度量的 guest 的轮廓已经能看见了。这三个项目能否一起长到那一步,正是本实验在探的问题。

## 启动流程

``````````
QEMU  -kernel + -initrd + -drive(vda 只读) + -drive(vdb 可写)     直接内核启动:无 GRUB、无 kexec
  |
  v
Asterinas 内核
  |  解包 initramfs.cpio.gz,以 /init 作为 PID 1 运行
  v
[dictyonos-init]                                  initramfs.nix + stage1-init.sh
  |  挂载 proc / sys / devtmpfs
  |  mount -t ext2 -o ro /dev/vda -> /sysroot     承载 /nix/store 与 configuration
  |  从 /proc/cmdline 读取 configuration=<store-path>
  |  mount -t ext2 -o rw /dev/vdb -> /var         可写状态盘
  |  把 /var/nix-var bind 到 /nix/var,并给 /nix/store 做自 bind
  |  mount --move 把 /proc /sys /dev 移入新根
  |  switch_root /sysroot <configuration>/boot/init
  v
s6-linux-init                                    挂载 tmpfs /run、解包自己的 cpio,
  |                                              把内核环境(含 configuration=、init=)
  |                                              倒入 /run/boot
  v
s6-svscan                                        长期存活的 PID 1
  |  rc.init -> <configuration>/bin/activate -> s6-rc-init + s6-rc change default
  v
s6-rc 服务:set-hostname、mounts.{proc,sys,dev.pts,dev.shm,tmp,""}、net-dhcp、
            lix-daemon(+log)、state-sync(+log)、ssh(+log)
  + ttyS0 上的 s6-linux-init-early-getty          交互式 root shell
``````````

### 为什么不用 ownerboot / kexec?

sixos 通常经由 `ownerboot` 启动,由它用 `kexec` 把新系统交给内核。Asterinas 没有实现 `kexec`,所以那条路走不通。
这里改为把 sixos 的**配置闭包**(也就是 `mkConfiguration` 产出的、平时喂给 kexec 的那个推导)当作根文件系统,
用 QEMU 直接内核启动。sixos 本身没被改动:它自己的 `boot/kernel-params` 已经提供了 `rc.init` 认识的那个
`configuration=` 参数。

## 目录结构

``````````
flake.nix                      inputs、packages、apps
default.nix                    sixos site + Lix 系统 profile + 内核/initramfs 接线
kernel.nix                     Asterinas 内核,写成纯推导式
vendor.nix                     cargo vendor 这个 FOD + 离线 .cargo/config.toml
initramfs.nix                  构建 stage-1 的 cpio.gz(静态 busybox + /init)
stage1-init.sh                 stage-1 的 /init 本体
rootfs.nix                     产出 rootfs.ext2 的纯推导式
scripts/run-vm.sh              在 QEMU 里把结果跑起来
scripts/merge-cargo-locks.py   合并构建需要的三份 Cargo.lock
scripts/vendor-git-deps.py     把 asterinas 的 git 依赖改写成 path 依赖
``````````

## 快速开始

``````````sh
git clone https://github.com/LinTrau/dictyonos
cd dictyonos
nix run                       # 构建内核 + initramfs + rootfs,然后启动 QEMU
``````````

首次运行会在 Nix sandbox 里构建 Asterinas 内核和约 640 MiB 的 ext2 镜像,耐心等几分钟。之后:

``````````sh
ssh -p 2222 root@127.0.0.1    # 启动器会生成一次性密钥并注入 guest
``````````

### Flake 输出(`x86_64-linux`)

| 输出 | 内容 |
| --- | --- |
| `packages.default` / `packages.rootfs` | ext2 根文件系统镜像 |
| `packages.kernel` | Asterinas 内核 ELF(`asterinas-osdk-bin.elf`) |
| `packages.system` | sixos 顶层配置推导式 |
| `packages.initramfs` | stage-1 的 `initramfs.cpio.gz` |
| `apps.default` | 一次性 QEMU 启动器 |
| `devShells.kernel` | Asterinas 工具链(Rust nightly + OSDK 前置) |

### 运行虚拟机

``````````sh
nix run                                  # 交互式串口控制台
AUTO=1 nix run                           # 验收:启动两次,然后退出
AUTO=1 BOOT2=0 nix run                   # 只跑两次启动中的第一次
EPHEMERAL=1 nix run                      # 先丢弃状态盘,从空白开始
NET=0 nix run                            # 不带网卡启动(也就没有 ssh)
SSH_PORT=2200 nix run                    # 换一个宿主端口转发
TIMEOUT=300 nix run                      # N 秒后放弃
MEM=16G SMP=4 nix run                    # 更多资源
``````````

常用环境变量:`DICTYONOS_KERNEL_ELF`、`DICTYONOS_ROOTFS`、`DICTYONOS_INITRAMFS`、`DICTYONOS_CONFIG`、
`DICTYONOS_STATE`、`DICTYONOS_WORKDIR`、`CMDLINE`、`NET`、`MEM`、`SMP`、`CPU`、`TIMEOUT`、`QEMU_BIN`、
`ENABLE_KVM`、`AUTO`、`AUTO_WAIT`、`BOOT2`、`STEP_WAIT`、`HALT_WAIT`、`SERIAL_LOG`、
`SERIAL_LOG_BOOT2`、`SERIAL_LOG_HOST`、`SSH_KEY`、`SSH_PORT`、`SSH_WAIT`。

调试时 `CMDLINE` 很好用:追加 `loglevel=info` 就能恢复 Asterinas 的逐系统调用日志。

### 两块盘

`/dev/vda` 是系统镜像,以 `readonly=on` 挂载。它是内容寻址、可共享的产物,因此任何东西都不会写它:
`/etc`、`/bin` 和 `/nix/store` 全是只读的。

`/dev/vdb` 是 512 MiB 的 ext2 状态盘,首次运行时创建在
`${DICTYONOS_WORKDIR:-$PWD/.dictyonos-vm}/state.ext2`,之后复用。
`EPHEMERAL=1` 会把抹掉重建。stage1 把它嫁接到 `/var`,再把 `/var/nix-var` bind 到 `/nix/var`,
于是 Lix 的数据库、profile 和守护进程 socket 都有地方可写。`.dictyonos-vm/` 之外不留任何痕迹。

Asterinas 从不主动回写脏页(见第 11 条坑),所以有个很小的 `state-sync` 服务每 30 秒用 `sync -f` 提交一次 `/var`。
正是它让状态盘真正可复用;没有它,盘里的内容会在虚机消失时一起蒸发。

### 不用 flakes

`default.nix` 和 `rootfs.nix` 把所有源码都作为显式参数接收,因此用 `nix-build` 也能工作。
实际使用中,flake 才是被支持的入口。

## 内核推导式

`cargo osdk build` 平时需要网络:它在构建期解析 crates.io 和 `git` 依赖。`packages.kernel`(`kernel.nix`)
把整件事变成纯推导式,所以全新的 checkout 真的能靠一条 `nix build` 完成:

* **所有依赖都提前 vendored。** Asterinas 用 `-Zbuild-std` 自举,因此有三份 lock 文件要紧:Asterinas 树里的
  `Cargo.lock`、`osdk/Cargo.lock`,以及 rust-src 自带的 `library/Cargo.lock`。
  `scripts/merge-cargo-locks.py` 把它们合并成一份,交给 `rustPlatform.fetchCargoVendor` 变成固定输出推导式
  (`vendor.nix`),连离线的 `.cargo/config.toml` 一并生成。
* **Asterinas 自己的 git 依赖被改写成 path 依赖。** `scripts/vendor-git-deps.py` 把指向 `asterinas` 自托管
  crate 的 `git = ...` 条目改写成 vendor 树内的 `path = ...`:cargo 拒绝在没有 lock 文件时解析被替换的 git 源,
  而 `cargo-osdk` 每次构建都会重新生成它的 base crate(一个没有 lock 的全新 workspace)。同样因为这些 crate 是
  路径依赖,cargo 不会给它们传 `--cap-lints=allow`,于是 `smoltcp` 里那句 `#![deny(missing_docs)]` 得手动放宽。
* **构建跑在 Asterinas 自己的包集里**,并叠加它自己的 overlay:这提供了匹配的 Rust nightly,以及内核要嵌入的
  预编译 Linux vDSO(`VDSO_LIBRARY_DIR`)。
* 设置了 `OSDK_LOCAL_DEV=1`,让 `cargo-osdk` 与内核在同一棵树里构建和使用,产出的路径对本次构建仍然有效。

**改动任何 lock 文件后,必须重新固定 vendor hash。** 固定输出推导式的 store path 只由 hash 和名字决定,
所以 `vendor.nix` 里陈旧的 `vendorHash` 会静默复用旧的 vendor 树。重新取值的方法:先把 hash 写成
`sha256-AAAA...`,构建,然后把错误里那行 `got:` 的值抄回来。

### 隐私:脱敏的构建元数据

Asterinas 会把编译时的用户与主机名烧进 `/proc/version`。`cargo-osdk` 为它拉起的 `cargo` 子进程从 `whoami`
设置 `OSDK_BUILD_USERNAME` / `OSDK_BUILD_HOSTNAME`,所以不改上游的唯一办法就是在 `PATH` 更前面放一个 `cargo` shim。
`kernel.nix` 就装了一个,因此结果永远是:

``````````
Linux version 5.13.0 (dictyonos@builder) (rustc ...) #1 SMP ...
``````````

而且一旦真实用户名或主机名泄漏,构建会直接失败。这个 shim 还把工具链与 vendor 的 store 路径从 ELF 的调试信息里
remap 掉:否则 Nix 的引用扫描会顺着它们把 4 GiB 的闭包拖进镜像,而不是 20 MB。

## 关键配置取舍

* **关掉 Nix sandbox。** Asterinas 没有实现严格 sandbox 需要的完整 namespace 集合,也还没有页缓存压力回收,
  所以生成的 `/etc/nix/nix.conf` 里写着 `sandbox = false`。(Lix 2.94 已经彻底移除 `filter-syscalls`,
  这个设置不再存在,因此刻意不写。)
* **没有 `mdevd` / `udev`。** Asterinas 提供 `devtmpfs`,`/dev` 由内核填充。默认的 sixos target 集合被换成
  一个精简集合;没有任何东西在等 netlink 热插拔事件。
* **`mounts.proc`、`mounts.sys` 与 `mounts.""` 都是空 bundle。** initramfs 已经把活的 `/proc`、`/sys` 移进了新根,
  再挂一次会 `EBUSY`;`/` 也不能被重新挂成可写,因为系统盘就是刻意只读的。这些 bundle 存在只是为了让其他 target
  的 after 引用仍然能解析。
* **首启激活分支被预先规避。** sixos 的首启分支会把 `/` 重新 bind 成可写并调用 `chattr +i`,而只读 QEMU 盘上的
  只读 ext2 做不到。`rootfs.nix` 预先建好了 activate 本来会建的那批 `/etc`、`/bin/sh`、`/usr/bin/env` 链接,
  并且使用它 `readlink` 比较时用的**字面目标**——于是整轮 linkify 会被整体跳过(原因见第 1 条坑,这非常关键)。
* **没有 getty target。** `s6-linux-init-maker -G`(由 sixos 从 `boot.kernel.console` 推出)已经在 `ttyS0` 上
  监管了一个 getty。第二个 getty 抢不到控制终端,只会以 `TIOCSCTTY: Operation not permitted` 失败。
* **`net-dhcp` 是尽力而为。** 它把每个非 `lo` 网卡拉起来并在超时保护下跑 `udhcpc`,但每一步都有防护、永远退出 0,
  所以网卡缺失或不被支持都不可能卡住启动。它还把 `/etc/resolv.conf`(指向 tmpfs 上的 `/run`,因为 `/etc` 本身只读)
  预先写成 QEMU user-mode 的解析器。
* **`ssh` 只允许公钥。** 启动器生成一次性密钥对,把公钥经内核命令行传入,服务把它写进
  `/root/.ssh/authorized_keys`(落在状态盘上)。dropbear 以 `-s` 运行,密码登录在构造上就是关的;
  它监听的是自己探测到的网卡地址(见第 8 条坑),而不是通配地址。
* **打开 `has-hwclock`。** Asterinas 没有 RTC 驱动,所以这个标签并不字面为真;但它的两个效果在这里都是想要的:
  一是阻止 sixos 安装基于文件的假时钟(`hwclock-fake` + `hwclock-fake-updater`,它们会往只读的 `/etc` 里
  `redirfd` 一个状态文件,于是立刻死掉、被 s6-supervise 大约每秒重启一次);二是改为安装 sixos 真正的 `hwclock`
  oneshot,其脚本以 `|| true` 结尾,既不会失败也不会空转。启动时的时间无论如何都来自内核。

## 踩过的上游坑

1. **sixos 的 `activate` 会静默中止,之后整个系统等于没起来。** 它在 `set -e` 下运行,而它的 linkify 一轮会写
   `$RWMOUNT/<path>`,其中 `$RWMOUNT` **只**由上面那个首启分支设置——所以在只读根上任何一次 `ln -sfT` 失败,
   都会在 `s6-rc-init` 之前就杀掉整个 activate。机器仍然会启动到 `s6-linux-init` 的 *early getty*,
   看起来像个正常的串口控制台,却一个服务都没有:`/run/s6-rc` 不存在、没有 ssh、没有 DHCP,
   而控制台上没有任何错误(输出进了 catch-all logger)。activate 碰过的每一个链接,要么预先存在、要么必须保证解析得了。
   `rootfs.nix` 现在会在自己创建的链接悬空时直接让构建失败。
2. **Lix 拒绝在一个不是挂载点的 store 上运行。** `LocalStore::makeStoreWritable` 在 `statvfs` 报告 `ST_RDONLY` 时
   会发出 `mount(NULL, /nix/store, none, MS_REMOUNT | MS_BIND, 0)`,而只要目标不是某个挂载的根,内核就回 `EINVAL`。
   于是 `stage1-init.sh` 给 `/nix/store` 做了个自 bind;超级块仍是只读的,所以实际上什么也写不进去。
   另外 `/nix/store/.links` 必须存在,因为 `LocalStore` 的构造函数会无条件创建它——哪怕只是跑一次纯 `nix eval`。
3. **没有激活任何 tag 时,sixos 的 `apply-tags` 会把 host 抹掉。** `lib.composeManyExtensions []` 求值成 `(_: _: {})`,
   于是空 tag 集合下 host 会塌缩成只剩 `tags`/`canonical`/`name`。本仓库声明了一个永远为真的身份 tag(`dictyonos`)
   专门用来让 host 活着;所有真正的上游 tag 都刻意不开,因为它们每一个都会拖进 Asterinas 用不了的 kexec/ownerboot/initrd 机器。
4. **sixos 的 s6-rc 补丁系列只适用于 nixpkgs 24.05。** 拿更新的 nixpkgs 构建 sixos 会在
   `0009-add-OLDSTATE_UNPROPAGATED_RESTART.patch` 上以 `2 out of 7 hunks FAILED` 失败。因此 `nixpkgs-sixos`
   固定在 `nixos-24.05` 分支,而 Lix 来自第二个(`nixos-26.05`)input。第二个用 release 分支而非 `nixos-unstable`,
   是因为成文时 unstable 里的 Lix 的 meson 选项与它自己的构建脚本已经不匹配(`ERROR: Unknown option: mimalloc`);
   26.05 也正好是 Asterinas 自家 NixOS 发行版所跟踪的 channel。
5. **长驻服务必须用 `six.mkFunnel`。** `six.mkService { type = "longrun"; ... }` 产出的是 `up`/`down`,
   而 `s6-rc-compile` 要的是 `run`;只有 `mkFunnel`/`mkLogger` 会产出它。
6. **Asterinas 不解析 `console=` 上的波特率后缀。** `console=ttyS0,115200n8` 会被拒绝
   (`console not found, falling back to tty0`),于是所有用户态输出被静默送进一个并不存在的 framebuffer。
   必须写单纯的 `console=ttyS0`。
7. **`fs.protected_hardlinks` 会阻止硬链接 store。** 手工用 `cp -al` 拼镜像会撞上 `EPERM`。
   在 sandbox 里构建(也就是 `rootfs.nix` 的做法)则完全绕过这个问题。
8. **Asterinas 不能绑定 IPv4 通配地址。** `bind()` 会在自己的本地路由表里解析地址参数
   (`kernel/core/src/net/route/mod.rs:lookup_local_iface`),凡不是本机地址一律回 `EADDRNOTAVAIL`——
   `0.0.0.0` 和 `::` 都在此列,所以惯常的 `listen(0.0.0.0:22)` 根本不可能成功。
   更糟的是 dropbear 的 `-p 22`:它从 getaddrinfo 拿到的是 IPv6 通配地址,`IPV6_V6ONLY` 和 `bind(::)` 双双失败后,
   直接以 "No listening ports available" 退出,根本不会去试 IPv4。因此 `ssh` 服务会等网卡拿到可路由地址,再绑定那个地址。
9. **dropbear 通过 `/etc/shells` 校验登录 shell。** 该文件缺失时,glibc 的 `getusershell(3)` 回退到
   `"/bin/sh,/bin/csh"`,而 sixos 生成的 `passwd` 里 root 的 shell 是个 store 路径——于是即便公钥已被接受,
   每次登录仍以 "User 'root' has invalid shell, rejected" 被拒。`rootfs.nix` 直接从 `passwd` 自身生成 `/etc/shells`。
10. **sixos 生成的 `finish.user` 脚本带着 `-Ws4`。** `execlineb -W -s 4` 要求四个位置参数,
    于是每个会死掉的服务每次重启都会在控制台上打一行
    `execlineb: fatal: too few arguments: expecting at least 4 but got 3`。这是症状不是病因:
    把不断死亡的那个服务治好,噪声自然消失。
11. **Asterinas 没有后台回写,而且 `sync(2)` 在这里不可用。** 脏页只有在有人对其所属文件系统调用 `syncfs()` 时才离开 guest。
    整机的 `sync` 会对着只读系统盘打出
    `block: failed to do Write on the device with error status: IoError`,并且不可靠地才轮到状态盘;
    而 `sync` **挂载选项**会被直接丢弃,因为 Asterinas 的 `PerMountFlags` 里没有 `SYNCHRONOUS` 位。
    只有 `sync -f /var`(对状态盘做 syncfs)有效并返回 0——`state-sync` 用的就是它。

## 验收

``````````sh
AUTO=1 nix run
``````````

它会把虚机启动**两次**。第一次在串口控制台上跑检查:`uname -a`、`cat /proc/version`、
`readlink /proc/1/exe`、完整的 `ps aux`,确认 sixos 的 activate 跑到了最后,输出每个长驻服务的
`s6-svstat` 并 tail 它们在 `/var/log` 下的日志,展示两块盘与网络配置,运行 `nix --version` 与
`nix eval --expr '1 + 1'`,并在状态盘上做一次写入/`sync -f`/读回。与此同时宿主机并行地验证一次
真实的 ssh 握手并通过它执行命令。

第二次启动是一台全新的虚机,挂的是**同一块**状态盘:它必须仍然读得到 `/var/persist-early` 与
`/var/persist-late` 且内容不变,并且必须出示同一把 dropbear 主机密钥——这才证明那把密钥是从盘上复用的,
而不是重新生成的。宿主机另外提供自己的证据:对镜像跑 `e2fsck -fn`,不挂载直接用 `debugfs` 读取
(guest 是 halt 而不是关机,所以镜像在退出时并没有被同步过),以及比较两次启动之间 `ssh-keyscan` 看到的
客户端侧主机密钥。只有以上全部成立,运行最后才会打印 `REBOOT-PERSISTENCE-OK`。

这些命令是一条一条打进 guest 的 getty 的,每一步结尾都带一个宿主机等待的哨兵串。固定 sleep 不够用:
其中一步故意 sleep 35 秒等 `state-sync` 跳一次,而抢跑的宿主机输入的命令会被 tty 回声到它们对应的输出
之前,导致日志交错,并让后来读日志的人看到被截断的内容。

一次运行会留下三份记录:`./serial.log`(第一次启动)、`./serial-boot2.log`(第二次启动)与
`./serial.host.log`(ssh、`e2fsck`、`debugfs`),一次完整的抓取见 [ACCEPTANCE.md](ACCEPTANCE.md)。
[.github/workflows/ci.yml](.github/workflows/ci.yml) 在每次 push 与 PR 时跑同一套验收,并且无论成败都
上传这三份记录。

## 已知限制

* `poweroff -f` 会报 `Failed to power off the system` 并停机:Asterinas 没有实现 ACPI poweroff。
  启动器用 `TIMEOUT` 结束运行。
* **guest 里不能构建。** `/nix/store` 是刻意只读的,所以 `nix eval` 以及一切只读 store 的操作都能用,
  但 `nix build` 没有地方放它的产物。
* **没有 INET 通配绑定**(见第 8 条坑):想要"监听所有网卡"的服务必须自己枚举手上的地址。
* **状态盘的持久化跑在 30 秒定时器上。** Asterinas 不做后台回写(第 11 条坑),所以 `/var` 是由 `state-sync`
  服务提交的,而不是内核;虚机消失前最后半分钟内写的东西会丢。验收把这条机制两头都证明了:guest 写入、`sync -f`、
  读回 `/var/persist-early`;guest 故意不同步 `/var/persist-late`,它靠服务跳一次才落到盘上;
  第二次启动再把两者都读回来。
* `uname -a` 报 `Linux 5.13.0` 是刻意的——Asterinas 对外宣布的是它模拟的 Linux ABI。
  说实话的是 `/proc/version`:它写的是 Rust 编译器,而不是 C 编译器。
* 系统调用 334(`rseq`)未实现,每个进程启动时记一条日志;glibc 能优雅处理 `ENOSYS`。

## 许可与上游致谢

本仓库的胶水层——`flake.nix`、`default.nix`、`kernel.nix`、`vendor.nix`、`initramfs.nix`、`rootfs.nix`、
`stage1-init.sh` 与 `scripts/`——以 **Mozilla Public License 2.0**(`LICENSE`)授权,与 Asterinas 保持一致。

它消费但不修改、也不再分发以下上游项目,它们的许可适用于它们自身:

| 上游 | 许可 | 说明 |
| --- | --- | --- |
| [Asterinas](https://github.com/asterinas/asterinas) | MPL-2.0 | 内核;经 `asterinas` input 按 revision 引用,由 `kernel.nix` 本地构建 |
| [sixos](https://codeberg.org/amjoseph/sixos) | GPL-3.0-only(见其 `COPYING.GPL3-ONLY`) | 基于 s6 的服务层 |
| [infuse.nix](https://codeberg.org/amjoseph/infuse.nix) | GPL-3.0(依其仓库) | sixos 赖以构建的属性集组合子 |
| [Lix](https://lix.systems/) | LGPL-2.1 | 包管理器;取自 nixpkgs 的预编译版本 |
| [dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html) | MIT | ssh 服务端 |
| [nixpkgs](https://github.com/NixOS/nixpkgs) | MIT | 包定义 |
| [skarnet s6 / s6-rc / s6-linux-init](https://skarnet.org/software/) | ISC | 进程监管,经 sixos 引入 |

由于 sixos 与 infuse.nix 是按各自 revision 取入的构建输入,任何再分发**构建产物**的人都在分发 GPL-3.0 二进制,
必须遵守相应条款。

