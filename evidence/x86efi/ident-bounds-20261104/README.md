# ident bounds, 2026-11-04 (EMULATED: QEMU + OVMF, not hardware)

Reviewer finding B1 on omega-mv#1022 / aien-train#55: `tests/x86efi/ident/id.om` trimmed the CPUID brand
with `while and lt s 48 ... get br s ...`. Omega's `and` evaluates both sides, so at `s = 48` the loop read
`br[48]` and a brand of only NULs or only blanks ended in trap 3. Findings N1/N2: the SMBIOS string and
structure walks could read past the copied table length. This directory is the before/after receipt for
the fix in `id.om`; `tests/x86efi/run.sh` now runs the same five cases (section "ident bounds").

## Inputs

| item | sha256 |
|---|---|
| omc (both builds; `seed/out/omc`, fixpoint of #1022 omc.om) | `3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194` |
| before: `id-fbcf0882.om` = `tests/x86efi/ident/id.om` at fbcf08826e | `af5cfa1e3d2096193c6c85cc4366195aab0471bd286c28e6a472a45682212e14` |
| before: app.efi | `1e468c22f23de9ddc4837ab123d24b7d75609f72badec57dace740a70cb74941` |
| after: `tests/x86efi/ident/id.om` as committed with this directory | `dcdf890baa78b06403fabb8110d246764b6b8fe7322890525a32a052949d63dd` |
| after: app.efi | `9c0de70f367f06471da7ebafb5135ce04e551ad1ef0b5856975297ed57ebe1fc` |
| OVMF `/usr/share/OVMF/OVMF_CODE_4M.fd` | `ad23261d43116abc3747d59a7837fbf578c9586a8993f4eeba064cd07eccb083` |

QEMU 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18), host Spark, `nice -n 19 taskset -c 9`, 60 s per boot.
`SHA256SUMS` covers every file here.

## Commands

`hb.sh OMC SRC OUTDIR CPU [SMBIOS]` is run.sh's `boot()` with machine `q35,smbios-entry-point-type=64`, a
`-cpu` value and one `-smbios` value. `blobs.sh` defines `t1 VER` (type 1, handle 0x0100, Manufacturer 1,
Product 2, Version VER, one string) and `t11 H N` (type 11, handle 0x0B00+H, N strings of 60 characters).

    . ./blobs.sh
    t1 3 > n2.bin                                          # Version names string 3 of a one-string set
    { t1 255; t11 1 100; t11 2 100; } > capwalk.bin        # Version 255: the string walk runs past 8192 bytes
    { for h in 1 2 3 4 5; do t11 $h 255; done; } > capscan.bin   # 77805 bytes, no type 1 under the cap
    sh hb.sh OMC SRC OUT-nul 'max,model-id='
    sh hb.sh OMC SRC OUT-blank "max,model-id=$(printf '%48s' '')"
    sh hb.sh OMC SRC OUT-n2 max file=n2.bin
    sh hb.sh OMC SRC OUT-capwalk max file=capwalk.bin
    sh hb.sh OMC SRC OUT-capscan max file=capscan.bin

`{old,new}-CASE.serial.txt` are the serial logs with CR and ANSI escapes removed.

## Results

| case | before (fbcf0882) | after |
|---|---|---|
| nul | `==B`, then `failed to start Boot0001 ...: 00000067` (trap 3) | `br=-`, `==E` |
| blank | trap 3 | `br=-`, `==E` |
| n2 | `sm=OmegaTest/-/??` (`ps` prints `?` for a byte outside 32..126: two bytes read past the one-string set), `==E` | `sm=OmegaTest/-/-`, `==E` |
| capwalk | trap 3 after `br=` | `sm=OmegaTest/-/-`, `==E` |
| capscan | trap 3 after `br=` | `sm=-`, `==E` |

These cases set no serial or UUID. Not covered here: real firmware (the iMac run is aien-train#55's), and
SMBIOS tables over 64 KiB other than capscan.

## run.sh

`run-sh.txt` is `nice -n 19 taskset -c 9 sh tests/x86efi/run.sh` on the working tree that was committed
with this directory (the merge of feat/x86efi-main `882e93c0`, the fixed `id.om` and the new "ident
bounds" section), followed by the shell's `RC_EXIT`. Last lines: `SUMMARY pass=23 fail=0 not_run=0`,
`RC_EXIT=0`. The five `ident bounds` rows are the cases above, run by run.sh's own generators.
