#!/bin/sh
# One command for the UXL checks. POSIX sh. The work is in Python.
# --install-deps is the only path that uses sudo. A fresh machine may not
# have python3 yet, so that flag bootstraps it on Debian/Ubuntu before the
# Python side installs the rest.
cd "$(dirname "$0")" || exit 1
want_install=0
for arg in "$@"; do
    if [ "$arg" = "--install-deps" ]; then
        want_install=1
    fi
done
if [ "$want_install" -eq 1 ] && ! command -v python3 >/dev/null 2>&1; then
    if [ -f /etc/debian_version ]; then
        if [ "$(id -u)" -eq 0 ]; then
            DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y python3 || exit 1
        else
            sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 || exit 1
        fi
    fi
fi
exec python3 tools/uxl/run_all.py "$@"
