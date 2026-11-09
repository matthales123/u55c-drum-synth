SHELL := /usr/bin/env bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
BUILD_DIR ?= $(ROOT_DIR)/build/hardware/$(TARGET)
KERNEL_NAME ?= drum_synth
TARGET ?= hw
PLATFORM ?= xilinx_u55c_gen3x16_xdma_3_202210_1
SRC := $(ROOT_DIR)/hardware/hls/src/$(KERNEL_NAME).cpp
XO := $(BUILD_DIR)/$(KERNEL_NAME).xo
XCLBIN := $(BUILD_DIR)/$(KERNEL_NAME).xclbin
CONNECTIVITY_CFG := $(BUILD_DIR)/$(KERNEL_NAME)_connectivity.cfg

ENABLE_EXPLICIT_HBM_MAP ?= 1
HBM_BANK_IN0 ?= HBM[0]
HBM_BANK_IN1 ?= HBM[1]
HBM_BANK_OUT ?= HBM[2]

LINK_HOOK_SCRIPT := $(ROOT_DIR)/hardware/hls/scripts/u55c_clk_metadata_adapter_workaround.tcl
LINK_HOOK_ARGS :=
LINK_CFG_ARGS :=

ifeq ($(TARGET),hw)
ifneq ($(wildcard $(LINK_HOOK_SCRIPT)),)
LINK_HOOK_ARGS += --linkhook.custom "postSysLink,$(LINK_HOOK_SCRIPT)"
endif
endif

ifneq ($(ENABLE_EXPLICIT_HBM_MAP),0)
LINK_CFG_ARGS += --config $(CONNECTIVITY_CFG)
XCLBIN_DEPS := $(XO) $(CONNECTIVITY_CFG)
else
XCLBIN_DEPS := $(XO)
endif

.PHONY: all xo xclbin clean

all: xclbin

xo: $(XO)

xclbin: $(XCLBIN)

$(XO): $(SRC)
	@mkdir -p $(BUILD_DIR)
	v++ -c -t $(TARGET) --platform $(PLATFORM) -k $(KERNEL_NAME) $< -o $@

$(CONNECTIVITY_CFG):
	@mkdir -p $(BUILD_DIR)
	@{ \
		echo "[connectivity]"; \
		if [[ "$(KERNEL_NAME)" == "drum_synth" ]]; then \
			echo "sp=$(KERNEL_NAME)_1.sample_mem:$(HBM_BANK_IN0)"; \
			echo "sp=$(KERNEL_NAME)_1.gain_mem:$(HBM_BANK_IN1)"; \
			echo "sp=$(KERNEL_NAME)_1.mixed_mem:$(HBM_BANK_OUT)"; \
		else \
			echo "sp=$(KERNEL_NAME)_1.a:$(HBM_BANK_IN0)"; \
			echo "sp=$(KERNEL_NAME)_1.b:$(HBM_BANK_IN1)"; \
			echo "sp=$(KERNEL_NAME)_1.c:$(HBM_BANK_OUT)"; \
		fi; \
	} > "$@"
	@echo "Generated connectivity map: $@"

$(XCLBIN): $(XCLBIN_DEPS)
	v++ -l -t $(TARGET) --platform $(PLATFORM) $(LINK_HOOK_ARGS) $(LINK_CFG_ARGS) $(XO) -o $@

clean:
	rm -rf $(ROOT_DIR)/build/hardware
