#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Exact distro C reference oracle. Never opens sysfs or a PCI device.
# POSIX sh, awk, sha256sum, patch, nice and cc.
#
# Usage: sh native/omega/platform/kernel-repro.sh OUT_DIR
#
# Applies the actual proposed patch to a disposable copy of the pinned
# reference source (not a hand-coded fixed oracle), extracts the original and
# patched pcie_cooling_get_* functions, and builds four programs with small
# reference structs: the bug reproduction and the full boundary suite, each
# against the old and the patched code. Every program must compile cleanly
# under -Wall -Wextra -Werror and exit with its expected status, so the red and
# green controls run in both directions. Writes the programs, their outputs
# and results.json into OUT_DIR.
set -eu
export LC_ALL=C
# cd prints the directory when CDPATH supplies it, which would corrupt $(cd ...).
unset CDPATH

die() { printf 'PCIE COOLING REPRO FAIL: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 1 ] || die "usage: kernel-repro.sh OUT_DIR"
here=$(cd "$(dirname "$0")" && pwd -P)
mkdir -p "$1"
out=$(cd "$1" && pwd -P)

ref=$here/pcie-cooling-ref.c
proposal=$here/pcie-cooling-proposal.patch
[ -f "$ref" ] && [ -f "$proposal" ] || die "missing reference source or proposal patch"
got=$(sha256sum < "$ref" | cut -d' ' -f1)
[ "$got" = fff34da417c7f8cdb642a8b8ac20b7a5d1010392a2a7b8662178078abd1824c9 ] || die "reference source pin mismatch (got $got)"

tree=$out/patch-tree/drivers/thermal
mkdir -p "$tree"
cp "$ref" "$tree/pcie_cooling.c"
rc=0
(cd "$out/patch-tree" && patch --batch -p1 -i "$proposal") > "$out/patch.stdout" 2> "$out/patch.stderr" || rc=$?
[ "$rc" -eq 0 ] || { cat "$out/patch.stderr" >&2; die "proposal patch does not apply (exit $rc)"; }
fixed=$tree/pcie_cooling.c

# Every match of: "static int pcie_cooling_get_" word "(" then one or more
# characters other than "}" up to the first "}" that starts a line. Matches
# are joined with one newline and no trailing newline. Requires exactly two
# (get_max_level and get_cur_level).
functions() { # file -> stdout
  awk '
    { text = text $0 "\n" }
    END {
      key = "static int pcie_cooling_get_"; s = text; first = 1; found = 0
      while ((i = index(s, key)) > 0) {
        rest = substr(s, i + length(key))
        if (!match(rest, /^[A-Za-z0-9_]+\(/)) { s = substr(s, i + 1); continue }
        body = substr(rest, RLENGTH + 1)
        j = index(body, "}")
        if (j < 3 || substr(body, j - 1, 1) != "\n") { s = substr(s, i + 1); continue }
        m = key substr(rest, 1, RLENGTH) substr(body, 1, j)
        printf "%s%s", (first ? "" : "\n"), m
        first = 0; found++
        s = substr(body, j + 1)
      }
      if (found != 2) { printf "PCIE COOLING REPRO FAIL: expected 2 get functions, found %d\n", found > "/dev/stderr"; exit 1 }
    }' "$1"
}
functions "$ref" > "$out/old.functions" || die "reference function extraction"
functions "$fixed" > "$out/fixed.functions" || die "patched function extraction"

cat > "$out/header.c" <<'EOF'
#include <stdio.h>
#include <errno.h>
#define READ_ONCE(x) (x)
enum pci_bus_speed { PCIE_SPEED_2_5GT=0x14, PCIE_SPEED_64_0GT=0x19, PCI_SPEED_UNKNOWN=0xff };
struct pci_bus { unsigned char max_bus_speed, cur_bus_speed; };
struct pci_dev { struct pci_bus *subordinate; };
struct thermal_cooling_device { void *devdata; unsigned long max_state; };
EOF

cat > "$out/bug-main.c" <<'EOF'
int main(void) {
struct pci_bus bus={0x18,0xff}; struct pci_dev dev={&bus};
struct thermal_cooling_device c={&dev,4}; unsigned long s=999;
if (pcie_cooling_get_max_level(&c,&s) || s!=4) return 7;
s=999;
int r=pcie_cooling_get_cur_level(&c,&s);
if (r || (long)s != -231) return 3;
printf("REPRODUCED unknown=0xff max_state=4 cur_state=%ld unsigned=%lu\n",(long)s,s);
return 0; }
EOF

cat > "$out/test-main.c" <<'EOF'
int main(void) {
struct pci_bus bus={0x18,0x14}; struct pci_dev dev={&bus};
struct thermal_cooling_device c={&dev,4}; unsigned long s;
for (unsigned int i=0x14; i<=0x19; i++) {
bus.max_bus_speed=i; s=999;
if (pcie_cooling_get_max_level(&c,&s) || s!=i-0x14) return 1;
c.max_state=i-0x14;
for (unsigned int j=0x14; j<=i; j++) {
bus.cur_bus_speed=j; s=999;
if (pcie_cooling_get_cur_level(&c,&s) || s!=i-j) return 2;
}}
unsigned int bad[]={0,0x13,0x1a,0xff};
for (unsigned int i=0;i<4;i++) {
bus.cur_bus_speed=bad[i]; s=999;
if (pcie_cooling_get_cur_level(&c,&s)!=-EAGAIN || s!=999) return 4;
bus.max_bus_speed=bad[i]; s=999;
if (pcie_cooling_get_max_level(&c,&s)!=-EINVAL || s!=999) return 5;
}
c.max_state=4; bus.cur_bus_speed=0x19; s=999;
if (pcie_cooling_get_cur_level(&c,&s)!=-EAGAIN || s!=999) return 6;
printf("FIX PASS all enum speeds, unknown/non-PCIe, stale-above-max; outputs unchanged on errors\n");
return 0; }
EOF

results=''
build() { # name functions main expected_exit
  name=$1 fns=$2 main=$3 want=$4
  src=$out/$name.c
  bin=$out/$name
  cat "$out/header.c" "$fns" "$main" > "$src"
  rc=0
  nice -n 15 cc -std=c11 -Wall -Wextra -Werror -o "$bin" "$src" > /dev/null 2> "$out/$name.compile.stderr" || rc=$?
  [ "$rc" -eq 0 ] || { cat "$out/$name.compile.stderr" >&2; die "$name: compile failed (exit $rc)"; }
  rc=0
  "$bin" > "$out/$name.stdout" 2> /dev/null || rc=$?
  [ "$rc" -eq "$want" ] || die "$name: exit $rc, expected $want"
  sum=$(sha256sum < "$bin" | cut -d' ' -f1)
  entry=$(printf '  {\n    "name": "%s",\n    "compile_exit": 0,\n    "run_exit": %d,\n    "expected": %d,\n    "binary_sha256": "%s"\n  }' "$name" "$rc" "$want" "$sum")
  if [ -n "$results" ]; then results="$results,
$entry"; else results=$entry; fi
}
build old-repro "$out/old.functions" "$out/bug-main.c" 0
build fixed-repro-negative "$out/fixed.functions" "$out/bug-main.c" 3
build fixed-boundaries "$out/fixed.functions" "$out/test-main.c" 0
build old-boundaries-negative "$out/old.functions" "$out/test-main.c" 4

printf '[\n%s\n]\n' "$results" > "$out/results.json"
printf 'PCIE COOLING REPRO PASS: old reproduces -231; proposed fix refuses; full boundary oracle passes and kills old code\n'
