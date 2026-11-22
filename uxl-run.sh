#!/bin/sh
# One command for the UXL checks.
# On AArch64 Linux with runnable seed/out/omc (default invocation, without --install-deps or --evidence),
# runs pure seeded-Omega seed/build/release.om uxl directly (zero Python on the delivery path).
# Cross-OS fallback (macOS/x86/Windows or --install-deps/--evidence) uses tools/uxl/run_all.py.
cd "$(dirname "$0")" || exit 1
want_install=0
want_py=0
for arg in "$@"; do
    case "$arg" in
        --install-deps) want_install=1; want_py=1 ;;
        --evidence|--evidence=*|--level1|--level1=*) want_py=1 ;;
    esac
done
if [ "$want_py" -eq 0 ] && [ -x seed/out/omc ] && [ "$(uname -s)-$(uname -m)" = "Linux-aarch64" ]; then
    mkdir -p build/uxl-om
    cat seed/build/common.om seed/build/release.om | seed/out/omc > build/uxl-om/om-release || exit 1
    chmod 755 build/uxl-om/om-release
    rm -rf build/uxl-om/work
    exec ./build/uxl-om/om-release uxl build/uxl-om/work
fi
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
