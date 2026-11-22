#!/usr/bin/env python3
"""
plot_results.py - turn simulation logs + synthesis reports into the
comparison tables and figures used in the Phase II report.

Inputs : results/logs/*.log           (make results)
         results/synth_summary.csv    (syn/run_all_synth.sh)
         results/numerics.csv, results/perf_model.csv
Outputs: results/figures/fig_throughput.png, fig_pipeline.png
         results/summary.md            (every table, ready to paste)
"""
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plot_style as ps            # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "results")
LOGS = os.path.join(RES, "logs")
MACS = 64                         # MACs in one 4x4x4 product


def log(name):
    p = os.path.join(LOGS, name)
    if not os.path.exists(p):
        sys.exit("missing %s - run 'make results' in sim/ first" % p)
    return open(p).read()


def first(pattern, text, cast=float):
    m = re.search(pattern, text)
    return cast(m.group(1)) if m else None


def synth():
    with open(os.path.join(RES, "synth_summary.csv")) as f:
        return {r["design"]: r for r in csv.DictReader(f)}


def top2_configs(text):
    """{(mul_pipe, buf_reg): (serial cycles/product, overlapped cycles/product)}"""
    out = {}
    for blk in text.split("tb_systolic_top_v2 :")[1:]:
        mp = int(re.search(r"MUL_PIPE = (\d)", blk).group(1))
        br = int(re.search(r"BUF_REG = (\d)", blk).group(1))
        a = float(re.search(r"Part A.*?-> ([\d.]+) cycles/product", blk).group(1))
        b = float(re.search(r"Part B.*?-> ([\d.]+) cycles/product", blk).group(1))
        out[(mp, br)] = (a, b)
    return out


def md_table(header, rows):
    s = "| " + " | ".join(header) + " |\n|" + "---|" * len(header) + "\n"
    for r in rows:
        s += "| " + " | ".join(str(x) for x in r) + " |\n"
    return s


def main():
    syn = synth()
    seq_host = first(r"host cycles per product\s+:\s+(\d+)", log("seq.log"))
    seq_lat = first(r"start->done latency\s+:\s+(\d+)", log("seq.log"))
    p1_host = first(r"host cycles per product\s+:\s+(\d+)", log("phase1.log"))
    p1_lat = first(r"start->done latency\s+:\s+(\d+)", log("phase1.log"))
    t2 = top2_configs(log("top2.log"))
    fmax = lambda d: float(syn[d]["ecp5_fmax_MHz"]) if syn.get(d, {}).get("ecp5_fmax_MHz") else None

    # ---------------- design comparison (host-visible, 4x4 product) ----------
    designs = [
        ("Sequential, 1 MAC",           seq_host,     fmax("seq_matmul"), "seq_matmul"),
        ("Phase I systolic",            p1_host,      fmax("p1_top"),     "p1_top"),
        ("Phase II, serial",            t2[(0, 0)][0], fmax("v2_n4"),     "v2_n4"),
        ("Phase II, overlapped",        t2[(0, 0)][1], fmax("v2_n4"),     "v2_n4"),
        ("Phase II, overlapped + pipe", t2[(1, 1)][1], fmax("v2_n4_fast"), "v2_n4_fast"),
    ]
    base_ns = seq_host * 1000.0 / fmax("seq_matmul")
    comp_rows = []
    for name, cyc, f, d in designs:
        ns = cyc * 1000.0 / f
        comp_rows.append([name, "%.2f" % cyc, "%.1f" % f, "%.0f" % ns,
                          "%.2f" % (2 * MACS / ns), "%.1fx" % (base_ns / ns),
                          syn[d]["xc7_DSP48"], syn[d]["xc7_LUT"], syn[d]["xc7_FF"]])

    # ---------------- pipeline study ----------------
    cfgs = [((0, 0), "v2_n4", "none"), ((1, 0), "v2_n4_pipe", "MAC pipe"),
            ((0, 1), "v2_n4_buf", "buffer reg"), ((1, 1), "v2_n4_fast", "both")]
    pipe_rows = []
    for key, d, label in cfgs:
        cyc = t2[key][1]
        f = fmax(d)
        pipe_rows.append([label, int(round(3 * 4 + key[0] + key[1])), "%.2f" % cyc, "%.1f" % f,
                          "%.0f" % (cyc * 1000.0 / f), syn[d]["xc7_LUT"], syn[d]["xc7_FF"]])

    # ---------------- figures ----------------
    ps.setup()
    import matplotlib.pyplot as plt
    short = ["Seq.\n1 MAC", "Phase I", "P-II\nserial", "P-II\noverlap", "P-II\noverlap+pipe"]
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(7.0, 2.6))
    b = a1.bar(short, [d[1] for d in designs], color=ps.SERIES[0], width=0.6)
    ps.bar_labels(a1, b, "{:.0f}")
    a1.set_ylabel("cycles per 4$\\times$4 product")
    a1.set_title("(a) clock cycles (host-visible)")
    b = a2.bar(short, [d[1] * 1000.0 / d[2] for d in designs], color=ps.SERIES[1], width=0.6)
    ps.bar_labels(a2, b, "{:.0f}")
    a2.set_ylabel("ns per 4$\\times$4 product")
    a2.set_title("(b) wall-clock time at ECP5 $f_{max}$")
    for ax in (a1, a2):
        ax.tick_params(axis="x", labelsize=7.5)
        ax.grid(axis="x", visible=False)
    fig.tight_layout()
    fig.savefig(os.path.join(RES, "figures", "fig_throughput.png"), dpi=220)

    labels = ["none", "MAC\npipe", "buffer\nreg", "both"]
    fig, (c1, c2) = plt.subplots(1, 2, figsize=(7.0, 2.4))
    b = c1.bar(labels, [float(r[3]) for r in pipe_rows], color=ps.SERIES[2], width=0.55)
    ps.bar_labels(c1, b, "{:.0f}")
    c1.set_ylabel("$f_{max}$ (MHz)")
    c1.set_title("(a) post-route $f_{max}$, ECP5-85F")
    b = c2.bar(labels, [float(r[4]) for r in pipe_rows], color=ps.SERIES[1], width=0.55)
    ps.bar_labels(c2, b, "{:.0f}")
    c2.set_ylabel("ns per product (overlapped)")
    c2.set_title("(b) time per product")
    for ax in (c1, c2):
        ax.grid(axis="x", visible=False)
    fig.tight_layout()
    fig.savefig(os.path.join(RES, "figures", "fig_pipeline.png"), dpi=220)

    # ---------------- summary.md ----------------
    s = "# Phase II results summary (generated by model/plot_results.py)\n\n"
    s += "## 1. Design comparison: one 4x4 product, host-visible\n\n"
    s += md_table(["design", "cycles/product", "Fmax MHz (ECP5)", "ns/product", "GOPS",
                   "speed-up vs seq", "DSP48 (xc7)", "LUT (xc7)", "FF (xc7)"], comp_rows)
    s += "\nCompute-only latency (start->done): sequential %d cycles, systolic %d cycles (%.1fx).\n" % (
        seq_lat, p1_lat, seq_lat / p1_lat)
    s += "\n## 2. Pipelining study (Phase II top, N = 4)\n\n"
    s += md_table(["pipeline registers", "start->done cycles", "cycles/product (overlapped)",
                   "Fmax MHz", "ns/product", "LUT (xc7)", "FF (xc7)"], pipe_rows)
    for name in ("synth_summary.csv", "perf_model.csv", "numerics.csv", "scaling.csv"):
        p = os.path.join(RES, name)
        if os.path.exists(p):
            with open(p) as f:
                rows = list(csv.reader(f))
            s += "\n## %s\n\n" % name + md_table(rows[0], rows[1:])
    with open(os.path.join(RES, "summary.md"), "w") as f:
        f.write(s)
    print(s.split("## synth_summary")[0])


if __name__ == "__main__":
    main()
