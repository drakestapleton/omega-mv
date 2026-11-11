# Aienux

<!-- languages -->
[English](README.md) · **简体中文**
<!-- /languages -->

> **状态：实验性，pre-alpha。这里的任何内容都未经可供实际使用的鉴定。** C 内核已在 Raspberry Pi 5 和一台 2017 年的 iMac 上运行过，但仅限于使用 TEST 密钥或一次性机密的测试构建。它尚未在 NVIDIA DGX Spark 上启动过。不提供任何支持、稳定性或兼容性承诺。预计会有破坏性变更。

Aienux 是 AienOS 的内核：它是我自己的操作系统内核，用来取代 DGX Spark 上的 Linux。AienOS 是构建在它之上的整个系统。它是智能体原生的：智能体是控制平面，而模型永远不是内核。内核保持小巧、确定且不含智能，智能体也永远不是信任根。内核的大部分是 `native/` 中的 C 代码。较早的 Rust 内核和工具位于 `crates/` 中。

```text
Firmware -> AIEN Boot -> AIEN Kernel -> AIEN Runtime -> AIEN Agent -> You
```

## 在 AIEN 中的位置

Aienux 负责可信基座：启动、内核、内存、存储、密码学和设备访问。相关的同级仓库有：

- [aien-dev/aien-architecture-mv](https://github.com/aien-dev/aien-architecture-mv)：整个系统的架构、ADR 和实施顺序。它对本仓库中的计划拥有最终决定权（见 [docs/PLAN_AUTHORITY.md](docs/PLAN_AUTHORITY.md)）。
- [aien-dev/omega-mv](https://github.com/aien-dev/omega-mv)：Omega，即 C 反应运行时和编译器。根据 aien-architecture ADR 0024，系统代码正在向 Omega 迁移。AIENOS 在 [native/kernel/third_party/omega/](native/kernel/third_party/omega/README.md) 中逐字节保存了一份 Omega 的 Cortex 存储副本，版本由 `omega.lock` 固定。
- [aien-dev/physics-mv](https://github.com/aien-dev/physics-mv)：FORGE，即面向 GB10 硬件路径的机器实现层。
- [aien-dev/aien-protocols-mv](https://github.com/aien-dev/aien-protocols-mv)：在各仓库之间共享的规范和传输格式。
- [aien-dev/aien-sovereign-core-mv](https://github.com/aien-dev/aien-sovereign-core-mv)：主机运行时，以及在 Spark 上运行的测试评判器 `aien-test`。
- [aien-dev/benchmarks-mv](https://github.com/aien-dev/benchmarks-mv)：测量框架和证据。
- [aien-dev/aien-receipts](https://github.com/aien-dev/aien-receipts)：Spark 为每个提交发布的已签名测试凭证。

## 当前状态（2026-10-19）

下面每一项都注明了存放其证据的文件。“QEMU”指 QEMU 模拟器：在 QEMU 中通过，并不能说明真实硬件上的任何情况。

**C 内核已冻结**（Drake，2026-10-24；ADR 0039，程序 L802）：在用 Omega 重写 Aienux 期间，它只接受缺陷修复，并保证实验室的 iMac 能继续启动；它不再接受新功能。见 [native/kernel/README.md](native/kernel/README.md)。

**QEMU 中的 C 内核。** `scripts/ck_gates.sh` 列出了 27 个模拟器门禁。这里提交的最新凭证是 [evidence/ck_gates_29ed03c9...json](evidence/ck_gates_29ed03c97454354a18676f768273dd7f7a8e15462c4be1939d9994d277d0d639.json)：24 个门禁，全部 PASS，于 2026-10-09 在提交 7f0de7e 上运行。该日期之后新增的门禁还没有已提交的完整凭证。各门禁的检查内容见 [native/kernel/GATES.md](native/kernel/GATES.md)。

**Raspberry Pi 5（仅限测试构建）。** 首次运行于 2026-10-13：内核启动了全部四个核心，运行了定时器，并把日志写入 SD 卡（[evidence/pi5_hardware_runs_2026-10-13/](evidence/pi5_hardware_runs_2026-10-13/README.md)）。之后在 Pi 上的各次运行，在 [docs/native/](docs/native/) 中都有各自的记录：

- 使用从卡中读取的一次性恢复机密解锁 Store（[PI5-4-UNLOCK-RUNS.md](docs/native/PI5-4-UNLOCK-RUNS.md)）。
- 一条事实被记住，并在重启后被召回（[PI5-5-CORTEX-RUNS.md](docs/native/PI5-5-CORTEX-RUNS.md)）。
- Pi 上的首次模型推理：Llama-3.2-1B，每秒 1.20 个 token（[PI5-6-INFER-RUNS.md](docs/native/PI5-6-INFER-RUNS.md)）。一条模型回复被保存到加密的 Store 中，并在重启后读回（[PI5-6-AGENT-RUNS.md](docs/native/PI5-6-AGENT-RUNS.md)）。
- 智能体的生命周期，包括完全断电后的召回（[PI5-7-LIFECYCLE-RUNS.md](docs/native/PI5-7-LIFECYCLE-RUNS.md)），以及使用 TEST 密钥加载的已签名用户态程序（[PI5-7-ARTIFACT-RUNS.md](docs/native/PI5-7-ARTIFACT-RUNS.md)）。
- 在线路上发出了一个以太网帧，设备内存访问被限制在一个固定窗口内（[PI5-NET-3-RUNS.md](docs/native/PI5-NET-3-RUNS.md)）。从网络接收尚未完成。
- 在 YubiKey 上进行的所有者密钥仪式，于 2026-10-14 执行过一次（[PI5-8-OWNER-CEREMONY.md](docs/native/PI5-8-OWNER-CEREMONY.md)），以及可复现的 Pi 镜像构建（[PI5-8-QUALIFICATION.md](docs/native/PI5-8-QUALIFICATION.md)）。

**2017 iMac（x86_64）。** 2026-10-16 的一次诊断启动记录了硬件信息（[evidence/imac_boot0_2026-10-16/](evidence/imac_boot0_2026-10-16/README.md)）。C 内核于 2026-10-16 在 iMac 上启动（[evidence/imac_kernel0_2026-10-16/](evidence/imac_kernel0_2026-10-16/README.md)）。2026-10-17，它启动了全部四个核心，在不写入的情况下读取了两块磁盘，并找到了以太网芯片（[evidence/imac_kernel1_2026-10-17/](evidence/imac_kernel1_2026-10-17/README.md)）。通过以太网发送测试报告的代码已合并（PR [#408](https://github.com/aien-dev/aienux/pull/408)）；本仓库中没有它在硬件上运行的记录。

**网络启动和音频（仅代码）。** 从 Spark 获取已签名内核的 iMac 网络加载器已合并（PR [#414](https://github.com/aien-dev/aienux/pull/414)），C 内核 USB 音频输出的第一步也已合并（PR [#423](https://github.com/aien-dev/aienux/pull/423)）；本仓库没有记录两者在硬件上的运行。

**DGX Spark。** Spark 上的首次原生启动于 2026-09-24 通过，使用的是较早的 Rust 路径（[evidence/m2_first_boot_2026-09-24.md](evidence/m2_first_boot_2026-09-24.md)）。C 内核尚未在 Spark 上启动过。

**未经鉴定。** Spark 上的信任链和加密存储（TRUST-1 和 M5）仍需要硬件和操作员步骤：[docs/TRUST-1-M5-GATE-MATRIX.md](docs/TRUST-1-M5-GATE-MATRIX.md)、[docs/TRUST-1-OPERATOR-STEPS.md](docs/TRUST-1-OPERATOR-STEPS.md)。

**待完成的工作。** 尚未关闭的跟踪 issue 包括：原生 OSH 流水线（[#428](https://github.com/aien-dev/aienux/issues/428) 至 [#432](https://github.com/aien-dev/aienux/issues/432)）、iMac 驱动（[#422](https://github.com/aien-dev/aienux/issues/422)）、Pi 5 与 Spark 之间的联网（[#398](https://github.com/aien-dev/aienux/issues/398)）、原生 NVMe 和 Store（[#31](https://github.com/aien-dev/aienux/issues/31)），以及 Spark 上的 TRUST-1/M5（[#32](https://github.com/aien-dev/aienux/issues/32)）。

关于组件状态，[ROADMAP.md](ROADMAP.md) 是 AIENOS 的计划，但它最新的状态块日期为 2026-10-01，没有涵盖上文所述的 Pi 5 和 iMac 工作。

## 本代码遵循的规则

- **主权：** 启动机器、访问你的数据、对你进行身份验证、授权智能体、构建可信核心、恢复、更换模型、迁移硬件或持续运行，都不需要任何外部组织。
- **开放的可信基座：** 启动、内核、内存、调度、存储、密码学、身份、AEGIS（授权层）、能力检查、更新检查和恢复，都可以从可读的源代码离线构建。
- **在可逆状态内自由行动；在不可逆的步骤上进行明确授权。**
- **语言：** Rust 是脚手架，Omega 是目标，C 或汇编只保留在硬件、启动、ABI 或测量确实需要的地方（aien-architecture ADR 0024）。启动、服务和工具中不使用 Python，不使用 CUDA 工具包，不使用 CUDA 风格的 API，也不使用 systemd 或 Linux init。可信基座中的依赖很少，并且都离线构建。

## 它如何工作，我又是如何构建它的

C 内核的一次启动，按顺序如下：

1. UEFI 调用 `_start`（[native/boot/efi_entry.S](native/boot/efi_entry.S)）。它重定位镜像，然后调用 `efi_main`，由后者退出启动服务。
2. `ck_kernel_entry`（[native/kernel/core/kmain.c](native/kernel/core/kmain.c)）建立内核自己的页表：代码段 RX，数据段 RW+XN，以及保护页。
3. 它从 EL2 降到 EL1h（[ADR 0009](docs/adr/0009-el2-bootstrap-to-el1h-kernel-transition.md)）。
4. 它启用 GICv3 和 10 ms 定时器。
5. 它运行 M3 检查：
   - 协作式线程、定时器抢占和 EL0 隔离；
   - 类型化 IPC，其中每一次发送、接收和委托都要经过同一个能力门禁（[native/kernel/core/ipc.c](native/kernel/core/ipc.c) 中的 `ck_cap_lookup` / `gated`）。缺少权限时返回 `CK_IPC_MISSING_RIGHTS`，EL0 调用方会收到 `DENIED`。

C 内核是从早期的 Rust 内核一步一步移植过来的：
- 核心启动，见 aienos #194（`34c6053`）；
- M3 隔离和 IPC 的移植，见 aienos #201（`0d0efa5`）。

每个 Rust 检查模式在 [native/kernel/GATES.md](native/kernel/GATES.md) 中都有对应的 C 门禁。有两条限制：
- 调度是在单个内核线程内协作进行的，没有任何次级核心运行任务；
- QEMU 的结果不构成对任何物理设备的鉴定。

[native/kernel/WALKTHROUGH.md](native/kernel/WALKTHROUGH.md) 逐个函数地讲解了这一启动过程。它介绍了从 Rust 到 C 的历史，以及门禁所规避的多线程 TCG 挂起问题，还给出一个十秒钟即可完成的复现及其预期输出，其中包括一个失败即关闭的拒绝用例：

```bash
make -s -C native/kernel OUT=$PWD/target/teach $PWD/target/teach/host/test_ipc && ./target/teach/host/test_ipc   # test_ipc: PASS (75 checks)
bash scripts/qemu_ck_boot_test.sh                                   # AIENOS_CK_M3: PASS, AIENOS_CK_M1: PASS
AIENOS_QEMU_CPU=neoverse-n1 bash scripts/qemu_ck_boot_test.sh       # no FEAT_RNG: AIENOS_CK_M1: FAIL (refusal)
```

## 构建和测试

C 代码只需要 gcc、binutils、make 和一个 shell。在非 AArch64 的主机上，内核 Makefile 会使用 `aarch64-linux-gnu-` 交叉工具。主机测试：

```bash
make -C native/kernel test        # C kernel host tests, ends CK_CORE_HOST: PASS
make -C native/kernel sanitize    # same under ASan and UBSan
make -C native/capability test    # capability authority (docs/CAPABILITY_ABI.md)
bash scripts/cap_abi_isolation_test.sh  # C and Rust capability ABIs stay separate
make -C native/store test         # Store v1 and the sealed Store
```

每个 `native/` 文件夹都有自己的 README 和各自的测试目标（`make test`，通常还有 `sanitize` 和 `mutants`）。

模拟器门禁需要 `qemu-system-aarch64` 和 AAVMF 固件（Ubuntu 软件包 `qemu-system-arm` 和 `qemu-efi-aarch64`）：

```bash
bash scripts/ck_gates.sh --self-test   # checks the gate runner itself, runs no QEMU
bash scripts/ck_gates.sh               # all C kernel gates; refuses a dirty tree; writes evidence/ck_gates_<sha256>.json
bash scripts/ck_pi5_build_check.sh     # builds the Pi 5 image (build only; it cannot boot in QEMU)
```

其他镜像：`make -C native/kernel pi5`（Raspberry Pi 5）和 `make -C native/kernel imac-kernel`（2017 iMac）。见 [native/kernel/README.md](native/kernel/README.md)。

`crates/` 中的 Rust 工作区由 `bash scripts/verify_all.sh` 检查（需要安装了 `aarch64-unknown-uefi` 和 `aarch64-unknown-none` 目标的 Rust）。

### 由谁来评判一项变更

自 2026-10-18 起（PR [#427](https://github.com/aien-dev/aienux/pull/427)），所有测试都在 Spark 上运行，而不是在 GitHub 上。Spark 运行 [tests/gates/](tests/gates/) 中的门禁清单（每个清单调用 `tests/gates/run.sh <step>`），并把已签名的结果发布到 [aien-dev/aien-receipts](https://github.com/aien-dev/aien-receipts)。GitHub 在 `main` 上只保留一个必需检查 `AIEN Verification`，它只检查这个已签名的结果。

## 证据存放在哪里

- [evidence/](evidence/)：模拟器凭证（`ck_gates_*.json`）、硬件运行记录（Pi 5、iMac、Spark）以及 TRUST-1 采集数据。
- [docs/native/](docs/native/)：Pi 5 运行记录。
- [native/kernel/GATES.md](native/kernel/GATES.md)：每一行模拟器门禁及其状态。
- [docs/adr/](docs/adr/README.md)：AIENOS 决策记录。
- [docs/design/DESIGN.md](docs/design/DESIGN.md)：Allen 的设计系统（色彩、字体、动效、声音、语音、无障碍），由 `cargo run -p allen-design-tokens -- generate` 导出为 C、Rust 和 CSS；启动参考草图及其数学推导位于 [docs/design/boot/](docs/design/boot/)，每个首次运行界面的设计稿位于 [docs/design/screens/](docs/design/screens/)（图片和一个浏览器草图，未在真实硬件上显示）

## 人类主导的智能体工程

开发遵循人类主导的智能体工程（HDAE）：由人类确定目标、架构、约束、验收标准和停止点；智能体在这些边界内实现、执行检查、诊断故障并进行修改。人工评审对主张、验收和发布决策保留责任。

关于该方法的文档说明和一个系统软件案例研究，见 Gregory M. Kurtzer，[*Ginux: Building an Independent Kernel That Runs Linux Userspace through Human-Directed Agentic Engineering* (2026)](https://doi.org/10.5281/zenodo.23682548)。该文讨论的是开发方法，而不是内核控制平面的行为，也不是对早期实验的追溯性鉴定。

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。适合入手的是标有 [`good first issue`](https://github.com/aien-dev/aienux/labels/good%20first%20issue) 或 [`emulator-ok`](https://github.com/aien-dev/aienux/labels/emulator-ok) 标签的 issue；它们不需要特殊硬件。需要真实 Spark 的工作标有 `needs-hardware`，由维护者运行。请向 `main` 提交拉取请求，并在开头列出你运行的命令及其输出。问题请发到[讨论区](https://github.com/aien-dev/aienux/discussions)。请通过 GitHub 安全公告私下报告漏洞。

## 许可

本项目依据 Apache License, Version 2.0（Apache-2.0）授权。见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。联系方式：aien@aienos.com。
