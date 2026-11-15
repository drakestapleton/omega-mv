#!/bin/sh
# TEST INSTRUMENT. Fails while a pool declaration still names the stand-in
# owner or still claims every unit is composed with seed/ng/sha256.om.
set -eu
ROOT=${1:-.}
cd "$ROOT"
bad=0
if grep -R -n -F 'composes it with the OM-2 core and seed/ng/sha256.om' --include='*.om' . >/tmp/omc-b-owner-hits 2>/dev/null; then
  echo "FAIL pasted composition sentence still present"
  cat /tmp/omc-b-owner-hits
  echo "OWNER-TRUTH FAIL"
  exit 1
fi
# Other units still name recovered-owners.sh for a reason that is true for them.
# These are the ones whose reason claimed a sha256 composition they do not have.
python3 - << 'PY'
import pathlib, runpy, sys
sys.argv = ["compose-owner.py", "seed/out/omc", "--recipes"]
ns = runpy.run_path("seed/omc/tests/pools/compose-owner.py")
# run_path executes main only when __name__ is __main__. Call the pieces.
recipe = ns["recipe"]
root = pathlib.Path(".")
bad = 0
owner = "owner=seed/omc/tests/pools/compose-owner.sh"
for path in list(root.rglob("*.om")):
    text = path.read_text(encoding="utf-8", errors="replace")
    if owner not in text:
        continue
    unit = str(path)
    name, source, parts = recipe(unit)
    for line in text.splitlines():
        if owner not in line:
            continue
        if f"Composed by {name} in {source} as" not in line:
            print(f"FAIL {unit} reason does not name {name} in {source}")
            bad = 1
        if name == "launch-a64" and "seed/ng/sha256.om" in line:
            print(f"FAIL {unit} launch composition names sha256")
            bad = 1
        if name in ("platrest", "apiplan", "hostrest", "classes") and "seed/ng/sha256.om" in line:
            print(f"FAIL {unit} {name} names sha256")
            bad = 1
        if name == "cfacts" and "seed/ng/sha256.om" not in line:
            print(f"FAIL {unit} cfacts omits sha256")
            bad = 1
if bad:
    sys.exit(1)
print("owner-truth recipes match the notes")
PY
if [ "$bad" != 0 ]; then
  echo "OWNER-TRUTH FAIL"
  exit 1
fi
echo "OWNER-TRUTH PASS"
