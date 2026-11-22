#!/usr/bin/env python3
"""
plot_wave_v2.py - waveform figure of the Phase II accelerator in overlapped
(streaming) mode, rendered from the VCD written by tb_systolic_top_v2.

Shows the host writing the NEXT operands into the shadow bank (wr_en) and
reading the PREVIOUS results (rd_row) while the array computes the current
product (ctrl.state), i.e. the ping-pong + result-buffer overlap.

Usage:  cd sim && make top2 && python3 ../model/plot_wave_v2.py
        (make top2 leaves the VCD of the last configuration; for the report
         figure run the MUL_PIPE=0, BUF_REG=0 build, see below)
Requires: matplotlib
"""
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


# ---------------------------------------------------------------- VCD parser
def parse_vcd(path):
    ids, scope, signals = {}, [], {}
    with open(path) as f:
        text = f.read()
    header, _, body = text.partition("$enddefinitions")
    for line in header.splitlines():
        tok = line.split()
        if not tok:
            continue
        if tok[0] == "$scope":
            scope.append(tok[2])
        elif tok[0] == "$upscope":
            scope.pop()
        elif tok[0] == "$var":
            width, code, name = int(tok[2]), tok[3], tok[4]
            full = ".".join(scope + [name])
            ids.setdefault(code, []).append(full)
            signals[full] = {"width": width, "code": code}
    changes = {code: [] for code in ids}
    t, pending = 0, None
    for tok in body.split():
        if pending is not None:
            if tok in changes:
                changes[tok].append((t, pending))
            pending = None
        elif tok.startswith("#"):
            t = int(tok[1:])
        elif tok[0] in "bB":
            pending = tok[1:]
        elif tok[0] in "01xzXZ" and len(tok) > 1 and tok[1:] in changes:
            changes[tok[1:]].append((t, tok[0]))
    for full, s in signals.items():
        s["changes"] = changes[s["code"]]
    return signals


def value_at(changes, t):
    v = None
    for ct, cv in changes:
        if ct > t:
            break
        v = cv
    return v


def to_int(v, width, signed=False):
    if v is None or re.search("[xzXZ]", v):
        return None
    n = int(v, 2)
    if signed and n >= 1 << (width - 1):
        n -= 1 << width
    return n


# ---------------------------------------------------------------- plotting
def plot(vcd, specs, t0, t1, out, title, clk_period=10000):
    sig = parse_vcd(vcd)
    rows = len(specs)
    fig, ax = plt.subplots(figsize=(13, 0.52 * rows + 0.9))
    ax.set_xlim(t0, t1)
    ax.set_ylim(-0.5, rows)
    ax.set_yticks([rows - 1 - i + 0.35 for i in range(rows)])
    ax.set_yticklabels([s[1] for s in specs], fontsize=9, family="monospace")
    ax.tick_params(axis="x", labelsize=8)
    ax.set_xlabel("time (ns)", fontsize=9)
    ax.xaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda x, _: "%d" % (x / 1000)))
    for spine in ("top", "right", "left"):
        ax.spines[spine].set_visible(False)
    # clock-edge grid
    t = (t0 // clk_period) * clk_period + 5000
    while t < t1:
        if t >= t0:
            ax.axvline(t, color="#dddddd", lw=0.6, zorder=0)
        t += clk_period

    for i, (name, label, fmt) in enumerate(specs):
        y = rows - 1 - i
        s = sig[name]
        ch = [(t0, value_at(s["changes"], t0))] + [c for c in s["changes"] if t0 < c[0] < t1]
        ch.append((t1, None))
        for (ta, va), (tb, _) in zip(ch[:-1], ch[1:]):
            if fmt == "bit":
                lvl = 0.7 if va == "1" else 0.0
                ax.plot([ta, tb], [y + lvl, y + lvl], color="#1f5fa8", lw=1.4)
                ax.plot([tb, tb], [y, y + 0.7], color="#1f5fa8", lw=0.6) if tb < t1 else None
            else:
                w = s["width"]
                if fmt == "sdec":
                    n = to_int(va, w, True); txt = "x" if n is None else str(n)
                elif fmt == "hex":
                    n = to_int(va, w); txt = "x" if n is None else format(n, "x")
                elif fmt.startswith("state:"):
                    names = fmt.split(":")[1].split(",")
                    n = to_int(va, w); txt = "x" if n is None else names[n]
                elif fmt == "lanes":
                    bits = (va or "").rjust(w, "0")
                    lanes = []
                    for k in range(w // 8):
                        seg = bits[w - 8 * (k + 1): w - 8 * k]
                        n = to_int(seg, 8, True)
                        lanes.append("x" if n is None else str(n))
                    txt = " ".join(lanes)
                else:
                    n = to_int(va, w); txt = "x" if n is None else str(n)
                ax.fill([ta + 300, ta, ta + 300, tb - 300, tb, tb - 300],
                        [y, y + 0.35, y + 0.7, y + 0.7, y + 0.35, y],
                        facecolor="#eef4fb" if txt not in ("0", "x", "0 0 0 0", "IDLE") else "white",
                        edgecolor="#1f5fa8", lw=0.8)
                if tb - ta > 1500:
                    ax.text((ta + tb) / 2, y + 0.35, txt, ha="center", va="center",
                            fontsize=7.5 if len(txt) < 12 else 6.2, family="monospace")
    ax.set_title(title, fontsize=10)
    plt.tight_layout()
    plt.savefig(out, dpi=200)
    plt.close(fig)
    print("wrote", out)


def first_rise(vcd, name, nth=1):
    s = parse_vcd(vcd)[name]
    count = 0
    for t, v in s["changes"]:
        if v == "1":
            count += 1
            if count == nth:
                return t
    raise SystemExit("no rising edge of " + name)



if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    vcd = sys.argv[1] if len(sys.argv) > 1 else "tb_systolic_top_v2.vcd"
    out = os.path.join(here, "..", "results", "figures", "fig_wave_v2.png")
    T = "tb_systolic_top_v2"
    D = T + ".dut"
    # Part B starts with a perf_clr pulse; show 3 products from the 20th start onwards
    st = first_rise(vcd, T + ".start", nth=208 + 20)
    plot(vcd, [
        (T + ".clk", "clk", "bit"),
        (T + ".start", "start", "bit"),
        (D + ".u_ctrl.state", "ctrl.state", "state:IDLE,CLEAR,FEED,DRAIN,DONE"),
        (D + ".u_buf.active", "active bank", "udec"),
        (T + ".wr_en", "wr_en (next A,B)", "bit"),
        (T + ".wr_sel", "wr_sel (0=A 1=B)", "bit"),
        (T + ".rd_row", "rd_row (prev. C)", "udec"),
        (D + ".u_array.g_row[0].g_col[0].u_pe.acc_out", "PE00 acc", "sdec"),
        (D + ".u_array.g_row[3].g_col[3].u_pe.acc_out", "PE33 acc", "sdec"),
        (T + ".done", "done", "bit"),
    ], st - 15000, st + 360000, out,
        "Overlapped mode: loading product t+1 and reading product t-1 while product t is computed")
