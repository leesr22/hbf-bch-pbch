# HBF용 K=4096 BCH/PBCH 하드웨어 평가 보고서

## 결론

요청한 네 구성을 새 RTL로 구현하고, Python reference model, VCS, UMC 28 nm Design
Compiler 합성으로 검증했다. Reliability-matched point라는 전제에서 얻은 핵심 결과는
다음과 같다.

- 같은 `W=64`, 250 MHz의 **단일 engine cell area**를 비교하면 PBCH encoder는
  D1에서 85.4%, D2에서 52.5% 크지만, PBCH decoder는 각각 30.9%, 68.2% 작다.
- 각 설계에 가장 유리한 `W`와 통과 주파수를 고르고 3,072 GB/s로 단순 복제하면,
  PBCH encoder는 두 pass 때문에 D1 10.12배, D2 7.83배의 면적이 필요하다.
- 반대로 PBCH decoder는 항상 `t=8`만 수행하므로 BCH decoder보다 D1 36.0%,
  D2 81.7% 작다.
- encoder와 decoder의 정규화 면적을 단순 합산하면 PBCH가 D1에서 23.6%, D2에서
  75.0% 작다. 다만 이는 실제 floorplan이 아니라 standalone engine 복제 지표이다.
- 저장 redundancy는 D1에서 156→107 bits로 31.4%, D2에서 364→119 bits로
  67.3% 감소한다.

즉 논문에서 가장 방어하기 좋은 표현은 “PBCH encoder 자체는 공짜가 아니며 두-pass
throughput 비용이 크지만, 동일 reliability를 위해 BCH의 `t`를 크게 올리는 경우
decoder와 저장 redundancy에서 얻는 이득이 전체 codec logic을 상쇄한다”이다.

## 평가 구성

| 이름 | 사용자 k | random t | selector l | BCH parity | 총 redundancy | codeword n | code rate |
|---|---:|---:|---:|---:|---:|---:|---:|
| BCH-D1 | 4096 | 12 | 0 | 156 | 156 | 4252 | 0.9633 |
| PBCH-D1 | 4096 | 8 | 3 | 104 | 107 | 4203 | 0.9745 |
| BCH-D2 | 4096 | 28 | 0 | 364 | 364 | 4460 | 0.9184 |
| PBCH-D2 | 4096 | 8 | 15 | 104 | 119 | 4215 | 0.9718 |

모두 `GF(2^13)`과 primitive polynomial `x^13+x^4+x^3+x+1`을 사용한다. BCH
parity 길이는 단순히 `13t`로 놓은 것이 아니라 cyclotomic coset으로 생성한 실제
generator polynomial 차수 104, 156, 364를 사용했다.

이 보고서의 D1/D2가 같은 reliability라는 판단은 제공된 ideal-probing 계산 결과를
평가점으로 채택한 것이다. RTL 합성 자체가 UBER 동등성을 다시 입증하는 것은 아니다.

## 구현 구조

### BCH

- `bch_enc`: systematic polynomial-division encoder
- `bch_syndrome`: odd syndrome만 직접 저장하고 even syndrome은 GF square로 복원
- `bch_bm`: two-phase inversionless Berlekamp-Massey
- `bch_chien`: W개 위치를 병렬 평가하면서 replay codeword를 정정
- `bch_dec`: syndrome→BM→external replay/Chien 순서 제어

### PBCH 추가 블록

- `pbch_probe`: `c(0)`와 pre-read bitmap을 함께 받아 defect 위치만 제약식으로 변환
- `pbch_g0`: 위치별 selector 영향 `h_i` 생성
- `pbch_solve`: `l=3`은 8개 후보 exact scoring, `l=15`는 15개 pivot row의 online
  GF(2) elimination
- `pbch_mask`: 선택된 `d`에 대해 `dM`을 streaming 생성
- `pbch_enc`: 첫 pass `c(0)` probing과 둘째 pass 최종 BCH encoding 제어
- `pbch_dec`: `t=8` BCH correction 뒤 corrected selector로 `dM` 제거

PBCH information coordinate는 `[d | m XOR dM]`로 배치했다. 이는 초안의 좌표를
permutation한 동등한 construction이며, decoder가 selector를 먼저 알아 4096-bit
message buffer 없이 data를 streaming 복원하게 한다.

어느 codec도 전체 codeword를 내부 FF에 저장하지 않는다. Decoder는 `replay_req`로
codec 외부 buffer에 같은 codeword를 다시 요청하고, PBCH encoder도 selector 결정 후
4096-bit 사용자 data만 replay받는다. `G0`, BCH generator, syndrome/Chien transform은
compile-time constant이며 FF array가 아니다.

## 검증

- Python: `pytest -q` 결과 **5 passed**
- VCS: 4 profiles × `W={32,64,128,256,512}` = **20/20 PASS**
- 각 decoder에 정정 한계만큼 실제 random error 주입:
  BCH-D1 12, BCH-D2 28, PBCH-D1/D2 8 errors
- PBCH encoder stress vector:
  D1 12 defects, D2 32 defects; selector, masking failure count, 최종 codeword를 model과 비교
- 모든 W에서 encoder output, decoder recovered data, error count를 beat 단위로 비교

`l=15` compact solver는 목표 환경의 작은 defect 수에서는 좋지만 global optimum
solver는 아니다. 200회 실험에서 defect 1/4/8개는 모두 exhaustive optimum과 같았고,
15개에서는 98.5%가 optimum이었다. 20/32/64개에서는 optimum 비율이 각각
36.0/9.5/2.0%로 낮아진다. 세부 값은 `solver_quality.csv`에 있다.

## 합성 조건

- Library: UMC 28 nm 35HSL SVT, SS / 0.9 V / 125°C
- Tool: Synopsys Design Compiler Q-2019.12-SP5-5
- `compile_ultra -no_autoungroup`
- clock uncertainty 0.20 ns, input/output delay 각각 0.40 ns
- NAND2 기준: `STP_ND2_0P5 = 0.504 um^2`
- target user bandwidth: HBF v0.7 Table 2의 3,072 GB/s
- 한 engine throughput: `512 bytes × MHz / 1000 / cycles`
- 필요 engine 수: `ceil(3072 / engine_GBps)`
- 총 면적: `mapped cell area × engine 수`

PBCH encoder VCS cycle은 solver를 stress하기 위해 많은 defect를 넣은 값이다. 목표
RBER에서는 구조상 defect 하나당 한 cycle이므로 D1은 평균 0.4203개, D2는 평균
4.215개로 보정했다. Decoder는 최대 `t` error vector의 cycle을 사용했다.

## 선택된 PPA 점

| Profile | Block | W | MHz | Engine area (um²) | NAND2 GE/engine | Cycles | GB/s/engine | Engines | 총 area (mm²) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| BCH-D1 | enc | 256 | 500 | 7,131.9 | 14,151 | 20.000 | 12.800 | 240 | 1.712 |
| BCH-D1 | dec | 128 | 325 | 56,020.6 | 111,152 | 125.000 | 1.331 | 2,308 | 129.296 |
| PBCH-D1 | enc | 64 | 250 | 5,102.0 | 10,123 | 141.420 | 0.905 | 3,395 | 17.321 |
| PBCH-D1 | dec | 64 | 350 | 27,589.1 | 54,740 | 175.000 | 1.024 | 3,000 | 82.767 |
| BCH-D2 | enc | 256 | 450 | 15,124.5 | 30,009 | 21.000 | 10.971 | 280 | 4.235 |
| BCH-D2 | dec | 64 | 300 | 92,090.2 | 182,719 | 261.000 | 0.589 | 5,220 | 480.711 |
| PBCH-D2 | enc | 64 | 250 | 8,621.6 | 17,106 | 160.215 | 0.799 | 3,846 | 33.159 |
| PBCH-D2 | dec | 64 | 350 | 29,345.4 | 58,225 | 175.000 | 1.024 | 3,000 | 88.036 |

### Reliability-matched 정규화 비교

| Point | Block | BCH (mm²) | PBCH (mm²) | PBCH 변화 | redundancy 감소 |
|---|---:|---:|---:|---:|---:|
| D1 | encoder | 1.712 | 17.321 | +912.0% | 31.4% |
| D1 | decoder | 129.296 | 82.767 | -36.0% | 31.4% |
| D1 | enc+dec | 131.007 | 100.089 | **-23.6%** | 31.4% |
| D2 | encoder | 4.235 | 33.159 | +683.0% | 67.3% |
| D2 | decoder | 480.711 | 88.036 | -81.7% | 67.3% |
| D2 | enc+dec | 484.946 | 121.195 | **-75.0%** | 67.3% |

### 같은 W=64, 250 MHz의 단일 engine 비교

이 표는 서로 다른 최적 폭/주파수의 영향 없이 순수한 logic 차이를 보여준다.

| Point | Block | BCH (um²) | PBCH (um²) | PBCH 변화 |
|---|---:|---:|---:|---:|
| D1 | encoder | 2,751.5 | 5,102.0 | +85.4% |
| D1 | decoder | 39,919.3 | 27,599.4 | -30.9% |
| D1 | enc+dec | 42,670.8 | 32,701.4 | **-23.4%** |
| D2 | encoder | 5,654.0 | 8,621.6 | +52.5% |
| D2 | decoder | 92,090.7 | 29,319.5 | -68.2% |
| D2 | enc+dec | 97,744.8 | 37,941.1 | **-61.2%** |

PBCH-D1 W=64 encoder의 면적 구성은 parent BCH 40.3%, probe/G0 35.3%, solver
16.9%, mask 2.0%이다. PBCH-D2는 parent BCH 26.6%, probe/G0 39.5%, solver
14.3%, mask 15.8%이다. 따라서 encoder overhead의 주원인은 codeword 저장 FF가 아니라
probe/G0/solver 조합망과 D2의 넓은 selector mask이다.

## W와 주파수 선택

- 모든 5개 W는 VCS 기능 검증을 통과했다.
- BCH encoder는 W=32/64/128/256을 실제 합성했고, W=256이 최적이었다. W=512는
  cycle이 20→12(D1), 21→12(D2)로만 줄지만 W-wide XOR 망이 거의 두 배가 되는
  비경쟁 후보라 기능 검증 후 pruning했다.
- PBCH encoder는 W=32/64를 최종 합성했다. W=128 exploratory run은 defect
  scanner/constraint path가 250 MHz를 만족하지 못했고 면적-cycle 추세도 W=64보다
  불리하여 그 이상을 pruning했다.
- BCH-D1 decoder는 W=32/64/128을 합성했고 W=128, 325 MHz가 최적이었다.
- BCH-D2 decoder는 W=64의 hierarchy에서 BM이 이미 29,144 um²이고, syndrome/Chien
  면적이 W에 따라 증가한다. W=32의 cycle 증가는 261→401, W=128은 261→191에
  그쳐 W=64가 경쟁점이다. 300 MHz 최종 합성으로 timing을 확인했다.
- PBCH decoder도 W=64에서 350 MHz를 만족했고, W=32는 cycle이 175→307로 늘어
  fixed BM/control 면적을 상쇄하지 못하므로 pruning했다.

## HBF integration 가정

HBF v0.7은 4 KiB user page와 Base die bank별 page-size cache buffer 2개를 정의한다
(명세 p.56, p.69). 4 KiB user page는 4096-bit dataword 8개로 나눌 수 있으므로,
codec 내부에 codeword FF를 두지 않고 외부 page/cache buffer에서 replay받는 구조는
자연스럽다.

그러나 명세가 PBCH pre-read나 codec 전용 replay 포트를 정의하는 것은 아니다. 다음은
본 RTL 밖의 integration 항목이다.

- NAND page buffer에서 pre-read bitmap을 가져오는 TSV/data path
- cache arbitration과 replay scheduling
- 4 KiB page의 ECC parity/spare-area 배치
- pre-read latency와 energy
- 여러 bank/channel 사이의 실제 engine pool 및 crossbar

## 반드시 같이 써야 할 한계

1. 정규화 면적은 standalone engine을 통째로 복제한 보수적 지표다. Syndrome, BM,
   Chien stage를 서로 다른 비율로 pool/pipeline하면 실제 총 면적은 크게 달라질 수 있다.
2. buffer, interconnect, clock tree, CTS, placement/routing, power는 포함하지 않은
   pre-layout cell-area 결과다. Library report도 zero wire-load net area를 사용한다.
3. 수백 mm²의 UMC28 정규화 면적을 HBF base-die 면적과 직접 비교하면 안 된다. 이식 시
   `총 NAND2 GE × 대상 공정 NAND2 면적`으로 다시 환산해야 한다.
4. `l=15` online solver는 inconsistent equation을 버리는 order-dependent heuristic이다.
   목표 평균 defect 4.215개 부근에서는 적합하지만, 매우 많은 defect에서 global optimum을
   보장하지 않는다.
5. 사용한 `G0/M`은 재현 가능한 maximal-LFSR 기반 representative matrix다. 논문의
   reliability 계산도 반드시 동일 matrix를 사용하거나, 최종 matrix가 바뀌면 RTL 상수와
   solver-quality 실험을 함께 재생성해야 한다.
6. PBCH의 pre-read sensing error, false positive/negative는 이 hardware-overhead RTL에
   포함하지 않았다. Non-ideal probing 평가는 별도의 reliability model로 연결해야 한다.

## 재현 방법

```bash
python3 scripts/gen_rtl.py
pytest -q
sim/run_all.sh
syn/run.sh pbch_d2 dec 64 350
python3 scripts/collect_synthesis.py
python3 scripts/collect_cycles.py
python3 scripts/analyze_results.py
```

세부 machine-readable 결과는 `cycles.csv`, `synthesis.csv`, `normalized.csv`,
`comparison.csv`, solver 결과는 `solver_quality.csv`에 있다.

## 구현 근거 자료

- PLBC/stuck-at construction: [Coding for Memory with Stuck-at Defects](https://arxiv.org/abs/1304.4821)
- finite-length redundancy allocation: [Redundancy Allocation in Finite-Length Nested Codes for Nonvolatile Memories](https://arxiv.org/abs/1803.00117)
- BCH hardware architecture survey: [Efficient Hardware Architectures for BCH Encoders and Decoders](https://arxiv.org/abs/2606.17837)
- inversionless BM example: [Low Complexity BCH Decoder Architecture for Emerging Wireless Body Area Networks](https://arxiv.org/abs/1408.2908)
- parallel Chien implementation: [US9413391B2](https://patents.google.com/patent/US9413391B2/en)
- GF(2) elimination hardware: [Systolic Gaussian Elimination over GF(2)](https://www.acsel-lab.com/arithmetic/arith8/papers/ARITH8_Hochet_Quinton_Robert.pdf)

외부 RTL을 복사하지 않았으며, 위 자료는 architecture 선택에만 사용했다.
