# seed/explain: refusals in words

`explain` is a small Omega program (`explain.om`, OM-2 profile) that runs the seeded compiler on one
source file and, when the compiler refuses it, says why in a sentence and shows the line:

```
$ seed/out/omc < seed/explain/explain.om > explain && chmod +x explain
$ ./explain seed/out/omc bad.om bad
bad.om:2: error 7: type mismatch
    2 | x = add int 1 uint 2
```

- The compiler is not changed. Its stderr line `omc: line L: error C` stays exactly as gate15, gate5,
  the OM-2 conductor and the x86 qualification compare it; `explain` reads it from a pipe.
- The exit status is the compiler's own code. `explain` adds 64 (usage), 65 (a file could not be
  opened or the compiler could not be started) and 66 (the compiler was stopped by a signal).
- The sentence for each code is the MEANING column of `seed/omc/error-codes.reg`, embedded as the
  `text means` line. `sh seed/explain/gate.sh table` prints that line; the gate fails when the two
  differ, so a registry change must regenerate it.
- An `om2 diag` unit's machine record follows the explanation unchanged.
- A message that is not in the expected form, or whose code differs from the exit status, is shown
  raw with a note instead of being explained.

`sh seed/explain/gate.sh` (run by `seed/host/check.sh` after gate15) checks: the table against the
registry with a changed-meaning negative control; every gate15 refusal case, read from `gate15.sh`,
for exit code, sentence and source line; a valid program giving the same bytes as the compiler alone;
the om2 diag pass-through; stand-in compilers for an odd message, a code mismatch, a signal, a missing
compiler and 100 KB of stderr; a missing source; usage; and two identical runs. Four planted bugs
(no code-mismatch check, meaning off by one, wrong source line, exit code lost) each fail it.

This covers the human-message part of ROADMAP-1.0 RM8 without touching the compiler's output. A
message inside omc itself, and diagnostics in every profile, remain open there.
