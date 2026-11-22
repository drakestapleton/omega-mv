# SPDX-License-Identifier: Apache-2.0
OMC ?= ../../seed/out/omc

origsel_indep: origsel_indep.om
	$(OMC) < origsel_indep.om > $@ && chmod +x $@

selftest: origsel_indep
	./origsel_indep --selftest

clean:
	rm -f origsel_indep

.PHONY: selftest clean
