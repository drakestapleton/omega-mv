#!/bin/sh
# loadC0.sh -- turn seedC0.c0 (colon-separated hex bytes with '%' comments) into the 404-byte W^X binary.
set -eu
[ "$#" -eq 2 ] || { printf 'usage: loadC0.sh INPUT OUTPUT\n' >&2; exit 2; }
hex=$(sed 's/%.*//' "$1" | tr -d ' \t\r\n:')
case $(( ${#hex} % 2 )) in
  0) ;;
  *) printf 'loadC0: odd hex nibble count\n' >&2; exit 12 ;;
esac
printf '%s\n' "$hex" | fold -w 2 | while IFS= read -r b; do
  case "$b" in
    [0-9a-fA-F][0-9a-fA-F]) printf "\\$(printf '%03o' "0x$b")" ;;
    *) printf 'loadC0: bad byte %s\n' "$b" >&2; exit 11 ;;
  esac
done > "$2"
chmod +x "$2"
