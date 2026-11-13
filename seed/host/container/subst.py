# SPDX-License-Identifier: Apache-2.0
# seed/host/container/subst.py (test instrument, Python): exact one-site substitution for the root-mode mutants of
# seed/host/container/check.sh, as the OM-2 conductor's subst. usage: subst.py FROMFILE TOFILE SRC DST
# The site (the bytes of FROMFILE) must occur exactly once in SRC; otherwise it exits 2 and writes nothing. The check is
# an explicit test, not an assert, so it holds under PYTHONOPTIMIZE (review omega-mv-d703365f finding 13).
import sys
if len(sys.argv) != 5:
    sys.stderr.write("usage: subst.py FROMFILE TOFILE SRC DST\n")
    sys.exit(2)
f, t, src, dst = sys.argv[1:]
s = open(src).read()
a = open(f).read()
n = s.count(a) if a else 0
if n != 1:
    sys.stderr.write("subst.py: the site %s occurs %d times in %s (exactly 1 required); no mutant written\n" % (f, n, src))
    sys.exit(2)
open(dst, "w").write(s.replace(a, open(t).read()))
