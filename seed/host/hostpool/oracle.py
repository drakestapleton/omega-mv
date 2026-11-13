# SPDX-License-Identifier: Apache-2.0
# seed/host/hostpool/oracle.py (test instrument, Python): the environment hostpool.om builds for its "oracle" row,
# written independently of the Omega fixture: entry i (0..69) is K<a><b>=<a><b>, a = chr(97 + i // 26),
# b = chr(97 + i % 26), one per line, the order /usr/bin/env prints them in.
import sys
for i in range(70):
    a, b = chr(97 + i // 26), chr(97 + i % 26)
    sys.stdout.write("K%s%s=%s%s\n" % (a, b, a, b))
