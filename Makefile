# Local entry points; CI runs the same scripts.

BRANCHES := 7.3 7.4
VARIANTS := cli fpm apache
IMAGES := $(foreach b,$(BRANCHES),$(foreach v,$(VARIANTS),$(b)-$(v)))
PROJECTS := $(shell awk 'NF && substr($$1, 1, 1) != "\043" { print $$1 }' tests/compat/projects)

# Builds share the machine: keep compiler parallelism modest by default.
MAKE_JOBS ?= 8
JOBS ?= $(MAKE_JOBS)
export MAKE_JOBS JOBS

.PHONY: help all $(IMAGES) $(addprefix smoke-,$(IMAGES)) $(addprefix compat-,$(BRANCHES)) update verify clean

help:
	@echo "make <image>          build one image as php-elts:<image>, e.g. make 7.4-fpm"
	@echo "                      images: $(IMAGES)"
	@echo "make all              build all six"
	@echo "make smoke-<image>    compare a built image with the official one"
	@echo "make compat-<branch>  real-world test suites, official vs php-elts:<branch>-cli"
	@echo "make update           vendor the latest ELTS sources of every branch"
	@echo "make verify           re-verify the vendored sources against ELTS"
	@echo "make clean            remove the local images"

all: $(IMAGES)

$(IMAGES):
	bin/build $(subst -, ,$@)

$(addprefix smoke-,$(IMAGES)): smoke-%:
	tests/smoke $(subst -, ,$*)

$(addprefix compat-,$(BRANCHES)): compat-%:
	@status=0; for p in $(PROJECTS); do \
		tests/compat/run $$p "$$(awk '$$1 == "cli" { print $$2 }' $*/base-images)" php-elts:$*-cli || status=1; \
	done; exit $$status

update:
	@for b in $(BRANCHES); do bin/update.sh $$b; done

verify:
	@for b in $(BRANCHES); do bin/update.sh --verify $$b; done

clean:
	-docker image rm $(addprefix php-elts:,$(IMAGES)) php-elts-compat:reference php-elts-compat:candidate
