# HBF K=4096 BCH/PBCH 파이프라인 하드웨어 평가

## 결론

네 codec을 모두 `W=64`, 250 MHz로 통일하고 codeword 간 pipeline/interleaving을
적용했다. 처리율은 단일 codeword latency가 아니라 VCS에서 연속 5개 codeword로
측정한 steady-state initiation interval(II)을 사용했다.

- D1의 3,072 GB/s 정규화 `encoder+decoder` 면적은 BCH 70.395 mm², PBCH
  58.281 mm²로 PBCH가 **17.2% 작다**.
- D2는 BCH 219.065 mm², PBCH 72.619 mm²로 PBCH가 **66.9% 작다**.
- PBCH encoder 자체는 BCH보다 D1 186.0%, D2 154.5% 큰 총 복제 면적을 요구한다.
  반면 항상 `t=8`인 PBCH decoder가 각각 30.9%, 76.9% 작아 전체 합계를 상쇄한다.
- BCH-D2 decoder는 BM 한 대일 때보다 두 대를 round-robin interleaving하는 편이
  단일 코어는 커지지만 3,072 GB/s 복제 총면적은 254.165→209.562 mm²로
  **17.5% 감소**한다.

이 수치는 동일 reliability 평가점이라는 ideal-probing 결과를 입력 조건으로 채택한
hardware-overhead 비교다. RTL 합성이 UBER 동등성을 다시 증명하는 것은 아니다.

## 공통 평가 조건

| 항목 | 값 |
|---|---|
| 사용자 dataword | 4,096 bits (512 B) |
| stream width | `W=64` bits |
| clock | 250 MHz (4.0 ns) |
| 공정/library | UMC 28 nm 35HSL SVT, SS/0.9 V/125 °C |
| 합성 | Design Compiler `compile_ultra -no_autoungroup` |
| target user bandwidth | 3,072 GB/s |
| NAND2 기준 | 0.504 µm² |

| 구성 | random `t` | selector `l` | BCH parity | codeword |
|---|---:|---:|---:|---:|
| BCH-D1 | 12 | 0 | 156 | 4,252 |
| PBCH-D1 | 8 | 3 | 104 | 4,203 |
| BCH-D2 | 28 | 0 | 364 | 4,460 |
| PBCH-D2 | 8 | 15 | 104 | 4,215 |

## 파이프라인 구조

- BCH encoder는 마지막 parity beat와 다음 `start`를 같은 cycle에 받아 codeword
  경계의 bubble을 없앴다.
- PBCH encoder는 `PREP(base BCH + probe + solve)`와
  `EMIT(mask + final BCH)`에 동일한 `t=8` BCH core를 하나씩 두고 서로 다른
  codeword를 겹쳐 처리한다.
- Decoder는 syndrome, BM, Chien/replay를 codeword-level pipeline으로 겹친다.
  전체 codeword는 내부 FF에 저장하지 않고 외부 replay buffer에서 다시 받는다.
- BCH-D2만 BM 한 대의 latency가 scan stage보다 길어서 동일 BM core 두 대를
  round-robin interleaving한다. D1/PBCH는 한 대만 사용한다.
- zero syndrome도 BM 경로로 보내므로 maximum-error, zero-error, 두 패턴이 섞인
  workload 모두 BCH-D2에서 같은 II=72와 in-order 출력을 유지한다.

## 최종 PPA

| 구성 | Block | 단일 면적 (µm²) | Slack (ns) | Latency | II | GB/s/engine | 엔진 수 | 총면적 (mm²) |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| BCH-D1 | Encoder | 2,754.0 | +2.379 | 68 | 67.000 | 1.910 | 1,608 | 4.428 |
| BCH-D1 | Decoder | 39,834.6 | +1.313 | 190 | 69.000 | 1.855 | 1,656 | 65.966 |
| PBCH-D1 | Encoder | 7,385.3 | +0.0004 | 153 | 71.420* | 1.792 | 1,715 | 12.666 |
| PBCH-D1 | Decoder | 27,545.3 | +1.342 | 174 | 69.000 | 1.855 | 1,656 | 45.615 |
| BCH-D2 | Encoder | 5,656.4 | +1.997 | 71 | 70.000 | 1.829 | 1,680 | 9.503 |
| BCH-D2 | Decoder | 121,274.3 | +0.940 | 260 | 72.000 | 1.778 | 1,728 | 209.562 |
| PBCH-D2 | Encoder | 11,163.8 | +0.0005 | 188 | 90.215* | 1.419 | 2,166 | 24.181 |
| PBCH-D2 | Decoder | 29,250.1 | +1.365 | 174 | 69.000 | 1.855 | 1,656 | 48.438 |

`*` PBCH encoder multi-frame test는 solver stress를 위해 D1 12개, D2 32개의 defect를
넣었다. 목표 defect RBER에서 평균 defect 수는 각각 0.4203개와 4.215개이므로,
제약 하나당 1 cycle인 구조를 이용해 measured II 83/118을 71.420/90.215로 보정했다.

### Reliability-matched 합계

| 평가점 | Block | BCH (mm²) | PBCH (mm²) | PBCH 변화 | redundancy 감소 |
|---|---|---:|---:|---:|---:|
| D1 | Encoder | 4.428 | 12.666 | +186.0% | 31.4% |
| D1 | Decoder | 65.966 | 45.615 | -30.9% | 31.4% |
| D1 | Encoder+Decoder | 70.395 | 58.281 | **-17.2%** | 31.4% |
| D2 | Encoder | 9.503 | 24.181 | +154.5% | 67.3% |
| D2 | Decoder | 209.562 | 48.438 | -76.9% | 67.3% |
| D2 | Encoder+Decoder | 219.065 | 72.619 | **-66.9%** | 67.3% |

### BCH-D2 BM resource balancing

| 구조 | 단일 면적 (µm²) | II | GB/s/engine | 엔진 수 | 총면적 (mm²) |
|---|---:|---:|---:|---:|---:|
| BM 1대 | 92,088.9 | 115 | 1.113 | 2,760 | 254.165 |
| BM 2대 interleaving | 121,274.3 | 72 | 1.778 | 1,728 | 209.562 |

## 검증

- Python reference/model regression: `5 passed`.
- VCS maximum-error 연속 5프레임: 4 profile 모두 PASS.
- 기존 단일-codeword VCS testbench: 4 profile 모두 PASS.
- 실제 주입 오류 수: BCH-D1 12, BCH-D2 28, PBCH-D1/D2 8.
- BCH-D2 추가 검증: maximum-error, zero-error, maximum/zero 교차 workload가 모두
  latency 260, II 72, in-order correction으로 PASS.
- UMC 28 nm 합성: 8개 공통점 모두 250 MHz PASS, slack 양수.
- `check_design.rpt`: unresolved reference, multiple driver, latch, black box, error 없음.

## 해석 시 주의점

1. 총면적은 standalone codec core를 3,072 GB/s까지 단순 복제한 pre-layout cell-area
   지표다. buffer, interconnect, clock tree, CTS, placement/routing와 power는 포함하지 않는다.
2. Decoder pipeline은 새 scan과 이전 codeword replay를 동시에 제공할 수 있는 외부
   banked buffer/arbitration을 가정한다. PBCH encoder도 PREP data/probe stream과 EMIT
   replay stream을 겹쳐 공급받는다. 해당 integration 면적은 포함하지 않았다.
3. PBCH-D1/D2 encoder의 250 MHz slack이 각각 약 0.4 ps, 0.5 ps로 매우 작다.
   합성상 PASS이지만 P&R margin까지 주장하려면 clock을 낮추거나 constraint/RTL을
   추가 최적화해야 한다.
4. `l=15` online solver는 inconsistent constraint를 버리는 order-dependent heuristic이며
   global minimum-unmasked-defect를 보장하지 않는다.
5. pre-read sensing의 false positive/negative와 non-ideal probing은 이 hardware-overhead
   평가 범위 밖이며 별도 reliability model로 연결해야 한다.

## 재현

```bash
python3 scripts/gen_rtl.py
pytest -q
sim/run_pipeline.sh bch_d1 64
sim/run_pipeline.sh bch_d2 64 zero
sim/run_pipeline.sh bch_d2 64 mixed
sim/run_pipeline.sh pbch_d1 64
sim/run_pipeline.sh pbch_d2 64
python3 scripts/collect_synthesis.py
python3 scripts/collect_pipeline_cycles.py
python3 scripts/analyze_pipeline_results.py
python3 scripts/plot_common_point_table.py
python3 scripts/plot_replicated_area.py
```

Machine-readable 결과는 `pipeline_common_w64_250mhz.csv`,
`pipeline_comparison.csv`, `pipeline_bch_d2_bm_comparison.csv`에 있고, 발표용 그림은
`results/figures/pipeline_common_point_table_w64_250mhz.*`와
`results/figures/pipeline_replicated_area_w64_250mhz.*`에 있다.
