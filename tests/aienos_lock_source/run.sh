#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Test for tools/aienos_lock_source.sh and the Makefile rule that builds the trusted
# capability root from it. Host only, no chip. Fixture git repositories stand in for aienos.
# Every counterexample must be refused with the right exit status: 1 = verified mismatch or
# absence, 2 = the locked commit cannot be read (never reported as absent, never as proven).
# Usage: bash tests/aienos_lock_source/run.sh
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCR=$(mktemp -d "${TMPDIR:-/tmp}/aienos-lock-src.XXXXXX") || exit 2
trap 'rm -rf "$SCR"' EXIT INT TERM
FAILS=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
T="$HERE/tools/aienos_lock_source.sh"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=advice.detachedHead GIT_CONFIG_VALUE_0=false

# Fixture aienos: commit GOOD has a buildable native/capability; commit A lacks aienos_cap_mint.
LK=$SCR/aienos
lkg() { git -C "$LK" -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false "$@"; }
mkdir -p "$LK/native/capability" "$LK/native/store"
printf 'out/\n' > "$LK/native/capability/.gitignore"
printf 'int aienos_cap_validate(int v)\n{ return v; }\nint aienos_cap_mint(int a)\n{ return a; }\n' > "$LK/native/capability/aienos_capability.c"
printf 'OUT ?= out\n$(OUT)/libaienos_capability.a: aienos_capability.c\n\tmkdir -p $(OUT) && $(CC) -c -o $(OUT)/aienos_capability.o aienos_capability.c && ar rcs $@ $(OUT)/aienos_capability.o\n' > "$LK/native/capability/Makefile"
printf 'int store_v1;\n' > "$LK/native/store/store_v1.c"
lkg init -q && lkg add -A && lkg commit -qm good
GOOD=$(git -C "$LK" rev-parse HEAD)
sed -i 's/aienos_cap_mint(/aienos_cap_other(/' "$LK/native/capability/aienos_capability.c"; lkg commit -qam "A: no mint"
A=$(git -C "$LK" rev-parse HEAD)
lkg checkout -q "$GOOD"
L() { env AIENOS_LOCK_REPO="$LK" AIENOS_R7_DIR= "$@"; }
rc() { "$@" >/dev/null 2>&1; echo $?; }

# 1. reading blobs of the locked commit
check "show: locked file read (exit 0)" '[ "$(L AIENOS_LOCK=$GOOD bash "$T" show native/capability/aienos_capability.c | grep -c aienos_cap_mint)" = 1 ]'
check "blob: equals the commit's blob id" '[ "$(L AIENOS_LOCK=$GOOD bash "$T" blob native/capability/aienos_capability.c)" = "$(git -C "$LK" rev-parse "$GOOD:native/capability/aienos_capability.c")" ]'
check "show: path absent at the locked commit is exit 1 (verified absence)" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" show native/capability/none.c)" = 1 ]'
check "show: lock A is read as A although HEAD is GOOD" '! L AIENOS_LOCK=$A bash "$T" show native/capability/aienos_capability.c | grep -q aienos_cap_mint'
check "identity: names the full lock and its tree" '[ "$(L AIENOS_LOCK=$GOOD bash "$T" identity | jq -r .commit_tree)" = "$(git -C "$LK" rev-parse "$GOOD^{tree}")" ]'
check "unavailable repository: exit 2, not 1" '[ "$(rc env AIENOS_LOCK_REPO=/nonexistent AIENOS_LOCK=$GOOD bash "$T" show native/capability/aienos_capability.c)" = 2 ]'
check "repository without the locked commit: exit 2" '[ "$(rc env AIENOS_LOCK_REPO="$LK" AIENOS_LOCK=0123456789abcdef0123456789abcdef01234567 bash "$T" identity)" = 2 ]'
check "abbreviated lock refused: exit 2" '[ "$(rc L AIENOS_LOCK=${GOOD:0:7} bash "$T" identity)" = 2 ]'
check "uppercase or padded lock refused: exit 2" '[ "$(rc L AIENOS_LOCK="${GOOD^^}" bash "$T" identity)" = 2 ] && [ "$(rc L AIENOS_LOCK="$GOOD " bash "$T" identity)" = 2 ]'
lkg replace "$A" "$GOOD"
check "replace ref A->GOOD ignored: A still lacks mint" '! L AIENOS_LOCK=$A bash "$T" show native/capability/aienos_capability.c | grep -q aienos_cap_mint'
lkg replace -d "$A" >/dev/null
# a loose object whose bytes were replaced on disk (here: by another object's bytes) no
# longer hashes to its id
CORR=$SCR/corrupt; cp -r "$LK" "$CORR"
B=$(git -C "$CORR" rev-parse "$A:native/capability/aienos_capability.c")
X=$(printf 'int aienos_cap_mint(int a)\n{ return a; }\n' | git -C "$CORR" hash-object --stdin -w)
obj="$CORR/.git/objects/${B:0:2}/${B:2}"
chmod u+w "$obj" && cp "$CORR/.git/objects/${X:0:2}/${X:2}" "$obj"
check "altered object bytes: refused (exit 2), never read as content" '[ "$(rc env AIENOS_LOCK_REPO="$CORR" AIENOS_R7_DIR= AIENOS_LOCK=$A bash "$T" show native/capability/aienos_capability.c)" = 2 ]'

# 1b. aienux folded into omega-mv as kernel/: the lock names an omega-mv commit, and the source is
# that commit's kernel/ tree; a commit without kernel/ is read at its root. No map is read.
OM=$SCR/omega-fold; mkdir -p "$OM/kernel"
git -C "$LK" archive "$GOOD" native | tar -x -C "$OM/kernel"
omg() { git -C "$OM" -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false "$@"; }
omg init -q && omg add -A && omg commit -qm "kernel/ at GOOD"; OMC=$(git -C "$OM" rev-parse HEAD)
omg rm -q -r kernel && omg commit -qm "no kernel/"; OMN=$(git -C "$OM" rev-parse HEAD)
printf 'old new\n%s %s\n' "$GOOD" "$OMN" > "$SCR/map-elsewhere"
K() { env AIENOS_LOCK_REPO="$OM" AIENOS_R7_DIR= "$@"; }
check "kernel/ commit: the locked file read from its kernel/ (exit 0)" '[ "$(K AIENOS_LOCK=$OMC bash "$T" show native/capability/aienos_capability.c)" = "$(git -C "$LK" show $GOOD:native/capability/aienos_capability.c)" ]'
check "kernel/ commit: identity names the lock and its kernel/ tree" '[ "$(K AIENOS_LOCK=$OMC bash "$T" identity | jq -r "[.source, .aienos_lock, .commit_tree] | join(\" \")")" = "omega-mv-kernel $OMC $(git -C "$OM" rev-parse $OMC:kernel)" ]'
check "kernel/ commit: a commit map naming another commit is not read (AIENOS_COMMIT_MAP)" '[ "$(K AIENOS_LOCK=$OMC AIENOS_COMMIT_MAP=$SCR/map-elsewhere bash "$T" identity | jq -r .commit_tree)" = "$(git -C "$OM" rev-parse $OMC:kernel)" ]'
check "kernel/ commit: an aienux lock the repository does not hold is unavailable, map or not: exit 2" '[ "$(rc K AIENOS_LOCK=$GOOD AIENOS_COMMIT_MAP=$SCR/map-elsewhere bash "$T" identity)" = 2 ]'
check "commit without kernel/: read at its root, where the file is absent: exit 1" '[ "$(rc K AIENOS_LOCK=$OMN bash "$T" show native/capability/aienos_capability.c)" = 1 ]'
KD=$SCR/kcache
check "kernel/ commit: materialize and verify (exit 0)" '[ "$(rc K AIENOS_LOCK=$OMC bash "$T" materialize "$KD" native/capability)" = 0 ]'
echo 'int edited;' >> "$KD/native/capability/aienos_capability.c"
check "kernel/ commit: an edited materialized file: exit 1" '[ "$(rc K AIENOS_LOCK=$OMC bash "$T" verify-dir "$KD" native/capability)" = 1 ]'

# This repository: aienos.lock and argus.lock name omega-mv commits whose kernel/ is the source (a
# full clone is needed; every clone the gates run in has the history). lockprov DIR LOCKFILE: line 1
# is a full commit id, the file has exactly one "# aienux H" line, and DIR's kernel/import/commit-map
# has exactly one row for H, naming line 1. That is a consistency check of the provenance line; the
# source itself is proven from line 1 alone.
lockprov() {
    local c h rows
    c=$(head -n 1 "$1/$2"); h=$(awk '$1 == "#" && $2 == "aienux" {print $3; n++} END {exit n != 1}' "$1/$2") || return 1
    [[ "$c" =~ ^[0-9a-f]{40}$ && "$h" =~ ^[0-9a-f]{40}$ ]] || return 1
    rows=$(awk -v h="$h" 'NR > 1 && $1 == h' "$1/kernel/import/commit-map")
    [ "$rows" = "$h $c" ]
}
for lf in aienos.lock argus.lock; do
    check "this repository: $lf is an omega-mv commit read at its kernel/ (exit 0)" '[ "$(env -u AIENOS_LOCK_REPO -u AIENOS_COMMIT_MAP AIENOS_R7_DIR= AIENOS_LOCK=$(head -n 1 "$HERE/$lf") bash "$T" identity | jq -r "[.source, .commit_tree] | join(\" \")")" = "omega-mv-kernel $(git -C "$HERE" rev-parse "$(head -n 1 "$HERE/$lf"):kernel")" ]'
    check "this repository: $lf provenance line agrees with kernel/import/commit-map" 'lockprov "$HERE" $lf'
done
check "this repository: an explicit lock repository without the commit is the only one tried: exit 2" '[ "$(rc env -u AIENOS_LOCK AIENOS_LOCK_REPO=/nonexistent AIENOS_R7_DIR= bash "$T" identity)" = 2 ]'
# Reviewer finding 4 (omega-mv c9e503afd) and variants, on a scratch clone S of this repository with
# this work tree's tool and locks: E is a commit whose kernel/native/capability/aienos_capability.c
# gains a line. Each forged state must leave the served source the locked one, or fail lockprov.
S=$SCR/forge; git clone -q -s -n "$HERE" "$S"
sg() { git -C "$S" -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
CAP=kernel/native/capability/aienos_capability.c
sg checkout -q HEAD -- kernel/import/commit-map "$CAP" && mkdir -p "$S/tools" &&
    cp "$HERE/tools/aienos_lock_source.sh" "$S/tools/" && cp "$HERE/aienos.lock" "$HERE/argus.lock" "$S/"
ALOCK=$(head -n 1 "$HERE/aienos.lock"); AUX=$(awk '$1 == "#" && $2 == "aienux" {print $3}' "$HERE/aienos.lock")
WANTCAP=$(git -C "$HERE" show "$ALOCK:$CAP")
echo 'int forged_capability;' >> "$S/$CAP"; sg commit -q --no-verify -m "edit capability source" -- "$CAP"; E=$(git -C "$S" rev-parse HEAD)
TS="$S/tools/aienos_lock_source.sh"
servedlocked() { [ "$(env -u AIENOS_LOCK -u AIENOS_LOCK_REPO AIENOS_R7_DIR= "$@" bash "$TS" show native/capability/aienos_capability.c)" = "$WANTCAP" ]; }
cp "$S/kernel/import/commit-map" "$SCR/map-orig"
awk -v h="$AUX" -v e="$E" '$1 == h {$2 = e} {print}' "$SCR/map-orig" > "$S/kernel/import/commit-map"
sg commit -q --no-verify -m "repoint map row" -- kernel/import/commit-map
check "finding 4: map row repointed to an edited capability source: the locked source is still served" 'servedlocked'
check "finding 4: map row repointed: the provenance check fails" '! lockprov "$S" aienos.lock'
check "finding 4: map row repointed: verify-dir of the edited kernel/ fails: exit 1" '[ "$(rc env -u AIENOS_LOCK -u AIENOS_LOCK_REPO AIENOS_R7_DIR= bash "$TS" verify-dir "$S/kernel" native/capability)" = 1 ]'
check "variant: AIENOS_COMMIT_MAP naming the forged map is not read" 'servedlocked AIENOS_COMMIT_MAP="$S/kernel/import/commit-map"'
cp "$SCR/map-orig" "$S/kernel/import/commit-map"
{ head -n 1 "$SCR/map-orig"; printf '%s %s\n' "$AUX" "$E"; tail -n +2 "$SCR/map-orig"; } > "$S/kernel/import/commit-map"
check "variant: a second map row for the locked aienux commit, naming E: the provenance check fails" '! lockprov "$S" aienos.lock'
check "variant: the second row is not read either" 'servedlocked'
cp "$SCR/map-orig" "$S/kernel/import/commit-map"
{ echo "$E"; tail -n +2 "$HERE/aienos.lock"; } > "$S/aienos.lock"
check "variant: aienos.lock repointed to E, map unchanged: the provenance check fails" '! lockprov "$S" aienos.lock'
{ echo "$E"; echo "# aienux $(printf 'a%.0s' $(seq 40))"; tail -n +3 "$HERE/aienos.lock"; } > "$S/aienos.lock"
check "variant: aienos.lock repointed to E with an aienux line no row has: the provenance check fails" '! lockprov "$S" aienos.lock'
{ echo "$E"; tail -n +3 "$HERE/aienos.lock"; } > "$S/aienos.lock"
check "variant: aienos.lock repointed to E without its aienux line: the provenance check fails" '! lockprov "$S" aienos.lock'
cp "$HERE/aienos.lock" "$S/aienos.lock"
sg replace "$ALOCK" "$E"
check "variant: a replace ref from the locked commit to E is ignored" 'servedlocked'
sg replace -d "$ALOCK" > /dev/null
check "control: the unforged scratch clone passes the provenance check" 'lockprov "$S" aienos.lock && lockprov "$S" argus.lock'

# 2. directories: proven only against the locked commit
D=$SCR/cache
check "materialize into an empty cache: exit 0" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" materialize "$D" native/capability)" = 0 ]'
check "proven cache verifies: exit 0" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 0 ]'
make -s -C "$D/native/capability" >/dev/null 2>&1
check "in-tree build outputs (ignored out/, could hold planted objects) refused: exit 1" '[ -f "$D/native/capability/out/libaienos_capability.a" ] && [ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
rm -rf "$D/native/capability/out"
echo 'int evil;' > "$D/native/capability/evil.c"; printf '*.c\n' > "$D/.gitignore"; printf 'evil.c\n' > "$D/native/.gitignore"
check "extra file hidden by ignore files above the checked subpath: exit 1" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
rm -f "$D/native/capability/evil.c" "$D/.gitignore" "$D/native/.gitignore"
chmod +x "$D/native/capability/aienos_capability.c"
check "file mode changed: exit 1" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
chmod -x "$D/native/capability/aienos_capability.c"
# Attribute and config filters must not decide what "matches" means: a planted
# "* text eol=lf" (root, above the subpath, or in the lock repo's info/attributes)
# plus core.autocrlf would make git normalize CRLF edits away.
sed -i 's/$/\r/' "$D/native/capability/aienos_capability.c"
printf '* text eol=lf\n' > "$D/.gitattributes"; printf '* text eol=lf\n' > "$D/native/.gitattributes"
mkdir -p "$(git -C "$LK" rev-parse --absolute-git-dir)/info"; printf '* text eol=lf\n' > "$(git -C "$LK" rev-parse --absolute-git-dir)/info/attributes"
check "CRLF edit hidden by planted .gitattributes and info/attributes: exit 1" '[ "$(rc L GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=input AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
rm -f "$D/.gitattributes" "$D/native/.gitattributes" "$(git -C "$LK" rev-parse --absolute-git-dir)/info/attributes"
git -C "$LK" show "$GOOD:native/capability/aienos_capability.c" > "$D/native/capability/aienos_capability.c"
check "restored file verifies again: exit 0" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 0 ]'
cp "$D/native/capability/aienos_capability.c" "$SCR/same-bytes.c"; rm "$D/native/capability/aienos_capability.c"
ln -s "$SCR/same-bytes.c" "$D/native/capability/aienos_capability.c"
check "file replaced by a symlink to identical bytes: exit 1" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
rm "$D/native/capability/aienos_capability.c"; cp "$SCR/same-bytes.c" "$D/native/capability/aienos_capability.c"
echo 'int injected;' >> "$D/native/capability/aienos_capability.c"
check "modified cached source: exit 1" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
check "materialize does not re-extract over a modified cache: exit 1" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" materialize "$D" native/capability)" = 1 ]'
git -C "$LK" show "$GOOD:native/capability/aienos_capability.c" > "$D/native/capability/aienos_capability.c"
echo 'int extra;' > "$D/native/capability/extra.c"
check "extra unignored file beside the locked sources: exit 1" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
rm "$D/native/capability/extra.c" "$D/native/capability/Makefile"
check "missing locked file: exit 1" '[ "$(rc L AIENOS_LOCK=$GOOD bash "$T" verify-dir "$D" native/capability)" = 1 ]'
UNREL=$SCR/unrelated; mkdir -p "$UNREL/native/capability"; cp "$LK/native/capability/"* "$UNREL/native/capability/"
check "unrelated directory with plausible functions, no lock repo: exit 2" '[ "$(rc env AIENOS_LOCK_REPO=/nonexistent AIENOS_R7_DIR="$UNREL" AIENOS_LOCK=$GOOD bash "$T" verify-dir "$UNREL" native/capability)" = 2 ]'
check "unrelated directory checked against lock A: exit 1" '[ "$(rc L AIENOS_LOCK=$A bash "$T" verify-dir "$UNREL" native/capability)" = 1 ]'
CL=$SCR/clone; git clone -q "$LK" "$CL"; git -C "$CL" -c advice.detachedHead=false checkout -q "$GOOD"
check "clean checkout of a different commit (GOOD) against lock A: exit 1" '[ "$(rc env AIENOS_LOCK_REPO=/nonexistent AIENOS_R7_DIR="$CL" AIENOS_LOCK=$A bash "$T" verify-dir "$CL" native/capability)" = 1 ]'
check "clean checkout of the locked commit, proven through its own repository: exit 0" '[ "$(rc env AIENOS_LOCK_REPO=/nonexistent AIENOS_R7_DIR="$CL" AIENOS_LOCK=$GOOD bash "$T" verify-dir "$CL" native/capability)" = 0 ]'
echo 'int dirty;' >> "$CL/native/capability/aienos_capability.c"
check "dirty checkout of the locked commit: exit 1" '[ "$(rc env AIENOS_LOCK_REPO=/nonexistent AIENOS_R7_DIR="$CL" AIENOS_LOCK=$GOOD bash "$T" verify-dir "$CL" native/capability)" = 1 ]'

# 3. the Makefile rule: the capability library is built only from a proven source, on every build
# This section drives the Makefile in its own private copy $W and checks the default layout
# ($W/build/...); a per-step OUT_DIR exported by tests/gates/run.sh does not apply here.
unset OUT_DIR
W=$SCR/omega; mkdir -p "$W"
cp -r "$HERE/Makefile" "$HERE/mk" "$HERE/tools" "$W/"
cp "$HERE/physics.lock" "$W/" 2>/dev/null || true
echo "$GOOD" > "$W/aienos.lock"
M() { make -s -C "$W" AIENOS_LOCK_REPO="$LK" "$@" >"$SCR/make.log" 2>&1; echo $?; }
check "make: default cache materialized and library built" '[ "$(M build/aienos-cap/$GOOD/libaienos_capability.a)" = 0 ] && [ -f "$W/build/aienos-cap/$GOOD/libaienos_capability.a" ] && [ ! -e "$W/build/aienos-authority/$GOOD/native/capability/out" ]'
L1=$(stat -c %Y.%s "$W/build/aienos-cap/$GOOD/libaienos_capability.a"); sleep 1
check "make: second build replaces nothing (no relink)" '[ "$(M build/aienos-cap/$GOOD/libaienos_capability.a)" = 0 ] && [ "$(stat -c %Y.%s "$W/build/aienos-cap/$GOOD/libaienos_capability.a")" = "$L1" ]'
printf 'junk' > "$W/build/aienos-cap/$GOOD/libaienos_capability.a"
check "make: planted library replaced by the fresh build from the proven source" '[ "$(M build/aienos-cap/$GOOD/libaienos_capability.a)" = 0 ] && ar t "$W/build/aienos-cap/$GOOD/libaienos_capability.a" | grep -q aienos_capability.o'
echo 'int injected;' >> "$W/build/aienos-authority/$GOOD/native/capability/aienos_capability.c"
check "make: cache edited after extraction stops the next build" '[ "$(M build/aienos-cap/$GOOD/libaienos_capability.a)" != 0 ] && grep -q "not the aienos.lock commit" "$SCR/make.log"'
check "make: unrelated AIENOS_R7_DIR override refused" '[ "$(M AIENOS_R7_DIR="$UNREL" build/aienos-cap/$GOOD/libaienos_capability.a)" != 0 ]'
git -C "$CL" checkout -q -- .
check "make: clean checkout of a different commit as override refused" '[ "$(cd "$CL" && git -c advice.detachedHead=false checkout -q "$A"; M AIENOS_R7_DIR="$CL" build/aienos-cap/$GOOD/libaienos_capability.a)" != 0 ]'
git -C "$CL" checkout -q "$GOOD"
mkdir -p "$CL/native/capability/out"; echo planted > "$CL/native/capability/out/aienos_capability.o"
check "make: locked checkout with a planted out/ object refused" '[ "$(M AIENOS_R7_DIR="$CL" build/aienos-cap/$GOOD/libaienos_capability.a)" != 0 ]'
rm -rf "$CL/native/capability/out"
check "make: clean checkout of the locked commit as override builds" '[ "$(M AIENOS_R7_DIR="$CL" build/aienos-cap/$GOOD/libaienos_capability.a)" = 0 ]'
check "make: lock repository missing the commit refused" '[ "$(make -s -C "$W" AIENOS_LOCK_REPO=/nonexistent AIENOS_R7_DIR="$UNREL" build/aienos-cap/$GOOD/libaienos_capability.a >/dev/null 2>&1; echo $?)" != 0 ]'

if [ "$FAILS" -ne 0 ]; then echo "aienos lock source test: $FAILS FAILED"; exit 1; fi
echo "aienos lock source test: PASS"
