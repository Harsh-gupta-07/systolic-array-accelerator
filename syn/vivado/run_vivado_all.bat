@echo off
REM Runs the Vivado out-of-context flow for every design in the report.
REM Open "Vivado Tcl Shell" (or a cmd with Vivado on PATH), cd to syn\vivado, run this file.
call vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs seq_matmul "" seq_matmul
call vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs systolic_top "" p1_top
call vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs systolic_top_v2 "" v2_n4
call vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs systolic_top_v2 "MUL_PIPE=1 BUF_REG=1" v2_n4_fast
call vivado -mode batch -nojournal -source synth_ooc.tcl -tclargs ws_top "" ws_n4
type reports\vivado_summary.csv
