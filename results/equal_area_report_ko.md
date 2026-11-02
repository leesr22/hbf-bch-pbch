# Equal-area PBCH reliability sweep

## 결론

UMC 28 nm pre-layout cell area와 3.072 TB/s 복제 조건을 동일하게 적용하면,
구현 가능한 마지막 정수 `l`은 다음과 같다.

| Comparison | BCH area budget | Maximum PBCH | PBCH total area | Maximum BER_defect at UBER=1E-17 | Increase from original point |
|---|---:|---:|---:|---:|---:|
| BCH(k=4096,t=12), original PBCH point 1E-4 | 70.395 mm² | PBCH(k=4096,t=8,l=11) | 67.876 mm² | 7.378E-4 | 7.38x (+637.8%) |
| BCH(k=4096,t=28), original PBCH point 1E-3 | 219.065 mm² | PBCH(k=4096,t=8,l=55) | 217.862 mm² | 3.421E-3 | 3.42x (+242.1%) |

경계 바로 밖의 구성은 `l=12`에서 70.925 mm², `l=56`에서
240.901 mm²이다. 따라서 현재 RTL, 상수, 합성 flow에서는 각각 `l=11`과
`l=55`가 마지막 구현 가능점이다.

## 경계 합성 결과

| l | Solver | Encoder area | Encoder engines | Encoder replicated area | Decoder area | Decoder engines | Decoder replicated area | Combined area |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 11 | one-cycle Gaussian | 10,081.0 µm² | 2,043 | 20.595 mm² | 28,550.9 µm² | 1,656 | 47.280 mm² | 67.876 mm² |
| 12 | one-cycle Gaussian | 11,045.5 µm² | 2,074 | 22.908 mm² | 28,995.3 µm² | 1,656 | 48.016 mm² | 70.925 mm² |
| 55 | block-pipelined Gaussian | 40,230.3 µm² | 4,046 | 162.772 mm² | 33,267.0 µm² | 1,656 | 55.090 mm² | 217.862 mm² |
| 56 | block-pipelined Gaussian | 45,423.8 µm² | 4,079 | 185.284 mm² | 33,585.0 µm² | 1,656 | 55.617 mm² | 240.901 mm² |

모든 점은 W=64 bits, 250 MHz에서 timing을 통과했다. Encoder engine 수는
VCS로 확인한 steady-state II와 해당 `l`의 BER 한계에서 예상되는 평균 probe
constraint 수를 사용했다. Decoder II는 69 cycles로 동일하다.

## Exhaustive/Gaussian 전환

면적만 비교하면 Gaussian solver가 이미 `l=3`에서 더 작다.

| l | Exhaustive encoder | Gaussian encoder | Gaussian reduction |
|---:|---:|---:|---:|
| 3 | 7,385.3 µm² | 6,759.1 µm² | 8.48% |
| 4 | 8,594.5 µm² | 7,077.0 µm² | 17.66% |

따라서 `l>=3` 구간에는 별도의 면적 crossover가 없다. 다만 `l=3` exhaustive는
8개 후보를 모두 평가해 최적 마스킹을 보장하고 총 복제 면적 premium이 작으므로
그대로 유지하고, `l>=4`부터 Gaussian으로 전환하는 구성이 합리적이다. 큰 `l`은
한 사이클 Gaussian 경로를 계속 늘리지 않고 stage당 두 pivot을 처리하는 pipeline을
사용했다.

## Solver quality check

workbook의 평균 physical defect 수 `2np`와 실제 생성된 influence columns를 사용해
경계점별 10,000회 Monte Carlo를 수행했다.

| l | Mean physical defects | Trials with residual | Mean residual bits | Extra check |
|---:|---:|---:|---:|---|
| 11 | 6.214 | 5.87% | 0.0673 | exhaustive optimum 0.0605; Gaussian optimum match 99.41% |
| 55 | 29.115 | 0.59% | 0.0059 | all observed residual cases were one bit |

Residual은 BCH(t=8)가 처리한다. 이 Monte Carlo는 solver 동작의 sanity check이며,
10^-17 UBER 자체를 직접 관측한 실험은 아니다.

## Interpretation limits

- BER 한계는 `UBER_BCH_vs_PBCH (1).xlsx`의 `Ideal_UBER` 열을 UBER=1E-17에서
  log-log 보간한 ideal-probing projection이다.
- Reliability model의 physical defects/codeword는 `2np`, 기존 hardware throughput
  표의 평균 probe constraints는 `np`를 사용한다.
- 면적은 UMC 28 nm pre-layout standard-cell area이며 배선, CTS, power grid와
  physical-design margin은 포함하지 않는다.
- 인접 `l`의 합성 면적은 primitive polynomial과 synthesis heuristic 때문에 완전히
  단조롭지 않다. 보고한 최대점은 현재 생성 상수와 compile flow에서 직접 합성한 결과다.
