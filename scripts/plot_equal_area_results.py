#!/usr/bin/env python3
"""Create professor-ready equal-area boundary figure and table."""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.lines import Line2D

from plot_replicated_area import (
    BLUE,
    BOLD,
    GREEN,
    GRID,
    MEDIUM,
    MUTED,
    REGULAR,
    TEXT,
    rounded_top_bar,
)


ROOT = Path(__file__).resolve().parents[1]
FIGURES = ROOT / "results" / "figures"
BASELINES = {
    "D1": {"budget": 70.394646420432, "p": 1e-4},
    "D2": {"budget": 219.064773723984, "p": 1e-3},
}


def read_rows() -> dict[int, dict[str, str]]:
    with (ROOT / "results" / "equal_area_measured.csv").open() as stream:
        return {int(row["l"]): row for row in csv.DictReader(stream)}


def fmt_ber(value: float) -> str:
    exponent = 0
    mantissa = value
    while mantissa < 1:
        mantissa *= 10
        exponent -= 1
    return f"{mantissa:.3f}E{exponent:+d}"


def plot_chart(rows: dict[int, dict[str, str]]) -> None:
    plt.rcParams.update({
        "font.size": 12,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "savefig.facecolor": "white",
    })
    lengths = (11, 12, 55, 56)
    encoder = np.array([
        float(rows[length]["encoder_total_mm2"]) for length in lengths])
    decoder = np.array([
        float(rows[length]["decoder_total_mm2"]) for length in lengths])
    total = encoder + decoder
    labels = [
        "PBCH(k=4096,\nt=8, l=11)\nLast within budget",
        "PBCH(k=4096,\nt=8, l=12)\nNext configuration",
        "PBCH(k=4096,\nt=8, l=55)\nLast within budget",
        "PBCH(k=4096,\nt=8, l=56)\nNext configuration",
    ]
    x = np.array([0.0, 1.0, 2.35, 3.35])
    width = 0.66
    budget_color = "#D86161"

    fig, ax = plt.subplots(figsize=(12.2, 7.0))
    fig.subplots_adjust(left=0.105, right=0.975, top=0.82, bottom=0.27)

    for xpos, enc, dec in zip(x, encoder, decoder):
        ax.bar(xpos, enc, width=width, color=BLUE, edgecolor="none", zorder=3)
        rounded_top_bar(ax, xpos, enc, dec, width, GREEN)

    group_lines = [
        (-0.42, 1.42, BASELINES["D1"]["budget"],
         "BCH(t=12) budget · 70.4 mm²"),
        (1.93, 3.77, BASELINES["D2"]["budget"],
         "BCH(t=28) budget · 219.1 mm²"),
    ]
    for xmin, xmax, budget, label in group_lines:
        ax.hlines(budget, xmin, xmax, color=budget_color, linewidth=1.8,
                  linestyle=(0, (5, 3)), zorder=4)
        ax.text((xmin + xmax) / 2, budget + 4.5, label,
                ha="center", va="bottom", color=budget_color,
                fontsize=10, fontproperties=REGULAR)

    ax.set_xlim(-0.62, 3.97)
    # Match the common-operating-point figure for direct visual comparison.
    ymax = 280.0
    ax.set_ylim(0, ymax)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, color=TEXT, linespacing=1.25,
                       fontproperties=REGULAR)
    ax.tick_params(axis="x", length=0, pad=12)

    yticks = list(range(0, int(ymax) + 1, 50))
    ax.set_yticks(yticks)
    ax.set_yticklabels([f"{value} mm²" for value in yticks], color=MUTED,
                       fontproperties=REGULAR)
    ax.tick_params(axis="y", length=0, pad=10)
    ax.yaxis.grid(True, color=GRID, linewidth=1.0, linestyle=(0, (2.5, 3.5)))
    ax.set_axisbelow(True)
    for spine in ax.spines.values():
        spine.set_visible(False)

    for xpos, value in zip(x, total):
        ax.text(xpos, value + 17, f"{value:.1f} mm²",
                ha="center", va="bottom", color=TEXT, fontsize=11.5,
                fontproperties=MEDIUM)

    fig.text(0.105, 0.925, "Equal-Area PBCH Reliability Boundary",
             ha="left", va="center", fontsize=20,
             fontproperties=BOLD, color=TEXT)
    fig.text(
        0.105, 0.88,
        "W = 64  ·  250 MHz  ·  Target bandwidth: 3,072 GB/s  ·  UMC 28 nm  ·  UBER target: 1E−17",
        ha="left", va="center", fontsize=11.5,
        fontproperties=REGULAR, color=MUTED)

    legend_handles = [
        Line2D([0], [0], marker="o", linestyle="", markersize=9,
               markerfacecolor=BLUE, markeredgecolor="none", label="Encoder"),
        Line2D([0], [0], marker="o", linestyle="", markersize=9,
               markerfacecolor=GREEN, markeredgecolor="none", label="Decoder"),
        Line2D([0], [0], color=budget_color, linewidth=1.8,
               linestyle=(0, (5, 3)), label="BCH area budget"),
    ]
    legend = fig.legend(
        handles=legend_handles, loc="lower center", bbox_to_anchor=(0.54, 0.045),
        ncol=3, frameon=False, handlelength=1.2, handletextpad=0.45,
        columnspacing=2.2, prop=REGULAR)
    for text in legend.get_texts():
        text.set_color(TEXT)

    FIGURES.mkdir(parents=True, exist_ok=True)
    base = FIGURES / "equal_area_boundary"
    fig.savefig(base.with_suffix(".png"), dpi=240, bbox_inches="tight")
    fig.savefig(base.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(base.with_suffix(".pdf"), bbox_inches="tight")
    plt.close(fig)


def plot_table(rows: dict[int, dict[str, str]]) -> None:
    selected = (("D1 limit", 11), ("D1 next", 12),
                ("D2 limit", 55), ("D2 next", 56))
    cell_rows = []
    for label, length in selected:
        row = rows[length]
        case = label[:2]
        baseline = BASELINES[case]
        ber = float(row["max_ber_defect"])
        ratio = ber / baseline["p"]
        total = float(row["combined_total_mm2"])
        cell_rows.append([
            label,
            f"PBCH(k=4096, t=8, l={length})",
            "One-cycle Gaussian" if length <= 12 else "Pipelined Gaussian",
            fmt_ber(ber),
            f"{ratio:.2f}× ({(ratio-1)*100:+.1f}%)",
            f"{float(row['encoder_total_mm2']):.2f}",
            f"{float(row['decoder_total_mm2']):.2f}",
            f"{total:.2f}",
            f"{baseline['budget']-total:+.2f}",
        ])
    columns = [
        "Case", "Configuration", "Solver", "Max BER_defect",
        "Reliability gain", "Encoder\n(mm²)", "Decoder\n(mm²)",
        "Total\n(mm²)", "Area margin\n(mm²)",
    ]
    fig, axis = plt.subplots(figsize=(17.2, 4.1))
    axis.axis("off")
    table = axis.table(cellText=cell_rows, colLabels=columns, cellLoc="center",
                       colLoc="center", loc="center",
                       colWidths=[0.075, 0.19, 0.15, 0.105, 0.13,
                                  0.09, 0.09, 0.08, 0.09])
    table.auto_set_font_size(False)
    table.set_fontsize(10.5)
    table.scale(1, 2.25)
    for (row_index, column_index), cell in table.get_celld().items():
        cell.set_edgecolor("#D9DEE7")
        cell.set_linewidth(0.7)
        if row_index == 0:
            cell.set_facecolor("#E9EDF3")
            cell.set_text_props(weight="bold", color="#202632")
        else:
            cell.set_facecolor("#F8FAFC" if row_index % 2 else "#FFFFFF")
            if column_index == 0:
                cell.set_text_props(weight="bold")
            if column_index == 8:
                value = float(cell_rows[row_index - 1][8])
                cell.set_text_props(color="#21864A" if value >= 0 else "#C33D3D",
                                    weight="bold")
    fig.suptitle("Equal-Area PBCH Reliability Sweep",
                 fontsize=16, fontweight="bold", y=0.97)
    fig.text(0.5, 0.065,
             "Area: UMC 28 nm pre-layout cell area · Target throughput: 3.072 TB/s · UBER target: 1E−17",
             ha="center", color="#5E6878", fontsize=10.5)
    FIGURES.mkdir(parents=True, exist_ok=True)
    fig.savefig(FIGURES / "equal_area_table.png", dpi=220,
                bbox_inches="tight", facecolor="white")
    plt.close(fig)


def main() -> None:
    rows = read_rows()
    plot_chart(rows)
    plot_table(rows)
    print(FIGURES / "equal_area_boundary.png")
    print(FIGURES / "equal_area_table.png")


if __name__ == "__main__":
    main()
