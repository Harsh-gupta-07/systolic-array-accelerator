#!/usr/bin/env python3
"""Collect Yosys / nextpnr reports in ../results/synth into one CSV + Markdown table."""
import csv, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.join(HERE, "..", "results", "synth")
ORDER = ["mac_comb", "mac_pipe", "mac_comb_nodsp", "seq_matmul", "p1_top",
         "v2_n2", "v2_n4", "v2_n4_pipe", "v2_n4_buf", "v2_n4_fast", "v2_n8", "ws_n4"]


def cells(path):
    d = {}
    if not os.path.exists(path):
        return d
    txt = open(path).read()
    # last (top-level, flattened) "Number of cells" block
    blocks = txt.split("Number of cells:")
    for line in blocks[-1].splitlines()[1:]:
        m = re.match(r"\s+(\S+)\s+(\d+)\s*$", line)
        if m:
            d[m.group(1)] = int(m.group(2))
    return d


def pnr(path):
    d = {}
    if not os.path.exists(path):
        return d
    txt = open(path).read()
    f = re.findall(r"Max frequency for clock '[^']*': ([\d.]+) MHz", txt)
    if f:
        d["fmax"] = float(f[-1])
    for key in ("TRELLIS_COMB", "TRELLIS_FF", "MULT18X18D"):
        m = re.findall(r"%s:\s+(\d+)/" % key, txt)
        if m:
            d[key] = int(m[-1])
    return d


rows = []
for name in ORDER:
    x = cells(os.path.join(SD, name + "_xc7.txt"))
    p = pnr(os.path.join(SD, name + "_pnr.txt"))
    e = cells(os.path.join(SD, name + "_ecp5.txt"))
    if not x:
        continue
    lut = sum(v for k, v in x.items() if k.startswith("LUT"))
    ff = sum(v for k, v in x.items() if k.startswith("FD"))
    rows.append({
        "design": name,
        "xc7_LUT": lut, "xc7_FF": ff,
        "xc7_LUTRAM": sum(v for k, v in x.items() if k.startswith("RAM")),
        "xc7_DSP48": x.get("DSP48E1", 0), "xc7_CARRY4": x.get("CARRY4", 0),
        "ecp5_LUT4": p.get("TRELLIS_COMB", e.get("LUT4", "")),
        "ecp5_FF": p.get("TRELLIS_FF", sum(v for k, v in e.items() if k.startswith("TRELLIS_FF"))),
        "ecp5_MULT18": p.get("MULT18X18D", e.get("MULT18X18D", 0)),
        "ecp5_fmax_MHz": p.get("fmax", ""),
    })

out_csv = os.path.join(HERE, "..", "results", "synth_summary.csv")
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

hdr = list(rows[0].keys())
print("| " + " | ".join(hdr) + " |")
print("|" + "---|" * len(hdr))
for r in rows:
    print("| " + " | ".join(str(r[h]) for h in hdr) + " |")
print("\nwritten:", os.path.normpath(out_csv))
