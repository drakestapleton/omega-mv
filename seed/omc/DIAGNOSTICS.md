# Source-bound compiler diagnostics

Set `OMC_DIAGNOSTICS=2` to keep the existing numeric error prefix and add a human
reason, an emitting-site identifier, and one `omc-diag 2` record on standard
error. Without this exact value all existing diagnostics remain unchanged.
The record names code, site, source line/column/span, mode, target, the input
digest and byte count, and the normalized compiler-source digest.

`input_complete=1` means EOF was observed. Otherwise the digest covers only the
reported prefix read before refusal. An invalid environment can therefore
report the empty prefix. The source identity is explicitly not an executable
identity: qualification records the executable SHA-256 separately and binds it
to the seed rebuild.

Site identifiers are carried at the emitting call, rather than inferred from
the numeric code. Forwarding helpers retain their caller's site. New emitting
calls must have new identifiers; do not renumber existing ones. The gate rejects
missing and duplicate sites and reports unexercised identifiers separately.
A registered site is not automatically a tested site.
The checked KFD request, header-size and span-alias refusals also carry sites.
The KFD CPU suite matches mutation seams across diagnostic annotations while
still requiring exactly one semantic match and exercising every mutant.

`diaggen.om` regenerates strings and the source identity from the registry,
inline site notes, SHA core and diagnostic runtime. It hashes the complete
result with the sole 64-byte `d2pin` value zeroed. The seed build uses its newborn
compiler to rebuild this generator and rejects stale generated source before
publishing the compiler. To refresh after an intentional source edit, run the
generated `build/seed/birth/diaggen` with the four inputs shown in
`seed/omega-from-seed.sh`, inspect its output, and replace the source with that
output. Run the seed build again. No identity is typed by hand.

`diagnostics-v2.py` independently checks hashes, refusal/success parity across
profiles, chunk boundaries and existing site fixtures, plus a compiler mutant
which omits hashing. Its machine-readable coverage inventory is written to
`build/seed/diagnostics-v2.json`; unexercised sites remain explicit obligations.
