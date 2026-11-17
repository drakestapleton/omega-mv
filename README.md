# Omega

Omega is a programming language, and a compiler for it that is written in Omega itself. It is the language of
Sovereign Intelligence (SI), my name for the whole stack: the language, the runtime, the GPU layer and the
models that run on them.

The aim is one path a person can inspect from start to finish. A hand-written seed of a few hundred bytes grows,
one small step at a time, into the compiler. That compiler is meant to build everything else, with no step
left as a black box.

This project is unfinished: part of it is still older C code. This page says what works, what is old and what
has not been run yet.

## Where it stands

| Part | Where it stands | Read more |
| --- | --- | --- |
| The compiler, written in Omega | Works. It is rebuilt from the seed and makes programs for 64-bit Arm Linux. | [seed/README.md](seed/README.md) |
| Programs for Intel and AMD processors | Candidate. This project's own checks of the Linux programs ran in an emulator only. One firmware program ran once on a real iMac, recorded in [docs/X86-EFI.md](docs/X86-EFI.md). | [docs/X86-LINUX.md](docs/X86-LINUX.md) |
| Output for web browsers (WebAssembly) and for SPIR-V, a common format for programs that run on graphics cards | In the compiler chain. The SPIR-V output has run on a processor only, not on a graphics card. | [docs/SPIRV.md](docs/SPIRV.md) |
| The GPU layer, "Omega GPU" | Moving here from CUDA++, my earlier GPU project, one piece at a time, as Omega only. | [gpu/README.md](gpu/README.md) |
| Older C code | Still here. Each piece is replaced by Omega and then removed. | [The list of what is left](docs/migration/C-TO-OM-INVENTORY.md) |
| Earlier runtime and numeric results | History. Each one is tied to the exact version in its receipt, the saved record of a check. | [ENGINEERING-NOTES.md](ENGINEERING-NOTES.md) |

The road to version 1.0 is in [docs/ROADMAP-1.0.md](docs/ROADMAP-1.0.md).

## Get a copy

The [project page on Interplane](https://interplane.io/drakestapleton/omega-mv) shows the files, the history
and how to get a copy on your machine.

## Try it

You need a 64-bit Arm Linux machine. The compiler is the file `seed/out/omc`. This writes a three-line
program, compiles it and runs it:

```sh
printf 'fn main to int\nret 7\nend\n' > seven.om
seed/out/omc < seven.om > seven
chmod +x seven
./seven; echo $?
```

It prints `7`, the number the program returns.

To rebuild a fixed, published version of the compiler from the seed on your own machine, and check every step
against published fingerprints without changing any tracked file (this needs a git copy that contains the one
commit the challenge pins; a normal clone has it, a zip download does not):

```sh
sh seed/challenge/run.sh
```

[seed/challenge/CHALLENGE.md](seed/challenge/CHALLENGE.md) names that version and explains what the run
proves. It is an earlier version than the `seed/out/omc` used above. The command that rebuilds today's
compiler from the seed is `sh seed/omega-from-seed.sh`; run it in a spare copy, because it writes into the
project folder.

- The language: [docs/one_layer/OMEGESE.md](docs/one_layer/OMEGESE.md)
- The newer language profile and what it guarantees (detailed, for engineers):
  [docs/one_layer/OM2-TUTORIAL.md](docs/one_layer/OM2-TUTORIAL.md)
- One small program, explained line by line (written for an older version of the compiler):
  [docs/TEACH_OMEGA.md](docs/TEACH_OMEGA.md)

## Core ideas

These are what the project is built toward. The notes under each say how far it has come.

- **Smart is not trusted, and intelligence is not authority.** Trust comes from checks that passed, never from
  how capable something is.
- **Meaning is permanent; the way it is written is disposable.** A program is meant to be named by a
  fingerprint of its written form once the form is tidied, so respellings such as spacing and names share one
  name. Today the older C code computes this name. Programs built with `seed/out/omc` do not get one yet.
  [spec/program-identity.md](spec/program-identity.md) says exactly how far the idea goes.
- **Pure computation is kept apart from effects.** The aim is that anything that changes the outside world
  needs a stated permission and leaves a receipt, a saved record of what was done. Programs built with
  `seed/out/omc` do not produce such receipts yet.

## Rules I keep

- Omega is the only language for new work here. Code in C, Rust or shell that remains is unfinished migration,
  not the plan.
- A claim counts only with the exact command, its result and a fingerprint of what it produced.
- Evidence is never edited or overwritten. Failed experiments stay.
- A result from a run that did not use the target chip, or from an emulator, is never reported as a hardware
  result.
- Results use fixed words: PASS, FAIL, NOT_RUN (the check was not run), BLOCKED_HARDWARE (it needs a machine
  that was not available), BLOCKED_OPERATOR (it needs a decision from me), MISSING_IMPLEMENTATION (the code
  does not exist yet).
- Builds are offline and in-house.

## What is in each folder

| Folder | What it holds |
| --- | --- |
| `seed/` | The compiler chain, from the hand-written seed up to `omc`. |
| `gpu/` | Omega GPU: the code that drives graphics cards, and the checks for it. |
| `spec/`, `docs/` | The language and its documents. |
| `tests/` | The gates. A gate is a check that must pass before a change lands. |
| `evidence/` | Receipts, each tied to an exact version. |
| `src/` | The older C implementation that is waiting to be replaced. |

[FOLDERS.md](FOLDERS.md) covers every folder and the rules each one keeps.

## How it fits with the other projects

- [CUDA++](https://interplane.io/drakestapleton/CUDApp) holds the parts of the GPU layer that have not moved
  into `gpu/` yet.
- [Omega Bridge](https://interplane.io/drakestapleton/omega-bridge) is the compatibility layer. It lets
  programs in other languages call compiled Omega.
- [aien-architecture-mv](https://interplane.io/drakestapleton/aien-architecture-mv) holds the decision records
  and the order of the work.
- Aienux, the kernel of AienOS, the operating system Omega is meant to run on, is folded into `kernel/` here
  with its history (Drake 2026-11-17), from aienux main `1f12818d`
  ([aienux](https://interplane.io/drakestapleton/aienux) served `d01b2f19`, 22 commits earlier).
  `kernel/MIGRATION.md` says how; `tests/gates/run.sh kernel` runs its gates.

## Papers

- [Omega: A Programming Language Built for Verified Programs](https://doi.org/10.5281/zenodo.23547810)
- [The Token Is the Instruction](https://doi.org/10.5281/zenodo.23644702)
- [A Call to Humanity: Breaking the CUDA Stranglehold on the Hardware Market](https://doi.org/10.5281/zenodo.23614483)

Author: Drake Stapleton, [ORCID 0009-0002-6890-7111](https://orcid.org/0009-0002-6890-7111). To cite this
work, use [CITATION.cff](CITATION.cff).

## Human-Directed Agentic Engineering

I set the goals, the architecture, the limits, what counts as done and where to stop. AI agents write the
code, run the checks, find what failed and fix it inside those limits. I stay responsible for every claim and
every release. [CONTRIBUTORS.md](CONTRIBUTORS.md) lists which model did what.

The method is described by Gregory M. Kurtzer in
[*Ginux: Building an Independent Kernel That Runs Linux Userspace through Human-Directed Agentic Engineering* (2026)](https://doi.org/10.5281/zenodo.23682548).
I cite it for the method only. It does not change authorship or the qualification of earlier experiments.

## Contributing

The way to send a change to this project through Interplane is still being built. Until it is ready, write to
aien@aienos.com. Bring the exact command you ran and what it printed, for the exact version you changed.
Receipts name the exact commit and refuse a dirty tree, and existing evidence is never edited in place.
Someone who did not write the change reviews it before it lands.

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## For engineers

The detailed notes that used to be on this page are in [ENGINEERING-NOTES.md](ENGINEERING-NOTES.md): the full
state of each part, the checks for the older C code, and how the host checks behave on a busy machine.
