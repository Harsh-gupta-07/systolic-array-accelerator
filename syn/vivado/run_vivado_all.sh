#!/usr/bin/env bash
# Runs the Vivado out-of-context flow for every design in the report.
# Open "Vivado Tcl Shell" (or a cmd with Vivado on PATH), cd to syn/vivado, run this file.
vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs seq_matmul "" seq_matmul
vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs systolic_top "" p1_top
vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs systolic_top_v2 "" v2_n4
vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs systolic_top_v2 "MUL_PIPE=1 BUF_REG=1" v2_n4_fast
vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs ws_top "" ws_n4
cat reports/vivado_summary.csv
