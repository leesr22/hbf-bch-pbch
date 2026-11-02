#!/usr/bin/env python3
"""Plot the common-point BCH/PBCH replication-equivalent area result."""

from pathlib import Path
import csv

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.font_manager import FontProperties
from matplotlib.lines import Line2D
from matplotlib.path import Path as MplPath
from matplotlib.patches import PathPatch, Rectangle


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results" / "figures"

FONT_REGULAR = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
FONT_MEDIUM = "/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc"
FONT_BOLD = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
REGULAR = FontProperties(fname=FONT_REGULAR)
MEDIUM = FontProperties(fname=FONT_MEDIUM)
BOLD = FontProperties(fname=FONT_BOLD)

# W=64, 250 MHz. Areas are the replicated cell areas required to reach
# 3,072 GB/s. PBCH encoder latency uses the mean defect count at the target
# defect RBER (D1: 0.4203, D2: 4.215 defects/codeword).
LABELS = [
    "BCH(k=4096,\nt=12)",
    "PBCH(k=4096,\nt=8, l=3)",
    "BCH(k=4096,\nt=28)",
    "PBCH(k=4096,\nt=8, l=15)",
]
BLUE = "#4C98F5"
GREEN = "#68C77D"
TEXT = "#4F555B"
MUTED = "#747B82"
GRID = "#E7EBEF"


def rounded_top_bar(ax, x, bottom, height, width, color, rx=0.075, ry=12.0):
    """Add a rectangle with only its two top corners rounded."""
    x0, x1 = x - width / 2, x + width / 2
    y0, y1 = bottom, bottom + height
    rx = min(rx, width / 2)
    ry = min(ry, height / 2)
    k = 0.5522847498
    verts = [
        (x0, y0),
        (x0, y1 - ry),
        (x0, y1 - ry + k * ry),
        (x0 + rx - k * rx, y1),
        (x0 + rx, y1),
        (x1 - rx, y1),
        (x1 - rx + k * rx, y1),
        (x1, y1 - ry + k * ry),
        (x1, y1 - ry),
        (x1, y0),
        (x0, y0),
    ]
    codes = [
        MplPath.MOVETO,
        MplPath.LINETO,
        MplPath.CURVE4,
        MplPath.CURVE4,
        MplPath.CURVE4,
        MplPath.LINETO,
        MplPath.CURVE4,
        MplPath.CURVE4,
        MplPath.CURVE4,
        MplPath.LINETO,
        MplPath.CLOSEPOLY,
    ]
    ax.add_patch(PathPatch(MplPath(verts, codes), facecolor=color, edgecolor="none"))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with (ROOT / "results" / "pipeline_common_w64_250mhz.csv").open() as handle:
        source = {(row["profile"], row["kind"]): float(row["total_area_mm2"])
                  for row in csv.DictReader(handle)}
    profiles = ("bch_d1", "pbch_d1", "bch_d2", "pbch_d2")
    encoder = np.array([source[(profile, "enc")] for profile in profiles])
    decoder = np.array([source[(profile, "dec")] for profile in profiles])

    x = np.array([0.0, 1.0, 2.35, 3.35])
    width = 0.66
    total = encoder + decoder

    plt.rcParams.update({
        "font.size": 12,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "savefig.facecolor": "white",
    })

    fig, ax = plt.subplots(figsize=(12.2, 7.0))
    fig.subplots_adjust(left=0.105, right=0.975, top=0.82, bottom=0.23)

    for xpos, enc, dec in zip(x, encoder, decoder):
        ax.add_patch(
            Rectangle(
                (xpos - width / 2, 0),
                width,
                enc,
                facecolor=BLUE,
                edgecolor="none",
                zorder=3,
            )
        )
        rounded_top_bar(ax, xpos, enc, dec, width, GREEN)

    ax.set_xlim(-0.62, 3.97)
    # Keep the same vertical scale as the equal-area boundary figure so the
    # two plots can be compared directly in a presentation.
    ymax = 280.0
    ax.set_ylim(0, ymax)
    ax.set_xticks(x)
    ax.set_xticklabels(LABELS, color=TEXT, linespacing=1.35, fontproperties=REGULAR)
    ax.tick_params(axis="x", length=0, pad=12)

    step = 25 if ymax <= 150 else 50 if ymax <= 300 else 100
    yticks = list(range(0, int(ymax)+1, step))
    ax.set_yticks(yticks)
    ax.set_yticklabels([f"{value} mm²" for value in yticks], color=MUTED,
                       fontproperties=REGULAR)
    ax.tick_params(axis="y", length=0, pad=10)
    ax.yaxis.grid(True, color=GRID, linewidth=1.0, linestyle=(0, (2.5, 3.5)))
    ax.set_axisbelow(True)
    for spine in ax.spines.values():
        spine.set_visible(False)

    for xpos, value in zip(x, total):
        ax.text(
            xpos,
            value + 15,
            f"{value:.1f} mm²",
            ha="center",
            va="bottom",
            color=TEXT,
            fontsize=11.5,
            fontproperties=MEDIUM,
        )

    fig.text(
        0.105,
        0.925,
        "Total Replicated ECC Area at a Common Operating Point",
        ha="left",
        va="center",
        fontsize=20,
        fontproperties=BOLD,
        color=TEXT,
    )
    fig.text(
        0.105,
        0.88,
        "W = 64  ·  250 MHz  ·  Steady-state codeword input interval  ·  Target bandwidth: 3,072 GB/s  ·  UMC 28 nm",
        ha="left",
        va="center",
        fontsize=11.5,
        fontproperties=REGULAR,
        color=MUTED,
    )

    legend_handles = [
        Line2D([0], [0], marker="o", linestyle="", markersize=9,
               markerfacecolor=BLUE, markeredgecolor="none", label="Encoder"),
        Line2D([0], [0], marker="o", linestyle="", markersize=9,
               markerfacecolor=GREEN, markeredgecolor="none", label="Decoder"),
    ]
    legend = fig.legend(
        handles=legend_handles,
        loc="lower center",
        bbox_to_anchor=(0.54, 0.055),
        ncol=2,
        frameon=False,
        handlelength=0.8,
        handletextpad=0.45,
        columnspacing=2.2,
        prop=REGULAR,
    )
    for text in legend.get_texts():
        text.set_color(TEXT)

    base = OUT / "pipeline_replicated_area_w64_250mhz"
    fig.savefig(base.with_suffix(".png"), dpi=240, bbox_inches="tight")
    fig.savefig(base.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(base.with_suffix(".pdf"), bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    main()
