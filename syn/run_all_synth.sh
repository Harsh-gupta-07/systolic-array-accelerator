#!/usr/bin/env bash
# =============================================================================
# run_all_synth.sh - every synthesis configuration used in the Phase II report
# Takes a few minutes. Results: ../results/synth/ and ../results/synth_summary.csv
# =============================================================================
set -e
cd "$(dirname "$0")"
# name            top                 chparam                         pnr     xilinx flags
./synth_one.sh mac_comb       mac_unit        "-set MUL_PIPE 0"               pnr
./synth_one.sh mac_pipe       mac_unit        "-set MUL_PIPE 1"               pnr
./synth_one.sh mac_comb_nodsp mac_unit        "-set MUL_PIPE 0"               nopnr  "-nodsp"
./synth_one.sh seq_matmul     seq_matmul      ""                              pnr
./synth_one.sh p1_top         systolic_top    ""                              pnr
./synth_one.sh v2_n4          systolic_top_v2 "-set N 4 -set MUL_PIPE 0"      pnr
./synth_one.sh v2_n4_pipe     systolic_top_v2 "-set N 4 -set MUL_PIPE 1"      pnr
./synth_one.sh v2_n4_buf      systolic_top_v2 "-set N 4 -set BUF_REG 1"       pnr
./synth_one.sh v2_n4_fast     systolic_top_v2 "-set N 4 -set MUL_PIPE 1 -set BUF_REG 1" pnr
./synth_one.sh ws_n4          ws_top          "-set N 4"                      pnr
./synth_one.sh v2_n2          systolic_top_v2 "-set N 2"                      pnr
./synth_one.sh v2_n8          systolic_top_v2 "-set N 8"                      nopnr
python3 collect_synth.py
