# NOT BUILT (no Makefile hook)
There is no Makefile hook and none may be added to Omega `src/`, `tests/` or `mk/`.
`src/oracle_clifford.om` (pure seeded OM-2, ported from the retired `src/oracle_clifford.c` with 23/23 byte-exact parity) builds directly with `seed/out/omc`:
`seed/out/omc < src/oracle_clifford.om > /tmp/oracle_clifford && chmod +x /tmp/oracle_clifford`.
