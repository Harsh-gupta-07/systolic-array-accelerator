# =============================================================================
# Makefile - Icarus Verilog simulation flow  (run from the sim/ directory)
#
#  Phase I
#   make mac        MAC unit testbench
#   make pe         Processing Element testbench
#   make array      4x4 array + skew testbench
#   make top        Phase I system testbench (directed golden vectors)
#  Phase II
#   make requant    requantiser (2000 golden vectors)
#   make macpipe    pipelined MAC vs combinational MAC
#   make top2       Phase II top: serial + overlapped, all 4 pipeline configs
#   make seq        sequential single-MAC baseline (directed + random)
#   make regress    1000-test random regression on the Phase I top
#   make ws         weight-stationary streaming array
#   make tiled      8x8 and 12x12 GEMM via tiling + accumulate mode
#   make sweep      array size sweep N = 2,3,4,8,16 -> ../results/scaling.csv
#  Everything
#   make all        all functional tests (Phase I + II)
#   make results    all tests + logs in ../results/logs + figures/tables
#   make vectors    regenerate golden-model vectors (Python 3)
#   make wave_<x>   open GTKWave (mac, pe, array, top, top2)
#   make clean
# =============================================================================
IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
FLAGS    := -g2005 -Wall
LOGS     := ../results/logs

CORE := ../rtl/mac_unit.v ../rtl/pe.v ../rtl/input_skew.v ../rtl/systolic_array.v
P1   := $(CORE) ../rtl/matrix_buffer.v ../rtl/systolic_controller.v ../rtl/systolic_top.v
V2   := $(CORE) ../rtl/requant.v ../rtl/matrix_buffer_pp.v ../rtl/systolic_controller_v2.v \
        ../rtl/perf_counters.v ../rtl/systolic_top_v2.v
WS   := ../rtl/input_skew.v ../rtl/ws/pe_ws.v ../rtl/ws/systolic_array_ws.v ../rtl/ws/ws_top.v

.PHONY: all phase1 phase2 mac pe array top vectors requant macpipe top2 seq regress \
        ws tiled sweep results clean

all: phase1 phase2
phase1: mac pe array top
phase2: requant macpipe top2 seq regress ws tiled sweep

# ------------------------------------------------------------------ Phase I
mac:
	$(IVERILOG) $(FLAGS) -o tb_mac_unit.vvp ../rtl/mac_unit.v ../tb/tb_mac_unit.v
	$(VVP) -n tb_mac_unit.vvp

pe:
	$(IVERILOG) $(FLAGS) -o tb_pe.vvp ../rtl/mac_unit.v ../rtl/pe.v ../tb/tb_pe.v
	$(VVP) -n tb_pe.vvp

array:
	$(IVERILOG) $(FLAGS) -o tb_systolic_array.vvp $(CORE) ../tb/tb_systolic_array.v
	$(VVP) -n tb_systolic_array.vvp

vectors:
	$(PYTHON) ../model/golden_model.py

top: vectors
	$(IVERILOG) $(FLAGS) -o tb_systolic_top.vvp $(P1) ../tb/tb_systolic_top.v
	$(VVP) -n tb_systolic_top.vvp

# ------------------------------------------------------------------ Phase II
requant: vectors
	$(IVERILOG) $(FLAGS) -o tb_requant.vvp ../rtl/requant.v ../tb/tb_requant.v
	$(VVP) -n tb_requant.vvp

macpipe:
	$(IVERILOG) $(FLAGS) -o tb_mac_pipe.vvp ../rtl/mac_unit.v ../tb/tb_mac_pipe.v
	$(VVP) -n tb_mac_pipe.vvp

top2: vectors
	@for cfg in "0 0" "1 0" "0 1" "1 1"; do set -- $$cfg; \
	  $(IVERILOG) $(FLAGS) -P tb_systolic_top_v2.MUL_PIPE=$$1 -P tb_systolic_top_v2.BUF_REG=$$2 \
	      -o tb_systolic_top_v2.vvp $(V2) ../tb/tb_systolic_top_v2.v && \
	  $(VVP) -n tb_systolic_top_v2.vvp | grep -v "VCD info\|finish called" ; done

seq: vectors
	$(IVERILOG) $(FLAGS) -DDUT_SEQ -o tb_seq.vvp $(P1) ../rtl/seq_matmul.v ../tb/tb_systolic_top.v
	$(VVP) -n tb_seq.vvp
	$(IVERILOG) $(FLAGS) -DDUT_SEQ -DRANDOM -o tb_seq_rand.vvp $(P1) ../rtl/seq_matmul.v ../tb/tb_systolic_top.v
	$(VVP) -n tb_seq_rand.vvp

regress: vectors
	$(IVERILOG) $(FLAGS) -DRANDOM -o tb_regress.vvp $(P1) ../tb/tb_systolic_top.v
	$(VVP) -n tb_regress.vvp

ws: vectors
	$(IVERILOG) $(FLAGS) -o tb_ws_top.vvp $(WS) ../tb/tb_ws_top.v
	$(VVP) -n tb_ws_top.vvp

tiled: vectors
	@for s in 8 12; do \
	  $(IVERILOG) $(FLAGS) -DSIZE=$$s -o tb_tiled_gemm.vvp $(V2) ../tb/tb_tiled_gemm.v && \
	  $(VVP) -n tb_tiled_gemm.vvp | grep -v "VCD info\|finish called" ; done

sweep:
	@mkdir -p ../results
	@echo "N,PEs,latency_cycles,cycles_per_product_x100,macs_per_cycle_x100,errors,checks" > ../results/scaling.csv
	@for n in 2 3 4 8 16; do \
	  $(IVERILOG) -g2005 -P tb_scaling.N=$$n -o tb_scaling.vvp $(V2) ../tb/tb_scaling.v && \
	  $(VVP) -n tb_scaling.vvp | tee /dev/stderr | grep "^SCALING" | sed 's/^SCALING,//' >> ../results/scaling.csv ; \
	done 2>&1 | grep RESULT
	@echo "written ../results/scaling.csv"

# ------------------------------------------------------------------ results
results:
	@mkdir -p $(LOGS)
	$(MAKE) --no-print-directory phase1  > $(LOGS)/phase1.log  2>&1
	$(MAKE) --no-print-directory requant > $(LOGS)/requant.log 2>&1
	$(MAKE) --no-print-directory macpipe > $(LOGS)/macpipe.log 2>&1
	$(MAKE) --no-print-directory top2    > $(LOGS)/top2.log    2>&1
	$(MAKE) --no-print-directory seq     > $(LOGS)/seq.log     2>&1
	$(MAKE) --no-print-directory regress > $(LOGS)/regress.log 2>&1
	$(MAKE) --no-print-directory ws      > $(LOGS)/ws.log      2>&1
	$(MAKE) --no-print-directory tiled   > $(LOGS)/tiled.log   2>&1
	$(MAKE) --no-print-directory sweep   > $(LOGS)/sweep.log   2>&1
	@grep -h "RESULT" $(LOGS)/*.log
	$(PYTHON) ../model/numerics_analysis.py
	$(PYTHON) ../model/perf_model.py
	$(PYTHON) ../model/plot_results.py

# ------------------------------------------------------------------ waves
wave_mac:   ; gtkwave tb_mac_unit.vcd       mac.gtkw   &
wave_pe:    ; gtkwave tb_pe.vcd             pe.gtkw    &
wave_array: ; gtkwave tb_systolic_array.vcd array.gtkw &
wave_top:   ; gtkwave tb_systolic_top.vcd   top.gtkw   &
wave_top2:  ; gtkwave tb_systolic_top_v2.vcd top2.gtkw &

clean:
	rm -f *.vvp *.vcd
