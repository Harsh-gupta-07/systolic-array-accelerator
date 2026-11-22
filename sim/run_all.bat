@echo off
REM Runs every Phase I + Phase II testbench with Icarus Verilog on Windows.
REM Usage:  cd sim  then  run_all.bat
cd /d %~dp0
set F=-g2005 -Wall
set CORE=..\rtl\mac_unit.v ..\rtl\pe.v ..\rtl\input_skew.v ..\rtl\systolic_array.v
set P1=%CORE% ..\rtl\matrix_buffer.v ..\rtl\systolic_controller.v ..\rtl\systolic_top.v
set V2=%CORE% ..\rtl\requant.v ..\rtl\matrix_buffer_pp.v ..\rtl\systolic_controller_v2.v ..\rtl\perf_counters.v ..\rtl\systolic_top_v2.v
set WS=..\rtl\input_skew.v ..\rtl\ws\pe_ws.v ..\rtl\ws\systolic_array_ws.v ..\rtl\ws\ws_top.v

python ..\model\golden_model.py
echo ---- Phase I ----
call :run ..\rtl\mac_unit.v ..\tb\tb_mac_unit.v
call :run ..\rtl\mac_unit.v ..\rtl\pe.v ..\tb\tb_pe.v
call :run %CORE% ..\tb\tb_systolic_array.v
call :run %P1% ..\tb\tb_systolic_top.v
echo ---- Phase II ----
call :run ..\rtl\requant.v ..\tb\tb_requant.v
call :run ..\rtl\mac_unit.v ..\tb\tb_mac_pipe.v
call :run -P tb_systolic_top_v2.MUL_PIPE=0 -P tb_systolic_top_v2.BUF_REG=0 %V2% ..\tb\tb_systolic_top_v2.v
call :run -P tb_systolic_top_v2.MUL_PIPE=1 -P tb_systolic_top_v2.BUF_REG=1 %V2% ..\tb\tb_systolic_top_v2.v
call :run -DDUT_SEQ %P1% ..\rtl\seq_matmul.v ..\tb\tb_systolic_top.v
call :run -DDUT_SEQ -DRANDOM %P1% ..\rtl\seq_matmul.v ..\tb\tb_systolic_top.v
call :run -DRANDOM %P1% ..\tb\tb_systolic_top.v
call :run %WS% ..\tb\tb_ws_top.v
call :run -DSIZE=8 %V2% ..\tb\tb_tiled_gemm.v
call :run -DSIZE=12 %V2% ..\tb\tb_tiled_gemm.v
for %%n in (2 3 4 8 16) do call :run -P tb_scaling.N=%%n %V2% ..\tb\tb_scaling.v
del t.vvp
echo.
echo Done. Waveforms: gtkwave tb_systolic_top_v2.vcd top2.gtkw
goto :eof

:run
iverilog %F% -o t.vvp %*
vvp -n t.vvp | findstr /C:"RESULT" /C:"cycles" /C:"SCALING"
goto :eof
