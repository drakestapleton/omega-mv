# TURING companion records (src/turing/ty_qrecord.om): differential qualification of the OM-2
# module against the C it replaced (src/turing/ty_qrecord.c, retired at main 3f2c70dc5). Host
# only, CPU only, no C compiler, no physics checkout. Picked up by `-include mk/*.mk`.
#
# test-turing-qrecord-parity
#   1. tests/turing/qrecord_parity.sh: the hand corpus (tests/turing/qrecord_corpus.txt) and the
#      generated text, enum, number, bind, write, write-failure and sidecar corpora through
#      tests/turing/qrecord_dump.om (built from the shipped ty_core_lib.om + ty_qrecord.om, as
#      mk/turing_qrecord.mk joins them), byte for byte against the committed goldens of the C at
#      main 3f2c70dc5 (tests/turing/qrecord_golden, MANIFEST with commit, generator and sha256):
#      every builder, verifier, the gain binding, the write-once writer and file verifier, and
#      the sidecar manifest builders, parsers, table checks and digest;
#   2. tests/turing/qrecord_mutants.sh: every mutant of the OM module must differ from the goldens.
ifndef PARITY_TURING_QRECORD_MK
PARITY_TURING_QRECORD_MK := 1
QRPAR_OMC ?= seed/out/omc
.PHONY: test-turing-qrecord-parity
test-turing-qrecord-parity: $(QRPAR_OMC)
	QRECORD_PARITY_WORK=$(abspath $(OUT_DIR))/qrecord-parity sh tests/turing/qrecord_parity.sh $(abspath $(QRPAR_OMC))
	QRECORD_PARITY_WORK=$(abspath $(OUT_DIR))/qrecord-parity sh tests/turing/qrecord_mutants.sh $(abspath $(QRPAR_OMC))
endif
