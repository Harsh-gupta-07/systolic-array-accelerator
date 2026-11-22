#!/usr/bin/env bash
# =============================================================================
# synth_one.sh - synthesise one design configuration with open-source tools
#
#   ./synth_one.sh <name> <top> "<chparam args>" [pnr|nopnr] ["<extra synth_xilinx flags>"]
#
#   * Yosys synth_xilinx (-family xc7)  -> Xilinx 7-series resource estimate
#                                          (LUT, FF, DSP48E1, CARRY4)
#   * Yosys synth_ecp5 + nextpnr-ecp5   -> real place & route on a Lattice
#                                          ECP5-85F: utilisation and Fmax
#     (only when the 4th argument is "pnr"; the design must fit the I/O count)
#
#   Results go to ../results/synth/<name>_*.txt
#   Requirements: yosys, nextpnr-ecp5 (apt install yosys nextpnr-ecp5 fpga-trellis)
# =============================================================================
set -e
cd "$(dirname "$0")"
NAME=$1; TOP=$2; PARAMS=$3; PNR=$4; XFLAGS=$5
OUT=../results/synth; mkdir -p "$OUT"
RTL="../rtl/mac_unit.v ../rtl/pe.v ../rtl/input_skew.v ../rtl/systolic_array.v \
     ../rtl/matrix_buffer.v ../rtl/systolic_controller.v ../rtl/systolic_top.v \
     ../rtl/requant.v ../rtl/matrix_buffer_pp.v ../rtl/systolic_controller_v2.v \
     ../rtl/perf_counters.v ../rtl/systolic_top_v2.v ../rtl/seq_matmul.v \
     ../rtl/ws/pe_ws.v ../rtl/ws/systolic_array_ws.v ../rtl/ws/ws_top.v"

CHP=""
[ -n "$PARAMS" ] && CHP="chparam $PARAMS $TOP;"

# ---- Xilinx 7-series resource estimate ----
yosys -q -l "$OUT/${NAME}_xc7.log" -p "read_verilog $RTL; $CHP synth_xilinx -family xc7 -top $TOP -flatten $XFLAGS; tee -o $OUT/${NAME}_xc7.txt stat" >/dev/null

# ---- ECP5 synthesis (+ optional place & route) ----
yosys -q -l "$OUT/${NAME}_ecp5.log" -p "read_verilog $RTL; $CHP synth_ecp5 -top $TOP -json $OUT/${NAME}.json; tee -o $OUT/${NAME}_ecp5.txt stat" >/dev/null
if [ "$PNR" = "pnr" ]; then
    nextpnr-ecp5 --85k --package CABGA756 --json "$OUT/${NAME}.json" --freq 100 \
        --timing-allow-fail --seed 1 --quiet --log "$OUT/${NAME}_pnr.txt" >/dev/null 2>&1 || true
fi
rm -f "$OUT/${NAME}.json"
echo "done: $NAME"
