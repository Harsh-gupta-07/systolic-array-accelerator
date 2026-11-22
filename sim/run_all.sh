#!/usr/bin/env bash
# Runs every Phase I + Phase II testbench with Icarus Verilog (Linux / macOS / Git-Bash).
# Same as "make all". Usage:  cd sim && ./run_all.sh
set -e
cd "$(dirname "$0")"
F="-g2005 -Wall"
CORE="../rtl/mac_unit.v ../rtl/pe.v ../rtl/input_skew.v ../rtl/systolic_array.v"
P1="$CORE ../rtl/matrix_buffer.v ../rtl/systolic_controller.v ../rtl/systolic_top.v"
V2="$CORE ../rtl/requant.v ../rtl/matrix_buffer_pp.v ../rtl/systolic_controller_v2.v ../rtl/perf_counters.v ../rtl/systolic_top_v2.v"
WS="../rtl/input_skew.v ../rtl/ws/pe_ws.v ../rtl/ws/systolic_array_ws.v ../rtl/ws/ws_top.v"
run() { iverilog $F -o t.vvp "$@" && vvp -n t.vvp | grep -E "RESULT|cycles|SCALING" ; }

python3 ../model/golden_model.py || python ../model/golden_model.py
echo "---- Phase I ----"
run ../rtl/mac_unit.v ../tb/tb_mac_unit.v
run ../rtl/mac_unit.v ../rtl/pe.v ../tb/tb_pe.v
run $CORE ../tb/tb_systolic_array.v
run $P1 ../tb/tb_systolic_top.v
echo "---- Phase II ----"
run ../rtl/requant.v ../tb/tb_requant.v
run ../rtl/mac_unit.v ../tb/tb_mac_pipe.v
for c in "0 0" "1 0" "0 1" "1 1"; do set -- $c
  run -P tb_systolic_top_v2.MUL_PIPE=$1 -P tb_systolic_top_v2.BUF_REG=$2 $V2 ../tb/tb_systolic_top_v2.v; done
run -DDUT_SEQ $P1 ../rtl/seq_matmul.v ../tb/tb_systolic_top.v
run -DDUT_SEQ -DRANDOM $P1 ../rtl/seq_matmul.v ../tb/tb_systolic_top.v
run -DRANDOM $P1 ../tb/tb_systolic_top.v
run $WS ../tb/tb_ws_top.v
run -DSIZE=8  $V2 ../tb/tb_tiled_gemm.v
run -DSIZE=12 $V2 ../tb/tb_tiled_gemm.v
for n in 2 3 4 8 16; do run -P tb_scaling.N=$n $V2 ../tb/tb_scaling.v; done
rm -f t.vvp
echo
echo "Done. Waveforms: gtkwave tb_systolic_top_v2.vcd top2.gtkw"
