# osh Linux host adapter (aien-architecture#158): pure seeded OM-2 execution service, capabilities, and journal.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`.
#   make test-osh-host     pure OM-2 execution service tests
#   make test-osh-caps     pure OM-2 capability enforcement tests
#   make test-osh-journal  pure OM-2 durable intent/outcome journal tests
ifndef OSH_HOST_MK
OSH_HOST_MK := 1
.PHONY: test-osh-host test-osh-caps test-osh-journal
OSH_HOST_DIR = $(OUT_DIR)/osh-host
OSH_OMC ?= seed/out/omc
OSH_HOST_BASE_OM = om/sha256/sha256-om2.om src/osh/osh_core.om src/osh/osh_layout.om \
	src/osh/host/osh_codes.om src/osh/host/osh_req.om src/osh/host/osh_vars.om \
	src/osh/host/osh_journal.om src/osh/host/osh_caps.om src/osh/host/osh_builtin.om \
	src/osh/host/osh_exec.om

define OSH_HOST_OM_BUILD
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $^) | $(OSH_OMC) > $@ && chmod +x $@
endef

$(OSH_HOST_DIR)/test_osh_host: $(OSH_HOST_BASE_OM) tests/osh/host/test_osh_host.om
	$(OSH_HOST_OM_BUILD)

test-osh-host: $(OSH_HOST_DIR)/test_osh_host
	$(abspath $(OSH_HOST_DIR)/test_osh_host) > $(OSH_HOST_DIR)/host.out; rc=$$?; tail -5 $(OSH_HOST_DIR)/host.out; test $$rc -eq 0 && tail -1 $(OSH_HOST_DIR)/host.out | grep -q '^OSH_HOST_PASS$$'
	@echo "test-osh-host: PASS (pure OM-2)"

$(OSH_HOST_DIR)/test_osh_caps: $(OSH_HOST_BASE_OM) tests/osh/host/test_osh_caps.om
	$(OSH_HOST_OM_BUILD)

test-osh-caps: $(OSH_HOST_DIR)/test_osh_caps
	$(abspath $(OSH_HOST_DIR)/test_osh_caps) > $(OSH_HOST_DIR)/caps.out; rc=$$?; tail -5 $(OSH_HOST_DIR)/caps.out; test $$rc -eq 0 && tail -1 $(OSH_HOST_DIR)/caps.out | grep -q '^OSH_CAPS_PASS$$'
	@echo "test-osh-caps: PASS (pure OM-2)"

$(OSH_HOST_DIR)/test_osh_journal: $(OSH_HOST_BASE_OM) tests/osh/host/test_osh_journal.om
	$(OSH_HOST_OM_BUILD)

test-osh-journal: $(OSH_HOST_DIR)/test_osh_journal
	$(abspath $(OSH_HOST_DIR)/test_osh_journal) > $(OSH_HOST_DIR)/journal.out; rc=$$?; tail -5 $(OSH_HOST_DIR)/journal.out; test $$rc -eq 0 && tail -1 $(OSH_HOST_DIR)/journal.out | grep -q '^OSH_JOURNAL_PASS$$'
	@echo "test-osh-journal: PASS (pure OM-2)"
endif
