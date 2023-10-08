##
# StreamingTraceBuffer
#
# @file
# @version 0.1

# Vivado Simulator Makefile based flow
# Copyright Norbertas Kremeris 2021
# www.itsembedded.com

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
root-dir := $(dir $(mkfile_path))
work-dir := work_dir
$(shell mkdir -p $(work-dir))
# --------------------------------------------------------------------
# ------- CONSTRAINTS AND BOARD DEFINITIONS --------------------------
# --------------------------------------------------------------------

# Either provide name of the board via commandline or change the
# default value here.
BOARD ?= nexys4ddr


# Don't forget to add your hardware target if it's not in the
# list.
ifeq ($(BOARD), nexys4ddr)
	XILINX_PART              := xc7a100tcsg324-1
	XILINX_BOARD             := digilentinc.com:nexys4_ddr:part0:1.1
	CONSTRAINTS 		     := $(root-dir)/constr/nexys4ddr.xdc
	TOPFILE                  := TOP_UART_STB.sv
else
$(error Unknown board - please specify a supported FPGA board)
endif

# --------------------------------------------------------------------
# ------- SOURCES ----------------------------------------------------
# --------------------------------------------------------------------

# SystemVerilog files.
TB_SV ?= $(wildcard tb/*.sv)
# Testbench topfile is assumed to be the same as the filename.
TB_TOP := $(subst .sv,,$(notdir $(basename $(TB_SV))))

INCDIR_TB_SV ?= tb

SRC_SV := $(TB_SV)           \
		$(wildcard hdl/*.sv)
SRC_SV := $(addprefix $(root-dir)/, $(SRC_SV))

COMPILE_ARTIFACTS_SV := $(shell echo $(notdir $(SRC_SV)) | perl -pe 's/([A-Z])/@\L$$1/g')
COMPILE_ARTIFACTS_SV := $(addprefix $(work-dir)/xsim.dir/work/,$(COMPILE_ARTIFACTS_SV:.sv=.sdb))
INCDIR_SV := \
		lib
INCDIR_SV := $(addprefix $(root-dir)/, $(INCDIR_SV))

OPT_SV := --incr --relax
DEFINES_SV := --include $(INCDIR_SV)


# Verilog files.
TB_V ?= $(wildcard tb/*.v)
# Testbench topfile is assumed to be the same as the filename.
TB_TOP += $(subst .v,,$(notdir $(basename $(TB_V))))

INCDIR_TB_V ?= tb

SRC_V := $(TB_V)           \
		$(wildcard hdl/*.v)
SRC_V := $(addprefix $(root-dir)/, $(SRC_V))

COMPILE_ARTIFACTS_V := $(shell echo $(notdir $(SRC_V)) | perl -pe 's/([A-Z])/@\L$$1/g')
COMPILE_ARTIFACTS_V := $(addprefix $(work-dir)/xsim.dir/work/,$(COMPILE_ARTIFACTS_V:.v=.sdb))
INCDIR_V := \
		lib
INCDIR_V := $(addprefix $(root-dir)/, $(INCDIR_V))

OPT_V := --incr --relax
DEFINES_V := --include $(INCDIR_V)

# VHDL files.
TB_VHDL ?= $(wildcard tb/*.vhd) $(wildcard tb/*.vhdl)
# Testbench topfile is assumed to be the same as the filename.
TB_TOP += $(subst .vhd,,$(notdir $(basename $(TB_VHDL)))) $(subst .vhdl,,$(notdir $(basename $(TB_VHDL))))

INCDIR_TB_VHDL ?= tb

SRC_VHDL := $(TB_VHDL)           \
		$(wildcard hdl/*.vhd)    \
		$(wildcard hdl/*.vhdl)

SRC_VHDL := $(addprefix $(root-dir)/, $(SRC_VHDL))

COMPILE_ARTIFACTS_VHDL := $(shell echo $(notdir $(SRC_VHDL)) | perl -pe 's/([A-Z])/@\L$$1/g')
COMPILE_ARTIFACTS_VHDL := $(addprefix $(work-dir)/xsim.dir/work/,$(COMPILE_ARTIFACTS_VHDL:.vhd=.sdb)) \
						  $(addprefix $(work-dir)/xsim.dir/work/,$(COMPILE_ARTIFACTS_VHDL:.vhdl=.sdb))

INCDIR_VHDL := lib
INCDIR_VHDL := $(addprefix $(root-dir)/, $(INCDIR_VHDL))

OPT_VHDL := --incr --relax

#==== Default target - running simulation without drawing waveforms ====#

.PHONY : simulate
simulate : $(addprefix $(work-dir)/, $(addsuffix _snapshot.wdb,$(TB_TOP)))

.PHONY : elaborate
elaborate : $(addprefix $(work-dir)/xsim.dir/, $(addsuffix _snapshot,$(TB_TOP)))

.PHONY : compile
compile : $(work-dir)/$(COMPILE_ARTIFACTS_SV) $(work-dir)/$(COMPILE_ARTIFACTS_V) $(work-dir)/$(COMPILE_ARTIFACTS_VHDL)

#==== COMPILING SYSTEMVERILOG ====#
$(COMPILE_ARTIFACTS_SV) &: $(SRC_SV)
	@echo
	@echo "### COMPILING SYSTEMVERILOG ###"
	cd $(work-dir) && xvlog --sv $(OPT_SV) $(DEFINES_SV) $^

#==== COMPILING VERILOG ====#
$(COMPILE_ARTIFACTS_V) &: $(SRC_V)
	@echo
	@echo "### COMPILING VERILOG ###"
	cd $(work-dir) && xvlog $(OPT_V) $(DEFINES_V) $^

#==== COMPILING VHDL ====#
$(COMPILE_ARTIFACTS_VHDL) &: $(SRC_VHDL)
	@echo
	@echo "### COMPILING VHDL ###"
	cd $(work-dir) && xvhdl $(OPT_VHDL) $^

#==== ELABORATION ====#
$(addprefix $(work-dir)/xsim.dir/, $(addsuffix _snapshot,$(TB_TOP))): $(COMPILE_ARTIFACTS_SV) $(COMPILE_ARTIFACTS_V) $(COMPILE_ARTIFACTS_VHDL)
	@echo
	@echo "### ELABORATING ###"
	cd $(work-dir) && xelab -debug all -top $(TB_TOP) -snapshot $(addsuffix _snapshot,$(TB_TOP))

#==== SIMULATION ====#
$(addprefix $(work-dir)/, $(addsuffix _snapshot.wdb,$(TB_TOP))): $(addprefix $(work-dir)/xsim.dir/, $(addsuffix _snapshot,$(TB_TOP)))
	@echo
	@echo "### RUNNING SIMULATION ###"
	@echo log_wave recursive -v \* >  $(work-dir)/xsim_cfg.tcl
	@echo run all 			   >> $(work-dir)/xsim_cfg.tcl
	@echo exit 				   >> $(work-dir)/xsim_cfg.tcl
	cd $(work-dir) && xsim $(addsuffix _snapshot, $(TB_TOP)) -tclbatch xsim_cfg.tcl

#==== WAVEFORM DRAWING ====#
SNAPSHOT ?=
.PHONY : gui
gui : $(SNAPSHOT)
	@echo
	@echo "### OPENING WAVES ###"
	xsim --gui $(SNAPSHOT)


.PHONY : clean
clean :
	rm -rf $(work-dir)


# end
