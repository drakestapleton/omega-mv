# Coordinated keyword-removal review repair

The intent is to keep the keyword gate load-bearing when the generator and compiler chain both lose a word. `gate18.sh` compares their emitted ID multiset and count with the separately committed semantic canonicalizer inventory. The gate does not regenerate that inventory. Its `tkw1` declaration was generated using the new `genkw.awk -v semhash=1` output mode; no numeric expectation is typed.

The KFD gate copies the generator, chain, gate and semantic inventory to its build directory, removes kfdctl from both generator and chain, and requires both exit 1 and the semantic-inventory mismatch diagnostic. It preserves the semantic table. `results.json` contains the observed baseline and negative-control outcomes. `receipt.json` derives command exits, counts and hashes from the captured run; `qualification.log` is the complete output.

Scope beyond the original compiler files: `seed/semhash/semhash.om` is the existing keyword consumer and independent gate inventory, so its stale table was regenerated; `seed/README.md` replaces the stale manually maintained pair count with the checked relationship. The existing foreign generator remains outside the seeded production path; no new host runtime dependency was introduced.

The seed ladder, full seed gate (including gate18 and gate5), compiler quick smoke, numeric CPU gate, realization gates, evidence immutability, secret-file gate and semantic-hash gate were run. Quick smoke is not OSC full qualification. Declared omissions remain in the log: absent sibling checkouts, unvendored Wycheproof corpus, declared OM-2 skips and chip-only numeric cases. Every AMD hardware/device, model, throughput, merge and deployment row is NOT_RUN. Old evidence was not changed.
