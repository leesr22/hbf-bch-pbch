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
- PBCH probing of the complete first-pass codeword, including selector and parity
  cells; exact 8-candidate selection for `l=3`; and compact incremental GF(2)
  elimination for `l=15`.
- Generated wrappers for `W={32,64,128,256,512}`, deterministic reference vectors,
  self-checking VCS testbenches, and UMC 28-nm Design Compiler scripts.

The compact `l=15` solver preserves every consistent constraint it accepts, but is
not a global minimum-unmasked-defect optimizer after the constraint set becomes
inconsistent. This limitation is measured in `results/solver_quality.csv` and is
spelled out in `docs/architecture_ko.md`.

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

Finally rebuild the machine-readable and Markdown summaries:

```bash
python3 scripts/collect_synthesis.py
python3 scripts/collect_cycles.py
python3 scripts/analyze_results.py
```

The synthesis license server is reachable from the normal lab shell. In a restricted
container the same command can report an apparent license failure even though the
tool and license are healthy.

See `docs/architecture_ko.md` for the hardware/dataflow explanation and
`results/final_report_ko.md` for the evaluated configuration, verification evidence,
and UMC 28-nm results.
