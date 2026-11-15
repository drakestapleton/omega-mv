#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/omc/tests/pins/admission-check.sh: TEST INSTRUMENT (shell; never on a product path).
# Compiler admission, measured at its boundary, for every consumer that is handed a compiler and takes
# the expected digest from the record seed/out/omc.sha256 (written by seed/omega-from-seed.sh).
# Usage, from anywhere: sh seed/omc/tests/pins/admission-check.sh [OMC]   (OMC defaults to seed/out/omc)
#
# One table (the consumers function) drives every row. Each row runs the unchanged consumer in a private
# scratch tree that holds only the consumer's own files, the record, sentinel files where it builds, and a
# decoy compiler: a script that is not the recorded compiler and appends to a marker file if it is run.
#   wrong      the real record, the decoy, and every pin-looking environment variable (EFFECTS_OMC_PIN,
#              SEMHASH_OMC_PIN, JSON_OMC_PIN, OMC_PIN, PIN, pin, canonical_pin) set to the decoy's digest
#   missing    no record
#   malformed  a record whose digest has 63 hex digits
#   twin       the setup of "wrong" with the record naming the decoy's digest: its positive twin
# wrong, missing and malformed must exit 3 and print exactly the consumer's refusal line and nothing else,
# with: the marker absent (the decoy never ran); the trace empty (git, cc, gcc, make, openssl, strace,
# bwrap, mkdir, rm, mktemp and python3 are found first on PATH as logging shims, and none was started);
# the tree manifest unchanged (every path, type, mode and file sha256, sentinels included); the private
# TMPDIR empty. The twin must get past admission: neither refusal line in its output, and the marker,
# the trace, the manifest, TMPDIR or a line the consumer prints after its admission shows later work
# (each twin row prints what it observed). A consumer whose twin still refuses has INVALID controls,
# which is a failure here, never a pass.
# seed/effects/check.sh has four more rows for the section-11 recording path (OMC_BINARY).
# Static row: one grep of the tracked files for the record's name; every hit must be classified in the
# classify function below (controlled here, or named with its class). An unclassified reader fails, so a
# new consumer cannot appear without a row.
# Exit 0 PASS (last line "ADMISSION PASS consumers=N rows=M twins=K readers=R"), 1 FAIL, 3 NOT_RUN.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
for t in sha256sum sed grep find sort stat timeout git python3 cmp readlink; do
  command -v $t > /dev/null || { echo "ADMISSION NOT_RUN: $t missing"; exit 3; }
done
PIN=$(sed -n '$!d;1s/^\([0-9a-f]\{64\}\)  seed\/out\/omc$/\1/p' "$ROOT/seed/out/omc.sha256" 2>/dev/null) || PIN=
[ ${#PIN} = 64 ] || { echo "ADMISSION NOT_RUN: no compiler pin in seed/out/omc.sha256"; exit 3; }
[ -x "$OMC" ] && [ "$(sha256sum < "$OMC" | cut -c1-64)" = "$PIN" ] || { echo "ADMISSION NOT_RUN: $OMC is not the recorded compiler $PIN"; exit 3; }
git -C "$ROOT" rev-parse --is-inside-work-tree > /dev/null 2>&1 || { echo "ADMISSION NOT_RUN: $ROOT is not a git checkout (the static row needs the tracked file list)"; exit 3; }
T=$(mktemp -d "${TMPDIR:-/tmp}/omega-admission.XXXXXXXX"); trap 'rm -rf "$T"' EXIT HUP INT TERM
PATH0=$PATH
PY=$(command -v python3)

# The decoy and its digest.
DECOY=$T/decoy-omc
printf '#!/bin/sh\n# admission-check.sh decoy: never the recorded compiler; running it leaves the marker\nprintf '"'"'executed\\n'"'"' >> "$ADMISSION_MARKER"\nexit 97\n' > "$DECOY"; chmod 755 "$DECOY"
DSHA=$(sha256sum < "$DECOY" | cut -c1-64)
[ "$DSHA" != "$PIN" ] || { echo "ADMISSION NOT_RUN: the decoy hashes to the pin"; exit 3; }

# Logging shims. Dependency and build tools only log and exit 97; the tools a consumer needs to make or
# remove build state log and then run, so a twin really changes its tree.
SHIM=$T/shim; mkdir "$SHIM"
for t in git cc gcc make openssl strace bwrap; do
  printf '#!/bin/sh\nprintf '"'"'%%s\\n'"'"' "%s $*" >> "$ADMISSION_TRACE"\nexit 97\n' "$t" > "$SHIM/$t"; chmod 755 "$SHIM/$t"
done
for t in mkdir rm mktemp python3; do
  real=$(command -v $t)
  printf '#!/bin/sh\nprintf '"'"'%%s\\n'"'"' "%s $*" >> "$ADMISSION_TRACE"\nexec %s "$@"\n' "$t" "$real" > "$SHIM/$t"; chmod 755 "$SHIM/$t"
done

# seed/profile/check.om is a program: build it once with the recorded compiler.
PROFILE=$T/profile-check
"$OMC" < "$ROOT/seed/profile/check.om" > "$PROFILE" 2> "$T/profile-check.err" && [ ! -s "$T/profile-check.err" ] || {
  echo "ADMISSION FAIL seed/profile/check.om does not compile: $(cat "$T/profile-check.err")"; exit 1; }
chmod 755 "$PROFILE"

# consumers: ID|files copied into the scratch tree (the first is the consumer)|directories given a sentinel
consumers() { cat <<'TABLE'
units|om/units.sh om/omega-bridge.lock|src
par-aarch64|om/aarch64/parity/run.sh om/omega-bridge.lock|
par-evidence|om/evidence/parity/run.sh om/omega-bridge.lock|
par-gpumath|om/gpumath/parity/run.sh om/omega-bridge.lock|
par-receipt|om/receipt/parity/run.sh om/omega-bridge.lock|
par-codec|om/codec/parity/run.sh|
par-blake3|om/blake3/parity/run.sh om/units.sh om/omega-bridge.lock|src
tls-ec|om/tls/test/ec/run.sh|build/tls/ec
tls-ecdh|om/tls/test/ecdh/run.sh|build/tls/ecdh
tls-rsa|om/tls/test/rsa/run.sh|build/tls/rsa
tls-rev|om/tls/test/rev/run.sh|build/tls/rev
tls-x509|om/tls/test/x509/run.sh|build/tls/x509
tls-limbo|om/tls/test/x509/limbo.sh|build/tls/x509/limbo
profile|seed/profile/check.om seed/qualification/om2/fixtures/sha256-k.dec seed/qualification/om2/fixtures/sha256-iv.dec|build/seed
qualify|seed/qualification/om2/current/qualify.py|build/seed
irequiv|seed/equiv/gate-irequiv.sh|build/seed/equiv
json|seed/json/tests/gate-json.sh|build/seed/json
irnki|seed/nki/gate-irnki.sh|build/seed/nki
irspirv|seed/spirv/gate-irspirv.sh|build/seed/spirv
vkspirv|seed/spirv/gate-vkspirv.sh|build/seed/vkspirv
irstablehlo|seed/stablehlo/gate-irstablehlo.sh|build/seed/stablehlo
tensix|seed/tensix/gate-tensix.sh|build/seed/tensix
irwasm|seed/wasm/gate-irwasm.sh|build/seed/wasm
orig4|tests/orig4/run.sh native/orig4/orig4.pin|build/orig4 build/orig4-build
semhash|seed/semhash/check.sh|build/semhash-check
effects|seed/effects/check.sh seed/omc/tests/pools/record-compiler.sh|build/seed/effects
TABLE
}

# refusal ID CASE W: the one line the consumer must print (W is the decoy's path in the scratch tree).
refusal() {
  case $2 in
  wrong)
    case $1 in
    units) echo "NOT_RUN: omc is not the pinned compiler" ;;
    par-aarch64) echo "AARCH64-PARITY NOT_RUN: omc is not the pinned compiler" ;;
    par-evidence) echo "EVIDENCE-PARITY NOT_RUN: omc is not the pinned compiler" ;;
    par-gpumath) echo "GPUMATH-PARITY NOT_RUN: omc is not the pinned compiler" ;;
    par-receipt) echo "RECEIPT-PARITY NOT_RUN: omc is not the pinned compiler" ;;
    par-codec) echo "NOT_RUN: $3 is not the pinned omc" ;;
    par-blake3) echo "BLAKE3-PARITY NOT_RUN: omc is not the pinned compiler" ;;
    tls-ec) echo "EC NOT_RUN: omc is not the pinned compiler $PIN" ;;
    tls-ecdh) echo "ECDH NOT_RUN: omc is not the pinned compiler $PIN" ;;
    tls-rsa) echo "RSA NOT_RUN: omc is not the pinned compiler $PIN" ;;
    tls-rev) echo "REV NOT_RUN: omc is not the pinned compiler $PIN" ;;
    tls-x509) echo "X509 NOT_RUN: omc is not the pinned compiler $PIN" ;;
    tls-limbo) echo "LIMBO NOT_RUN: omc is not the pinned compiler $PIN" ;;
    profile) echo "NOT_RUN profile: omc is not the pinned compiler $PIN" ;;
    qualify) echo "ABI_SHA_GATE NOT_RUN: omc is not the pinned compiler $PIN; nothing was created" ;;
    json) echo "JSONGATE NOT_RUN gate-json: compiler $3 sha256 $DSHA differs from pin $PIN" ;;
    irequiv|irnki|irspirv|vkspirv|irstablehlo|tensix|irwasm) echo "NOT_RUN gate-$1: compiler $3 sha256 $DSHA differs from pin $PIN" ;;
    orig4) echo "ORIG4_SHADOW NOT_RUN: compiler hash $DSHA differs from seed/out/omc.sha256" ;;
    semhash) echo "SEMHASH NOT_RUN compiler $3 sha256 $DSHA differs from pin $PIN" ;;
    effects) echo "NOT_RUN effects: omc is not the pinned compiler $PIN" ;;
    esac ;;
  missing|malformed)
    case $1 in
    units|par-codec) echo "NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    par-aarch64) echo "AARCH64-PARITY NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    par-evidence) echo "EVIDENCE-PARITY NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    par-gpumath) echo "GPUMATH-PARITY NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    par-receipt) echo "RECEIPT-PARITY NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    par-blake3) echo "BLAKE3-PARITY NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    tls-ec) echo "EC NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    tls-ecdh) echo "ECDH NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    tls-rsa) echo "RSA NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    tls-rev) echo "REV NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    tls-x509) echo "X509 NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    tls-limbo) echo "LIMBO NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    profile) echo "NOT_RUN profile: no compiler pin in seed/out/omc.sha256" ;;
    qualify)
      if [ "$2" = missing ]; then echo "ABI_SHA_GATE NOT_RUN: no compiler pin in seed/out/omc.sha256: [Errno 2] No such file or directory: '${3%/omc}/omc.sha256'; nothing was created"
      else echo "ABI_SHA_GATE NOT_RUN: no compiler pin in seed/out/omc.sha256; nothing was created"; fi ;;
    json) echo "JSONGATE NOT_RUN gate-json: no compiler pin in seed/out/omc.sha256" ;;
    irequiv|irnki|irspirv|vkspirv|irstablehlo|tensix|irwasm) echo "NOT_RUN gate-$1: compiler pin file missing or malformed" ;;
    orig4) echo "ORIG4_SHADOW NOT_RUN: no compiler pin in seed/out/omc.sha256" ;;
    semhash) echo "SEMHASH NOT_RUN no compiler pin in seed/out/omc.sha256" ;;
    effects) echo "NOT_RUN effects: no compiler pin in seed/out/omc.sha256" ;;
    esac ;;
  esac
}

manifest() { # TREE: every path with type, mode and content digest
  (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then printf 'l %s -> %s\n' "$p" "$(readlink "$p")"
    elif [ -f "$p" ]; then printf 'f %s %s %s\n' "$(stat -c %a "$p")" "$(sha256sum < "$p" | cut -c1-64)" "$p"
    elif [ -d "$p" ]; then printf 'd %s %s\n' "$(stat -c %a "$p")" "$p"
    else printf '? %s\n' "$p"; fi
  done)
}

# setup ID CASE FILES SENTINELS: builds $T/ID.CASE/{tree,home,tmp}; the record follows CASE.
setup() {
  r=$T/$1.$2; t=$r/tree
  mkdir -p "$t/seed/out" "$t/build" "$t/bridge" "$r/home" "$r/tmp"
  for f in $3; do mkdir -p "$t/$(dirname "$f")"; cp -p "$ROOT/$f" "$t/$f"; done
  cp "$DECOY" "$t/seed/out/omc"
  case $2 in
    wrong|wrapped-*) cp "$ROOT/seed/out/omc.sha256" "$t/seed/out/omc.sha256" ;;
    missing) ;;
    malformed) printf '%s  seed/out/omc\n' "$(printf '%s' "$PIN" | cut -c1-63)" > "$t/seed/out/omc.sha256" ;;
    twin) printf '%s  seed/out/omc\n' "$DSHA" > "$t/seed/out/omc.sha256" ;;
  esac
  for d in build $4; do mkdir -p "$t/$d"; printf 'sentinel %s\n' "$d" > "$t/$d/SENTINEL"; done
  if [ "$1" = orig4 ]; then printf 'sentinel summary\n' > "$t/build/orig4/summary.txt"; fi
  manifest "$t" > "$r/manifest.before"
}

# invoke ID: runs the consumer of the scratch tree prepared by setup, in a cleared environment.
invoke() {
  w=$t/seed/out/omc
  case $1 in
    units) set -- OMEGA_OMC="$w" OMEGA_BRIDGE="$t/bridge" sh "$t/om/units.sh" --check ;;
    par-aarch64|par-evidence|par-gpumath|par-receipt) d=${1#par-}; set -- OMEGA_OMC="$w" OMEGA_BRIDGE="$t/bridge" sh "$t/om/$d/parity/run.sh" ;;
    par-codec) set -- OMEGA_OMC="$w" sh "$t/om/codec/parity/run.sh" ;;
    par-blake3) set -- OMEGA_OMC="$w" OMEGA_BRIDGE="$t/bridge" sh "$t/om/blake3/parity/run.sh" ;;
    tls-ec|tls-ecdh|tls-rsa|tls-rev|tls-x509) s=${1#tls-}; set -- sh "$t/om/tls/test/$s/run.sh" "$w" ;;
    tls-limbo) set -- sh "$t/om/tls/test/x509/limbo.sh" "$w" "$t/build/tls/x509/limbo-src" ;;
    profile) set -- "$PROFILE" ;;
    qualify) set -- "$PY" "$t/seed/qualification/om2/current/qualify.py" --bridge "$t/bridge" --output "$t/build/qualify-out" ;;
    irequiv) set -- OMC="$w" sh "$t/seed/equiv/gate-irequiv.sh" ;;
    json) set -- OMC="$w" sh "$t/seed/json/tests/gate-json.sh" ;;
    irnki) set -- OMC="$w" sh "$t/seed/nki/gate-irnki.sh" ;;
    irspirv) set -- OMC="$w" sh "$t/seed/spirv/gate-irspirv.sh" ;;
    vkspirv) set -- OMC="$w" sh "$t/seed/spirv/gate-vkspirv.sh" ;;
    irstablehlo) set -- OMC="$w" sh "$t/seed/stablehlo/gate-irstablehlo.sh" ;;
    tensix) set -- OMC="$w" sh "$t/seed/tensix/gate-tensix.sh" ;;
    irwasm) set -- OMC="$w" sh "$t/seed/wasm/gate-irwasm.sh" ;;
    orig4) set -- OUT="$t/build/orig4" BUILD="$t/build/orig4-build" ORIG4_TRAIN_GIT="$t/no-train" sh "$t/tests/orig4/run.sh" ;;
    semhash) set -- OMC="$w" sh "$t/seed/semhash/check.sh" ;;
    effects) set -- OMC="$w" sh "$t/seed/effects/check.sh" ;;
    effects-wrapped) shift; set -- OMC="$1" OMC_BINARY="$2" sh "$t/seed/effects/check.sh" ;;
  esac
  rc=0
  (cd "$t" && exec timeout 120 env -i PATH="$SHIM:$PATH0" HOME="$r/home" TMPDIR="$r/tmp" LC_ALL=C \
      ADMISSION_MARKER="$r/marker" ADMISSION_TRACE="$r/trace" \
      EFFECTS_OMC_PIN="$DSHA" SEMHASH_OMC_PIN="$DSHA" JSON_OMC_PIN="$DSHA" OMC_PIN="$DSHA" PIN="$DSHA" pin="$DSHA" canonical_pin="$DSHA" \
      "$@") > "$r/out" 2>&1 < /dev/null || rc=$?
  manifest "$t" > "$r/manifest.after"
  marker=absent; [ ! -e "$r/marker" ] || marker=PRESENT
  trace=empty; [ ! -s "$r/trace" ] || trace="[$(tr '\n' ';' < "$r/trace" | cut -c1-120)]"
  tree=unchanged; cmp -s "$r/manifest.before" "$r/manifest.after" || tree=CHANGED
  tmp=empty; [ -z "$(ls -A "$r/tmp")" ] || tmp=USED
}

fails=0; rows=0; twins=0; ncons=0
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

# refused NAME WANT: the last invoke must be an exact refusal that did nothing.
refused() {
  rows=$((rows + 1))
  printf '%s\n' "$2" > "$r/want"
  if [ "$rc" = 3 ] && cmp -s "$r/want" "$r/out" && [ "$marker" = absent ] && [ "$trace" = empty ] && [ "$tree" = unchanged ] && [ "$tmp" = empty ]; then
    echo "PASS $1: exit 3, exact line [$2], marker absent, trace empty, tree unchanged, TMPDIR empty"
  else
    bad "$1: exit $rc marker=$marker trace=$trace tree=$tree tmp=$tmp; wanted exit 3 and exactly [$2]; got:"; sed 's/^/  | /' "$r/out" | head -n 6
  fi
}

consumers > "$T/table"
while IFS='|' read -r id files sentinels; do
  ncons=$((ncons + 1))
  # The twin first: a consumer whose twin does not get past admission has no valid control.
  setup "$id" twin "$files" "$sentinels"; invoke "$id"
  w=$t/seed/out/omc
  twins=$((twins + 1)); rows=$((rows + 1))
  refusal "$id" wrong "$w" > "$r/no1"; refusal "$id" missing "$w" > "$r/no2"
  if grep -qFf "$r/no1" "$r/out" || grep -qFf "$r/no2" "$r/out"; then
    bad "$id twin: INVALID, the record names the decoy and the consumer still refuses (exit $rc):"; sed 's/^/  | /' "$r/out" | head -n 4
  elif [ "$marker" = absent ] && [ "$trace" = empty ] && [ "$tree" = unchanged ] && [ "$tmp" = empty ] && [ ! -s "$r/out" ]; then
    bad "$id twin: INVALID, nothing observed after admission (exit $rc, no output)"
  else
    echo "PASS $id twin: admitted when the record names the decoy (exit $rc, marker=$marker trace=$trace tree=$tree tmp=$tmp, first line [$(sed -n 1p "$r/out" | cut -c1-90)])"
  fi
  for c in wrong missing malformed; do
    setup "$id" "$c" "$files" "$sentinels"; invoke "$id"
    refused "$id $c" "$(refusal "$id" "$c" "$t/seed/out/omc")"
  done
done < "$T/table"

# seed/effects/check.sh, section-11 recording path: OMC is a runner and OMC_BINARY names the compiler ELF.
# The runner is admitted by what it is (shebang, the binding of OMC_BINARY, one log binding, the tracked
# record-compiler.sh), never by a digest the caller supplies.
recorder() { # OUT REAL LOG [EXTRA-LINE]
  { printf "#!/bin/sh\nOMC_RECORD_REAL='%s'\nOMC_RECORD_LOG='%s'\n" "$2" "$3"; cat "$ROOT/seed/omc/tests/pools/record-compiler.sh"; [ -z "${4:-}" ] || printf '%s\n' "$4"; } > "$1"; chmod 755 "$1"
}
EF="seed/effects/check.sh seed/omc/tests/pools/record-compiler.sh"
setup effects wrapped-twin "$EF" build/seed/effects; cp "$OMC" "$r/real-omc"
recorder "$r/runner" "$r/real-omc" "$r/record.log"
invoke effects-wrapped "$r/runner" "$r/real-omc"
rows=$((rows + 1)); twins=$((twins + 1))
if [ "$(sed -n 1p "$r/out")" = "effects wrapped runner-sha256=$(sha256sum < "$r/runner" | cut -c1-64) compiler-artifact-sha256=$PIN" ]; then
  echo "PASS effects wrapped-twin: the section-11 recorder bound to the recorded compiler is admitted as a wrapped run"
else
  bad "effects wrapped-twin: INVALID, the real recorder is not admitted (exit $rc):"; sed 's/^/  | /' "$r/out" | head -n 4
fi
NOTREC="NOT_RUN effects: OMC is not section 11's recording runner for the pinned compiler $PIN"
setup effects wrapped-decoy "$EF" build/seed/effects; cp "$OMC" "$r/real-omc"
invoke effects-wrapped "$t/seed/out/omc" "$r/real-omc"
refused "effects wrapped-decoy (OMC=decoy, OMC_BINARY=recorded compiler, EFFECTS_OMC_PIN=decoy digest)" "$NOTREC"
setup effects wrapped-lookalike "$EF" build/seed/effects; cp "$OMC" "$r/real-omc"
recorder "$r/runner" "$r/real-omc" "$r/record.log" 'printf '"'"'executed\n'"'"' >> "$ADMISSION_MARKER"'
invoke effects-wrapped "$r/runner" "$r/real-omc"
refused "effects wrapped-lookalike (recorder text plus one appended line)" "$NOTREC"
setup effects wrapped-artifact "$EF" build/seed/effects
recorder "$r/runner" "$t/seed/out/omc" "$r/record.log"
invoke effects-wrapped "$r/runner" "$t/seed/out/omc"
refused "effects wrapped-artifact (exact recorder bound to the decoy as OMC_BINARY)" "NOT_RUN effects: omc is not the pinned compiler $PIN"

# Static row: one grep; every tracked reader of the record is classified.
classify() {
  if grep -q "^[a-z0-9-]*|$1[ |]" "$T/table"; then echo controlled; return; fi
  case $1 in
    seed/omc/tests/pins/*.sh) echo instrument ;;
    tests/landgate/*.sh|tests/landgate/*.py) echo "instrument: the landing campaign and its record judges, which check the head compiler against the record" ;;
    seed/omega-from-seed.sh|seed/omc/gate6.sh) echo "writer of the record" ;;
    seed/omc/gate5.sh|tests/autodiff664/run-tape.sh|bench/inference_cost/verify-test.om) echo "another omc.sha256 file, not the record" ;;
    native/orig4/orig4.pin) echo "data: names the record for tests/orig4/run.sh (controlled as orig4)" ;;
    tools/omegatool.c) echo "reader, no compiler handed in: m15 compares src/omega_om_units.ident with the record" ;;
    # Omega gate programs that take the compiler as OMC and carry their own digest refusal (exit 69, nothing written). Each listed
    # file must still hold the refusal text and the exit; this class is not an admission row: no decoy or twin runs against them.
    bridge/shlib/gate.om|gpu/amd/gate.om|gpu/amd/rest/gate.om|gpu/nvidia/checks/gate.om|gpu/runtime/gate.om|gpu/units-gate.om)
      if grep -q -F "REFUSED: compiler digest differs from seed/out/omc.sha256 (exit 69)" "$ROOT/$1" && grep -q -E "^ret 69$" "$ROOT/$1"; then
        echo "gate program with its own digest refusal (exit 69, text and exit checked here); NOT_COVERED by an admission twin row"
      else echo UNCLASSIFIED; fi ;;
    gpu/amd/NOT-YET-OMEGA.tsv|gpu/amd/rest/classes.tsv) echo "data: a table row that names the record as the launcher compiler pin of a moved piece" ;;
    seed/host/check.sh|seed/omc/qualify-ir-trap.sh|seed/rung0/gate0.sh|seed/tilelab/gate.sh|seed/trace/cli-gate.sh|seed/trace/gate.sh|tests/gates/run.sh) echo "self-check of the fixed seed/out/omc against the record; no compiler handed in" ;;
    bench/inference_cost/driver.sh|bench/inference_cost/tests/handover/run.sh) echo "consumer that already read the record before pins were derived; unchanged, no row here" ;;
    tests/gates/*.gate) echo "gate manifest listing the record as an input" ;;
    .github/workflows/*) echo "frozen workflow" ;;
    *.md|*.txt|docs/*|evidence/*|*/evidence/*) echo "prose or history" ;;
    *) echo UNCLASSIFIED ;;
  esac
}
readers=0; controlled=0
git -C "$ROOT" grep -l -I 'omc\.sha256' > "$T/readers"
while IFS= read -r f; do
  readers=$((readers + 1)); c=$(classify "$f")
  case $c in
    UNCLASSIFIED) bad "static: $f reads omc.sha256 and has no class in admission-check.sh" ;;
    controlled) controlled=$((controlled + 1)); echo "READER $f: controlled" ;;
    *) echo "READER $f: $c" ;;
  esac
done < "$T/readers"
rows=$((rows + 1))
if [ "$controlled" = "$ncons" ]; then echo "PASS static: $readers tracked files name omc.sha256; $controlled are the consumers with rows above"
else bad "static: $controlled readers classified as controlled, $ncons consumers in the table"; fi

if [ "$fails" = 0 ]; then echo "ADMISSION PASS consumers=$ncons rows=$rows twins=$twins readers=$readers"; exit 0; fi
echo "ADMISSION FAIL failed=$fails consumers=$ncons rows=$rows twins=$twins readers=$readers"; exit 1
