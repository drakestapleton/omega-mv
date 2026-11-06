# Typed VFIO IRQ/eventfd host receipt

## Identity and scope

- Compiler source base: `397e67040fb74853c6814097fe02ae4e1ebd6f66`, confirmed with DriverOmega against its tools/getomc.sh pin.
- Baseline binary SHA-256: `bcfa582892afca8f65e551fe56867d918d86e84540c7381be8fa9ef18d0cf0f6`.
- Candidate compiler `seed/out/omc` SHA-256: `734bf4f3f858d56288902700cf581cdbaa4a24d1b3254a2beea014aaccf0fa38`.
- Candidate source `seed/omc/omc.om` SHA-256: `3695b2b9ed9298b1073ee0235a2c0b2e7d086406f87f6a5eb19c7546a6c846f4`.
- Branch: `feat/vfio-irq-eventfd`. Exact enclosing commit is supplied by the draft PR; no merge/deployment is claimed.
- This revision has AArch64 Linux VFIO lowering only. It has no hosted x86 VFIO path. Do not mix this profile with the independently pinned BridgeHost context compiler.
- Absolute home paths in logs were replaced by `~`; no other normalization was applied.

## Commands actually run

| Command | rc | Final line | Evidence |
| --- | --- | --- | --- |
| `taskset -c 10-14 nice -n 10 make -j3 build/omegese/omegese build/omega_emit/omega_emit build/checker2/checker2` | 0 | `cc -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc -Isrc/checker2 -DC2_SOURCES_SHA256='"b0c67cbe49be01007a76c875f100c87d53f6836c889959468666694a77e77be7"' -o build/checker2/checker2 src/checker2/checker2_main.c src/checker2/c2_ir.c src/checker2/c2_check.c src/checker2/c2_lrat.c src/checker2/c2_blast.c src/checker2/c2_receipt.c src/omega_om_units.c src/searchtrace/sig/ed25519.c src/searchtrace/sig/sha512.c src/searchtrace/sig/ct.c` | [oracle-build.log](oracle-build.log) |
| `taskset -c 10-14 nice -n 10 sh seed/host/check.sh` | 0 | `PASS native-host qualification; seeded build, C tools are comparison oracles only` | [host-check.log](host-check.log) |
| `taskset -c 10-14 nice -n 10 sh seed/host/irq.sh` | 0 | `PASS typed VFIO IRQ/eventfd host qualification; real device IRQ delivery NOT_RUN` | [irq-final.log](irq-final.log) |
| `taskset -c 10-14 nice -n 10 sh seed/omc/gate18.sh` | 0 | `PASS gate18 162 literal packs and both computed entries match the committed chain` | [keywords-final.log](keywords-final.log) |
| `taskset -c 10-14 nice -n 10 sh -c 'gcc --version; qemu-aarch64 --version; dpkg-query -W linux-libc-dev'` | 0 | `linux-libc-dev:arm64 6.8.0-139.139` | [oracle-versions.log](oracle-versions.log) |
| `taskset -c 10-14 nice -n 10 sh -c 'crumb compile . && crumb verify .'` | 0 | `crumb verify: OK: 164 crumbs current` | [crumb-final.log](crumb-final.log) |

The full host check rebuilt the seed chain and checked stage1=stage2=stage3, scalar IR against independent C oracles, existing compiler/contract cases, all host fixtures/refusals and the original regression corpus. The final IRQ-only gate then added maximum-count/last-payload coverage and the payload-loop compiler mutant without changing compiler source or binary. Full-host logs therefore contain12 IRQ mutants; the final IRQ log contains13. The keyword gate was run again on the final tree.

## Tier verdicts

- **PASS / EXERCISED**: seeded stage fixpoint; compiler SHA above. `host-check.log` records `PASS omc fixpoint` and `RC=0`.
- **PASS / EXERCISED**: typed positive compile cases,10 compiler refusals,15 runtime refusals; exact argsz, count/range/payload/flag and descriptor-kind checks.
- **PASS / EXERCISED**: GCC Linux UAPI layout differential, comparing serialized C and Omega IRQ records byte-for-byte. Measured sizes/offsets and ioctl/flag constants are in `irq-final.log`.
- **PASS / EXERCISED**: real eventfd initial-value, read/write/drain, empty EAGAIN, poll readiness, close/EBADF and registry-capacity behavior.
- **PASS / EXERCISED**: ptrace memfd fixture; real IRQ ioctls return ENOTTY; only GET_DEVICE_FD return is substituted. Covers bind/deassign/disable/mask/unmask,64-eventfd records, invalid last payload, successful/failed dup3 invalidation, close/reuse, high fd numbers and pre-acquisition table exhaustion. It never opens a VFIO or NVIDIA device.
- **PASS / EXERCISED**:13 built compiler mutants killed by the independent runtime oracle. Compiler or fixture build failure is INVALID, not a kill.
- **PASS / EMULATED**: QEMU user-mode VFIO-less refusal and translated real eventfd behavior. This is not a system-emulator VFIO delivery test.
- **NOT_RUN**: real VFIO IRQ delivery, GPU completion, hardware qualification, kernel-module/binding changes. No hardware window was requested or used.
- **NOT_RUN**: x86 host VFIO, because this exact base has no such lowering path.
- **NOT_MERGED / NOT_DEPLOYED**: draft trust-surface change; requires Drake's explicit approval before merge.

## Trust and dependencies

Products contain seeded Omega/AArch64 emission only. GCC13.3.0, QEMU8.2.2, the Linux UAPI headers, the C ptrace/ABI fixture and Python mutation runner are verification-only oracles/orchestration, not product dependencies. Actual package/version output is in `oracle-versions.log`. Existing shell/bootstrap tooling is unchanged except qualification wiring.

Read-only trust review was performed by OmcVfioIrq.IrqTrustReview (resolved model openai-codex/gpt-6-astra). It recommended full-fd keyed slots, reserve-before-acquire, close invalidation, successful-only dup3 destination invalidation, explicit teardown and non-sandbox disclaimers; these are implemented/documented. No consultant implementation was adopted.

WolframLanguageEvaluator: `{128*16,1073741824-128*16,2^64-24,2^32-1}` -> `{2048,1073739776,18446744073709551592,4294967295}` (registry bytes, pool bound, encoded -24 and uint32 maximum). Keyword/flag/record-size query and result are recorded in `seed/host/README.md`.

Harness guidance is pending under [omega-harness#184](https://github.com/aien-dev/omega-harness/issues/184), because this lane's write authority is scoped to omega-mv. No historical receipt was edited.
