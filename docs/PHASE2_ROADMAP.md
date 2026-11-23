# Phase II Roadmap (70% of the grade)

> **Status (final): completed.** Every core item below was implemented, verified and measured. The optional NumPy timing comparison and the 16-bit operand variant were not pursued.
> The results are in [`report/final_report.pdf`](../report/final_report.pdf) and [`results/summary.md`](../results/summary.md).
> Differences from the original plan:
> - **Synthesis:** done with the open-source Yosys + nextpnr flow (Lattice ECP5 post-route Fmax, Xilinx 7-series resource estimates). The Vivado script is in `syn/vivado/`.
> - **Timing:** a registered buffer output (`BUF_REG`) was added after the critical path was found in the buffer read mux.
> - **Weight-stationary:** implemented as a full streaming design (`rtl/ws/`), not just an optional study.
> - **Result buffer:** used instead of a shift-out chain.
> - **Diagonal clear propagation:** not needed. Back-to-back starts from the DONE state plus accumulate mode give the same benefit with a simpler controller.

Phase I delivered a **functionally correct** prototype. Phase II is about **results and discussion**: numbers, comparisons and trade-offs. Every member owns at least one deliverable that produces a quantitative result, so that everyone has something concrete to present and defend in the interview.

The final report needs a *Results and Discussion* section. Each item below feeds a table or plot in that section.

---

## Member 1: arithmetic and numerics (MAC v2)

| Task | Output for the report |
|---|---|
| Add **output requantisation**: Q24.8 → Q8.8 or Q4.4 with round-to-nearest and **saturation**, plus an overflow flag | Table of error vs the floating-point result (Python) for the Q4.4/Q8.8 outputs |
| Make `DATA_W` 8/16 configurable; optionally add a **pipelined multiplier register** | Area vs Fmax for the 1-stage and 2-stage MAC |
| Synthesise the MAC alone in Vivado with `use_dsp = "yes"` and `"no"` | DSP48 vs LUT multiplier: resources and timing |
| Interview prep | Why Q4.4? Why a 32-bit accumulator? Fixed vs floating point |

## Member 2: PE and dataflow comparison

| Task | Output for the report |
|---|---|
| Add **valid-bit propagation** and a **diagonally propagated clear** in the PE, so the next matrix can enter while the previous one drains (removes the CLEAR/DRAIN bubble) | Cycles per matrix, before vs after |
| Add a **result shift-out chain** (accumulators shift out through the array instead of using a wide 512-bit mux) | Mux area vs shift-chain latency |
| Optional: a **weight-stationary PE** variant for comparison | WS vs OS: cycles, registers, control complexity (fills in Table I of the report with measured numbers) |

## Member 3: scaling and tiling

| Task | Output for the report |
|---|---|
| Parameter sweep `N = 2, 3, 4, 8` | Latency, throughput and PE count vs N (plot) |
| **Tiling**: compute 8×8 and 16×16 products on the 4×4 array (block matrix multiply with accumulation across tiles) | Cycles for a large GEMM vs ideal |
| **PE utilisation** analysis: active MAC-cycles / (N² × total cycles) | Utilisation plot; explain the ramp-up/ramp-down of the wavefront |
| Analytical model `T(N) = 3N − 2 (+ overhead)` vs measured | Model vs simulation table |

## Member 4: control, buffering and synthesis

| Task | Output for the report |
|---|---|
| **Double-buffered (ping-pong) input buffers**: load the next A/B while the current product is computing | Throughput with and without overlap |
| **Hardware performance counters**: total cycles, busy cycles, MAC count, readable through the interface | Measured MAC/cycle and utilisation |
| **Vivado synthesis and implementation** of `systolic_top` for an Artix-7 part (e.g. xc7a35t, as on Basys-3/Arty). Only the part number is needed, no board | Utilisation table (LUT/FF/DSP/BRAM), **Fmax** from timing (WNS), critical path |
| Compute **GOPS = 2·N²·Fmax** (peak) and the achieved value | Peak vs achieved throughput |

## Member 5: baseline, regression and final integration

| Task | Output for the report |
|---|---|
| **Sequential baseline**: one MAC unit plus counters computing C in N³ cycles (`rtl/seq_matmul.v` + testbench) | **Speed-up** = T_seq / T_systolic for N = 2…8, and **speed-up per unit area** (with the Vivado numbers) |
| **Constrained-random regression**: the golden model generates ≥ 1000 random matrices (seeded) | Pass rate and coverage of corner cases |
| Optional: a Python/NumPy timing comparison (as in Lab 6C) for context | Plot of cycles vs N |
| Final report integration: *Results and Discussion*, *Conclusion*, final figures | Final IEEE report |

---

## Suggested timeline

| Week | Milestone |
|---|---|
| 1 | Baseline RTL, perf counters, valid/clear propagation, requantisation |
| 2 | Double buffering, tiling, random regression green |
| 3 | Vivado runs, parameter sweeps, plots |
| 4 | Final report, rehearse the interview (each member explains *every* module, not only their own) |

## Interview preparation: questions to expect

- Why output-stationary and not weight-stationary? What does the TPU use?
- Derive the 3N − 2 latency. Where do the 2N − 2 drain cycles come from?
- What limits Fmax in your design? How would you pipeline it further?
- How does throughput change if matrices are streamed back-to-back?
- Why can the 32-bit accumulator not overflow for N = 4? What happens at N = 256?
- Speed-up vs the sequential version, and is the area cost worth it?
- How does a systolic array address the memory wall (operand reuse)?
