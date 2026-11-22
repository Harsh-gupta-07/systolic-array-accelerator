# =============================================================================
# synth_ooc.tcl - Vivado non-project flow: synthesis + place & route of one
# design out-of-context (no board / pin constraints needed) on an Artix-7.
#
# Usage (from this folder, Vivado 2020.x or newer, Windows or Linux):
#   vivado -mode batch -source synth_ooc.tcl -tclargs systolic_top_v2 "MUL_PIPE=1 BUF_REG=1" v2_n4_fast
#   vivado -mode batch -source synth_ooc.tcl -tclargs seq_matmul "" seq_matmul
#   vivado -mode batch -source synth_ooc.tcl -tclargs systolic_top "" p1_top
#
# Outputs: reports/<name>_util.txt, reports/<name>_timing.txt and one line in
#          reports/vivado_summary.csv (LUT, FF, DSP, WNS, Fmax)
# Fmax is computed as 1000 / (clock period - WNS).
# =============================================================================
set top     [lindex $argv 0]
set generic [lindex $argv 1]
set name    [lindex $argv 2]
set part    xc7a35tcpg236-1          ;# Artix-7 35T (Basys-3); change if needed
set period  8.0                       ;# 125 MHz target; WNS tells the real limit

file mkdir reports
read_verilog [glob ../../rtl/*.v ../../rtl/ws/*.v]

set gargs {}
foreach g $generic { lappend gargs -generic $g }
synth_design -top $top -part $part -mode out_of_context {*}$gargs

create_clock -name clk -period $period [get_ports clk]
opt_design
place_design
route_design

report_utilization    -file reports/${name}_util.txt
report_timing_summary -file reports/${name}_timing.txt

set wns  [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set fmax [expr {1000.0 / ($period - $wns)}]
set lut  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]]
set ff   [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]
set dsp  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == ARITHMETIC && REF_NAME =~ DSP*}]]

set csv reports/vivado_summary.csv
if {![file exists $csv]} {
    set f [open $csv w]; puts $f "design,LUT,FF,DSP,WNS_ns,Fmax_MHz"; close $f
}
set f [open $csv a]
puts $f [format "%s,%d,%d,%d,%.3f,%.1f" $name $lut $ff $dsp $wns $fmax]
close $f
puts "==== $name : LUT $lut  FF $ff  DSP $dsp  WNS $wns ns  Fmax [format %.1f $fmax] MHz"
