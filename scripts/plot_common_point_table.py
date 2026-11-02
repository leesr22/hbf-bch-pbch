#!/usr/bin/env python3
"""Render the W=64, 250 MHz common-point result as a publication table."""

from pathlib import Path
import csv

import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
from matplotlib.patches import Circle, FancyBboxPatch, Rectangle


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results" / "figures"

FONT_REGULAR = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
FONT_MEDIUM = "/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc"
FONT_BOLD = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"

REGULAR = FontProperties(fname=FONT_REGULAR)
MEDIUM = FontProperties(fname=FONT_MEDIUM)
BOLD = FontProperties(fname=FONT_BOLD)

BLUE = "#4C98F5"
GREEN = "#68C77D"
TEXT = "#343A40"
MUTED = "#747B82"
HEADER = "#E9EDF1"
ROW_ALT = "#F8FAFB"
LINE = "#E2E6EA"
GROUP_LINE = "#BCC5CE"
TABLE_EDGE = "#D7DDE2"
NAND2_AREA_UM2 = 0.504

HEADERS = [
    "Configuration",
    "Block",
    "Single-engine area",
    "Single-engine\nthroughput",
    "Engines required for\n3.072 TB/s",
    "Total replicated area",
    "Total NAND2\ngate equivalents",
]

ORDER = [(profile, kind) for profile in
         ("bch_d1", "pbch_d1", "bch_d2", "pbch_d2")
         for kind in ("enc", "dec")]


def load_rows():
    with (ROOT / "results" / "pipeline_common_w64_250mhz.csv").open() as handle:
        source = {(row["profile"], row["kind"]): row for row in csv.DictReader(handle)}
    labels = {
        "bch_d1": "BCH(k=4096, t=12)",
        "pbch_d1": "PBCH(k=4096, t=8, l=3)",
        "bch_d2": "BCH(k=4096, t=28)",
        "pbch_d2": "PBCH(k=4096, t=8, l=15)",
    }
    rows = []
    for key in ORDER:
        row = source[key]
        adjusted = key[0].startswith("pbch") and key[1] == "enc"
        throughput = f'{float(row["engine_gbps"]):.3f}{"*" if adjusted else ""} GB/s'
        total_area_mm2 = float(row["total_area_mm2"])
        nand2_ge_million = total_area_mm2 / NAND2_AREA_UM2
        rows.append((
            labels[key[0]], "Encoder" if key[1] == "enc" else "Decoder",
            f'{float(row["area_um2"]):,.1f} µm²', throughput,
            f'{int(row["engines_for_3072_gbps"]):,}', f'{total_area_mm2:.3f} mm²',
            f'{nand2_ge_million:.2f} M',
        ))
    return rows


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = load_rows()

    fig = plt.figure(figsize=(19.5, 9.3), facecolor="white")
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    fig.text(
        0.055,
        0.942,
        "Pipelined ECC Hardware Results at a Common Operating Point",
        color=TEXT,
        fontsize=24,
        fontproperties=BOLD,
        va="center",
    )
    fig.text(
        0.055,
        0.900,
        "W = 64  ·  250 MHz  ·  Target bandwidth: 3,072 GB/s  ·  UMC 28 nm pre-layout cell area",
        color=MUTED,
        fontsize=12.5,
        fontproperties=REGULAR,
        va="center",
    )

    left, right = 0.045, 0.955
    table_top, table_bottom = 0.855, 0.195
    header_h = 0.082
    row_h = (table_top - table_bottom - header_h) / len(rows)

    ax.add_patch(
        FancyBboxPatch(
            (left, table_bottom),
            right - left,
            table_top - table_bottom,
            boxstyle="round,pad=0.003,rounding_size=0.010",
            facecolor="white",
            edgecolor=TABLE_EDGE,
            linewidth=1.0,
        )
    )
    ax.add_patch(
        FancyBboxPatch(
            (left, table_top - header_h),
            right - left,
            header_h,
            boxstyle="round,pad=0.003,rounding_size=0.010",
            facecolor=HEADER,
            edgecolor="none",
        )
    )
    # Square the lower header corners while retaining the rounded table top.
    ax.add_patch(
        Rectangle(
            (left, table_top - header_h),
            right - left,
            0.025,
            facecolor=HEADER,
            edgecolor="none",
        )
    )

    widths = [0.225, 0.105, 0.140, 0.140, 0.130, 0.120, 0.140]
    edges = [left]
    for width in widths:
        edges.append(edges[-1] + (right - left) * width)

    for col, header in enumerate(HEADERS):
        x0, x1 = edges[col], edges[col + 1]
        align = "left" if col < 2 else "center"
        x = x0 + 0.018 if align == "left" else (x0 + x1) / 2
        ax.text(
            x,
            table_top - header_h / 2,
            header,
            ha=align,
            va="center",
            color=TEXT,
            fontsize=11.4,
            fontproperties=BOLD,
            linespacing=1.25,
        )

    body_top = table_top - header_h
    for row_idx, row in enumerate(rows):
        y_top = body_top - row_idx * row_h
        y_bottom = y_top - row_h
        y_mid = (y_top + y_bottom) / 2

        if (row_idx // 2) % 2 == 1:
            ax.add_patch(
                Rectangle(
                    (left, y_bottom),
                    right - left,
                    row_h,
                    facecolor=ROW_ALT,
                    edgecolor="none",
                )
            )

        # Keep the first column visually merged within each encoder/decoder pair.
        if row_idx % 2 == 1:
            group_mid = y_top
            ax.text(
                edges[0] + 0.018,
                group_mid,
                row[0],
                ha="left",
                va="center",
                color=TEXT,
                fontsize=13,
                fontproperties=MEDIUM,
            )

        block_color = BLUE if row[1] == "Encoder" else GREEN
        block_x = edges[1] + 0.031
        ax.add_patch(Circle((block_x, y_mid), 0.0052, facecolor=block_color, edgecolor="none"))
        ax.text(
            block_x + 0.013,
            y_mid,
            row[1],
            ha="left",
            va="center",
            color=TEXT,
            fontsize=12.5,
            fontproperties=REGULAR,
        )

        for col in range(2, len(row)):
            ax.text(
                edges[col + 1] - 0.017,
                y_mid,
                row[col],
                ha="right",
                va="center",
                color=TEXT,
                fontsize=11.9,
                fontproperties=REGULAR,
            )

        # Light line inside a pair, stronger line between configurations.
        if row_idx < len(rows) - 1:
            if row_idx % 2 == 0:
                ax.plot([edges[1], right], [y_bottom, y_bottom], color=LINE, linewidth=0.8)
            else:
                linewidth = 1.6 if row_idx == 3 else 1.0
                color = GROUP_LINE if row_idx == 3 else LINE
                ax.plot([left, right], [y_bottom, y_bottom], color=color, linewidth=linewidth)

    fig.text(
        0.055,
        0.145,
        "*: PBCH 인코더 throughput은 BER_defect로 인한 평균 defect 수"
        "(l=3: 0.4203개, l=15: 4.215개/codeword) 기준",
        color=MUTED,
        fontsize=10.8,
        fontproperties=REGULAR,
        va="center",
    )
    fig.text(
        0.055,
        0.105,
        "Throughput: steady-state codeword 입력 간격 기준",
        color=MUTED,
        fontsize=10.8,
        fontproperties=REGULAR,
        va="center",
    )
    fig.text(
        0.055,
        0.065,
        "Area: UMC 28 nm pre-layout cell area  ·  NAND2 GE: STP_ND2_0P5 = 0.504 µm²",
        color=MUTED,
        fontsize=10.8,
        fontproperties=REGULAR,
        va="center",
    )

    base = OUT / "pipeline_common_point_table_w64_250mhz"
    fig.savefig(base.with_suffix(".png"), dpi=220, bbox_inches="tight", pad_inches=0.10)
    fig.savefig(base.with_suffix(".svg"), bbox_inches="tight", pad_inches=0.10)
    fig.savefig(base.with_suffix(".pdf"), bbox_inches="tight", pad_inches=0.10)
    plt.close(fig)


if __name__ == "__main__":
    main()
