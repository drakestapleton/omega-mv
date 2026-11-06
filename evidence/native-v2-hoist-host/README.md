# Combined native-v2 hoist / function-host compiler

IMPLEMENTED and EXERCISED; AArch64 Linux host only. Not merged, installed, deployed, or GPU-qualified. This draft is stacked on `hoist/865-main` at `7286d61d23c2b92ef6606c6b66072335e6a09813`, not a replacement for current omega-mv main.

## Composition

The compiler source is exactly 7286d61d plus #1008's 21-line `hostval` change from `dbc72448cd20798595bccfdab9f3c81e8fe6ee45`. The nine permitted function-mode host words and refusals are unchanged. The original ten host cases and four compiler mutants, their expected output hashes, and the host-check hook were carried with that feature. The loop optimization, its register ceiling, and gate19 are unchanged.

A direct full local merge with #1008 head `2992a68b7a3bc1fa8b322924c3b3e786bebc9ee4` merged the compiler source cleanly, but seed0 bootstrap failed: om4 error 14 at line 17014, `fn xe` (function 513). That merged source had 525 functions, exceeding om4's existing 512-function table; there were also unrelated pin/generated-file conflicts. `full-merge-failure.log` preserves the observed bootstrap failure. That scratch merge was abandoned. This bounded backport avoids bringing the unrelated newer compiler functions onto the hoist branch; no seed capacity or test was weakened.

Combined source sha256: `9ef9831bf9a3e27947bbfab13bf607d024c973bba5630a75f7c26dde706a9b30`.
Combined seeded `seed/out/omc` sha256: `c6a9c71f3a00cbe5d3aa53a79b7540492efee6180d45aee40ebfc4762628cac0`.
The source contains 16834 lines and 510 functions. The binary has 524936 bytes. Ledger arithmetic: `WolframLanguageEvaluator: (524936 - 176)/4 -> 131190` instruction words.

Current compiler-consumer digest pins were moved from 07820046 to c6a9c71f, and generated bindings were regenerated with their existing pinned bridge `431fff0a95f84c0a8bf9d3383f94d7e1f02d913e` (`src/native.om` sha256 `c77a5922f91d53d4a0bbd4e7b1c4703f7098263abc843be2918db1ece7496782`). Historical receipts were not changed.

## Actual commands and results

Every compiler, executable, caller and mutant ran inside:

```
bwrap --dev-bind / / --dev /dev --proc /proc -- taskset -c 10-14 nice -n 10 COMMAND
```

Commands from this candidate tree:

- `sh seed/omega-from-seed.sh`: rc 0, final `RC=0` (`bootstrap.log`). Seed0 -> hex1 -> asm2 -> om4, then om4/self/self rebuilds byte-identical.
- `sh seed/omc/gate19.sh`: rc 0, final `PASS gate19 14 cases, 9 mutants caught, f1, register scan, fuzz 64` (`gate19.log`).
- Compile `seed/qualification/om2/gate.om` with `seed/out/omc` into `build/seed/fnhost-gate`: rc 0. Then `build/seed/fnhost-gate seed/out/omc c6a9c71f3a00cbe5d3aa53a79b7540492efee6180d45aee40ebfc4762628cac0 seed/omc/om2/fnhost/fnhost.cases build/seed/combined-fnhost`: rc 0, final `OM2GATE PASS cases=10 pass=10 fail=0 invalid=0 not_run=0` (`fnhost.log`). The actual scratch argument was absolute and is recorded in the log.
- The same conductor and digest with `seed/omc/om2/fnhost/mutants.cases build/seed/combined-fnhostmut`: rc 1 **as required**, final `OM2GATE FAIL cases=8 pass=4 fail=4 invalid=0 not_run=0` (`fnhostmut.log`). All four controls pass; all four semantic mutants are caught.
- `OMEGA_OMC=<this tree>/seed/out/omc OMEGA_BRIDGE=<pinned bridge source> sh om/units.sh`: rc 0 (`regenerate-units.log`). With `--check`: rc 0, final `PASS src/{omega_om_units.c,omega_native.h,omega_api_decl.h,omega_om_units.ident} regenerate byte for byte` (`check-units.log`).

## Unchanged bridge gate

`combined-v2.log` exercises the **unmodified** script body from omega-bridge `758d74aadf465ed5d4b3c80d798615c8ed4e18f8:tests/native/v2/run.sh` (blob `ec7aca4826001c2f0e53fa0717f0f9024ad13b8d`, also identical on main 3d01b49 and #73 79e8c36). Its original path is passed as `$0` when evaluating the script, so fixtures/output/generator resolve in the bridge checkout. No expectation, hoist assertion, scanner check, or mutant was edited.

Environment:

```
PATH="$HOME/.cargo/bin:$HOME/.local/opt/zig-linux-aarch64-0.13.0:$HOME/.local/opt/go-1.27.3/bin:$PATH"
OMEGA_NATIVE_OMC="$HOME/work/cudastack/lanes/bh-tools/omc-native"
OMEGA_NATIVE_OMC2=/tmp/bridge-v2-profile/omega-hoist/seed/out/omc
```

Generator compiler sha256: `734f0a39319fbfa930bcc62cb30dbf06d47d78e126372b74f5baf478e6126b61`. The combined compiler alone compiles both hoist units and host fixtures. Full gate rc 0, final `NATIVE-V2 PASS (not run: none)`. All language callers run; decoded hoist writes x20..x26; normal scanner rejects the parenthesized host word with 110; `hscan-off` mutant is caught by accepting it with 0. This is behavior evidence, not merely compiler success.

Qualification ran before the evidence commit; the exact compiled source is bound by the source and binary hashes above. Paths in captured logs replace the home-directory prefix with `~`; other output is retained. `bootstrap.log`, `gate19.log`, and `full-merge-failure.log` copy the complete short tool-delivered stdout; the other logs are subprocess captures.

NOT_RUN: full omega-mv host/C-oracle suite, unrelated accelerator backend gates, chip/hardware qualification, deployment. No live model, GPU lock, driver or port was touched. The bridge-side repair keeps separate pinned compiler roles until an upstream combined compiler is reviewed and merged.
