"""Shared matplotlib style for all Phase II report figures (print, light surface)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]   # categorical slots 1-4, fixed order
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#ffffff"


def setup():
    plt.rcParams.update({
        "figure.facecolor": SURFACE, "axes.facecolor": SURFACE,
        "axes.edgecolor": INK2, "axes.labelcolor": INK, "axes.titlecolor": INK,
        "xtick.color": INK2, "ytick.color": INK2, "text.color": INK,
        "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.6,
        "axes.spines.top": False, "axes.spines.right": False,
        "axes.axisbelow": True, "font.size": 9, "axes.titlesize": 10,
        "legend.frameon": False, "lines.linewidth": 2, "lines.markersize": 6,
    })


def bar_labels(ax, bars, fmt="{:.0f}", pad=3):
    top = max(b.get_height() for b in bars)
    ax.set_ylim(0, top * 1.18)                     # headroom so labels clear the title
    for b in bars:
        ax.annotate(fmt.format(b.get_height()), (b.get_x() + b.get_width() / 2, b.get_height()),
                    xytext=(0, pad), textcoords="offset points", ha="center", va="bottom",
                    fontsize=8, color=INK)
