#!/bin/sh
# require_physics_pin.sh PHYSICS_DIR
# omega#456: the chip runners build against a Physics checkout given on their command line (default
# ~/workspace/physics-own30b-k). They build single targets, so the Makefile's check-physics-lock (run by `all`)
# never ran for them. Each runner calls this first, before it writes evidence or builds anything: it refuses
# (exit 2) unless PHYSICS_DIR's commit, trees, blobs, raw worktree bytes and modes exactly match physics.lock.
# PHYSICS_LOCK_CHECK=0 skips the check, the same override the Makefile honours, and says so on stderr.
set -u
PHYS="${1:?usage: require_physics_pin.sh PHYSICS_DIR}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
if [ "${PHYSICS_LOCK_CHECK:-1}" = "0" ]; then
    echo "require_physics_pin: PHYSICS_LOCK_CHECK=0, Physics pin NOT checked for $PHYS" >&2
    exit 0
fi
[ -f "$ROOT/physics.lock" ] || { echo "require_physics_pin: REFUSED: $ROOT/physics.lock not found" >&2; exit 2; }
locked=$(tr -d '[:space:]' < "$ROOT/physics.lock")
printf '%s' "$locked" | grep -qxE '^[0-9a-f]{40}$' || {
    echo "require_physics_pin: REFUSED: physics.lock must contain exactly one lowercase 40-hex commit" >&2
    exit 2
}
if ! "$ROOT/tools/pinned_checkout.sh" verify "$PHYS" "$locked" >/dev/null; then
    printf '%s\n' "require_physics_pin: REFUSED: PHYSICS_DIR=$PHYS is not an exact worktree of physics.lock ($locked)" >&2
    echo "  pass an unmodified checkout at the pin, or set PHYSICS_LOCK_CHECK=0" >&2
    exit 2
fi
exit 0
