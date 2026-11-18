# Folders: what each one is for

These notes were kept from the retired crumb files (Drake, 2026-11-08: "get rid of crumbs",
"keep the parts that worked"). They are plain notes: nothing generates or checks them. If a change
makes a note wrong, fix the note in the same change. Folders with no written note are not listed.
Two crumb files already under evidence/ stay, because existing evidence is never deleted; their notes are still listed here.

## `bench/inference_cost/`

Held-out inference-cost benchmark: evaluate verified programs produced per unit of inference cost; `handover.om` decides from its run records whether a candidate model takes over a job (no real handover decided yet)

## `bench/omc_efficiency/`

OMC-EFF fixed efficiency protocol for the seeded Omega compiler (PROTOCOL.md; PROTOCOL-2.md in-process runtime metric; PROTOCOL-3.md OM-2 source profile; PROTOCOL-4.md Omega drivers and corrected control and exit checks): seven scalar kernels with C twins and committed OM-2 variants, Wolfram-computed expected outputs, the Omega measurement conductor, its coordinator and its self-test

Rules:

- PROTOCOL.md, PROTOCOL-2.md, PROTOCOL-3.md and PROTOCOL-4.md are frozen at their commits; any change to cases, arms, rounds, seeds, metrics or rules is a new protocol version, never an edit
- want/*.out values are computed by Wolfram independently of both compilers; never regenerate them from a compiler's output
- the conductor computes no statistics and never reruns a case to select a result
- kernels/om2/CASE.om is kernels/CASE.om plus one om2 line and out spelled obuf, checked by run.om and never generated at run time
- the drivers are Omega (conductor.om, run.om, selftest.om); a control counts as detected only on a valid run whose output differs, and run exits 1 when any conductor invocation fails

## `bench/prime_race/`

AIEN Prime Drag Race implementation side: the shared protocol helper (command line, timed loop, report, canonical bitmap export) and the conventional CPU baseline sieve that other entries are checked and compared against

Rules:

- canonical bitmap format is the contract; never reuse previous pass results; no CUDA symbols in AIEN binaries

## `bridge/cuda/`

The CUDA compatibility profile slice: one slice of CUDApp `compat/` at `84b524ca` (its `compat/cuda/` profile), written in Omega only: the profile checker (`c0_check.om`), the frozen profiles, the fixture writer that makes the PTX, the link-only `libcuda.so.1` stub and synthetic executables (`fixture.om`), and the gate (`gate.om`, step `bridge-cuda`) that replays CUDApp's `test.sh`. See its README.

Rules:

- the profiles and `c0_check.om` are byte copies of CUDApp's, pinned by `copied.tsv`; v1 and v2 are history and never edited
- `test-sh-84b524ca.txt` and `fixture-*.tsv` are outputs of the old implementation, never retyped; only the oracle tier (CUDApp checkout and old omc given) checks gcc's builds and transcript lines 1 and 2
- no C, Python or shell in this directory; the C test application stays in CUDApp as the foreign program under test

## `bridge/nvml/`

The NVML library slice: one slice of CUDApp `compat/` at `84b524ca` (its `compat/nvml/` files). `libnvidia-ml.c`, `nvml.h` and `libnvidia-ml.map` are omega-bridge output of `gpu/nvidia/native/nvml/api.om`, so they are listed as derived in `derived.tsv` and not stored; the gate (`gate.om`, step `bridge-nvml`) makes them again with a pinned omega-bridge generator and compares digests. See its README.

Rules:

- nothing generated is stored here; a derived file is a row of `derived.tsv` (source, generator and output digests)
- the omega-bridge generator is an input pinned by digest, never a copy in this tree

## `bridge/shlib/`

AArch64 Linux shared libraries written by Omega alone: `shlib.om` turns omc's object-mode output (`OMOBJ001`) and a table into an ELF shared object (no C compiler, assembler or linker), and writes a probe executable that loads it through the system's dynamic loader. Libraries can need other libraries, import C functions, keep state between calls and run every call under a lock. `test.om`, `dep.om` and `imp.om` are the gate's test units; `nvml.om` is CUDApp's libnvidia-ml.so.1 with real bodies over `gpu/nvidia/native/nvml/`, and `nvrmfake.om` with `rmfake.om` (CUDApp's RM fake, unchanged) is the transport the gate runs it against. `ampqmd.om` is CUDApp's `src/omega_ampere_qmd.c` as `libomega-ampere-qmd.so.1`. `README.md` says what works and its limits.

Rules:

- only Omega source and its tables; C and `gcc` checks run outside the tree, and the gate runs `readelf` only as a read-only oracle
- every change keeps `tests/gates/run.sh shlib` passing with all its controls caught

## `docs/autodiff/`

M21 OMEGA_AUTODIFF scope, op and error-contract table, status (not qualified)

## `docs/dual/`

DUAL (ARCH-0031) documents in omega: applicability experiment method and findings (APPLICABILITY_EXPERIMENT.md). Experimental; no production gate.

## `docs/reservoir/`

Reservoir reference and contracts (omega#440): RESERVOIR_REFERENCE.md pins the authors' paper and code, lists discrepancies, declares the Gate 2 contract and benchmark protocol before any run, and reports the results; gate2_config.json is generated by res_qualify config and checked for drift.

## `docs/tensor/`

M20 OMEGA_TENSOR spec and qualification checklist

## `evidence/hosted-x86-aien-abi1/`

Seed0-born exact ABI1 plus hosted-x86 superset CPU qualification; no GPU or driver execution

## `evidence/physics0/learner/`

Immutable receipts of learner development runs (seeds 1..5 per level, HOLDOUT/TRIAL/REP withheld by the harness). New files per cut, never rewritten.

## `gpu/`

Omega GPU, the GPU layer of Sovereign Intelligence (SI) (aien-architecture-mv ADR 0047): one directory per back end (`gpu/amd/` so far), moved here from CUDApp one piece per landing with the history of its Omega files. `gpu/README.md` gives the layout.

Rules:

- only Omega source and the data tables its units read; a C, Python, shell or other file is rewritten in Omega first or stays out (Drake, 2026-11-14: "make sure it's pure omega"); for AMD, `gpu/amd/NOT-YET-OMEGA.tsv` lists each such file and its class, generated by `gpu/amd/rest/classify.om`, never typed
- every unit is built by this repository's own `seed/out/omc`; a back end carries no compiler pin of its own and its gate refuses any other compiler
- `gpu/<vendor>/card.tsv` records the bytes the receipts record (what ran on hardware, and host-built references marked `host`), written once from the receipts it names; never regenerated from a build
- `gpu/<vendor>/import/` is the record of a move (command, commit map); never edited after the landing that wrote it
- receipts stay in CUDApp where they were written; new receipts are written in this repository's `evidence/`

## `gpu/amd/rest/`

One slice of the AMD back end: the checks that CUDApp `84b524ca` ran in C, Python, shell and LLVM assembly, written in Omega: `gate.om` (step `gpu-amd-rest`) replays the verdicts those checkers recorded against the Omega-built units, `classify.om` writes `gpu/amd/NOT-YET-OMEGA.tsv` from `classes.tsv`. See its README.

Rules:

- the `*-verdicts.tsv` and `llvm18-sections.tsv` tables are outputs of the old checkers, generated by the oracle scripts named in their headers and the README, never retyped; a case not replayed is a `notrun` row with its reason
- `gpu/amd/NOT-YET-OMEGA.tsv` is regenerated by `classify.om` when `classes.tsv` or the CUDApp tree changes; a CUDApp AMD path no rule covers fails it
- no C, Python or shell here; the old checkers stay in CUDApp as the oracles that recorded the tables

## `gpu/amd/bench/barrier/`

Host micro-benchmark for a gfx942 grid barrier against an AQL dispatch barrier. `gate.om` is the program (compiled with `gpu/amd/gfx942/exec/fma.om` by `seed/out/omc`). `seq.s` and `seq.enc` are the data tables that program feeds to `llvm-mc-18` and compares. It does not submit a packet. `README.md` has the command; `CAPABILITY.md` is the list of operations Omega cannot express yet.

## `gpu/nvidia/`

The NVIDIA units of Omega GPU, the GPU layer of Sovereign Intelligence (SI) (aien-architecture-mv ADR 0047), moved from CUDApp with the history of their files. Step 2 brought the five seeded-Omega units Omega NG pins (`seed/ng/cudapp.lock`): the sm_121 encoder ng pins (a different file from the top-level `om/encoder/bw_enc_sm121.om`, which the Makefile uses), the allocator, the cubin writer, the Blackwell launch unit and the nvrm context unit. Step 3 brought the rest of CUDApp's `om/` tree to `gpu/nvidia/om/` and step 4 the rest of its `native/` tree to `gpu/nvidia/native/` (their CUDApp layout kept). `gpu/nvidia/README.md` and `gpu/UNITS.md` say what is here and what is still in CUDApp.

Rules:

- only Omega source (Drake, 2026-11-14: "make sure it's pure omega"); anything else is rewritten in Omega first or stays in CUDApp, listed in the README
- the bytes of the five pinned units are checked by `seed/ng/gpu/gate.cases` against the digests in `seed/ng/cudapp.lock`; a change to one is a re-qualification of that gate, never a silent edit
- `gpu/nvidia/import/` and `gpu/import/` are the records of the moves (command, commit map); never edited after the landing that wrote them
- every unit in `gpu/units.tsv` must compile reproducibly with `seed/out/omc` (`tests/gates/run.sh gpu-units`); the table is written from CUDApp `om/units.sh` and the moved `native/` programs, and changes only with the units it lists

## `gpu/nvidia/driver/`

New Omega for decision logic still written in C in CUDApp `nvrm/` and `m16/` (84b524ca), not a move: card selection, the class-list marshalling, the GPFIFO retire window, the `/proc` readers and failure messages, the M16 marker wait, the enqueue bound and slot search, the extra-channel guard, the copy, allocation-size and VRAM checks. Its gate (`tests/gates/run.sh gpu-driver`) compares it with `oracle-cases.tsv`, printed by a C oracle kept outside the tree. `coverage.tsv` says where the logic of every C function of those directories lives. See its README.

Rules:

- `oracle-cases.tsv` is output of the old C, never retyped; regenerate it with the oracle the README names (sha256) and change it only with that oracle
- the parts are joined in the order of `parts.txt`, not listed in `gpu/units.tsv`
- `coverage.tsv` is generated by the generator the README names, never edited by hand
- no C, Python or shell in this directory; the oracle, its mutation controls and the coverage generator stay outside

## `gpu/runtime/`

One slice of the work on CUDApp `src/` (the C runtime, `84b524ca`), not its move: the inventory of every CUDApp `src/` file against this tree (`inventory.om`, its input lists and its committed output `INVENTORY.tsv`), the Omega rewrites done so far of files without an ident record (listed in `rewrites.tsv`; `scanref.om` replaces CUDApp's `src/omega_gpu_scan_ref.c`, not this tree's own `src/` copy), and the gate (`gate.om`, step `gpu-runtime`). See its README.

Rules:

- only Omega source and the tables it reads; the old C stays in CUDApp, and the oracle drivers that run it are kept outside the repository by the lane that wrote them, identified by sha256 in the README
- `INVENTORY.tsv` and `check/*.expect.txt` are outputs, never typed: the first is regenerated by `inventory.om`, the second by the oracle
- a rewrite adds its row to `rewrites.tsv` and a `checks.tsv` row whose parts include the Omega file; the gate fails a rewrite with no such row

## `gpu/nvidia/checks/`

Omega checks for part of CUDApp `tests/` and `tools/` (one slice of porting them, not the whole port), each with its table of expected values, their gate `OMEGA-GPU-CHECKS` (`tests/gates/run.sh gpu-checks`), and `INVENTORY.tsv`, which lists every file of CUDApp `tests/` and `tools/` with its status. `README.md` says what each check covers and what it does not.

Rules:

- only Omega, tables and Markdown; the C oracles that wrote the tables are kept outside the repository by the lane, identified by sha256, with their build line in `README.md`
- a table is the output of its oracle at the CUDApp commit its header names; regenerate it, never retype a value
- `ports.tsv` is the only hand-written input; `INVENTORY.tsv` is written by `inventory.om` from it, a CUDApp checkout and the `gpu/` file list, and the gate fails when it disagrees with `ports.tsv` or names a `gpu/` file this tree does not have
- every check has a table control, every row of `mutants.tsv` must compile and be caught, and a FROM must match exactly one line of its part

## `gpu/spirv/` and `gpu/hw/`

Seeded-Omega programs moved from CUDApp `backend/` (ADR 0047, step 3): the SPIR-V kernel builder and its bit-exact host reference (`gpu/spirv/emit.om`, `conform.om`), and `hwman`, the hardware capability manifest (`gpu/hw/*.om` with the table `gpu/hw/manifest.tsv` it reads). Their run-time checks are still shell and C in CUDApp; here they are compiled by `tests/gates/run.sh gpu-units`.

## `kernel/`

Aienux, the kernel of AienOS, folded into omega-mv with its history (Drake 2026-11-17) from aienux main `1f12818d`: the C kernel (`native/kernel/`), the other native suites, the Rust crates under `crates/` with their vendored dependencies in `vendor/`, scripts, tools, docs and aienux's own evidence, in aienux's layout. `kernel/MIGRATION.md` says how it came, what was left out and why, and what the fold changed; `kernel/import/` is the filter-repo record. `kernel/AGENTS.md` and `kernel/README.md` are aienux's files as they were at the fold.

Rules:

- the kernel compiles Omega with this repository's `seed/out/omc`, checked against `seed/out/omc.sha256`; it has no compiler pin of its own (aienux's `PIN` and `REPIN` are gone)
- the kernel's gates run from `kernel/` through `kernel/tests/gates/run.sh`; `tests/gates/run.sh kernel` runs six steps from the omega-mv root: `make test` of `native/kernel`, `ck-host-tests`, `hw-gates`, `omega-nvme`, `tcp-corpus` and `spinlock`
- every gate aienux had reaches omega-mv's judge through `tests/gates/omega-kernel-<step>.gate`, which runs `tests/gates/run.sh kernel-<step>`, or is listed with its reason in `kernel/MIGRATION.md` ("Aienux gates without a manifest"); `kernel/tests/gates/aienos-*.gate` are aienux's manifests, kept as history and read by no judge here. OMEGA-KERNEL-GATE-WIRING (`kernel/scripts/omega_gate_wiring.sh`, always-run) fails when one has neither; OMEGA-KERNEL-CRYPTO-BOUNDARY is always-run, as aienux's was
- receipts in `kernel/evidence/` are kept as written, as under `evidence/`: the `evidence-immutable` step (`tools/evidence_immutable.sh`) checks `evidence/`, `kernel/evidence/`, `kernel/import/` and aienux's other receipt folders, `kernel/native/om/lm1b/evidence/`, `kernel/native/net/receipts/` and `kernel/docs/design/boot/receipts/`, against the base, the commit that brought `kernel/` in and the commits after it; with a base ref that has no `tools/evidence_immutable.sh` (origin/main until the fold lands there) its `kernel/` part is NOT_RUN [ctl:OMEGA-EVIDENCE-IMMUTABLE/kernel-base-without-script]. It does not check the other folders named `evidence/`: `om/evidence/`, `om/quantity/evidence/`, `native/control/evidence/`, `research/om-bench/evidence/`, `seed/ng/bench/evidence/`, the `evidence/` folders under `seed/qualification/`, and the gate fixtures `tests/visor/fixtures/evidence/` and `kernel/tools/hwgates/fixtures/evidence/` (the last is a gate anchor, see `tools/`). An aienux hash in a receipt stays the aienux hash, and `kernel/import/commit-map` gives its commit here
- `kernel/import/` is the record of the move; additions only (the same check), never edited after the landing that wrote it

## `native/`

Handwritten .om units of omega-mv that are not part of the seed ladder: the ORIG-4 shadow advisor (native/orig4).

## `native/autodiff664/`

Bounded native .om reverse-mode tape (rank 2, f32, 32 nodes) over M20 metadata-v1; E1-tile reductions and C M21 accumulation order (#664, not qualified)

## `native/orig4/`

ORIG-4 shadow advice for the matvec arm chooser (omega-mv#731, spec/shadow-advice-v0.md): shadow.om advisor unit, shadowmain.om entry, orig4.pin, immutable ORIG-2 candidate images. Default off; advice only, never a decision.

## `native/orig4/candidates/`

Immutable ORIG-2 candidate checkpoints (aien-train evidence/SI19-ORIG2/candidates, byte-identical; SHA256SUMS) scored by the ORIG-4 shadow advisor. Never edited; a new candidate is a new file.

## `neuralese/`

Bounded untrusted representation envelopes and explicit checked Omega decoding; learned extension remains proposed

## `neuralese/fixtures/`

Independent SHA-256 envelope fixtures and exact decoded-source oracles for the native Omega host conductor

## `om/tls/`

TLS 1.3 client (chacha20-poly1305, aes-gcm, x25519, P-256/RSA signatures, X.509 path validation) in seeded Omega with its KAT, DNS, interop and mutant suites

## `research/atemporal/`

AT-0 Clock-Free Universe research program: relational (Page-Wootters) quantum models with no external time parameter; contracts live in aien-architecture docs/plans/atemporal

## `research/atemporal/at0/`

AT-0 V1: finite clock plus one qubit under the AT0_CASE_V1 / AT0_RESULT_V1 contracts

## `research/atemporal/at0/evaluator/`

Agent 4 independent adversarial evaluator for AT-0: independent AT0_CASE_V1 codec, exact-arithmetic AT0_RESULT_V2 checker, long-double shadow oracle, 25 planted-defect mutants, 59-case public corpus, hidden-set commitment, isolation gate, qualification harness (run.sh) and machine-readable results

## `research/atemporal/at0/integration/`

AT-0 Agent 5 integration runner, exact result assembler/judge, hygiene and isolation controls, and the first-run qualification report

## `research/atemporal/at0/model/`

Agent 3 candidate relational quantum engine in portable C11: state, Hamiltonians, constraint kernel, clock POVM, conditional states, Pauli probabilities, versioned case input and engine output

## `research/atemporal/at0/model/tests/`

Component tests and case files for the candidate engine

## `research/atemporal/at0/model/tests/cases/`

AT0_CASE_V1 case files used by the tests; the KAT file is the contract section 6 example byte for byte

## `research/atemporal/at0/oracle/`

AT-0 reference oracle (Rust, standard library only, built by rustc directly; research cross-check, not part of active execution): AT0_CASE_V1 parser, direct-matrix and analytic paths, exact judge, AT0_RESULT_V2 writer, tests, isolation gate

## `research/atemporal/at0/oracle/fixtures/`

Deterministic AT-0 oracle calibration fixtures: case files, computed values/verdict blocks, CALIBRATION.md

## `research/atemporal/at1/evaluator/`

AT-1 Agent 4 adversarial evaluator: independent AT1_CASE_V1 codec, exact-arithmetic AT1_RESULT_V1 / AT0_RESULT_V2 verifier with exact shadow model, runner splice, 95-file public corpus (12 positive, 12 negative, 71 refusals), mutant kill receipt, isolation gate with controls, 27-case hidden-set commitment, qualification harness (run.sh)

## `research/atemporal/at1/integration/`

AT-1 Agent 5 integration runner (run.sh), engine and oracle shims for the evaluator, contract pin, and the qualification report

## `research/atemporal/at1/oracle/`

AT-1 reference oracle (Rust, standard library only, built by rustc directly; research cross-check, not part of active execution): AT1_CASE_V1 validator, exact level kernel, literal matrix route plus closed-form and Bloch references, exact judge, AT1_RESULT_V1 oracle-record writer, tests, isolation gate

## `research/om-bench/`

om-bench (#653): frozen measurement contract, family-disjoint task splits, oracles, controls and runner for agent-written Omega

## `seed/agent/`

Seeded Omega coding agent omagent (nanobot-style): agent loop, permissioned tools, JSONL session memory, SSE model streaming, CLI; scripted-mock test referee and nanobot benchmark

Rules:

- Every implementation byte is seeded .om compiled by seed/out/omc; Python under tests/ and bench/ is a test-only referee or mock
- The model is untrusted: its output is parsed by json.om/http.om under fixed caps and a malformed reply runs nothing
- Tool permissions come only from the operator's command line; the default is read_file inside the workspace
- The API key appears only in the Authorization header, never in stdout, stderr, the session file or a child environment
- Tests and benchmarks bind 127.0.0.1 with kernel-chosen ports only and never contact port 18091

## `seed/agent/bench/`

Test-only equal-work benchmark of omagent against nanobot reduced to the same four tools: scripted streaming mock, paired interleaved driver, nanobot launcher.

## `seed/effects/`

Effect-derived capability manifest in seeded Omega: host-word manifest, ELF syscall check, seccomp cBPF, with probe-parity, strace and bwrap oracle gate

## `seed/equiv/`

Seeded Omega exhaustive u8/u16 equivalence checker for OSC IR v1 scalar functions (issue 826)

## `seed/json/`

Strict RFC 8259 JSON reader, writer and optional exact binary64 conversion in seeded Omega, with CPython-oracle parity gate (omega-mv #788)

## `seed/net/`

Seeded Omega network protocol libraries: bounded HTTP/1.1 server and client (http.om) with chunked bodies, keep-alive and server-sent events, embeddable examples and a host referee (omega-mv #788)

Rules:

- Every implementation byte is seeded .om compiled by seed/out/omc; Python under tests/ is a read-only referee
- No globals in http.om: connection state and buffers are caller-owned arrays (cs ulong HCSLEN, io uchar)
- Strict framing per RFC 9112: CRLF only, no obs-fold, Content-Length with Transfer-Encoding refused, only chunked transfer coding
- Every read, write and wait is bounded by a cap, a loop bound or a monotonic deadline; no busy wait
- Tests bind 127.0.0.1 with kernel-chosen ephemeral ports only and never contact port 18091

## `seed/ng/`

Omega NG: the next Omega compiler (Hive NG). Its intermediate form ΩIR (IR.md) with validator, text tools and gate; the ng compiler units (src/, ng.units, ngbuild)

## `seed/ng/front/`

ng-front tools and evidence: the differential gate gate-front.om (front.om against the pinned omc: same refusal line and code, BEYOND_OMC and scope classes, mutants), the ΩIR emission gate gate-front-ir.om (@ng front-ir output through ngcheck and ngrun against the omc binary), the renamer and pruner that made src/front.om from omc.om@943d9555, case lists, fixtures and kernel copies

Rules:

- Every tool here is seeded .om compiled by the pinned seed/out/omc (sha256 5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df); no shell, C or Python
- gate-front and gate-front-ir refuse (INVALID) unless the oracle omc matches the given sha256; they never edit seed/omc/omc.om
- gate-front-ir passes only when every run case agrees (ngcheck ACCEPT; ngrun equal to the omc binary on exit status and stdout), every refuse case keeps omc's exit and stderr, and every lowering mutant and mode control fails a case
- declared.txt holds only beyond (omc refused with 12, 14, 24 or 25 for a code generator limit, D6) and scope (x86/EFI, IR v1, om2 fmt: exit 64) rows, each with its reason; a declared row no case uses is a FAIL
- Every mutant in mutants.txt must be KILLED by a real case failure; a SURVIVED mutant fails the gate
- No committed copy of the whole omc.om: src/front.om carries only the front end, with no machine code emission

## `seed/ng/front/cases/`

ng-front fixture programs for gate-front: f64 rem/and/or/xor refusals and the gate15 refusal cases that error-codes.reg names (D9)

## `seed/ng/front/kernels/`

ng-front copies of the ten ng-bench kernels, the run cases of gate-front-ir (omc binary against ngrun on ng's @ng front-ir output)

Rules:

- Each .om is a verbatim copy of the ng-bench kernel of the same name; its sha256 is listed in PROVENANCE.md and equals ng-bench's PROVENANCE.md; a changed kernel is a new name

## `seed/ng/front/mutants/`

ng-front mutant pairs for gate-front: NAME.from text that occurs exactly once in src/front.om and the NAME.to text that replaces it; each mutant must be KILLED

## `seed/ng/src/`

The ng compiler units listed in ../ng.units and built into the one ng binary (D1b): ir.om (ΩIR in memory, ng-ir), front.om (Omega source checks, ng-front), main.om (modes, ng-ir)

## `seed/nki/`

Seeded Omega OSC IR v1 elementwise scalar to AWS NKI (nki.isa) kernel emitter with NKI CPU simulator interop-oracle verification

## `seed/node/`

Bounded shared-memory artifact transport for cooperative Omega workers

## `seed/omc/contracts/`

Executable native contract fixtures, C oracle parity, release erasure and enforcement mutant

## `seed/profile/`

Critical source profile (DRA-419) in seeded Omega: Power-of-Ten rules B1 B2 B3 E1 X1 P1 C1 over .om units, fixtures, checker mutants, authority-module check

## `seed/qualification/security673/`

Issue #671 packed-list hostile-ingress campaign: corpus generator, execprog consumer and OM-2 conductor cases run by seed/host/check.sh.

## `seed/qualification/security673/packets/`

Packed-list fixtures for #671: generated packet bytes (proven equal to packet-corpus.om), expected echo output, and exact-once compiler substitutions for the bound mutants.

## `seed/spirv/`

Seeded Omega OSC IR v1 to SPIR-V OpenCL Kernel backend with CPU differential verification and demo

## `seed/stablehlo/`

Seeded Omega OSC IR scalar unit to StableHLO MLIR, verified on IREE and XLA CPU PJRT interop oracles (Google TPU path)

## `seed/tensix/`

Tenstorrent Tensix RV32IM vecadd: seeded Omega emitter irrv32.om (OSC IR v1 -> RV32) and asm2 table, interop-oracle gate (ttsim WH/BH, qemu, two disassemblers)

## `seed/wasm/`

Seeded Omega OSC IR v1 scalar to WebAssembly MVP backend with host differential verification

## `src/ans/`

ANS (Alignment Navigation System), Inertial Alignment v1: frozen reference atoms, drift filter over EST-1, three sensor classes, autonomy tiers, promotion gate. Advisory only: measures and recommends, never grants, revokes or promotes (ARCH-0017 shape); the candidate never receives a mutable reference. No allocation, globals or I/O.

## `src/autodiff/`

M21 OMEGA_AUTODIFF: reverse-mode tape over M20 tensor CPU ops, caller-owned nodes and scratch, per-op error contract, flat float32 gradients for M22 (not qualified)

Rules:

- never edit src/tensor or src/train from here; tensor API needs are filed as change requests in docs/autodiff/M21_OMEGA_AUTODIFF.md
- no heap allocation and no global state in src/autodiff
- every MUT: marker must stay in tools/autodiff_mutations.sh

## `src/dual_experiment/`

DUAL applicability experiment library (ARCH-0031 offline evidence lane): deterministic discrete workload simulator with exact ledger, aggregate flow-balance predictor, heterogeneity measurements, campaign driver, digests. Pure calculator: no I/O, no allocation, no globals; nm -u purity check. EXPERIMENT ONLY, never linked by src/runtime/.

## `src/osh/`

osh (Omega-native shell, arch#158) lexer unit: layout list, generator, osh_lex.osc, C reference tokenizer

## `src/osh/host/`

osh Linux host: execution service (request decoder, resolution, builtins, redirections, pipelines), unit loader, driver loop and main for the osh program (arch#158; replaceable scaffolding per ADR 0024)

## `src/physics0/`

PD-0 hidden-equation benchmark (Physics-0 Discovery Engine cut 1): world, oracle, scorer, ladder checker, planner, learner. Generators live only in pd0_gen.c; learner objects must never link it.

## `src/physics0/controls/`

PD-0 controls: see docs on physics main

## `src/physics0/ladder/`

PD-0 ladder: see docs on physics main

## `src/physics0/learner/`

PD-0 learner (Physics-0 Discovery Engine D4): fits compact one-step relations over a bounded monomial vocabulary from FIT/SELECT records only; emits candidates, correlation evidence and preregistered experiments for the independent ladder checker. Links only ladder/pd0_fmt.c and sha256; never the generators, the world, file I/O or a level identity (p0l-isolation).

## `src/physics0/learner_v2/`

PD-0 learner v2 (G3): seal-1 learner plus 20-step SELECT rollout ranking, rollout hidden-state flag and an injectable prior. New version; src/physics0/learner stays frozen.

## `src/physics0/regime/`

Dev-only PD-0 regime switch: redraws the world constants from the declared ranges at an episode boundary. World side, links the generator; never sealed runs.

## `src/physics0/score/`

PD-0 score: see docs on physics main

## `src/reservoir/`

Ionic-droplet reservoir simulator (omega#440): binary32 fixed-step RK4 of the authors' droplet model, refusals instead of silent repair, run receipts, binary64 ridge readout. CPU only; the reference and contract are docs/reservoir/RESERVOIR_REFERENCE.md.

## `src/synapse/`

Synapse ADR 0003 J1 binary codec port: layout list, generator, syn_codec.osc (A1 WAL records + checkpoints, strict decode, typed refusals)

## `src/tensor/`

M20 OMEGA_TENSOR: immutable tensor semantic layer, views, generation-checked storage, CPU realization over E1 (not qualified)

## `tests/ans/`

Tests 1-10 for ANS (docs/ans/INERTIAL_ALIGNMENT_SPEC_V1.md): freeze/digest, hostile reference mutation, drift growth, FIX restore, IMU limit, disagreement, refusals, promotion gate, encodings with golden digests, self-modification. Run with make test-ans (plain + ASan/UBSan).

## `tests/autodiff664/`

Native tape tests: differential checks, refusals, no-FMA control, compiled source mutants of native/autodiff664/tape.om

## `tests/dual_experiment/`

Tests for the DUAL applicability experiment: determinism (same seed, byte-identical results digest), exact ledger at every step, predictor finite and bounded, shuffled and constant negative controls, pinned parameter digest. Run with make test-dual-applicability (plain + ASan/UBSan + purity).

## `tests/numeric_native/`

Simulated M16 driver for numeric resource-lifecycle tests. No device execution or numeric parity evidence.

Rules:

- Never link this driver into production executables.

## `tests/orig4/`

ORIG-4 shadow advisor tests: shadow-test.om (in-process checks over the SYNTHETIC fixture and the real candidate) and run.sh (POSIX sh glue sequencing pin checks, compile, fixture, refusals, budget, default-off proof; gate omega-orig4-shadow).

## `tests/osh/`

osh lexer host driver, vendored aien-protocols PR#16 draft vectors (5ae5292)

## `tests/osh/e2e/`

end-to-end tests of the osh program: argprint helper plus a runner comparing native and OSH_INTERP=1 (arch#158)

## `tests/osh/host/`

tests for the osh Linux host adapter execution service (hand-built request records, helper-mode test binary)

## `tests/osh/trace/`

Core-only step traces of the osh shell units over fixture scripts (OSH-AIENOS-0 differential fixture); .trace files are generated by make osh-trace-gen

## `tests/physics0/`

PD-0 gates: world self-test, oracle calibration, learner L0/L1/NULL, mutations, OSC differential, isolation check.

## `tests/physics0/learner/`

Learner gates: unit tests (determinism, PDLAW1 round trip, memoriser vs compact theory, null world, withholding), the development harness that drives pd0-world and the test-only truth process over pipes, tags the split, builds the PD0LEDG1 ledger and scores against the truth. The truth process is the only binary here that links the generators.

## `tests/physics0/learner_v2/`

Learner v2 tests and dev drivers: unit tests, byte-level dev world, C1 flag, C2 regime switch and C3 prior dev runs; receipts/ holds the text dev receipts (development evidence only).

## `tests/physics0/verify/`

PD-0 verify: see docs on physics main

## `tests/reservoir/`

Reservoir tests (omega#440): Gate 1 simulator and readout checks against an independent binary64 oracle, and the Gate 2 .mat and inflate reader tests; run by make test-reservoir, plain and ASan/UBSan.

## `tests/reservoir/fixtures/`

Two unmodified CC-BY-4.0 files from the authors' Zenodo archive 10.5281/zenodo.17296788 (Length5.mat, Length50.mat), sha256-pinned in RESERVOIR_REFERENCE.md section 11.6, so CI can test the .mat reader without the archive. Data, never code; do not edit.

## `tests/synapse/`

J1 parity driver for syn_codec.osc against the sealed Rust A1 corpus (aien-dev/synapse j1-codec-corpus), interp and native

## `tools/`

Harnesses and gate scripts. `gate_anchor.sh` (OMEGA-GATE-ANCHOR, always-run) reads `gate-anchors.txt`, the list of gate-integrity files (gate scripts, pins, count pins, control lists). A head that changes a listed path against the base ref prints `GATE-ANCHOR CHANGED <path>` and is BLOCKED_OPERATOR until the operator run that writes the landing receipt lists those paths there and sets `AIEN_GATE_ANCHOR_ACK` to exactly them [ctl:OMEGA-GATE-ANCHOR/ack-subset]. A lane that adds or relies on a gate-integrity file sends its path to whoever keeps the list. `evidence_immutable.sh` is the additions-only check of the receipt folders named under `kernel/`.

## `tools/dual_experiment/`

Runner for the DUAL applicability experiment: runs the pre-registered campaign and writes results.csv, params.txt and results.md under evidence/DUAL/applicability/. make dual-applic-run.

## `tools/reservoir/`

Gate 2 tooling for the reservoir (omega#440): in-house zlib inflate and MAT v5 reader, the archived-reference comparison (res_qualify), benchmarks and timing (res_bench), and qualify_reservoir.sh, which writes the content-addressed receipt under evidence/RESERVOIR. No Python; reads the untrusted archive as data only.

## `seed/omc/tests/struct-bool/`

Boolean struct-field execution regressions, exact expected outcomes, scalar controls and deliberate broken-compiler controls. Run by the seeded host gate. Results are kept in unique build directories.
