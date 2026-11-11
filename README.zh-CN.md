# OMEGA（.om 或 .omg）

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23547810.svg)](https://doi.org/10.5281/zenodo.23547810) [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23644702.svg)](https://doi.org/10.5281/zenodo.23644702) [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23614483.svg)](https://doi.org/10.5281/zenodo.23614483)
论文：[Omega](https://doi.org/10.5281/zenodo.23547810)、[词元即指令](https://doi.org/10.5281/zenodo.23644702)、[致全人类的呼吁](https://doi.org/10.5281/zenodo.23614483) · 作者：Drake Stapleton <a href="https://orcid.org/0009-0002-6890-7111"><img src="https://orcid.org/assets/vectors/orcid.logo.icon.svg" alt="ORCID iD" width="16" height="16"></a>

> **GPU 栈归 [CUDA++ (aien-dev/CUDApp)](https://github.com/aien-dev/CUDApp) 所有**（[ARCH-0042](https://github.com/aien-dev/aien-architecture-mv/blob/main/docs/adr/0042-omega-cudapp-bridge-ownership.md)：Omega 负责计算，CUDApp 负责 GPU 执行）。CUDA++ 是 GB10 GPU 栈的唯一事实来源：`src/omega_gpu_*`、`src/omega_blackwell_*`、`src/omega_bw_*`、`src/omega_sm121_*`，GPU 主机测试（`tests/gpu_*`、`tests/bw_*`、`tests/test_omega_gpu_*`），`mk/omega-gpu-*`、`mk/sm121dis.mk` 和 `tools/sm121dis/`（完整列表见 `.github/CODEOWNERS`）。新的 GPU 改动请在那里进行。这里的副本仍保留在本仓库中；移除它们需要 Drake 另行决定（ARCH-0042，决定 7）。如果在切换基线（`e5b32567`）之后，这些文件中有一个在这里发生了改动，而 CUDA++ 中没有相同的字节，CUDA++ 的漂移门禁（`tools/extract/drift.sh`）就会失败。基于 `cudapp.lock` 中固定的 CUDA++ 构建服务器（aien-sovereign-core）一事尚待完成（[aien-sovereign-core-mv#784](https://github.com/aien-dev/aien-sovereign-core-mv/pull/784)）。

**Omega 是一门系统语言和计算平台，正在用手写、种子自举的 `.om` 实现**。它的目标是一条可检查的路径：从一个小小的种子出发，经过编译器、运行时和应用程序，直到机器执行。纯计算和经授权的副作用有各自不同的契约；语义标识用来标识已声明的计算，而校验和凭证记录的是实际检查过的内容。

**迁移尚未完成**。本仓库的默认分支仍包含大量 C 实现以及构建/测试工具。种子自举的 `.om` 编译器、它的原生主机词和设备/映射词、OM-2 配置档以及 WebAssembly 后端都已在 `main` 上；现有的 C 实现是一项尚未完成的替换任务，而不是 Omega 的最终语言。

- [Omega 计划：从种子到模型](https://github.com/aien-dev/omega-mv/issues/599)
- [Omega 1.0 路线图：就绪度审计、里程碑和验收门禁](docs/ROADMAP-1.0.md)
- [一个小型 Omega 程序，以及标识边界](docs/TEACH_OMEGA.md)：为议题 #619 准备的一节范围有限的课程。它使用的是一个历史上的教学固定版本，而不是当前的编译器，也不主张旧的标识机制能覆盖种子自举的程序。
- [剩余的 C 源文件/头文件清单](docs/migration/C-TO-OM-INVENTORY.md)
- [实验性的 `.om` 确定性流后继实现](seed/physics0/README.md)：源码/主机检查已通过；原生编译和执行为 NOT_RUN。
- [Neuralese 补充文档](neuralese/README.md)：处于 PROPOSED 状态的模型绑定表示设计，带有一个有界的原生 `.om` 封装/码本候选方案，以及普通的已检查源码边界。不主张任何习得的推理或模型实验。
- [Alpha 模型/平台鉴定](https://github.com/aien-dev/aien-architecture-mv/issues/305)

### 为什么 GitHub 仍然显示 C

GitHub 的语言栏统计的是默认分支上可识别的源码字节数；它既不是项目的语言规范，也不是迁移完成与否的判定。GitHub Linguist 目前不识别 Omega/`.om`，而这里仍在使用的 C 文件尚未被替换和移除。我不会把手写的 C 标记为生成代码或第三方代码，不会把它改名为 `.om`，也不会为了改变这个统计而指定一种无关的语言。实际剩余的工作见上面的清单。要让 GitHub 原生识别，需要 [Linguist](https://github.com/github-linguist/linguist/blob/main/CONTRIBUTING.md#adding-a-language) 提供支持。

```text
SILICON -> ATLAS -> PHYSICS/FORGE -> OMEGA -> AIEN        (full picture: aien-architecture)
```

2026-09-29，Drake 决定让 Omega 同时作为反应运行时和 Omega Systems Core 的编译器（[决策记录](docs/adr/OMEGA-SYSTEMS-CORE-0000.md)，已冻结）。此前“不是编译器”的说法就此废止。

## 当前状态

研究级，分阶段的 Alpha 鉴定计划正在进行中。一份 Alpha 计划或一个未关闭的 PR 并不等于一个已鉴定的发布版本。直白地说：

- **种子自举的 `.om` 编译器（自 PR #696 起在 `main` 上）**：只有一个编译器，即 `seed/out/omc`，用 `.om` 编写，并通过 `sh seed/omega-from-seed.sh`（`seed0 -> hex1 -> asm2 -> om4 -> omc`）从 408 字节的加载器重建。它唯一支持的配置是 AArch64 Linux、静态 ELF 输出，整个语言定义在 `docs/one_layer/OMEGESE.md` 中：原生主机词（编号 100..165）和经过检查的设备/映射词（编号 166..177）。主机鉴定使用 `tests/gates/run.sh seed`（即 `OMEGA-SEED` 门禁：阶段不动点、`seed/host/check.sh` 以及与 C 参照基准的 IR 比对，不跳过任何门禁）。它不能证明的是：不动点只是同一谱系内的重建检查，而不是多样化双重编译；`seed/omega-ref` 上的参考解释器早于这份编译器源码（它会拒绝调用在后面才定义的函数，第一处是 `fexp`，位于 `seed/omc/omc.om` 第 935 行）。多样化双重编译是单独的门禁 `seed/qualification/ddc650/ddc.om`（PROPOSED，主机 EXERCISED，未进入 CI，未 QUALIFIED；[omega#650](https://github.com/aien-dev/omega-mv/issues/650)）：种子的 `om4` 路径，以及同步后规范解释器的一个 GCC 构建副本（未合并的 `seed/omega-ref-sync` 分支上 190130b7 处的 `tools/omega_ref/omega_ref.c`，以 SHA-256 固定），各自重建 `omc.om`；在 `62d1d0d6` 处，两者都逐字节复现了 `seed/out/omc`（`62775d2a`），而每个负对照都失败了（2026-10-30，一台 AArch64 主机，同一项目谱系；见[它的 README](seed/qualification/ddc650/README.md)）。较早的 `tools/omega_ref/gate_ddc.sh` PASS（omc `734f0a39`，2026-10-24）只存在于那个未合并的分支上，并不描述当前的编译器。通过这些设备词进行的 GPU 启动和模型执行尚未鉴定。该语言支持有界的原生递归；一个受限的导入器并不能描述整个语言。见[一致性与证据的局限](https://github.com/aien-dev/omega-mv/issues/624)。
- **候选的 x86-64 Linux 后端（FR-9）**：在开头写一行 `target x86linux`，即可为整个程序选择 x86-64 静态 ELF 输出；不写选择行则保持 AArch64 输出。该后端在 `seed/omc/omc.om` 中实现，而不是一份 C 翻译。[设计、ABI、来源与鉴定](docs/X86-LINUX.md)区分了模拟执行、原生 x86 执行以及现有的 AArch64 种子链。裸 x86 单元使用私有的栈帧 ABI，而不是 SysV C ABI；外部调用方仍然使用 omega-bridge。已作为 #923 合并；状态为 DRAFT。到目前为止，x86 执行仅为 EMULATED（QEMU）；原生 x86 执行和原生 x86 seed0 链为 NOT_RUN。最近一次完整的差分测试在源码 `62d1d0d6` 处进行（2026-10-30，`seed/qualification/x86-linux/20261030-main-62d1d0d6.json`），报告 15182 个 PASS、0 个 FAIL、2 个 NOT_RUN 和 222 个 EXCLUDED；这两个 NOT_RUN 用例是无效 fd 的 ioctl 测试夹具，QEMU 对它们返回 ENOTTY，而原生 Linux 返回 EBADF。其总体判定仍为 FAIL，因为 NOT_RUN 不等于 PASS。这不是一个经过硬件鉴定的发布版本。
- **`main` 上的旧版 OSC/C 实现**：OSC-0/1/2 和 OSC-3 材料描述的是早期实现和未完成的迁移，而不是今后的源语言路径。旧的里程碑 6“自托管”结果只是一次固定输出的自我复制检查，并不是编译（[历史说明](docs/osc/OSC-1-SELF-HOST-STATEMENT.md)）；不要把它和后来的种子自举编译器工作混为一谈。
- **反应运行时**：R1 到 R16 鉴定阶梯曾在早于组合模块（omega#126）的构建上通过，这是一个历史结果。在 `3108fc2` 处的重新鉴定记录了 R15 FAIL（16 个门禁中的 14 个：G1、G15）和 R16 FAIL（`evidence/REQUAL-3108fc2/`）；`850fc54` 处的 R16 凭证 `22d7a79a` 不能作为当前主张，因为它的脚本后来被发现有缺陷；R1 到 R16 都没有在当前候选版本上重新鉴定，阶梯重跑正在进行中。R16 循环点清单已在候选树上核对完毕（502 个点，0 个未分类，0 个过期，PR #279）；那只是清单门禁，不是 R16。当前的活态构建在重新鉴定之前为 IMPLEMENTED / NOT QUALIFIED。Composition、Capability Graph、Skill Router、J-Space 和 Cortex 在主机上运行；Fabric 接口是一个仅限主机、不联网的环回接口；这些都没有作为经过鉴定的系统运行在芯片上。
- **数值（E1）**：已于 2026-10-02 在 GB10 芯片测试中关闭（门禁 5 为 26/26，含 47 条一致性行，SUM/MAX/MIN/MEAN 归约，九种超越函数运算各自覆盖全部 2^32 个输入，148 个加载/存储核函数），汇总凭证为 `evidence/E1-CLOSURE/e7851c69d34ac777a9436af16d0bdd5d69264c8528c62d562b600f5d89153061.json`。自然底数的 EXP 和 LOG，即 2026-10-02 的排除项，现在已有 GB10 核函数：在 omega `cb6d201` 上，全部十一种 E1 超越函数运算（上述九种加上 EXP 和 LOG）都在芯片上对各自全部 2^32 个输入通过，不匹配数为 0（`evidence/E1-TRANSC-GB10/b2f4afe9…`、`ae3a4123…`、`d846fbe3…`），M20 张量 GB10 层级在 `0919efc3` 上通过了 99 个用例中的 99 个（`evidence/M20-TENSOR-GB10/a00b4178…`）；见 [E1_GAP_TABLE](docs/numeric/E1_GAP_TABLE.md) 中的“Update, 2026-10-27”。
- **解码注意力（OWN-30B）**：一个缓存最多容纳 131072 个位置（128K 上下文，`OMEGA_GPU_DATTN_MAX_POS`）。在 GB10 芯片上，上下文长度 65536、100000 和 131072 的结果与双精度参考完全一致（`evidence/dattn-maxpos-128k-20261018/`）；在这些长度下，核函数以约 57 GB/s 的速度流式读取 K/V，因此长上下文的速度低于仅读取权重时所能达到的速度。
- **Qwen3.8-27B 核函数（GB10，2026-10-18）**：每个核函数都在芯片上对照双精度参考进行检查，并配有必须失败的故意损坏变体；目前还没有一个接入服务引擎。FP8 矩阵向量乘和张量核心预填充 GEMM 现在支持最大 32768 的 k，覆盖了 27B 在 k = 17408 处的下投影（`evidence/fp8-k32768-20261018/`，omega#541）。Gated DeltaNet 解码步骤（64 层中有 48 层使用的循环层）每层一次启动完成，与参考结果的误差约为 2e-7；每层耗时 125.7 us，以 50.1 GB/s 搬运它的 6.29 MB 状态，而名义带宽为 273 GB/s（`evidence/gdn-decode-20261018/`，omega#542）。DeltaNet 预填充每层用三次启动读完整个提示词，并把状态交给解码步骤，后者可以精确地接续；在 2048 个 token 时，每个 token 每层耗时 3.80 us，其中的循环扫描每秒执行约 2.4 万亿次运算，而芯片在这类计算上的峰值尚未测量（`evidence/gdn-prefill-20261018/`，omega#543）。其余 16 层的全注意力解码步骤（24 个查询头对应 4 个键值头，每个头 256 个数，只对前 64 个做旋转，通过在加载时对这些数重排一次来实现）每层一次启动完成，在每个测试过的上下文长度（1、7、256、301、1024、4096、8192、32768 和 131072 个 token）上都与参考结果一致，五个损坏变体全部被捕获；在 32768 个 token 的上下文下每层耗时 2.10 ms，以 63.8 GB/s 流式读取它的 134 MB 缓存键和值，而名义带宽为 273 GB/s（`evidence/QWEN38-DATTN256-8bb4494e-20261018/`，omega#544）。这 16 层的预填充注意力每层用两次启动读取提示词中一个 2048 token 的块，写下的缓存行与解码步骤本应写入的行逐位相同；它在直到 129024 + 2048 个 token 的每个测试点上都与参考结果一致，四个损坏变体全部被捕获；一个 2048 token 的块在提示词开头每层耗时 10.0 ms，在 128K 提示词末尾耗时 591 ms，以 230.6 GB/s 流式读取缓存键和值，而名义带宽为 273 GB/s（`evidence/pattn256-chip-20261018T1517Z/`，omega#545）。在让它跑起来的过程中，发现了所有核函数共有的一个缺陷：编码器在写入整数加法、一条比较指令和退出指令时使用了固定的时序字，因此代码生成器为它们安排的等待从未到达芯片。编码器现在会保留这些等待，`make test-bw-encode-control` 会检查每一种指令类型，19 个核函数家族中有 18 个在修复后通过了芯片测试（三元运算家族只在速度门禁上失败，而旧编码器在同样负载下也以同样的方式失败；`evidence/encoder-fix-sweep-20261018T1512Z/`）。
- **专家槽位（Expert Ribbon，omega#533）**：`src/omega_gpu_fp8_slots.h` 维护一个固定的 FP8 专家槽位池，可以在模型运行时重新填充。槽位在被重写期间是隐藏的，只有在复制完成后才会获得新版本，并且只要还有任何启动或已录制的命令列表在读取它，就不能被重写。已在 GB10 上、在槽位提交 a8ae3a1f 和 d8185686 各自的 2026-10-18 基线上演示（`tools/run_gpu_fp8_slots_chip.sh`，凭证位于 `evidence/RIBBON-SLOTS-*`；未在当前基线上重新运行）：槽位给出的结果与常驻的同一专家逐位相同，并且负对照（忽略固定标记）被捕获。SSD 一侧和模型接线位于 aien-sovereign-core 中。
- **硬件**：DGX Spark GB10 上的结果与每份凭证中的确切提交绑定。主机和模拟器上的通过从不报告为硬件鉴定。

实时状态由 [aien-architecture-mv](https://github.com/aien-dev/aien-architecture-mv) 维护：[CURRENT_EXECUTION_PLAN.md](https://github.com/aien-dev/aien-architecture-mv/blob/main/CURRENT_EXECUTION_PLAN.md) 和 [doctrine/ROADMAP.md](https://github.com/aien-dev/aien-architecture-mv/blob/main/doctrine/ROADMAP.md)。本文件不重复那些会变动的数字。历史里程碑凭证（例如里程碑 4、`OMEGA_SEMANTICS`、12 个门禁中的 12 个）作为历史原样保留在 `evidence/` 中。

- **FP8 专家启动合并为一个波次（2026-10-24，L310，在真实芯片上测量）**：分组专家 GEMV 原先每组使用 6 个 CTA，这个值是在 8 组上调出来的；因此 9 组模型（即 35B，Qwen3.6-35B-A3B，一个每个 token 约有 30 亿激活参数的混合专家模型：8 个路由专家 + 共享专家）在每个 token 的 80 次专家启动中，每次都在 48 个 SM 上启动 54 个 CTA，即两个波次。`AIEN_OMEGA_FP8_GROUPED_WAVE=1` 把启动规模调整为一个波次（min(6, 48 / 组数)；9 组 -> 5），35B 的 1 行步骤测得 20.498 -> 19.347 ms，专家流 160.5 -> 193.3 GB/s（N=3，仅芯片时间，不是经过服务器的端到端时间；凭证位于 aien-sovereign-core 的 `docs/speed/Q36_CEILING.md` 第 11 节，该文件还不在那个仓库的 main 上：[提交 65444d38](https://github.com/aien-dev/aien-sovereign-core-mv/blob/65444d3810ddf691e3bffb3276ec4a39eef838fe/docs/speed/Q36_CEILING.md)）。这些 GPU 核函数是本仓库中的 C 代码，而不是 Omega 语言代码（`docs/OMEGA.md` 中的门槛 C1）。在合并队列评判之前默认关闭；`AIEN_OMEGA_FP8_GROUPED_CTAS=n` 可强制指定一个确切值。`gpu_fp8_api_test --sim` 无需芯片即可检查规则表；服务器在加载时会打印它所使用的值。

## 核心理念

- **聪明不等于可信，智能不等于权威**。信任来自经过验证的不变量，绝不来自能力。
- **意义是永久的；表示是可丢弃的**。一个程序的 `SEMANTIC_ID`（规范编码的 SHA-256）命名的是它的规范主体，因此同一主体的不同写法（空白、参数名、操作数顺序）共享同一个 ID，但 `x + 1 + 1` 和 `x + 2` 不共享。单独的 `FUNCTION_ID` 命名的是函数：在多项式片段内（`+ - *` 以及模 2^w 的精确 `and`/`or` 恒等式，w = 1..64），两个程序当且仅当计算同一个函数时获得相同的 `FUNCTION_ID`；在该片段之外，该 ID 回退到主体，并会明确说明。任意程序的等价性是不可判定的，所以不存在对所有程序都具有外延性的 ID。节点、类型化关系和有凭证支撑的等价关系构成意义图（[spec/program-identity.md](spec/program-identity.md) 第 9 至 10 节，`om/meaning/`；已在主机上实际运行，尚未接入 C 库或 Visor）。
- **纯计算与副作用相分离**，副作用需要受能力约束、会产生凭证的事务。

## 与其他仓库的关系

归属规则（[ARCH-0042](https://github.com/aien-dev/aien-architecture-mv/blob/main/docs/adr/0042-omega-cudapp-bridge-ownership.md)，由 Drake 于 2026-10-30 接受，并作为 [aien-architecture-mv#342](https://github.com/aien-dev/aien-architecture-mv/pull/342) 合并）：Omega 负责计算，CUDA++ 负责 GPU 执行，Omega Bridge 负责兼容性。

- **本仓库**负责语言、语言的语义和 IR、种子自举编译器（`seed/out/omc`）以及供其他仓库使用的编译器固定版本，还有关于核函数计算什么的声明契约。
- **[CUDA++](https://github.com/aien-dev/CUDApp)** 负责 GPU 执行：sm_121 编码器和 GPU 代码生成器、cubin 写入器、反汇编器、驱动客户端、任务提交以及 GPU 运行时。
- **[Omega Bridge](https://github.com/aien-dev/omega-bridge)** 负责兼容性：从经过检查的 Omega 子集生成 C 和 Python，提供原生绑定，让外部调用方能调用编译后的 Omega（在这里由 `om/omega-bridge.lock` 固定），以及框架挂接和 GPU 产物协商。它不为其他仓库编译 Omega，也不运行核函数。

在 main 上尚未成立的是：`src/omega_blackwell_*`、`src/omega_gpu_*` 和 `src/omega_sm121_disasm.c` 下的 GPU C 代码是 CUDA++ 代码的一个已分叉副本，仍在这里开发，驱动客户端则来自 physics-mv。现有代码保持原位（Drake，2026-10-27）；新的 GPU 执行工作放到 CUDA++ 或与之相连的仓库中。这些副本记录在 [CUDApp#106](https://github.com/aien-dev/CUDApp/issues/106)、[CUDApp#107](https://github.com/aien-dev/CUDApp/issues/107)、[CUDApp#108](https://github.com/aien-dev/CUDApp/issues/108) 和 [CUDApp#10](https://github.com/aien-dev/CUDApp/issues/10) 中。桥自身的种子自举和前端是 [#870](https://github.com/aien-dev/omega-mv/issues/870) 和 [#871](https://github.com/aien-dev/omega-mv/issues/871)。

[aienux](https://github.com/aien-dev/aienux) 存放 Aienux，即 AienOS 的内核，Omega 预期运行在它之上。[physics-mv](https://github.com/aien-dev/physics-mv) 提供 FORGE 机器实现和 GB10 原生路径（由 `physics.lock` 固定）。[aien-architecture-mv](https://github.com/aien-dev/aien-architecture-mv) 负责状态和排期。ARGUS-0/1（一个防御平面）在 aienux 中实现（`native/argus`，由 `argus.lock` 固定）；Omega 只携带可选启用的 `RX_ARGUS` 钩子（`src/runtime/rx_argus.c`）以及 `evidence/ARGUS/` 中的凭证。Physics Zero 在这里作为主机基准装置和学习器存在（`src/physics0/`、`tests/physics0/`、`mk/physics0-learner.mk`、`docs/physics0/`，凭证位于 `evidence/physics0/`），它的规范位于 physics 仓库中。DIRAC-0 是 aien-architecture-mv 中的一份规范，外加 `research/dirac-oracle/` 中一份从未构建或运行过的参照基准源码。Evolution Arena 只是一个计划。

子仓库会固定一个 omega-mv 提交以及它生成的 `omc` 的 sha256：[omega-gpu-driver](https://github.com/aien-dev/omega-gpu-driver) 是用种子自举的 Omega 编写的 GB10 GPU 驱动（通过 `vfioctl`/`vfiomap` 在 VFIO 上进行 W0 bind/read/release；已在 QEMU 中实际运行，未经硬件鉴定）。[hive-view](https://github.com/aien-dev/hive-view) 是 Spark 上的 hive 仪表盘，一个用种子自举的 Omega 编写、基于 `seed/net/http.om` 的 HTTP 服务（尚待在 Radicle 上完成首次合并，`rad:zimVqDToqH8NL2YvgM8fQBQrvgHa`）。

## 常设规则

语言规则：`.om` 是今后唯一的第一方实现语言。先实现每个替代品并完成鉴定，再切换它的实际使用方，然后从活跃树中移除被取代的第一方源码以及过时的构建/运行时依赖。这包括编译器/运行时代码、服务、工具、自动化以及项目自有的测试；如今剩下的 C/Rust/shell 是未完成的迁移，而不是永久豁免。保留 Git 历史和不可变的证据。外部协议格式、生成的机器码、设备固件以及独立来源的鉴定参照基准各有单独声明的角色；它们不得掩盖 Omega 的外部实现。见[替换/删除契约](https://github.com/aien-dev/aien-architecture-mv/issues/300)。

保留原生 GPU 工作及其明确记录的操作系统/驱动依赖；不要因为移除了某个用户空间库，就推断出硬件或操作系统无关性。不使用 systemd。离线、内部构建。绝不覆盖失败的实验或旧凭证。判定词：PASS、FAIL、NOT_RUN、BLOCKED_HARDWARE、BLOCKED_OPERATOR、MISSING_IMPLEMENTATION。

## 构建并验证现有的默认分支实现

这些是 **C/旧版兼容性检查**，不是种子自举的 `.om` 编译器的命令。种子自举编译器通过 `sh seed/omega-from-seed.sh` 和 `tests/gates/run.sh seed` 重建并完成鉴定（见 `seed/README.md`）；不要混用编译器二进制文件，也不要给旧凭证重新贴标签。

需要在 AArch64 Linux 主机上安装 gcc 和 make：CI 在 `ubuntu-24.04-arm` 上运行主机测试套件，而 `test-realize` 使用 `-march=armv8.6-a+dotprod+i8mm+sve` 编译。主机测试套件不需要 GPU，也不需要 physics 检出：

```bash
make PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 test-compiler-quick   # compiler, quick suite
make PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 test-numeric-cpu      # E1 CPU numerics
make PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 test-realize
```

完整的 omegatool 构建（`make`）会链接 `physics` 仓库中 `physics.lock` 所记录的那个提交。一些较早的里程碑门禁脚本会就地重写它们的凭证，所以不要在你想保留的干净检出上运行它们；请优先使用上面的 `make test-*` 目标。一些 GPU 测试套件基于 physics 构建，但仍不打开任何设备：`make test-gpu-decode-graph` 检查解码图的胶水核函数，并在一个假平台上检查：失败或被放弃的解码 token 总会归还 GPU 会话锁（仅在假平台上演示；真实芯片上的解码运行是 `tools/run_gpu_decode_graph_chip.sh`）。涉及 GB10 的目标需要 DGX Spark，一次只运行一个，并且绝不在运行中途终止。M19 干净克隆门禁会在临时目录中重建整个树，并在那里运行里程碑门禁；当嵌套构建或嵌套运行失败时，它现在会把自己日志的末尾打印到 stderr，因此失败会指明原因，而不是只报告一个光秃秃的 FAIL。`.github/workflows/` 中的 CI 定义列出了每次推送都会运行的测试套件。

`make test-bw-hazard`（仅主机，链接 `libomega_gpu.a`，因此和 `make` 一样需要 physics 检出）读取生成器构建的每个 GPU 核函数的编码字节，并检查记分板等待：被加载指令写入的寄存器在被读取之前必须等待，而排队中的加载或存储仍在读取的寄存器在被覆盖之前必须等待（omega-mv#554）。模拟器不模拟这些等待，所以这项主机检查本可以捕获 omega-mv#545 芯片故障。较旧核函数上的已知发现及各自的确认方式列在 `tests/bw_hazard_test.c` 中。

在共享的 Spark 评判器上（其 1 分钟平均负载很少低于 2），主机检查保留了原有的每一项检查，绝不把负载变成通过。`tests/runtime/r11_own_hold_test.sh` 为自己的运行提高 R11 负载上限（`R11_LOAD_LIMIT`，只能调高），并依据程序打印的静默标志保持决策进行判定；活态运行的速度检查只有在平均负载不超过 2 时才在那里判定。速度检查（`tests/runtime/rx_action_graph.c` 中动作图的 2 倍加速、工作流融合）取机器未受干扰的那些重复的中位数（依据 schedstat 中的运行队列延迟，`tests/runtime/rx_quiet_reps.h`）；当未受干扰的重复太少时，检查报告 `NOT_RUN`，原因为 `cpu_busy`，`tests/gates/run.sh` 会从凭证中读取这一拒绝，运行该步骤的其余部分，并以 NOT_RUN 结束该步骤。Omega 的服务成本是服务线程的 CPU 时间（`src/runtime/rx_omega.c` 中的 `cost_ns`），而不是挂钟时间，R15 一致性测试台给双方使用固定的成本表（`r15_use_cost_model`）。

## 仓库结构

`src/` 是现有核心以及等待替换的 C 编译器（`src/compiler/`），`src/runtime/` 是反应运行时，`src/fabric/` 是仅限主机的 fabric 接口，`src/physics0/` 是 Physics Zero 装置，`spec/` 和 `docs/` 是规范，`tests/` 是门禁测试套件，`evidence/` 是按内容寻址的凭证，`tools/` 是测试框架，`mk/` 是被 `Makefile` 包含的 make 片段。此外还有 `bench/prime_race/`（Prime Drag Race 实现）、`calibration/`（图灵校准实验、预注册和盲法协议）、`research/`（实验和原型）以及 `doctrine/`（里程碑 4 准则）。

## 人类主导的智能体工程

开发遵循人类主导的智能体工程（HDAE）：人类定义目标、架构、约束、验收标准和停止点；智能体在这些边界内实现、执行检查、诊断失败并进行修订。人工评审对主张、验收和发布决定承担责任。

关于这一方法的文档化说明和一个系统软件案例研究，见 Gregory M. Kurtzer，[*Ginux: Building an Independent Kernel That Runs Linux Userspace through Human-Directed Agentic Engineering* (2026)](https://doi.org/10.5281/zenodo.23682548)。这是一处方法引用，不改变作者署名，也不改变早期实验的鉴定。

## 参与贡献

请提交一个拉取请求，附上你运行的确切命令及其输出。凭证按内容寻址，注明确切的提交，并拒绝脏工作树。不要就地编辑已有的证据。合并前应当经过外部评审。见 [CONTRIBUTORS.md](CONTRIBUTORS.md)。联系方式：aien@aienos.com。

## 文件夹说明

[FOLDERS.md](FOLDERS.md) 说明每个文件夹的用途及其遵循的规则。它保存了本仓库过去携带的碎屑文件中的书面说明。这些碎屑文件已于 2026-11-08 移除（Drake：“去掉碎屑”，“保留有效的部分”），但 `evidence/hosted-x86-aien-abi1/.crumb` 和 `evidence/physics0/learner/.crumb` 除外，它们会保留，因为现有证据从不删除。Git 历史记录了谁改了什么。
