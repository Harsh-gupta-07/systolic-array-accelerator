#!/usr/bin/env python3
"""
perf_model.py - analytical performance model of the accelerator, checked
against the cycle counts measured in simulation.

Model (output-stationary array, N x N PEs, no optional pipeline registers)
  start->done latency        L(N)   = 3N          (1 clear + N feed + 2N-2 drain + 1 done)
  back-to-back period        P(N)   = 3N          (one product every 3N cycles)
  throughput                 N^3 / 3N = N^2 / 3   MACs per cycle
  PE utilisation             (N^3) / (N^2 * 3N) = 1/3
  sequential baseline        N^3 cycles (+1 done)

Weight-stationary array streaming M rows of A against one N x N B
  WS cycles                  T_ws(M) = N (weight load) + M + (2N - 1)
  OS cycles (same problem)   T_os(M) = ceil(M/N) * 3N  (one OS product per N rows)
  WS utilisation             M*N^2 / (N^2 * T_ws) = M / (M + 3N - 1)

Tiled S x S GEMM on the 4x4 array (T = S/N tiles per dimension)
  T^2 output tiles, each needs T tile products: the first clears (3N cycles),
  the other T-1 use accumulate mode (3N - 1 cycles, no CLEAR state).
  total = 2N (first load) + T^2 * (3N + (T-1)(3N-1)) + N (last read) + 1

Inputs : results/scaling.csv, results/logs/{ws,tiled,top2}.log
Outputs: results/perf_model.csv, results/figures/fig_scaling.png, fig_os_vs_ws.png
"""
import csv
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plot_style as ps            # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "results")
LOGS = os.path.join(RES, "logs")


def read_log(name):
    p = os.path.join(LOGS, name)
    return open(p).read() if os.path.exists(p) else ""


def os_latency(n):  return 3 * n
def os_period(n):   return 3 * n
def seq_cycles(n):  return n ** 3
def ws_cycles(n, m): return n + m + 2 * n - 1
def os_rows(n, m):  return math.ceil(m / n) * os_period(n)


def tiled_cycles(s, n=4):
    t = s // n
    return 2 * n + t * t * (3 * n + (t - 1) * (3 * n - 1)) + n + 1


def main():
    rows = []

    # ---- scaling sweep ----
    scal = []
    with open(os.path.join(RES, "scaling.csv")) as f:
        for r in csv.DictReader(f):
            n = int(r["N"])
            meas_p = int(r["cycles_per_product_x100"]) / 100.0
            meas_tp = int(r["macs_per_cycle_x100"]) / 100.0
            scal.append((n, int(r["latency_cycles"]), meas_p, meas_tp))
            rows.append(["latency start->done", "N=%d" % n, os_latency(n), int(r["latency_cycles"])])
            rows.append(["cycles per product (50 back-to-back)", "N=%d" % n, os_period(n), meas_p])
            rows.append(["MACs per cycle", "N=%d" % n, round(n * n / 3, 2), meas_tp])

    # ---- weight-stationary ----
    ws_meas = {int(m): int(c) for m, c in re.findall(r"M =\s*(\d+) rows : \d+ rows checked, (\d+) cycles",
                                                     read_log("ws.log"))}
    for m, c in sorted(ws_meas.items()):
        rows.append(["WS cycles, M rows of A", "M=%d" % m, ws_cycles(4, m), c])

    # ---- tiled GEMM ----
    for s, c in re.findall(r"tb_tiled_gemm : (\d+)x\d+.*?total cycles\s+:\s+(\d+)", read_log("tiled.log"), re.S):
        rows.append(["tiled GEMM total cycles", "%sx%s" % (s, s), tiled_cycles(int(s)), int(c)])

    with open(os.path.join(RES, "perf_model.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["metric", "config", "model", "measured"])
        w.writerows(rows)

    # ---- figures ----
    ps.setup()
    import matplotlib.pyplot as plt

    ns = [s[0] for s in scal]
    nn = list(range(2, 17))
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(7.0, 2.6))
    a1.plot(nn, [seq_cycles(n) for n in nn], color=ps.SERIES[1], label="sequential, model $N^3$")
    a1.plot(nn, [os_period(n) for n in nn], color=ps.SERIES[0], label="systolic, model $3N$")
    a1.plot(ns, [s[2] for s in scal], "o", color=ps.SERIES[0], markeredgecolor="white",
            label="systolic, measured")
    a1.set_yscale("log")
    a1.set_xlabel("array size N")
    a1.set_ylabel("cycles per N$\\times$N product")
    a1.set_title("(a) cycles per product")
    a1.legend(fontsize=7.5)
    for ax in (a1, a2):
        ax.set_xticks([2, 3, 4, 8, 16])

    a2.plot(nn, [n * n for n in nn], color=ps.SERIES[2], label="peak $N^2$ (every PE busy)")
    a2.plot(nn, [n * n / 3 for n in nn], color=ps.SERIES[0], label="model $N^2/3$")
    a2.plot(ns, [s[3] for s in scal], "o", color=ps.SERIES[0], markeredgecolor="white", label="measured")
    a2.set_xlabel("array size N")
    a2.set_ylabel("MACs per cycle")
    a2.set_title("(b) throughput")
    a2.legend(fontsize=7.5)
    fig.tight_layout()
    fig.savefig(os.path.join(RES, "figures", "fig_scaling.png"), dpi=220)

    ms = list(range(4, 65, 4))
    fig, (b1, b2) = plt.subplots(1, 2, figsize=(7.0, 2.6))
    b1.plot(ms, [os_rows(4, m) for m in ms], color=ps.SERIES[0], label="output-stationary (model)")
    b1.plot(ms, [ws_cycles(4, m) for m in ms], color=ps.SERIES[1], label="weight-stationary (model)")
    b1.plot(list(ws_meas), list(ws_meas.values()), "o", color=ps.SERIES[1], markeredgecolor="white",
            label="WS measured")
    b1.plot([4, 16], [12, round(4 * 12.06)], "o", color=ps.SERIES[0], markeredgecolor="white",
            label="OS measured")
    b1.set_xlabel("rows of A (M), B is 4$\\times$4")
    b1.set_ylabel("cycles")
    b1.set_title("(a) cycles for (M$\\times$4)$\\cdot$(4$\\times$4)")
    b1.legend(fontsize=7.5)
    b2.plot(ms, [100 * m * 16 / (16 * os_rows(4, m)) for m in ms], color=ps.SERIES[0], label="output-stationary")
    b2.plot(ms, [100 * m / (m + 11) for m in ms], color=ps.SERIES[1], label="weight-stationary")
    b2.set_ylim(0, 100)
    b2.set_xlabel("rows of A (M)")
    b2.set_ylabel("PE utilisation (%)")
    b2.set_title("(b) PE utilisation")
    b2.legend(fontsize=7.5)
    fig.tight_layout()
    fig.savefig(os.path.join(RES, "figures", "fig_os_vs_ws.png"), dpi=220)

    print("perf_model: model vs measured")
    for r in rows:
        print("  {:40s} {:8s} model {:>8} measured {:>8}".format(*[str(x) for x in r]))


if __name__ == "__main__":
    main()
