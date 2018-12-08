JL_VERSION_BASE := 0.6
JL_VERSION_PATCH := 4
JL_VERSION := $(JL_VERSION_BASE).$(JL_VERSION_PATCH)

IMAGE_NAME := roames/lambda_julia_runtime_build:$(JL_VERSION)
BUNDLE := aws-lambda-julia-runtime-$(JL_VERSION).zip
LAMBDA_MODULE := word_count

.PHONY: default
default: help

.PHONY: build-base
## Build base docker container to build runtime
build-base:
	@echo '$(GREEN)Building base...$(RESET)'
	@git submodule update --init --recursive
	@$(MAKE) -C "$(CURDIR)/packaging/lambdajl" build

.PHONY: build-runtime
## Build runtime
build-runtime:
	@echo '$(GREEN)Building runtime...$(RESET)'
	-@rm -f $(CURDIR)/packaging/$(BUNDLE)
	-@rm -rf $(CURDIR)/packaging/bundle/
	@mkdir -p $(CURDIR)/packaging/bundle
	@cp src/* $(CURDIR)/packaging/bundle/
	@mkdir -p $(CURDIR)/packaging/bundle/$(LAMBDA_MODULE)/
	@cp examples/word_count.jl $(CURDIR)/packaging/bundle/$(LAMBDA_MODULE)/
	@docker build \
		--build-arg JL_VERSION_BASE=$(JL_VERSION_BASE) \
		--build-arg JL_VERSION_PATCH=$(JL_VERSION_PATCH) \
		--build-arg LAMBDA_MODULE=$(LAMBDA_MODULE) \
		-t $(IMAGE_NAME) packaging
	-@rm -rf $(CURDIR)/packaging/bundle/
	@docker run --rm -it -v "$(CURDIR)/packaging:/var/host" $(IMAGE_NAME) zip --symlinks -r -9 /var/host/$(BUNDLE) .


################################ HELPER TARGETS - DO NOT EDIT #############################
## `help` target will show description of each target
## Target description should be immediate line before target starting with `##`

# COLORS
RED    := $(shell tput -Txterm setaf 1)
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

TARGET_MAX_CHAR_NUM=20
## Show help
help:
	@echo ''
	@echo 'Usage:'
	@echo '  $(YELLOW)make$(RESET) $(GREEN)<target>$(RESET)'
	@echo ''
	@echo 'Targets:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			split($$1, arr, ":"); \
			helpCommand = arr[1]; \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  $(YELLOW)%-$(TARGET_MAX_CHAR_NUM)s$(RESET) $(GREEN)%s$(RESET)\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

.PHONY: help
