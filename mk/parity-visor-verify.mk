# Omega Visor V1 lane 4 (verification report and evidence explorer): differential qualification
# of the OM-2 modules the omega binary runs (src/visor/visor_verify.om, src/visor/visor_evidence.om)
# against the C they replaced (src/visor/visor_verify.c, src/visor/visor_evidence.c, retired at
# main commit 3f2c70dc5). Host only, CPU only, no physics checkout, no C compiler.
#
# test-visor-verify-parity
#   1. tests/visor/verify_parity.sh: the hand scenario and the generated opcode, field and
#      AArch64 program corpora through tests/visor/verify_dump.om (built from
#      $(VISOR_VERIFY_OM_SRCS) and the helpers of tests/visor/test_visor_verify.om), byte for
#      byte against the committed goldens of the C at main 3f2c70dc5 (tests/visor/verify_golden,
#      MANIFEST with commit, generator and sha256): report return codes, both renderings and
#      their lengths around the exact buffer size, V0 structure and the execution of every
#      generated program (native in the C, the V1 interpreter in the OM);
#   2. tests/visor/verify_mutants.sh: every mutant of the OM lane must differ from the goldens.
# test-visor-evidence-parity
#   1. tests/visor/evidence_parity.sh: the fixture tree and the generated JSON, field and walk
#      corpora (trees built from the corpus lines) through tests/visor/evidence_dump.om (built
#      from $(VISOR_EVIDENCE_OM_SRCS)), byte for byte against tests/visor/evidence_golden;
#   2. tests/visor/evidence_mutants.sh: every mutant of the OM lane must differ from the goldens.
.PHONY: test-visor-verify-parity test-visor-evidence-parity
test-visor-verify-parity: $(VISOR_OMC)
	VERIFY_PARITY_WORK=$(abspath $(OUT_DIR))/verify-parity sh tests/visor/verify_parity.sh $(abspath $(VISOR_OMC))
	VERIFY_PARITY_WORK=$(abspath $(OUT_DIR))/verify-parity sh tests/visor/verify_mutants.sh $(abspath $(VISOR_OMC))

test-visor-evidence-parity: $(VISOR_OMC)
	EVIDENCE_PARITY_WORK=$(abspath $(OUT_DIR))/evidence-parity sh tests/visor/evidence_parity.sh $(abspath $(VISOR_OMC))
	EVIDENCE_PARITY_WORK=$(abspath $(OUT_DIR))/evidence-parity sh tests/visor/evidence_mutants.sh $(abspath $(VISOR_OMC))
