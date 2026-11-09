# Omegese profile OM-3: additions after the OM-2 freeze

Status: PROPOSED (draft omega-mv#1008, 2026-10-31). Not frozen. `spec/omegese-om2.md` is frozen and says
"A change after freeze needs `omegese-om3.md`"; this file is where such changes are written. It is
additive to `spec/omegese-om2.md`, its errata and `docs/one_layer/OMEGESE.md`, which stay normative for
everything not stated here.

Coordinator review (#599 language-evolution coordinator L835, card t_d732a0bb, run 349, 2026-11-09, base
omega-mv main `1e3ecbba`): section 0 C2 corrected, every compiler-side claim of section 1 checked against
`seed/omc/omc.om` and the gate `seed/omc/om2/fnhost/` (verdicts in `docs/omegese-om3-review.md`); the
bridge-side sentences are NOT_RUN. The context ABI revision in section 1 is not reviewed into force: it
still needs Drake's decision.

## 0. Opt-in and compatibility

- Each addition below names the units it applies to. Section 1 applies to units whose first line that
  is not a `note` is `om2`; this draft adds no `om3` line. Whether later additions need their own
  opt-in line is open.
- **C1 of OM-2 still holds.** Every OM-1 unit keeps its meaning, error code and line. An addition may
  only turn an OM-2 refusal into an accepted unit; it never changes the output of a unit that compiles
  today.
- **C2 of OM-2 is checked against a declared chain, not against the frozen manifest alone.** The frozen
  manifest `seed/qualification/om2/manifest-c2.txt` does not compile byte-identically at omega-mv main
  `1e3ecbba`: with the seed-born omc `6d1b1cf5` and the #748 conductor `gate.om` it gives 5835 of 5876
  rows (41 failures: 37 byte changes with the expected exit status, 3 former error-14 refusals that now
  compile, 1 error-3 line change; L835 run 300). C2 for an OM-3 addition holds at the addition's base pin
  when, with the seed-born omc of that pin, every row of the frozen manifest matches its frozen value or
  the value in a declared delta manifest, and the declared deltas form a complete chain from the frozen
  manifest to that base pin. A declared delta is a `seed/qualification/om2/manifest-c2-<name>.txt` whose
  header names the compiler pin, the causing commits, a behaviour check per row (same inputs, same exit
  status, stdout and stderr) and a negative control. A row that matches neither is a failure of the chain
  at the base, and an addition may not claim C2 PASS on top of it. At `1e3ecbba` the chain is incomplete:
  29 rows match neither the frozen value nor a declared delta (card t_2d8ccba8, L1041, owns closing it),
  so an OM-3 addition reports C2 as NOT_RUN there, never as PASS.
- **C3 still holds.** The compiler source stays inside om4's language and om4's function limit (512
  functions; `seed/omc/omc.om` has 510 at `1e3ecbba`).

## 1. Host words in function mode (#1008)

- An OM-2 function unit (first line `om2`, no `fn main`) may use the host words `fopen`, `fclose`,
  `fstat`, `stat`, `lstat`, `getuid`, `geteuid`, `getgid` and `getegid` (OMEGESE.md section 10) on
  AArch64 and under `target x86linux`, with their program-mode meaning. On AArch64 the machine code is the
  program-mode save, inline `svc`, restore sequence without the program-mode stack-floor check (a function
  unit has no x28 stack floor), so it is not byte-identical to the program-mode code.
- The same units may use the clocks `monons`, `realns` and `sleepns` and the device words `devctl`,
  `mapnew`, `mapdrop`, `mapread`, `mapwrite`, `devcall`, `uvmctl`, `mapaddr`, `mapget`,
  `mapset`, `maphold` and `mapbind` (`seed/host/MAPPING.md`). Function-mode entry 31
  is a data pointer to a 32-byte capacity/generation header followed by 1..4098
  32-byte owned slots; handles have 13 low slot bits. The bridge supplies an
  explicit context with disjoint generation ranges and serializes its calls.
  Fixed bind can replace only the whole owned PROT_NONE reservation; failure
  unmaps/retires the token if cleanup succeeds. Cleanup failure traps 3 with a
  quarantined owner: bind/read/write refuse; mapaddr/drop remain available,
  and destroy stays busy until drop succeeds. Neither outcome promises to
  preserve a reservation. An absent table pointer may fault, not status 34.
- **Context ABI revision is DRAFT and requires Drake approval before merge.**
  It supersedes the unmerged #1040 raw 128-slot function-mode format, not an
  accepted frozen OM-2 feature. The bridge must reject incompatible mapping
  compiler/runtime fingerprints. Program-mode raw 128-slot tables with eight slot bits,
  pure units and file/identity units stay unchanged; the frozen C2 manifest is judged by section 0.
- In function mode, under AArch64 and under `target x86linux`, every host word other than `read`, `write`
  and the no-system-call barriers `cpufence` and `cpurelax` (OMEGESE.md section 10, accepted in every
  function unit, OM-1 included) is error 9 in an OM-1 function unit; in an OM-2 function unit the same
  holds for every host word outside the two lists above. A function unit under `target x86efi` is error 25
  (that target has no function mode).
- These words do not form a sandbox: a caller that embeds such a unit grants it the file and identity
  view (and, for the device words, the ioctl and mapping view) of its own process, so the omega-bridge refuses a unit that names one unless the caller opts in.
- Gate: `seed/omc/om2/fnhost/fnhost.cases` (22 cases, AArch64, x86linux and x86efi) with the mutants in
  `seed/omc/om2/fnhost/mutants.cases` (12 mutants, each detected), run by `seed/host/check.sh`.
