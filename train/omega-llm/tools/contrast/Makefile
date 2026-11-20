# Build on AArch64 Linux with the repository's seeded compiler.
ROOT := $(abspath ../../../..)
OUT ?= $(ROOT)/build/omega-contrast
OMC ?= $(ROOT)/seed/out/omc
DRIVER := ../wdrive/wbuild.om
JSON := $(ROOT)/seed/json/json.om
MODEL := $(addprefix $(ROOT)/,$(shell awk '$$1=="ollm_aarch64" {$$1=""; print}' $(ROOT)/train/units.tsv))
.DELETE_ON_ERROR:
.PHONY: all replay
all: $(addprefix $(OUT)/,contrast mix grade select with-example mean)

$(OUT):
	mkdir -p "$@"

$(OUT)/driver.om: $(DRIVER) | $(OUT)
	sed 's/^fn main to int$$/fn wbmain to int/' $< > "$@"

$(OUT)/common.om: $(OUT)/driver.om $(JSON) grade.om
	cat $^ | sed 's/^fn main to int$$/fn priorgrade to int/' > "$@"

$(OUT)/contrast: $(OUT)/driver.om contrast.om $(OMC)
	cat $(filter %.om,$^) | "$(OMC)" > "$@" && chmod +x "$@"

$(OUT)/mix: mix.om $(OMC) | $(OUT)
	"$(OMC)" < $< > "$@" && chmod +x "$@"

$(OUT)/grade: $(OUT)/driver.om $(JSON) grade.om $(OMC)
	cat $(filter %.om,$^) | "$(OMC)" > "$@" && chmod +x "$@"

$(OUT)/select: $(OUT)/common.om select.om $(OMC)
	cat $(filter %.om,$^) | "$(OMC)" > "$@" && chmod +x "$@"

$(OUT)/with-example: $(OUT)/common.om read.om with-example.om $(OMC)
	cat $(filter %.om,$^) | "$(OMC)" > "$@" && chmod +x "$@"

$(OUT)/mean: $(MODEL) mean.om $(OMC) | $(OUT)
	sed 's/^fn main to int$$/fn previousmodel to int/' $(MODEL) > "$(OUT)/model-library.om"
	cat "$(OUT)/model-library.om" mean.om | "$(OMC)" > "$@" && chmod +x "$@"

replay: all
	bash replay.sh "$(OUT)" "$(OMC)"
