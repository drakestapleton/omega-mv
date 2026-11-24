# Arboris SM121 scoreboard oracle (tests/arboris/scoreboard_oracle.om). Pure seeded OM-2, host-only.
ARBORIS_SCOREBOARD_OMC ?= seed/out/omc
ARBORIS_SCOREBOARD_OM_SRCS := src/omega_bw_hazard.om tests/arboris/scoreboard_oracle.om
ARBORIS_SCOREBOARD_BIN = $(OUT_DIR)/arboris-scoreboard-oracle

$(ARBORIS_SCOREBOARD_BIN): $(ARBORIS_SCOREBOARD_OM_SRCS) $(ARBORIS_SCOREBOARD_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(ARBORIS_SCOREBOARD_OM_SRCS)) | $(ARBORIS_SCOREBOARD_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-arboris-scoreboard-om
test-arboris-scoreboard-om: $(ARBORIS_SCOREBOARD_BIN)
	@python3 -c 'import struct,subprocess; cw=lambda s,w,r,m:(s<<9)|(w<<14)|(r<<17)|(m<<20); \
	  c=struct.pack("<12I",0x04027981,0,0x100,cw(1,0,1,0),0x02037221,5,0,cw(1,7,7,1),0x0000794d,0,0,cw(5,7,7,0)); \
	  b=struct.pack("<12I",0x04027981,0,0x100,cw(1,0,1,0),0x02037221,5,0,cw(5,7,7,0),0x0000794d,0,0,cw(5,7,7,0)); \
	  p1=subprocess.run(["$(abspath $(ARBORIS_SCOREBOARD_BIN))"],input=c,capture_output=True); \
	  p2=subprocess.run(["$(abspath $(ARBORIS_SCOREBOARD_BIN))"],input=b,capture_output=True); \
	  assert p1.returncode==0 and b"0 hazards" in p1.stdout, p1; \
	  assert p2.returncode==1 and b"1 hazards" in p2.stdout, p2; \
	  print("ARBORIS_SCOREBOARD_OM_PASS")'
