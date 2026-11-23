#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# qrecord_parity.sh -- differential qualification of the pure OM-2 TURING companion records
# (src/turing/ty_qrecord.om, composed after src/turing/ty_core_lib.om as mk/turing_qrecord.mk
# joins them) against the C they replace (src/turing/ty_qrecord.c, retired at main 3f2c70dc5).
#
# Every corpus runs through tests/turing/qrecord_dump.om in a fresh work directory and is
# compared byte for byte with tests/turing/qrecord_golden/<corpus>.out: the return code and
# digest of every record builder, verifier and the gain binding, the write-once writer (code,
# digest, path length, file sha256, file mode), the file verifier, and the sidecar manifest
# builders, parsers, table checks and digest. The goldens were generated ONCE from the C at main
# commit 3f2c70dc5 by the reference-only C dumper tests/turing/qrecord_dump.c (committed once,
# then removed); tests/turing/qrecord_golden/MANIFEST records the commit, the generator and the
# sha256 of every corpus and golden. This script needs no C compiler.
#
# Corpus commands (one per line, tokens separated by one space, '#' and blank lines skipped).
# k is the record: 0 qprofile, 1 qworld, 2 qfreeze, 3 qgain (4 with i = 0: the freeze run_commit).
# Field index i is the OM storage index (src/turing/ty_qrecord.om, "Record global state").
#   Z k            zero record k
#   S k i hex      string field = the hex bytes ("." = empty); NUL-terminated when shorter
#                  than the field (513 bytes; 41 for run_commit)
#   T k i text     string field = the rest of the line (leading spaces are skipped: use S)
#   U k i v        u64 field     I k i v   i64 field (signed decimal)
#   D k i r        digest field = register r (0..15)
#   X r hex64      register r = the 32 bytes     F r b   register r = 32 bytes of value b
#   P r            print register r
#   G k r          digest of record k into r: G k rc [hex]; r is zeroed when rc != 0
#   V k r          verify record k against r: V k rc
#   B g w f p      bind the gain, world and freeze with digest registers g w f and profile p
#   W k r n        write record k (digest into r) under a directory of n bytes ("qr_w" padded
#                  with "/."; n = 0: a missing directory): W k rc [hex pathlen filesha mode]
#   Y k r          verify the last written file with the domain of k against r
#   YN name k r    verify the fixture file name (qr_empty, qr_40000, qr_40001, qr_w)
#   M0 | MX hex | MT text | MN n b   clear / append to the sidecar buffer (8192 bytes)
#   SD r           sidecar digest of the buffer into r
#   RE j rep r     repman entry j (rep, register r)   DE j block r hex   devman entry j (cell hex)
#   RB n cap | DB n cap   build n entries into the buffer (cap <= 8192, n <= 64): rc len text
#   RP cap | DP cap       parse the buffer (cap <= 64): rc [n entries]
#   CT | TT        cell table / thresholds table check of the buffer
#
# usage: tests/turing/qrecord_parity.sh [OMC]
#          prints PARITY lines and QRECORD_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/turing/qrecord_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
set -eu
export LC_ALL=C
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/turing/qrecord_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: qrecord_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${QRECORD_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/turing/qrecord_corpus.txt "$C/hand.txt"
# The shared valid records (awk functions): registers 1..15 distinct, 0 zero; prof(), world(s)
# (s = 0 dev, 1 sealed by register 11), freeze(d) (d = 0 certification, 1 discovery), gain(d).
LIB='function regs(  r) { for (r = 0; r < 16; r++) print "F " r " " (r == 0 ? 0 : 16 * r + 1) }
function prof() { print "Z 0"; print "T 0 0 dummy.profile.v9"; print "D 0 0 1"; print "D 0 1 3";
  print "T 0 1 dummy.line.v9"; print "T 0 2 dummyq.v9"; print "I 0 0 -3"; print "T 0 3 dummy.edge";
  print "I 0 1 -20"; print "T 0 4 dummy.floor.rule"; print "T 0 5 0 1"; print "U 0 0 16"; print "U 0 1 100";
  print "U 0 2 2"; print "D 0 2 4"; print "T 0 6 dummy.rider"; print "T 0 7 dummy.lm.rule.id";
  print "T 0 8 X1:0x01 X2:0x02"; print "D 0 3 6"; print "T 0 9 dummy.thr.v9"; print "T 0 10 dummy.gen.v9";
  print "U 0 3 1000"; print "T 0 11 micro-bits (1 T = 1 bit = 1000000 ub)" }
function world(s) { print "Z 1"; print "D 1 0 2"; print "T 1 0 " (s ? "certification" : "dev");
  print "T 1 1 " (s ? "sealed" : "dev"); print "D 1 1 " (s ? 11 : 0); print "T 1 2 cellA"; print "U 1 0 3";
  print "T 1 3 dummy-label-bytes"; print "T 1 4 dummy.gen.v9"; print "D 1 2 7"; print "U 1 1 0"; print "U 1 2 10";
  print "D 1 3 8"; print "T 1 5 dummy.traj.v9" }
function freeze(d) { print "Z 2"; print "T 2 0 " (d ? "discovery" : "certification"); print "D 2 0 5";
  print "T 2 1 cand.c"; print "D 2 1 " (d ? 9 : 0); print "D 2 2 2"; print "D 2 3 12"; print "T 2 2 POSITIVE";
  print "T 2 3 AGREE"; print "T 2 4 cellA:10 cellB:20"; print "T 2 5 PASS"; print "T 2 6 FAIL";
  print "T 2 7 ref.c"; print "T 4 0 0123456789abcdef0123456789abcdef01234567"; print "U 2 0 0";
  print "T 2 8 A=0123456789abcdef0123456789abcdef01234567 B=89abcdef0123456789abcdef0123456789abcdef";
  print "T 2 9 " (d ? "tool 1.0" : "none"); print "T 2 10 " (d ? "model-x" : "none");
  print "D 2 4 " (d ? 13 : 0); print "D 2 5 " (d ? 14 : 0); print "U 2 1 0" }
function gain(d) { print "Z 3"; print "D 3 0 2"; print "D 3 1 10"; print "D 3 2 11";
  print "T 3 0 " (d ? "discovery" : "certification"); print "T 3 1 cellA"; print "T 3 2 dummy.gen.v9";
  print "U 3 0 1"; print "D 3 3 12"; print "D 3 4 5"; print "U 3 1 " (d ? 255 : 3); print "D 3 5 13";
  print "D 3 6 14"; print "U 3 2 " (d ? 0 : 1); print "T 3 3 " (d ? "item.7" : "-");
  print "I 3 0 100"; print "I 3 1 200"; print "I 3 2 300"; print "I 3 3 400"; print "I 3 4 1000";
  print "I 3 5 600"; print "I 3 6 400"; print "I 3 7 -5"; print "I 3 8 5"; print "I 3 9 7"; print "I 3 10 1";
  print "U 3 3 5"; print "U 3 4 6"; print "U 3 5 7"; print "U 3 6 8"; print "U 3 7 0"; print "U 3 8 0";
  print "T 3 4 0"; print "I 3 11 -1"; print "I 3 12 0"; print "I 3 13 5"; print "T 3 5 -";
  print "T 3 6 POSITIVE"; print "T 3 7 PASS"; print "T 3 8 micro-bits" }
function base(k, v) { regs(); if (k == 0) prof(); if (k == 1) world(v); if (k == 2) freeze(v); if (k == 3) gain(v) }
function hexs(s,   i, o) { o = ""; for (i = 1; i <= length(s); i++) o = o sprintf("%02x", ord[substr(s, i, 1)]); return o == "" ? "." : o }
function rep(c, n,   o) { o = ""; while (n-- > 0) o = o c; return o }
BEGIN { for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i }'

# Strings: every string field of every record (both variants) set to the empty value, the
# boundary bytes 0x1f 0x20 0x7e 0x7f 0x80 0xff alone and inside a value, 512 and 513 bytes (513:
# no NUL), and list / name shapes (leading, trailing and doubled spaces, an inner space).
awk "$LIB"'
BEGIN { nf[0] = 12; nf[1] = 6; nf[2] = 11; nf[3] = 9;
  split("1f 20 7e 7f 80 ff", bb, " ");
  for (k = 0; k <= 3; k++) for (v = 0; v <= (k ? 1 : 0); v++) for (i = 0; i < nf[k]; i++) {
    n = 0
    val[++n] = "."; for (j = 1; j <= 6; j++) { val[++n] = bb[j]; val[++n] = "61" bb[j] "62" }
    val[++n] = rep("61", 512); val[++n] = rep("61", 513); val[++n] = rep("61", 511) "20"
    val[++n] = "2061"; val[++n] = "6120"; val[++n] = "61202062"; val[++n] = "612062"; val[++n] = "612d"
    for (j = 1; j <= n; j++) { base(k, v); print "S " k " " i " " val[j]; print "G " k " 15" } }
  # run_commit: 39, 40, 41 (no NUL) bytes, upper case, a non-hex byte at every position
  for (v = 0; v <= 1; v++) {
    split("30 39 61 66 41 46 67 2f 3a 60", cc, " ")
    for (j = 1; j <= 10; j++) for (p = 0; p < 40; p += 13) { base(2, v); print "S 4 0 " rep("61", p) cc[j] rep("62", 39 - p); print "G 2 15" }
    base(2, v); print "S 4 0 " rep("61", 39); print "G 2 15"
    base(2, v); print "S 4 0 " rep("61", 41); print "G 2 15"
    base(2, v); print "S 4 0 ."; print "G 2 15" } }' > "$C/gen-text.txt"

# Enumerations: every enum field with each allowed value of every enum set, case and prefix near
# misses; status shapes (PASS, FAIL_, FAIL_x, STOPPED with and without protocol failures, FAIL, a
# space); the leak flag, the classification.
awk "$LIB"'
BEGIN { split("dev certification discovery sealed POSITIVE NEGATIVE AMBIGUOUS WEAK STOPPED AGREE STOP PASS FAIL 0 1 INCONCLUSIVE none - FAIL_ FAIL_x pass Dev certificatio discoveryx STOPPEDX 2 00", ev, " ")
  # (k, i, variants)
  n = split("1:0:1 1:1:1 2:0:1 2:2:1 2:3:1 2:5:1 2:6:1 2:9:1 2:10:1 3:0:1 3:4:1 3:6:1 3:7:1 3:3:1", fl, " ")
  for (f = 1; f <= n; f++) { split(fl[f], a, ":"); for (v = 0; v <= 1; v++) for (j = 1; j in ev; j++) {
    base(a[1] + 0, v); print "T " a[1] " " a[2] " " ev[j]; print "G " a[1] " 15" } }
  for (v = 0; v <= 1; v++) {
    split("PASS FAIL_ FAIL_x STOPPED FAIL STOP FAILX", st, " ")
    for (j = 1; j <= 7; j++) for (pf = 0; pf <= 2; pf++) { base(3, v); print "T 3 7 " st[j]; print "U 3 8 " pf; print "G 3 15" }
    base(3, v); print "S 3 7 4641494c5f2061"; print "G 3 15"
    base(3, v); print "S 3 7 5354"; print "G 3 15" }
  # world: mode x parent x qfreeze zero / non-zero
  split("dev certification discovery", wm, " "); split("dev sealed", wp, " ")
  for (m = 1; m <= 3; m++) for (p = 1; p <= 2; p++) for (z = 0; z <= 1; z++) {
    base(1, 0); print "T 1 0 " wm[m]; print "T 1 1 " wp[p]; print "D 1 1 " (z ? 11 : 0); print "G 1 15" }
  # freeze: mode x artifact_bin x producer fields x prompt / transcript
  split("certification discovery", fm, " ")
  for (m = 1; m <= 2; m++) for (ab = 0; ab <= 1; ab++) for (pt = 0; pt <= 1; pt++) for (pm = 0; pm <= 1; pm++)
    for (pr = 0; pr <= 1; pr++) for (tr = 0; tr <= 1; tr++) {
      base(2, 0); print "T 2 0 " fm[m]; print "D 2 1 " (ab ? 9 : 0); print "T 2 9 " (pt ? "tool" : "none");
      print "T 2 10 " (pm ? "model" : "none"); print "D 2 4 " (pr ? 13 : 0); print "D 2 5 " (tr ? 14 : 0); print "G 2 15" } }' > "$C/gen-enum.txt"

# Numbers: u64 and i64 fields at their boundaries; gain opcode, official / ladder, t_ub
# relation (including the ty_sub overflow), t_lo_ub / t_hi_ub order, coverage below -1, freeze
# tree_dirty and n_lineage 0..9 with every lineage slot set.
awk "$LIB"'
BEGIN { split("0 1 2 7 8 9 10 99 255 256 4294967295 4294967296 9223372036854775807 9223372036854775808 18446744073709551614 18446744073709551615", uv, " ")
  split("0 1 -1 -2 7 -7 2147483647 -2147483648 9223372036854775807 -9223372036854775807 -9223372036854775808", iv, " ")
  nu[0] = 4; nu[1] = 3; nu[2] = 2; nu[3] = 9
  for (k = 0; k <= 3; k++) for (v = 0; v <= (k ? 1 : 0); v++) for (i = 0; i < nu[k]; i++) for (j = 1; j <= 16; j++) {
    base(k, v); print "U " k " " i " " uv[j]; print "G " k " 15" }
  for (i = 0; i < 2; i++) for (j = 1; j <= 11; j++) { base(0, 0); print "I 0 " i " " iv[j]; print "G 0 15" }
  for (v = 0; v <= 1; v++) for (i = 0; i < 14; i++) for (j = 1; j <= 11; j++) { base(3, v); print "I 3 " i " " iv[j]; print "G 3 15" }
  # t_ub = lengths[4] - lengths[5]
  split("1000:600:400 1000:600:401 -9223372036854775808:1:0 9223372036854775807:-1:0 -9223372036854775807:1:-9223372036854775808 0:-9223372036854775807:9223372036854775807 5:5:0 -5:5:-10", tu, " ")
  for (v = 0; v <= 1; v++) for (j = 1; j <= 8; j++) { split(tu[j], a, ":"); base(3, v); print "I 3 4 " a[1]; print "I 3 5 " a[2]; print "I 3 6 " a[3]; print "G 3 15" }
  split("-5:5 5:5 6:5 -9223372036854775808:9223372036854775807 9223372036854775807:-9223372036854775808", lh, " ")
  for (v = 0; v <= 1; v++) for (j = 1; j <= 5; j++) { split(lh[j], a, ":"); base(3, v); print "I 3 7 " a[1]; print "I 3 8 " a[2]; print "G 3 15" }
  for (v = 0; v <= 1; v++) for (o = 0; o <= 2; o++) for (l = 0; l <= 2; l++) {
    base(3, v); print "U 3 2 " o; print "T 3 3 " (l == 0 ? "-" : (l == 1 ? "item" : "--")); print "G 3 15" }
  for (v = 0; v <= 1; v++) for (c = 0; c <= 8; c++) { base(3, v); print "U 3 1 " (c == 8 ? 255 : c); print "G 3 15"; base(3, v); print "U 3 0 " c; print "G 3 15" }
  for (v = 0; v <= 1; v++) for (n = 0; n <= 9; n++) {
    base(2, v); print "U 2 1 " n; for (j = 0; j < 8; j++) print "D 2 " (6 + j) " " (j < n ? j + 1 : 0); print "G 2 15"
    for (j = 0; j < 8; j++) { base(2, v); print "U 2 1 " n; print "D 2 " (6 + j) " 15"; print "G 2 15" } }
  for (v = 0; v <= 1; v++) for (j = 0; j < 14; j++) { base(2, v); print "D 2 " j " 0"; print "G 2 15"; base(2, v); print "D 2 " j " 3"; print "G 2 15" }
  for (k = 0; k <= 3; k++) for (v = 0; v <= (k ? 1 : 0); v++) for (j = 0; j < 7; j++) { base(k, v); print "D " k " " j " 0"; print "G " k " 15"; base(k, v); print "D " k " " j " 15"; print "G " k " 15" } }' > "$C/gen-num.txt"

# Verify and bind: each record verified against its digest, a one-bit-off digest and the zero
# digest; the full chain profile -> freeze -> world -> gain bound, then each of the eleven
# disagreements the binding refuses (and a malformed record of each kind first).
awk "$LIB"'
function chain(d) { regs(); prof(); print "G 0 2"; freeze(d); print "G 2 11"; world(1); if (d) print "T 1 0 discovery"; print "G 1 10"; gain(d); print "G 3 15" }
BEGIN {
  for (d = 0; d <= 1; d++) {
    chain(d); print "B 15 10 11 2"; for (k = 0; k <= 3; k++) { print "V " k " " (k == 0 ? 2 : (k == 1 ? 10 : (k == 2 ? 11 : 15))); print "V " k " 0"; print "V " k " 9" }
    chain(d); print "P 15"; print "B 0 10 11 2"; print "B 15 0 11 2"; print "B 15 10 0 2"; print "B 15 10 11 0"
    split("D 3 0 9|D 1 0 9|D 2 2 9|D 3 1 9|D 3 2 9|D 1 1 9|T 3 0 X|T 1 0 X|T 2 0 X|T 3 1 cellB|T 1 2 cellB|T 3 2 g2|T 1 4 g2|D 3 4 9|D 2 0 9|T 3 0 certification|T 3 0 discovery", mm, "|")
    for (j = 1; j in mm; j++) { chain(d); print mm[j]; split(mm[j], a, " ");
      print "G 0 2"; print "G 2 11"; print "G 1 10"; print "G 3 15"; print "B 15 10 11 2"
      chain(d); print mm[j]; print "B 15 10 11 2" }
    # each disagreement built into a record before the records that name it are digested, so
    # every record verifies and only the named binding check can refuse (stage:line)
    split("3:D 3 0 9|1:D 1 0 9|2:D 2 2 9|3:D 3 1 9|3:D 3 2 9|1:D 1 1 9|1:T 1 0 " (d ? "certification" : "discovery") "|2:OTHER|3:T 3 1 cellB|1:T 1 2 cellB|3:T 3 2 g2|1:T 1 4 g2|3:D 3 4 9|2:D 2 0 9|0:-", st, "|")
    for (j = 1; j in st; j++) { s = substr(st[j], 1, 1); l = substr(st[j], 3)
      regs(); prof(); print "G 0 2"; if (s == 2 && l == "OTHER") freeze(1 - d); else freeze(d); if (s == 2 && l != "OTHER") print l; print "G 2 11"
      world(1); if (d) print "T 1 0 discovery"; if (s == 1) print l; print "G 1 10"
      gain(d); if (s == 3) print l; print "G 3 15"; print "B 15 10 11 2"; print "B 15 10 11 9" } } }' > "$C/gen-bind.txt"

# Writer and file verifier: each record written under directories of 4..12 bytes and at the
# path-length boundary (1023 accepted, 1024 refused) of its record name; a second write finds the
# file (EXISTS); a missing directory; a malformed record; the written file verified against its
# digest and the other domains; the fixture files.
awk "$LIB"'
BEGIN { rl[0] = 15; rl[1] = 13; rl[2] = 14; rl[3] = 12
  for (k = 0; k <= 3; k++) for (v = 0; v <= (k ? 1 : 0); v++) {
    base(k, v); if (v) print "U " k " 0 1"
    for (n = 4; n <= 12; n++) print "W " k " 9 " n
    lim = 1023 - rl[k] - 71
    for (n = lim - 2; n <= lim + 2; n++) print "W " k " 9 " n
    print "W " k " 9 0"; print "Y " k " 9"; for (d = 0; d <= 4; d++) print "Y " d " 9"; print "Y " k " 0"
    print "YN qr_empty " k " 9"; print "YN qr_40000 " k " 9"; print "YN qr_40001 " k " 9"; print "YN qr_w " k " 9"; print "YN qr_nofile " k " 9"
    base(k, v); print "S " k " 0 ."; if (k == 2) print "T 2 0 x"; print "W " k " 8 4"; print "P 8" } }' > "$C/gen-write.txt"

# Sidecars: repman and devman built from 1..64 entries, at every output capacity around their
# length, out of order, duplicate, zero entries; parsed back, and parsed after a byte of every
# value at every position class; cell and threshold tables of every shape; sidecar digests.
awk "$LIB"'
function hx(s) { return hexs(s) }
BEGIN { regs()
  for (n = 1; n <= 64; n = (n < 4 ? n + 1 : n * 2)) {
    for (j = 0; j < n; j++) print "RE " j " " (j == 0 ? 0 : j * 1000 + 7) " " (j % 16)
    print "RB " n " 8192"; print "SD 3"; print "RP 64"; print "RP " n; print "RP " (n - 1)
    for (j = 0; j < n; j++) print "DE " j " " (j % 3) " " (j % 16) " " hx("cell" sprintf("%03d", int(j / 3)))
    print "DB " n " 8192"; print "SD 4"; print "DP 64"; print "DP " n; print "DP " (n - 1) }
  for (j = 0; j < 3; j++) print "RE " j " " (j * 10 + 5) " " (j + 1)
  for (cap = 60; cap <= 72; cap++) print "RB 1 " cap
  for (cap = 128; cap <= 140; cap++) print "RB 2 " cap
  print "RB 0 8192"; print "RE 1 5 2"; print "RB 2 8192"; print "RE 1 4 2"; print "RB 2 8192"
  print "RE 0 18446744073709551615 1"; print "RB 1 8192"; print "RP 1"
  for (j = 0; j < 3; j++) print "DE " j " " j " " (j + 1) " " hx("c" j)
  for (cap = 60; cap <= 76; cap++) print "DB 1 " cap
  print "DB 0 8192"
  print "DE 1 0 2 " hx("c0"); print "DB 2 8192"; print "DE 1 1 2 " hx("c0"); print "DB 2 8192"
  print "DE 1 0 2 " hx("c"); print "DB 2 8192"; print "DE 1 0 2 " hx("c00"); print "DB 2 8192"
  print "DE 0 0 1 ."; print "DB 1 8192"; print "DE 0 0 1 " hx("a b"); print "DB 1 8192"
  print "DE 0 0 1 1f"; print "DB 1 8192"; print "DE 0 0 1 7f"; print "DB 1 8192"; print "DE 0 0 1 ff"; print "DB 1 8192"
  print "DE 0 0 1 " rep("61", 127); print "DB 1 8192"; print "DP 1"; print "DE 0 0 1 " rep("61", 128); print "DB 1 8192"
  d = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  # repman parse shapes
  split("0 " d "|1 " d "|01 " d "|18446744073709551615 " d "|18446744073709551616 " d "|99999999999999999999 " d "|100000000000000000000 " d "|-1 " d "|+1 " d "|1  " d "|1 " d " |1 " d " x| 1 " d "|1|" d "|1 " substr(d, 2) "|1 " d "0|1 0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef|1 g123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", rp, "|")
  for (j = 1; j in rp; j++) { print "M0"; print "MT " rp[j]; print "RP 64"; print "M0"; print "MT 0 " d; print "MT " rp[j]; print "RP 64"; print "M0"; print "MT " rp[j]; print "MT 9 " d; print "RP 64" }
  print "M0"; print "RP 64"; print "M0"; print "MX " hx("1 ") hx(d); print "RP 64"
  print "M0"; print "MT 1 " d; print "MX " hx("2 ") hx(d); print "RP 64"; print "M0"; print "MT a 0 " d; print "MX " hx("b 0 ") hx(d); print "DP 64"
  print "M0"; print "MT a k=v"; print "MX " hx("b k=v"); print "CT"; print "M0"; print "MT a f v"; print "MX " hx("b f v"); print "TT"
  print "M0"; print "MT 1 " d; print "MT 1 " d; print "RP 64"; print "M0"; print "MT 2 " d; print "MT 1 " d; print "RP 64"
  print "M0"; print "MT 1 " d; print "MX 0a"; print "RP 64"; print "M0"; print "MX 0a"; print "RP 64"
  for (b = 0; b < 256; b += 1) { if (b == 10) continue; print "M0"; print "MX " sprintf("31%02x", b) hx(d) "0a"; print "RP 64"; print "M0"; print "MX 31" sprintf("20%02x", b) hx(substr(d, 2)) "0a"; print "RP 64" }
  # devman parse shapes
  split("c 0 " d "|c 1 " d "|c 01 " d "|c " d "|c 0 0 " d "|" rep("a", 127) " 0 " d "|" rep("a", 128) " 0 " d "|c  0 " d "|c 0 " d " |c 0 " substr(d, 2) "|c 18446744073709551616 " d, dp, "|")
  for (j = 1; j in dp; j++) { print "M0"; print "MT " dp[j]; print "DP 64"; print "M0"; print "MT a 0 " d; print "MT " dp[j]; print "DP 64" }
  split("a 1|a 0|b 0|ab 0|A 9", order, "|")
  for (i = 1; i <= 5; i++) for (j = 1; j <= 5; j++) { print "M0"; print "MT " order[i] " " d; print "MT " order[j] " " d; print "DP 64" }
  print "M0"; for (j = 0; j < 65; j++) print "MT " j " " d; print "RP 64"
  print "M0"; for (j = 0; j < 65; j++) print "MT c" sprintf("%02d", j) " 0 " d; print "DP 64"
  for (b = 0; b < 256; b += 1) { if (b == 10) continue; print "M0"; print "MX " sprintf("63%02x", b) hx(" 0 ") hx(d) "0a"; print "DP 64" }
  # cell table and thresholds table
  split("a k=v|a k=v x=y|a|a k|a =v|a k=|a k==|a ==v|a k=v=w|a  k=v|a k=v |" " a k=v|a k=v\tx", ct, "|")
  for (j = 1; j in ct; j++) { print "M0"; print "MT " ct[j]; print "CT"; print "TT"; print "M0"; print "MT " ct[j]; print "MT b k=v"; print "CT" }
  split("a k=v|b k=v|a x=v|ab k=v|A k=v|a k=u", c2, "|")
  for (i = 1; i <= 6; i++) for (j = 1; j <= 6; j++) { print "M0"; print "MT " c2[i]; print "MT " c2[j]; print "CT"; print "TT" }
  split("i f v|i f|i f v w|i  f v|i f v |i f v|j f v|i g v|i f w|I f v|i f vv", tt, "|")
  for (i = 1; i in tt; i++) for (j = 1; j in tt; j++) { print "M0"; print "MT " tt[i]; print "MT " tt[j]; print "TT" }
  print "M0"; print "CT"; print "TT"; print "M0"; print "MX 612062"; print "TT"; print "CT"
  print "M0"; s = "a"; for (j = 1; j < 64; j++) s = s " k" j "=v"; print "MT " s; print "CT"; print "M0"; print "MT " s " k64=v"; print "CT"
  print "M0"; s = "a"; for (j = 1; j < 63; j++) s = s " f"; print "MT " s; print "TT"
  for (b = 0; b < 256; b += 1) { if (b == 10) continue; print "M0"; print "MX " sprintf("61%02x", b) "6b3d760a"; print "CT"; print "TT"; print "M0"; print "MX 61206b" sprintf("%02x", b) "3d760a"; print "CT"; print "M0"; print "MX 69206620" sprintf("%02x", b) "0a"; print "TT"; print "M0"; print "MX 6920662076" sprintf("%02x", b) "0a"; print "TT" }
  print "M0"; print "SD 1"; print "M0"; print "MT abc"; print "SD 1"; print "MN 8188 97"; print "SD 1"; print "MN 1 97"; print "SD 1" }' > "$C/gen-side.txt"

# Write failure: the fsize-* corpora run with a file size limit of 12 blocks (6144 bytes) and
# SIGXFSZ ignored. A qprofile whose twelve strings hold 512 bytes each encodes to more than that,
# so its write stops part way (EFBIG): the writer must remove the file and return TY_E_IO.
awk "$LIB"'
BEGIN { for (n = 0; n <= 1; n++) { base(0, 0); for (i = 0; i < 12; i++) print "S 0 " i " " rep(n ? "62" : "61", 512); print "G 0 9"; print "W 0 9 4"; print "W 0 9 4"; print "W 0 9 0"; print "YN qr_empty 0 9" } }' > "$C/fsize-write.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
run() { # dumper corpus out: in a fresh work directory with the fixture files
  R=$W/run; rm -rf "$R"; mkdir -p "$R/qr_w"
  : > "$R/qr_empty"; head -c 40000 /dev/zero > "$R/qr_40000"; head -c 40001 /dev/zero > "$R/qr_40001"
  case $(basename "$2") in
    fsize-*) (cd "$R" && trap '' XFSZ && ulimit -f 12 &&"$1" < "$2") | cat > "$3"
             [ -z "$(ls "$R/qr_w")" ] || { echo "QRECORD_PARITY FAIL a failed write left a file in qr_w"; return 1; } ;;
    *) (cd "$R" && "$1" < "$2" > "$3") ;;
  esac
}
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "QRECORD_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "QRECORD_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    run "$GEN" "$c" "$GOLD/$b.out" || { echo "QRECORD_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "QRECORD_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "QRECORD_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "QRECORD_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "QRECORD_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "QRECORD_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "QRECORD_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "QRECORD_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "QRECORD_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped modules (as mk/turing_qrecord.mk joins them) ----
OMS="src/turing/ty_core_lib.om src/turing/ty_qrecord.om tests/turing/qrecord_dump.om"
(printf 'om2\n'; sed '/^om2$/d' $OMS) | "$OMC" > "$W/qrecord_dump_om"
chmod +x "$W/qrecord_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  run "$W/qrecord_dump_om" "$c" "$W/out/$b.om" || rc=$?
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  if [ "$rc" -eq 0 ] && cmp -s "$GOLD/$b.out" "$W/out/$b.om"; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF exit=$rc"
    diff "$GOLD/$b.out" "$W/out/$b.om" | head -20 || true
  fi
done
echo "QRECORD_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
