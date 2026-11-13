# TEST INSTRUMENT TEMPLATE: section 11 prepends a shebang and its real compiler's absolute path assignment.
# Record stdin SHA256, observed compiler exit, executed compiler SHA256 and wrapper PID; these are trusted owner records, not authenticated process tracing.
set -u
: "${OMC_RECORD_REAL:?generated compiler binding required}" "${OMC_RECORD_LOG:?record log required}"
tmp=$(mktemp "${TMPDIR:-/tmp}/omega-record-source.XXXXXX") || exit 125
trap 'rm -f "$tmp"' EXIT HUP INT TERM
cat > "$tmp" || { echo 'compiler recorder: reading source failed' >&2; exit 125; }
hash=$(sha256sum "$tmp") || exit 125
hash=${hash%% *}
binary=$(sha256sum "$OMC_RECORD_REAL") || exit 125
binary=${binary%% *}
"$OMC_RECORD_REAL" < "$tmp"
r=$?
after=$(sha256sum "$OMC_RECORD_REAL") || exit 125
after=${after%% *}
[ "$binary" = "$after" ] || { echo 'compiler recorder: compiler changed during execution' >&2; exit 125; }
(
  flock 9 || exit 125
  printf '%s\t%s\t%s\t%s\n' "$hash" "$r" "$binary" "$$" >> "$OMC_RECORD_LOG"
) 9>>"$OMC_RECORD_LOG.lock" || { echo 'compiler recorder: recording result failed' >&2; exit 125; }
exit "$r"
