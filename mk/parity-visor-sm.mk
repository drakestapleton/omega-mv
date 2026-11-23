# Omega Visor V1 lane 1 (semantic inspection) and lane 5 (machine view): differential
# qualification of the OM-2 modules the omega binary runs (src/visor/visor_semantic.om,
# src/visor/visor_machine.om) against the retired C they replaced (src/visor/visor_semantic.c,
# src/visor/visor_machine.c). Host only, CPU only, no physics checkout, no C compiler.
#
# test-visor-semantic-parity
#   1. tests/visor/sem_parity.sh: the hand corpus (tests/visor/sem_corpus.txt) and the generated
#      type, value, operation, apply, eval, attribute, relation, graph and name corpora through
#      tests/visor/sem_dump.om, byte for byte against the committed goldens of the C at main
#      3f2c70dc5 (tests/visor/sem_golden, MANIFEST with commit, generator and sha256);
#   2. tests/visor/sem_mutants.sh: every mutant of the OM lane must differ from the goldens.
# test-visor-machine-parity
#   1. tests/visor/mach_parity.sh: the same over tests/visor/mach_corpus.txt and the generated
#      field, unit and cache, seal and name, host-fact and unit-name corpora through
#      tests/visor/mach_dump.om against tests/visor/mach_golden; the `host` corpus (this host's
#      facts) is compared only on the generating host (the Spark) and reported SKIPPED elsewhere;
#   2. tests/visor/mach_mutants.sh: every mutant must differ (the two host-reading mutants only
#      where the host corpus is compared).
.PHONY: test-visor-semantic-parity test-visor-machine-parity
test-visor-semantic-parity: $(VISOR_OMC)
	SEM_PARITY_WORK=$(abspath $(OUT_DIR))/sem-parity sh tests/visor/sem_parity.sh $(abspath $(VISOR_OMC))
	SEM_PARITY_WORK=$(abspath $(OUT_DIR))/sem-parity sh tests/visor/sem_mutants.sh $(abspath $(VISOR_OMC))

test-visor-machine-parity: $(VISOR_OMC)
	MACH_PARITY_WORK=$(abspath $(OUT_DIR))/mach-parity sh tests/visor/mach_parity.sh $(abspath $(VISOR_OMC))
	MACH_PARITY_WORK=$(abspath $(OUT_DIR))/mach-parity sh tests/visor/mach_mutants.sh $(abspath $(VISOR_OMC))
