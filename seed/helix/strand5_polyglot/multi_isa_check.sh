#!/bin/sh
# seed/helix/strand5_polyglot/multi_isa_check.sh -- Strand E ("The Polyglot"):
# Multi-ISA Deterministic Emission Braid (WebAssembly + SPIR-V + Tenstorrent Tensix RV32IM).
#
# Compiles the three pure-Omega ISA translators from source using OMC (and optionally cross-checks
# against a second independent compiler OMC_B):
#   - seed/wasm/irwasm.om   -> WebAssembly (.wasm)
#   - seed/spirv/irspirv.om -> SPIR-V (.spv)
#   - seed/tensix/irrv32.om -> Tenstorrent Tensix RISC-V RV32IM (.rv32)
#
# Verifies:
#   1. Deterministic compiler builds (and OMC == OMC_B byte-for-byte when OMC_B is provided).
#   2. Deterministic byte-for-byte emission across shared Omega IR units into all 3 ISAs,
#      including valid binary magic headers (\0asm v1, SPIR-V 0x07230203) and exact byte-for-byte
#      match of Tensix RV32IM vecadd output against committed seed/tensix/vecadd.bin.
#   3. Negative controls:
#      - Source mutation (add -> sub in vecadd.unit.om) changes ALL 3 ISA binaries.
#      - Corrupt IR magic byte is refused fail-closed (non-zero exit, 0 stdout bytes) by all 3.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$R"

OMC=${OMC:-seed/out/omc}
OMC_B=${OMC_B:-}
B=${BUILD_DIR:-build/strand5_polyglot/multi_isa}

bad() { printf 'MULTI_ISA_CHECK FAIL: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = aarch64 ] || {
  printf 'MULTI_ISA_CHECK NOT_RUN: requires Linux AArch64 host (got %s %s)\n' "$(uname -s)" "$(uname -m)"
  exit 3
}
[ -x "$OMC" ] || bad "compiler OMC=$OMC not executable"

rm -rf "$B"
mkdir -p "$B"

build_tool() {
  name=$1
  src=$2
  "$OMC" < "$src" > "$B/$name" 2> "$B/$name.err" || bad "OMC refused $src: $(cat "$B/$name.err")"
  [ ! -s "$B/$name.err" ] || bad "OMC stderr on $src: $(cat "$B/$name.err")"
  "$OMC" < "$src" > "$B/$name.again" 2>/dev/null
  cmp -s "$B/$name" "$B/$name.again" || bad "$name build nondeterministic"
  chmod +x "$B/$name"
  if [ -n "$OMC_B" ]; then
    [ -x "$OMC_B" ] || bad "OMC_B=$OMC_B not executable"
    "$OMC_B" < "$src" > "$B/$name.B" 2> "$B/$name.B.err" || bad "OMC_B refused $src: $(cat "$B/$name.B.err")"
    cmp -s "$B/$name" "$B/$name.B" || bad "$name diverged between OMC and OMC_B"
  fi
  printf '  PASS built %-8s sha256=%s (%s bytes)\n' "$name" "$(sha "$B/$name")" "$(wc -c < "$B/$name" | tr -d ' ')"
}

emit_ir() {
  id=$1
  src=$2
  { printf 'ir\n'; cat "$src"; } > "$B/$id.ir.om"
  "$OMC" < "$B/$id.ir.om" > "$B/$id.ir" 2> "$B/$id.ir.err" || bad "OMC IR emit failed on $src: $(cat "$B/$id.ir.err")"
  if [ -n "$OMC_B" ]; then
    "$OMC_B" < "$B/$id.ir.om" > "$B/$id.ir.B" 2> "$B/$id.ir.B.err" || bad "OMC_B IR emit failed on $src"
    cmp -s "$B/$id.ir" "$B/$id.ir.B" || bad "IR for $id diverged between OMC and OMC_B"
  fi
}

check_magic() {
  file=$1
  want=$2
  label=$3
  got=$(od -An -tx1 -N 8 "$file" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')
  case "$got" in
    "$want"*) ;;
    *) bad "$label bad magic in $file: got '$got', want prefix '$want'" ;;
  esac
}

printf '=== [1/4] BUILD PURE-OMEGA MULTI-ISA BACKENDS (WASM, SPIR-V, TENSIX RV32IM) ===\n'
build_tool irwasm  seed/wasm/irwasm.om
build_tool irspirv seed/spirv/irspirv.om
build_tool irrv32  seed/tensix/irrv32.om

printf '=== [2/4] EMIT SHARED OMEGA IR UNITS TO WASM + SPIR-V + TENSIX RV32IM ===\n'
emit_ir vecadd seed/tensix/vecadd.unit.om
emit_ir mix    seed/tensix/mix.unit.om
emit_ir demo   seed/spirv/demo.unit.om
emit_ir mutant seed/wasm/mutant.unit.om

for u in vecadd mix demo mutant; do
  "$B/irwasm"  < "$B/$u.ir" > "$B/$u.wasm"       2> "$B/$u.wasm.err"  || bad "irwasm failed on $u"
  "$B/irwasm"  < "$B/$u.ir" > "$B/$u.again.wasm" 2>/dev/null
  cmp -s "$B/$u.wasm" "$B/$u.again.wasm" || bad "irwasm nondeterministic on $u"
  check_magic "$B/$u.wasm" "00 61 73 6d 01 00 00 00" "WebAssembly"

  "$B/irspirv" < "$B/$u.ir" > "$B/$u.spv"        2> "$B/$u.spv.err"   || bad "irspirv failed on $u"
  "$B/irspirv" < "$B/$u.ir" > "$B/$u.again.spv"  2>/dev/null
  cmp -s "$B/$u.spv" "$B/$u.again.spv" || bad "irspirv nondeterministic on $u"
  check_magic "$B/$u.spv" "03 02 23 07" "SPIR-V"

  printf '  PASS %-6s wasm=%s (%sB) spv=%s (%sB)\n' \
    "$u" "$(sha "$B/$u.wasm" | cut -c1-16)" "$(wc -c < "$B/$u.wasm" | tr -d ' ')" \
    "$(sha "$B/$u.spv" | cut -c1-16)" "$(wc -c < "$B/$u.spv" | tr -d ' ')"
done

for u in vecadd mix; do
  "$B/irrv32" < "$B/$u.ir" > "$B/$u.rv32"       2> "$B/$u.rv32.err" || bad "irrv32 failed on $u"
  "$B/irrv32" < "$B/$u.ir" > "$B/$u.again.rv32" 2>/dev/null
  cmp -s "$B/$u.rv32" "$B/$u.again.rv32" || bad "irrv32 nondeterministic on $u"
  printf '  PASS %-6s rv32=%s (%sB)\n' \
    "$u" "$(sha "$B/$u.rv32" | cut -c1-16)" "$(wc -c < "$B/$u.rv32" | tr -d ' ')"
done

printf '=== [3/4] COMPARE TENSIX RV32IM vecadd AGAINST COMMITTED seed/tensix/vecadd.bin ===\n'
cmp -s "$B/vecadd.rv32" seed/tensix/vecadd.bin || bad "vecadd.rv32 differs from committed seed/tensix/vecadd.bin"
printf '  PASS vecadd.rv32 == seed/tensix/vecadd.bin (%s, %s bytes)\n' \
  "$(sha "$B/vecadd.rv32")" "$(wc -c < "$B/vecadd.rv32" | tr -d ' ')"

printf '=== [4/4] NEGATIVE CONTROLS (MUTATION SENSITIVITY & FAIL-CLOSED CORRUPT IR) ===\n'
sed 's/^ret add a b$/ret sub a b/' seed/tensix/vecadd.unit.om > "$B/vecsub.unit.om"
! cmp -s "$B/vecsub.unit.om" seed/tensix/vecadd.unit.om || bad "mutation edit did not change vecadd.unit.om"
emit_ir vecsub "$B/vecsub.unit.om"
"$B/irwasm"  < "$B/vecsub.ir" > "$B/vecsub.wasm"
"$B/irspirv" < "$B/vecsub.ir" > "$B/vecsub.spv"
"$B/irrv32"  < "$B/vecsub.ir" > "$B/vecsub.rv32"
! cmp -s "$B/vecadd.wasm" "$B/vecsub.wasm" || bad "Wasm output unchanged by add->sub mutation"
! cmp -s "$B/vecadd.spv"  "$B/vecsub.spv"  || bad "SPIR-V output unchanged by add->sub mutation"
! cmp -s "$B/vecadd.rv32" "$B/vecsub.rv32" || bad "Tensix RV32IM output unchanged by add->sub mutation"
printf '  PASS add->sub mutation detected across all 3 ISAs (wasm, spv, rv32)\n'

cp "$B/vecadd.ir" "$B/badmagic.ir"
printf 'X' | dd of="$B/badmagic.ir" bs=1 seek=0 conv=notrunc 2>/dev/null
for tool in irwasm irspirv irrv32; do
  set +e
  "$B/$tool" < "$B/badmagic.ir" > "$B/bad.$tool.out" 2> "$B/bad.$tool.err"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || bad "$tool accepted corrupt IR magic!"
  [ ! -s "$B/bad.$tool.out" ] || bad "$tool emitted partial stdout on corrupt IR!"
done
printf '  PASS corrupt IR magic refused fail-closed by irwasm, irspirv, and irrv32 (0 bytes out)\n'

xchk=single
[ -n "$OMC_B" ] && xchk=dual_compiler_exact
printf '\nMULTI_ISA_CHECK PASS mode=%s wasm=4/4 spv=4/4 rv32=2/2 vecadd_bin=EXACT neg_controls=PASS\n' "$xchk"
