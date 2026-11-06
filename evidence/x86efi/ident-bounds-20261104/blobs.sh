# SMBIOS test structures (raw bytes for QEMU -smbios file=).
# t1 VER: type 1, handle 0x0100, Manufacturer 1, Product 2, Version VER, one string "OmegaTest".
t1() {
  printf '\001\033\000\001\001\002'
  printf "\\$(printf %03o "$1")"
  printf '\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\006\000\000OmegaTest\000\000'
}
# t11 H N: type 11 (OEM strings), handle 0x0B00+H, N strings of 60 characters.
t11() {
  printf '\013\005'
  printf "\\$(printf %03o "$1")"
  printf '\013'
  printf "\\$(printf %03o "$2")"
  s=$(printf '%060d' 0)
  i=0
  while [ "$i" -lt "$2" ]; do printf '%s\000' "$s"; i=$((i + 1)); done
  printf '\000'
}
