# HBF BCH/PBCH K=4096 Hardware Evaluation

Clean-room, parameterized SystemVerilog and a reproducible evaluation flow for four
reliability-matched codec points:

| Profile | User bits | Random-error strength | Select bits | Code bits |
|---|---:|---:|---:|---:|
| BCH-D1 | 4096 | 12 | 0 | 4252 |
| BCH-D2 | 4096 | 28 | 0 | 4460 |
| PBCH-D1 | 4096 | 8 | 3 | 4203 |
| PBCH-D2 | 4096 | 8 | 15 | 4215 |

All codes are shortened primitive binary BCH codes over `GF(2^13)`.  PBCH uses a
selector-first pre-candidate `[d | message XOR dM]`, followed by the parent `t=8`
BCH encoder.  The coordinate order is chosen so that a decoder learns `d` before
streaming the recovered message; it does not alter the code construction.

This directory is intentionally independent of the older BCH/PBCH repositories.
Those repositories are used only to identify the installed simulator, synthesis
library, and reporting conventions.

## What is implemented

- Systematic shortened binary-BCH encoder and decoder over `GF(2^13)`.
- Streaming syndrome, two-phase inversionless Berlekamp-Massey, and parallel Chien
  search. The decoder replays its codeword from an external buffer instead of keeping
  roughly 4 Kbits in flip-flops.
- Inter-frame pipelines: BCH encoding has a zero-bubble codeword boundary, PBCH
  overlaps prepare/probe/solve with final emission, and every decoder overlaps
  syndrome, BM, and replay/Chien work from different codewords. BCH-D2 interleaves
  two unchanged BM cores because one `t=28` core is slower than the scan stage.
- PBCH probing of the complete first-pass codeword, including selector and parity
  cells; exact 8-candidate selection for `l=3`; and compact incremental GF(2)
  elimination for `l=15`.
- Generated wrappers for `W={32,64,128,256,512}`, deterministic reference vectors,
  self-checking VCS testbenches, and UMC 28-nm Design Compiler scripts.

The compact `l=15` solver preserves every consistent constraint it accepts, but is
not a global minimum-unmasked-defect optimizer after the constraint set becomes
inconsistent. This limitation is measured in `results/solver_quality.csv` and is
spelled out in `docs/architecture_ko.md`.

## Current pipelined result

The common comparison point is `W=64`, 250 MHz, normalized to 3,072 GB/s using
the verified steady-state codeword initiation interval:

| Defect RBER point | BCH encoder+decoder | PBCH encoder+decoder | PBCH change |
|---|---:|---:|---:|
| `1E-4` | 70.395 mm² | 58.281 mm² | -17.2% |
| `1E-3` | 219.065 mm² | 72.619 mm² | -66.9% |

The detailed pipeline report is in `results/pipeline_final_report_ko.md`.  The
tracked presentation artifacts are
`results/figures/pipeline_common_point_table_w64_250mhz.*` and
`results/figures/pipeline_replicated_area_w64_250mhz.*`.  The optional equal-area
PBCH sweep and its interpretation are in `results/equal_area_report_ko.md`.

## Directory map

| Path | Purpose |
|---|---|
| `model/ecc.py` | Executable BCH/PBCH reference model |
| `rtl/bch/` | Shared BCH encoder/decoder blocks |
| `rtl/pbch/` | PBCH probe, solver, mask, and top levels |
| `rtl/generated/` | Profile/width wrappers and compile-time linear transforms |
| `tb/` | Self-checking streaming testbenches |
| `vectors/` | Deterministic test vectors generated from the model |
| `sim/` | VCS launch scripts |
| `syn/` | Design Compiler flow and reports |
| `results/` | Collected cycles, PPA, normalized area, and final report |

## Reproduce

Regenerate wrappers and vectors, then run the software checks:

```bash
python3 scripts/gen_rtl.py
pytest -q
```

Run one VCS profile or the complete 20-point profile/width regression:

```bash
export VCS_CMD=/authorized/path/to/vcs  # optional when vcs is already in PATH
sim/run_profile.sh pbch_d2 128
sim/run_all.sh
```

Measure latency and steady-state initiation interval with five consecutive frames:

```bash
sim/run_pipeline.sh bch_d1 64
sim/run_pipeline.sh pbch_d2 64
sim/run_pipeline.sh bch_d2 64 zero
sim/run_pipeline.sh bch_d2 64 mixed
python3 scripts/collect_pipeline_cycles.py
```

Run one UMC 28-nm synthesis point or a width matrix at 250 MHz:

```bash
export HBF_ECC_TARGET_LIBRARY=/authorized/path/to/target_library.db
export DC_CMD=/authorized/path/to/dc_shell-xg-t
syn/run.sh pbch_d2 enc 128 250
syn/run_matrix.sh dec 250 32 64 128
```

Raw Design Compiler reports and mapped netlists are intentionally ignored because
they can expose licensed-library metadata and lab filesystem paths. Aggregate PPA
results used by the report remain under `results/`.

Finally rebuild the machine-readable and Markdown summaries.  The pipeline report
uses the common `W=64`, 250-MHz point for all eight encoder/decoder blocks:

```bash
python3 scripts/collect_synthesis.py
python3 scripts/collect_pipeline_cycles.py
python3 scripts/analyze_pipeline_results.py
python3 scripts/plot_common_point_table.py
python3 scripts/plot_replicated_area.py
```

The synthesis license server is reachable from the normal lab shell. In a restricted
container the same command can report an apparent license failure even though the
tool and license are healthy.

See `docs/architecture_ko.md` for the hardware/dataflow explanation and
`results/pipeline_final_report_ko.md` for the common-point pipeline configuration,
verification evidence, and UMC 28-nm results.
