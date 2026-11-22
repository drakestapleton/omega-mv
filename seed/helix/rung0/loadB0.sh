#!/bin/sh
# loadB0.sh -- turn seedB0.b0 (byte-pair hex with ';' comments) into the first 396-byte binary.
# Strand B's one outside step (POSIX sh + printf only). Independent of Strand A's load0.sh.
set -eu
[ "$#" -eq 2 ] || { printf 'usage: loadB0.sh INPUT OUTPUT\n' >&2; exit 2; }
in=$1
out=$2
# Strip ';' comments, keep only hex pairs, emit raw bytes via POSIX printf.
hex=$(sed 's/;.*//' "$in" | tr -d ' \t\r\n')
case $(( ${#hex} % 2 )) in
  0) ;;
  *) printf 'loadB0: odd hex nibble count\n' >&2; exit 6 ;;
esac
# Emit bytes in octal via POSIX printf
printf '%s\n' "$hex" | fold -w 2 | while IFS= read -r b; do
  case "$b" in
    [0-9a-fA-F][0-9a-fA-F])
      printf "\\$(printf '%03o' "0x$b")"
      ;;
    *)
      printf 'loadB0: bad byte %s\n' "$b" >&2
      exit 5
      ;;
  esac
done > "$out"
chmod +x "$out"
