# Fabric interface F5-0 (src/fabric/fabric.om): membership, capability
# advertisement, leases and loss detection keyed by AienMachineId, over the
# in-process loopback transport. Pure seeded OM-2 (seed/out/omc).
#
# test-fabric         purity check, then the exit-gate tests in pure OM-2
# fabric-purity       fabric .om sources reference no authority, World, socket or process builtin
# fabric-receipt      digest-named receipt under evidence/F5-0 (clean tree only)
# test-fabric-living  Lane 13: a second machine's Skill found and used by the
#                     COMPOSITION-2 causal path (rx_compose.om) through the Fabric
#                     dispatcher (fab_dispatch.om); lease loss, forgery and wrong
#                     machine refused; two deterministic pure OM-2 runs.
ifndef FABRIC_MK
FABRIC_MK := 1
.PHONY: test-fabric test-fab-dispatch test-fabric-living fabric-purity fabric-receipt
FAB_DIR = $(OUT_DIR)/fabric
FAB_OMC ?= seed/out/omc
FAB_OM_SRCS = seed/ng/sha256.om src/runtime/aien_machine_id.om \
	src/fabric/fab_hmac.om src/fabric/fab_loopback.om src/fabric/fabric.om
FAB_OM_PURITY_SRCS = src/fabric/fabric.om src/fabric/fab_hmac.om \
	src/fabric/fab_loopback.om src/fabric/fab_dispatch.om
FAB_LIVING_OM_SRCS = $(FAB_OM_SRCS) src/fabric/fab_dispatch.om src/runtime/rx_compose.om \
	tests/fabric/fabric_living_test.om
# Routing discovers and carries records; it never grants authority, never
# touches the World, and F5-0 opens no socket and starts no process.
FAB_FORBIDDEN_OM = '\b(aienos_|rx_caproot_|rx_world_|rx_aegis|argus_|ag_cap|socknew|sockbind|socklisten|sockaccept|sockconnect|fork|execprog|mapnew)\b'

fabric-purity: $(FAB_OM_PURITY_SRCS)
	@if grep -Eq $(FAB_FORBIDDEN_OM) $(FAB_OM_PURITY_SRCS) ; then \
		echo "fabric source references an operation the Fabric must not have"; exit 1; fi
	@echo "fabric-purity: fabric.om, fab_hmac.om, fab_loopback.om and fab_dispatch.om reference no forbidden symbol"

$(FAB_DIR)/fabric_test: tests/fabric/fabric_test.om $(FAB_OM_SRCS) $(FAB_OMC)
	@mkdir -p $(FAB_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(FAB_OM_SRCS) tests/fabric/fabric_test.om) | $(FAB_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(FAB_DIR)/test_fab_dispatch: tests/fabric/test_fab_dispatch.om $(FAB_OM_SRCS) src/fabric/fab_dispatch.om $(FAB_OMC)
	@mkdir -p $(FAB_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(FAB_OM_SRCS) src/fabric/fab_dispatch.om tests/fabric/test_fab_dispatch.om) | $(FAB_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

$(FAB_DIR)/fabric_living_test: $(FAB_LIVING_OM_SRCS) $(FAB_OMC)
	@mkdir -p $(FAB_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(FAB_LIVING_OM_SRCS)) | $(FAB_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-fab-dispatch: $(FAB_DIR)/test_fab_dispatch
	$(abspath $(FAB_DIR)/test_fab_dispatch)

test-fabric: fabric-purity $(FAB_DIR)/fabric_test $(FAB_DIR)/test_fab_dispatch
	$(abspath $(FAB_DIR)/fabric_test)
	$(abspath $(FAB_DIR)/test_fab_dispatch)

test-fabric-living: fabric-purity $(FAB_DIR)/fabric_living_test
	$(abspath $(FAB_DIR)/fabric_living_test) > $(FAB_DIR)/living.out
	@cat $(FAB_DIR)/living.out
	@grep -q '^FABRIC_LIVING_PASS$$' $(FAB_DIR)/living.out && echo "test-fabric-living: pure OM-2 run PASS"

fabric-receipt:
	tests/fabric/fabric_receipt.sh
endif
