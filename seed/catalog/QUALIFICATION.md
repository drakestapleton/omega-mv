# Compilation with compression: qualification status

Status: working compiler prototype, not a qualified faster coding release.
Canonical base: Radicle omega-mv 1a7aa1e50a226af3e1f925d240def8f71f4252f8.
Compiler unchanged: cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a.
Compatibility compiler: 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f.
Existing SemCat commits 7e02fbe6 and a70a10a0 were reused, with subsequent
reserved-name, write-diagnostic, signature-only and total-operation corrections.
No dead-function elimination or further optimization is included in this patch.

## Correctness and preparation

The catalog gate passes 218 checks. The total gate passes full-width ordinary
and inline checks, deterministic source/map/accounting, and deliberately bad
constant, type, name and I/O controls. The compiler is the final grammar/type
checker. Errors map back through C/E/R source-map records. Host CPU execution
on physical Spark is not GPU, firmware, emulator, or full hardware qualification.
x86linux total output is cross-compiled only. No iMac full suite was run; the
unchanged compiler's full suite is not rerun for this additive catalog change.
The required evidence-immutability and zero-disk-secret checks are separate.

## Historical frozen add_times experiment (MEASURED)

These measurements belong to existing SemCat/SemAgent artifacts, not to total.om.
The catalog had 493 bytes. For each f4 task:

| Arm | model source bytes | lock bytes | compiled unit bytes | executable bytes |
| --- | ---: | ---: | ---: | ---: |
| A existing useful function | 106 | 0 | 106 | 324 |
| B catalog ordinary call | 80 | 75 | 166 | 424 |
| C catalog inline call | 80 | 82 | 177 | 464 |

The dictionary is additional to source plus lock. Sharing does not remove the
per-build lock charge. Compilation requires the resolver executable and its
SHA256 dependency, plus documentation and tooling. The previous microbenchmark
excluded resolver-build cold cost; it is not end-to-end acceptance evidence.
A smaller model source made a larger executable in both catalog arms.

Previous round40 own-model bring-up (one run each, not a matched statistical trial):

| Arm/card | workflow verdicts accepted | elapsed ms |
| --- | ---: | ---: |
| A historical f4 | 4/4 | 1492808 |
| B full card | 0/4 | 726242 |
| C full card | 0/4 | 727432 |
| B no card | 3/4 | 1203098 |
| B signature | 1/4 | 1071505 |
| C no card | 3/4 | 1196179 |

Missing-file handling is one accepted workflow verdict, not generated correct
code. Both no-card catalog arms repaired the syntax task through resolve,
compile, verify and review; the logic task failed. Full cards overflowed the
256-token context and caused path-copy errors. Failed runs cannot establish
time-to-accepted-code improvement. The historical signature selector also
assumed fixed three-line cards; the new `sig` API removes that assumption.

The repeated A/B/C campaign belongs to the existing SemBase owner. At the last
inspection it had no completed positive A repeat. Its gate retry loop has no
finite overall deadline, and the queued tasks are not an untouched holdout.
It is retained as unfinished evidence, not release qualification.

## Actual current own model (MEASURED, distinct from round40)

Current checkpoint ckC1500 SHA256:
fdc1f64cca3b936efa665fc56602f8f2942a1aa40537e480f20c8508cba41275.
Tokenizer SHA256: 688b723a894baa831ee92aaf814918d30823225c45de68c85d9dd244eb79947c.
Runtime SHA256: 768c26c94a047a6e7999ed26bf802165322ab6377145c9320d924b3af4297515.
A fresh existing coding acceptance task `cd-de-ringbuf-write-rotate` ran with
this model, its tokenizer and existing adapter. Result FAIL (malformed generated
code, SyntaxError), HTTP 200, normal EOS, 465 prompt and 15 completion tokens,
9895 ms adapter time, 9898 ms server time, 13.02 s total with 3.018455582 s cold
startup. Fixed limits: request 180 s, overall 240 s; neither timeout fired.
Temperature zero, seed one, no repairs. No substitution, GPU or training.
The raw request and response are retained in the private evidence handoff.
This was an existing Python coding task, not proof of Omega catalog integration.
The model's earlier completed DRA-124 coding suite was also 0/28.

## Release limits and next executable work

No current-model paired A/B/C accepted workflow, untouched family, uncertainty
estimate, cold/amortized model speedup, or executable-byte reduction is claimed.
The Node catalog integration depends on an unmerged node stack absent from
canonical main. It is a separate review branch, not silently imported here.
Next: land the reviewed resolver and node dependency stack via the desk; use
private per-run catalog/lock snapshots; adapt the current ckC1500 coding path;
freeze a relevant catalog and run a finite-deadline held-out acceptance campaign.
Only a measured useful elapsed-time win admits optimization or offline mining.
DRA-189 and automatic discovery remain incomplete under that dependency order.
