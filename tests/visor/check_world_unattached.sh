#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# check_world_unattached.sh -- proves from the source that the omega binary can only render the
# UNATTACHED World view, the one view tests/visor/effect_parity.sh pins against the C
# (visor_world_unattached + visor_world_format_text/_json, command G).
#
# The argument list is the omega binary's OM sources ($(OMEGA_OM_SRCS)); one of them must be
# src/visor/visor_world.om (the view module). The check fails unless:
#  1. in the view module, every store into a view global (`put vwld_...`) is inside vwld_reset,
#     vwld_gap_put or vwld_unattached (so only the unattached constructor fills the view);
#  2. the only fixed view words the other sources use are vwld_unattached,
#     vwld_format_text and vwld_format_json (no setter, no gap append, no global);
#  3. in every function of the other sources that calls vwld_format_text or vwld_format_json,
#     vwld_unattached is called on an earlier line of the same function.
# usage: tests/visor/check_world_unattached.sh <omega OM sources...>
set -eu
mod=""
for f in "$@"; do
  case $f in */visor_world.om) mod=$f ;; esac
done
[ -n "$mod" ] || { echo "WORLD_UNATTACHED FAIL src/visor/visor_world.om is not among the sources"; exit 1; }
bad=0
w=$(awk '/^fn /{f=$2} /^[ \t]*put vwld_/{ if (f != "vwld_reset" && f != "vwld_gap_put" && f != "vwld_unattached") print FILENAME ":" FNR ": " f ": " $0 }' "$mod")
if [ -n "$w" ]; then echo "WORLD_UNATTACHED FAIL a view global is written outside the unattached constructor:"; echo "$w"; bad=1; fi
for f in "$@"; do
  [ "$f" = "$mod" ] && continue
  u=$(grep -o 'vwld_[A-Za-z0-9_]*' "$f" | sort -u | grep -v -x -e vwld_unattached -e vwld_format_text -e vwld_format_json || true)
  if [ -n "$u" ]; then echo "WORLD_UNATTACHED FAIL $f uses view words other than the unattached view and its renderings: $(echo $u)"; bad=1; fi
  o=$(awk '/^fn /{f=$2; un=0} /vwld_unattached/{un=1} /vwld_format_(text|json)/{ if (!un) print FILENAME ":" FNR ": " f }' "$f")
  if [ -n "$o" ]; then echo "WORLD_UNATTACHED FAIL a rendering is not preceded by vwld_unattached in its function:"; echo "$o"; bad=1; fi
done
[ "$bad" -eq 0 ] || exit 1
echo "WORLD_UNATTACHED PASS omega renders only the unattached World view ($# sources)"
