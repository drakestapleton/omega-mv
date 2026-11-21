#!/bin/sh
# One command for the UXL checks. POSIX sh. The work is in Python.
cd "$(dirname "$0")" || exit 1
exec python3 tools/uxl/run_all.py "$@"
