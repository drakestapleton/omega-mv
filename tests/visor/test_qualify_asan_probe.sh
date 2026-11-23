#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# test_qualify_asan_probe.sh -- the sanitizer dry run of tools/qualify_visor.sh (step 4) records
# what its probe actually showed:
#  1. the real `make -n` of the OM-2 omega build succeeds without -fsanitize=: NOT_APPLICABLE;
#  2. a dry run that fails (make exits 2): ERROR with dry_run_exit 2, never NOT_APPLICABLE;
#  3. a dry run that succeeds and shows -fsanitize=: the sanitizer run applies.
# Runs only the probe (tools/qualify_visor.sh --asan-probe-only); builds nothing.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() {   # name, output, wanted fixed string, unwanted fixed string
  if printf '%s\n' "$2" | grep -qF -- "$3" && ! printf '%s\n' "$2" | grep -qF -- "$4"; then
    echo "PROBE $1 PASS"
  else
    echo "PROBE $1 FAIL: $2"; fail=1
  fi
}

out=$(bash "$ROOT/tools/qualify_visor.sh" --asan-probe-only)
check om2-not-applicable "$out" 'applies=0 json={"status": "NOT_APPLICABLE"' '"ERROR"'

printf '#!/bin/sh\necho "make: *** no rule" >&2\nexit 2\n' > "$T/make-fails"
chmod +x "$T/make-fails"
out=$(QUALIFY_VISOR_MAKE="$T/make-fails" bash "$ROOT/tools/qualify_visor.sh" --asan-probe-only)
check failed-dry-run-is-error "$out" '"status": "ERROR"' 'NOT_APPLICABLE'
check failed-dry-run-exit "$out" '"dry_run_exit": 2,' 'applies=1'

printf '#!/bin/sh\necho "cc -fsanitize=address,undefined -c x.c"\nexit 0\n' > "$T/make-asan"
chmod +x "$T/make-asan"
out=$(QUALIFY_VISOR_MAKE="$T/make-asan" bash "$ROOT/tools/qualify_visor.sh" --asan-probe-only)
check sanitizer-reaches-build "$out" 'applies=1 json={"status": "WOULD_RUN"}' 'NOT_APPLICABLE'

printf '#!/bin/sh\necho "cc -fsanitize=address -c x.c"\nexit 1\n' > "$T/make-asan-fails"
chmod +x "$T/make-asan-fails"
out=$(QUALIFY_VISOR_MAKE="$T/make-asan-fails" bash "$ROOT/tools/qualify_visor.sh" --asan-probe-only)
check failed-dry-run-with-flags-is-error "$out" '"dry_run_exit": 1,' 'applies=1'

[ "$fail" -eq 0 ] || { echo "QUALIFY_ASAN_PROBE FAIL"; exit 1; }
echo "QUALIFY_ASAN_PROBE PASS 5 checks"
