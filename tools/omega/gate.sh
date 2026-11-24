#!/bin/sh
# tools/omega/gate.sh: build the omega package from seed/out/omc and check it on every CPU this host can
# run (docs/OMEGA-PACKAGE.md). The package and every check are seeded Omega; this script only builds,
# runs and compares. An x86_64 run on a non-x86 host goes through qemu-user binfmt and is EMULATED.
# Last line: RC=0 when every check passed. A CPU this host cannot run is NOT_RUN and fails the gate.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
B=$(mktemp -d "${TMPDIR:-/tmp}/omega-gate.XXXXXX")
trap 'rm -rf "$B"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
[ "$(sha256sum seed/out/omc | cut -d' ' -f1)" = "$(cut -d' ' -f1 seed/out/omc.sha256)" ] || bad "seed/out/omc is not seed/out/omc.sha256"
cat seed/build/common.om tools/omega/build.om | seed/out/omc > "$B/om-package" || bad "the package builder does not compile"
chmod +x "$B/om-package"
"$B/om-package" "$B/pkg" > "$B/build.log" 2>&1 || { tail -3 "$B/build.log"; bad "package build"; }
cmp -s "$B/pkg/lib/aarch64/omc" seed/out/omc || bad "lib/aarch64/omc is not seed/out/omc"
say "PASS package: $(grep -c '^program' "$B/pkg/MANIFEST.tsv") programs, $(grep -c '^share' "$B/pkg/MANIFEST.tsv") shared files, compiler $(cut -c1-16 seed/out/omc.sha256)"
P=$B/pkg/bin/omega
printf 'text m "hi\\n"\nfn main to int\nr = write 1 m 0 len m\nret 3\nend\n' > "$B/hi.om"
nr=
for cpu in aarch64 x86_64; do
  if ! OMEGA_CPU=$cpu "$P" hw > "$B/hw" 2>&1; then
    nr="$nr $cpu"; say "NOT_RUN $cpu: this host cannot run lib/$cpu ($(head -1 "$B/hw"))"; continue
  fi
  export OMEGA_CPU=$cpu OMEGA_CACHE="$B/cache-$cpu"
  unset OMEGA_GPU || true
  grep -qx "cpu=$cpu" "$B/hw" || bad "$cpu: hw does not say cpu=$cpu"
  set +e; out=$("$P" run "$B/hi.om"); rc=$?; set -e
  [ "$out" = hi ] && [ $rc = 3 ] || bad "$cpu: run gave '$out' status $rc, wanted 'hi' status 3"
  "$P" compile "$B/hi.om" -o "$B/hi.$cpu" || bad "$cpu: compile"
  m=$(od -An -tu2 -j18 -N2 "$B/hi.$cpu" | tr -d ' ')
  { [ $cpu = x86_64 ] && [ "$m" = 62 ]; } || { [ $cpu = aarch64 ] && [ "$m" = 183 ]; } || bad "$cpu: compile gave e_machine $m"
  say "PASS $cpu: hw, run (status 3 passed through), compile (e_machine $m)"
  # kernels: cpu build then hit
  "$P" kernels get rmsnorm > "$B/k1" || bad "$cpu: kernels get rmsnorm"
  grep -q '^cache=built ' "$B/k1" || bad "$cpu: first get was not a build"
  "$P" kernels get rmsnorm > "$B/k2" || bad "$cpu: second get"
  grep -q '^cache=hit ' "$B/k2" || bad "$cpu: second get was not a hit"
  # intel order: SPIR-V, bit-exact host check
  OMEGA_GPU=intel "$P" kernels get vecadd > "$B/k3" || bad "$cpu: spirv vecadd"
  grep -q '^CONFORM vadd n=1048576 wrong=0 ' "$B/k3" || bad "$cpu: spirv vecadd conform line missing"
  grep '^CONFORM' "$B/k3" | sed 's/.*sha256=//' > "$B/conf.$cpu"
  # amd order: HSACO, loader check
  OMEGA_GPU=amd "$P" kernels get reduce_sum row16 > "$B/k4" || bad "$cpu: amd reduce_sum"
  grep -q '^LOAD ACCEPT AMDGPU_HSACO target=amdgcn-amd-amdhsa--gfx942 ' "$B/k4" || bad "$cpu: hsaco not accepted"
  # nvidia order: the skip and the cpu fallback
  OMEGA_GPU=nvidia "$P" kernels select gemm_nn > "$B/k5" || bad "$cpu: nvidia select"
  grep -q '^skip target=nvidia-sm121 ' "$B/k5" && grep -q '^select target=cpu ' "$B/k5" || bad "$cpu: nvidia fallback"
  "$P" kernels model "$B/pkg/share/gpu/kernels/models/decoder-step.ops" > "$B/k6" || bad "$cpu: model"
  grep -q '^omega-kernels-model ops=8 failed=0$' "$B/k6" || bad "$cpu: model summary"
  # control: an unknown op is refused, exit 1
  set +e; "$P" kernels get no_such_op > /dev/null; rc=$?; set -e
  [ $rc = 1 ] || bad "$cpu: unknown op gave $rc, wanted 1"
  # control: the emitter's own wrong kernel (sum-order/operation mutant) must fail and never be cached
  cp -R "$B/pkg" "$B/mut"
  printf 'vecadd\tany\tspirv-cl\tSPIRV_CL\tspirv-emit\tvadd cl mutant\tspirv opencl2.2 vadd 2 1048576 1048576\n' > "$B/row"
  grep -v '^vecadd	any	spirv-cl' "$B/pkg/share/gpu/kernels/registry.tsv" > "$B/mut/share/gpu/kernels/registry.tsv"
  cat "$B/row" >> "$B/mut/share/gpu/kernels/registry.tsv"
  set +e; OMEGA_GPU=intel OMEGA_CACHE="$B/mcache" "$B/mut/bin/omega" kernels get vecadd > "$B/k7" 2>&1; rc=$?; set -e
  [ $rc != 0 ] || bad "$cpu: the mutant SPIR-V kernel passed its check"
  grep -q '^CONFORM vadd n=1048576 wrong=[1-9]' "$B/k7" || bad "$cpu: the mutant was not refused by the bit-exact compare ($(grep -m1 'CONFORM\|FAIL' "$B/k7"))"
  ! ls "$B/mcache/kernels" 2> /dev/null | grep -qv '\.tmp-' || bad "$cpu: a failed kernel entered the cache"
  # control: a different compiler is a different key (no stale hit)
  printf '\n' >> "$B/mut/lib/$cpu/omc"
  OMEGA_CACHE="$B/cache-$cpu" "$B/mut/bin/omega" kernels select rmsnorm > /dev/null
  k1=$(grep '^key=' "$B/k1"); set +e; OMEGA_CACHE="$B/cache-$cpu" "$B/mut/bin/omega" kernels get rmsnorm > "$B/k8" 2>&1; set -e
  k8=$(grep '^key=' "$B/k8" || true)
  [ -n "$k8" ] && [ "$k8" != "$k1" ] || bad "$cpu: a changed omc kept the key ($k1)"
  rm -rf "$B/mut" "$B/mcache"
  say "PASS $cpu kernels: cpu build+hit, spirv vecadd 0 ulp, hsaco gfx942 accepted, nvidia->cpu fallback, model 8/8; controls: unknown op, mutant kernel refused and uncached, new compiler = new key"
done
if [ -f "$B/conf.aarch64" ] && [ -f "$B/conf.x86_64" ]; then
  cmp -s "$B/conf.aarch64" "$B/conf.x86_64" || bad "the SPIR-V vecadd output differs between CPUs"
  say "PASS cross-CPU: SPIR-V vecadd host output sha256 $(cut -c1-16 "$B/conf.aarch64") on both CPUs"
fi
[ -z "$nr" ] || bad "NOT_RUN on:$nr (NOT_RUN is not PASS)"
say "PASS omega package gate"
say "RC=0"
