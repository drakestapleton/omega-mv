#!/bin/bash
# ORACLE test code (host verification only, outside the build and production path).
# Negative controls for the L608 C export corpus. Each mutant changes exactly one line of the exporter in a
# scratch worktree of HEAD, rebuilds with the unchanged pinned build, and c_export_corpus.py must FAIL (exit 1).
# Needs SA_SEED_REPO (as mk/c-u64-export.mk) and an existing build/L574 toolchain in this checkout, which is
# copied so the seed compiler is not rebuilt. Output: one row per mutant; exit 1 if any mutant survives.
set -u
root=$(cd "$(dirname "$0")/../../.." && pwd)
: "${SA_SEED_REPO:?set SA_SEED_REPO to an omega-bridge clone holding 0fc7d866}"
export SA_SEED_REPO
[ -d "$root/build/L574/toolchain" ] || { echo 'NOT_RUN build/L574 missing: make -f mk/c-u64-export.mk c-u64-export'; exit 3; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
f=src/adapters/c-u64-export.om
survived=0
mut() { # id line old new
  d=$scratch/$1
  git -C "$root" worktree add -q --detach "$d" HEAD
  mkdir -p "$d/build" && cp -a "$root/build/L574" "$d/build/L574" && rm -f "$d/build/L574/sa"
  if [ "$(sed -n "${2}p" "$d/$f")" != "$3" ]; then echo "$1 ANCHOR_MISMATCH"; survived=1
  else
    sed -i "${2}s/.*/$4/" "$d/$f"
    if (cd "$d" && python3 tools/adapters/build-c-export.py && python3 tools/adapters/build-c-import.py \
        && python3 tools/adapters/build-python-import.py) > "$d.build.log" 2>&1; then
      (cd "$d" && python3 tests/universal/translation/c_export_corpus.py --out "$d.out") > /dev/null; rc=$?
      failed=$(python3 -c "import json,sys; print(','.join(json.load(open(sys.argv[1]))['failed']))" "$d.out/result.json" 2>/dev/null)
      if [ "$rc" = 1 ]; then echo "$1 KILLED failed=$failed"; else echo "$1 SURVIVED rc=$rc"; survived=1; fi
    else echo "$1 BUILD_FAILED"; survived=1
    fi
  fi
  git -C "$root" worktree remove --force "$d"
}
mut M1-right-paren-lt 198 'if le get Xpr get Ob k get Xpr k' 'if lt get Xpr get Ob k get Xpr k'
mut M2-depth-limit-17 434 'if gt get Xdp root 16' 'if gt get Xdp root 17'
mut M3-no-root-selection 306 'ret get Oa y' 'ret y'
mut M4-mul-prints-plus 278 'xbyte 42' 'xbyte 43'
exit $survived
