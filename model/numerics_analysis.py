#!/usr/bin/env python3
"""
numerics_analysis.py - accuracy of the fixed-point datapath vs floating point.

For thousands of random real-valued 4x4 matrix pairs:
  1. quantise A, B to Q4.4 (what the host writes into the accelerator)
  2. compute the exact hardware result (Q24.8, integer MACs)
  3. requantise to Q4.4 (rtl/requant.v) and to Q8.8 (16-bit option)
  4. compare every stage against the float64 reference C = A @ B

Three input distributions are studied:
  uniform[-1,1)   small activations/weights (typical after normalisation)
  uniform[-2,2)   larger range -> outputs exceed +/-8 more often
  normal(0,0.5)   bell-shaped, like trained NN weights

Outputs: results/numerics.csv and results/figures/fig_numerics.png
Requires: numpy, matplotlib
"""
import csv
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import golden_model as gm          # noqa: E402
import plot_style as ps            # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "results")
TRIALS = 5000
N = gm.N


def quant_in(x):
    """float -> Q4.4 code (round to nearest, saturate) - same as gm.to_q44."""
    return np.clip(np.round(x * 16), -128, 127).astype(np.int64)


def requant_np(acc, out_w, out_frac, in_frac=8):
    """Vectorised, bit-exact copy of gm.requant / rtl/requant.v."""
    sh = in_frac - out_frac
    v = (acc + (1 << (sh - 1))) >> sh if sh > 0 else acc.copy()
    lo, hi = -(1 << (out_w - 1)), (1 << (out_w - 1)) - 1
    return np.clip(v, lo, hi), (v > hi) | (v < lo)


def analyse(name, A, B):
    C_true = A @ B                                        # float64 reference
    Aq, Bq = quant_in(A), quant_in(B)
    C_raw = Aq @ Bq                                       # exact integer MACs (Q24.8)
    e_raw = C_raw / 256.0 - C_true
    q44, s44 = requant_np(C_raw, 8, 4)
    e44 = q44 / 16.0 - C_true
    q88, s88 = requant_np(C_raw, 16, 8)
    e88 = q88 / 256.0 - C_true
    ok = ~s44
    return {
        "distribution": name,
        "rmse_q24_8": float(np.sqrt(np.mean(e_raw ** 2))),
        "max_err_q24_8": float(np.max(np.abs(e_raw))),
        "rmse_q8_8": float(np.sqrt(np.mean(e88 ** 2))),
        "sat_pct_q8_8": float(100 * np.mean(s88)),
        "rmse_q4_4_unsat": float(np.sqrt(np.mean(e44[ok] ** 2))),
        "max_err_q4_4_unsat": float(np.max(np.abs(e44[ok]))),
        "sat_pct_q4_4": float(100 * np.mean(s44)),
        "output_range": float(np.max(np.abs(C_true))),
    }, e_raw.ravel(), e44[ok].ravel()


def self_check(rng):
    """The vectorised requant must match the scalar golden model bit for bit."""
    vals = rng.integers(-(1 << 20), 1 << 20, 20000)
    q, s = requant_np(vals, 8, 4)
    for v, qq, ss in zip(vals[:2000], q[:2000], s[:2000]):
        assert gm.requant(int(v)) == (int(qq), bool(ss))


def main():
    rng = np.random.default_rng(2026)
    self_check(rng)
    dists = {
        "uniform[-1,1)": lambda: rng.uniform(-1, 1, (TRIALS, N, N)),
        "uniform[-2,2)": lambda: rng.uniform(-2, 2, (TRIALS, N, N)),
        "normal(0,0.5)": lambda: rng.normal(0, 0.5, (TRIALS, N, N)),
    }
    rows, hist = [], {}
    for name, gen in dists.items():
        r, e_raw, e44 = analyse(name, gen(), gen())
        rows.append(r)
        hist[name] = (e_raw, e44)

    os.makedirs(os.path.join(RES, "figures"), exist_ok=True)
    with open(os.path.join(RES, "numerics.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 5) if isinstance(v, float) else v) for k, v in r.items()})

    # ---- figure: error distribution for uniform[-1,1) ----
    ps.setup()
    import matplotlib.pyplot as plt
    e_raw, e44 = hist["uniform[-1,1)"]
    fig, axes = plt.subplots(1, 2, figsize=(7.0, 2.4))
    bins = np.linspace(-0.12, 0.12, 49)
    axes[0].hist(e_raw, bins=bins, color=ps.SERIES[0], edgecolor="white", linewidth=0.6)
    axes[0].set_title("(a) Q24.8 accumulator vs float")
    axes[1].hist(e44, bins=bins, color=ps.SERIES[1], edgecolor="white", linewidth=0.6)
    axes[1].set_title("(b) after requantisation to Q4.4")
    for ax in axes:
        ax.set_xlabel("error (real units)")
        ax.set_ylabel("elements")
        ax.axvline(0, color=ps.INK2, lw=0.8)
    fig.tight_layout()
    fig.savefig(os.path.join(RES, "figures", "fig_numerics.png"), dpi=220)

    print("numerics_analysis: %d products per distribution" % TRIALS)
    for r in rows:
        print("  {distribution:14s} RMSE Q24.8 {rmse_q24_8:.4f} | Q8.8 {rmse_q8_8:.4f} "
              "(sat {sat_pct_q8_8:.2f}%) | Q4.4 {rmse_q4_4_unsat:.4f} (sat {sat_pct_q4_4:.2f}%)".format(**r))


if __name__ == "__main__":
    main()
