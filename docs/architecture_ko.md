# BCH/PBCH 하드웨어 구조

## 평가 구성

| 이름 | 사용자 데이터 `k` | random-error `t` | selector `l` | BCH parity | 최종 codeword |
|---|---:|---:|---:|---:|---:|
| BCH-D1 | 4096 | 12 | 0 | 156 | 4252 |
| BCH-D2 | 4096 | 28 | 0 | 364 | 4460 |
| PBCH-D1 | 4096 | 8 | 3 | 104 | 4203 |
| PBCH-D2 | 4096 | 8 | 15 | 104 | 4215 |

모두 `GF(2^13)`, primitive polynomial `x^13+x^4+x^3+x+1`을 쓰는 shortened
primitive binary BCH이다. BCH parity 길이는 임의로 `13t`라고 가정하지 않고 실제
cyclotomic coset으로 생성한 generator polynomial의 차수(156, 364, 104)를 사용한다.

## 스트림 규약

- 한 beat에서 유효 비트는 MSB lane부터 놓인다.
- codeword는 polynomial의 최고 차수 비트부터 전송한다.
- `valid/ready`가 동시에 1인 clock edge에서만 beat가 소비된다.
- 지원하는 모든 `W`가 4096을 나누므로 사용자 데이터에는 partial beat가 없다.
- page/codeword 저장공간은 codec 면적에 넣지 않는다. Decoder는 syndrome 계산 후
  `replay_req`를 내고, codec 외부의 page/cache buffer가 같은 codeword를 다시 보낸다.
- PBCH encoder도 selector를 고른 뒤 사용자 데이터만 한 번 더 요청한다. 이 때문에
  4096-bit 데이터나 4200-bit codeword를 codec 내부 FF에 저장하지 않는다.

HBF v0.7의 4 KiB user page는 4096-bit dataword 8개로 나눌 수 있으며, 명세는 Base
die의 각 bank에 page-size cache buffer 2개를 둔다고 정의한다(명세 p.56, p.69).
따라서 decoder
replay를 codec 내부 FF 대신 외부 page buffer에서 받는 계약은 자연스럽다. 다만 실제
cache arbitration, pre-read 전송, write accumulation은 이 codec RTL과 면적 평가 범위
밖의 integration 문제이며, 명세가 PBCH용 replay 포트를 직접 정의한다는 뜻은 아니다.

## BCH encoder

`bch_enc` 하나가 systematic codeword `[data | parity]`를 출력한다.

1. data를 그대로 출력하면서 polynomial-division remainder를 갱신한다.
2. 마지막 data beat 뒤에 remainder를 parity로 출력한다.
3. W-bit data beat와 PBCH의 고정 l-bit selector beat만 별도의 고정 GF(2)
   선형전이로 서술한다. 가변 길이 loop를 합성하지 않으므로 DC가 XOR network로
   줄일 수 있다.

## PBCH encoder

PBCH information word의 좌표 순서는 `[d | m XOR dM]`이다. 논문 초안의
`[m XOR sM | s]`와 좌표만 바꾼 동등한 construction이며, decoder가 selector `d`를
먼저 받아 4096-bit 임시 버퍼 없이 메시지를 복원할 수 있게 한다.

모듈은 다음처럼 나뉜다.

- `bch_enc`: `t=8` parent BCH를 두 pass에서 재사용한다.
- `pbch_probe`: `c(0)`와 pre-read bitmap을 같은 beat로 받아 defect가 있는 위치만
  한 개씩 제약식으로 만든다. defect가 없는 beat는 매 cycle 통과한다.
- `pbch_g0`: 해당 위치에서 selector가 codeword를 어떻게 바꾸는지 나타내는
  `h_i`를 만든다. selector/data 부분은 작은 LFSR 구조, parity 부분은 104개의
  합성-time 상수이다.
- `pbch_solve`: `h_i d = c(0)_i`를 푼다. `l=3`은 8개 후보를 모두 점수화한다.
  `l=15`는 최대 15개의 `(l+1)`-bit pivot row만 유지하는 incremental Gaussian
  elimination을 쓴다.
- `pbch_mask`: 선택한 `d`로 `dM`을 스트리밍 생성해 replay된 메시지에 XOR한다.
  4096은 모든 후보 W로 나누어지므로 full beat만 처리한다.
- `pbch_enc`: 위 모듈의 두 pass와 handshake를 제어한다.

첫 pass는 `d=0`인 parent BCH codeword 전체를 probe하므로 data뿐 아니라 selector와
BCH parity가 놓일 cell의 stuck-at-0 후보도 선택에 반영한다. 둘째 pass에서
`BCH([d | m XOR dM])`를 실제 codeword로 출력한다.

### l=15 fallback의 정확한 의미

새 제약을 기존 pivot으로 소거했을 때 `0=1`이면 그 제약은 버리고
`mask_failures`를 증가시킨다. 따라서 반환한 `d`는 저장한 모든 제약을 만족하지만,
모든 가능한 `d` 중 unmasked defect가 최소라는 보장은 없다. 무작위 실험에서는
1/4/8 defects 200회 모두 exhaustive optimum과 같았고, 15개에서는 98.5%가
optimum이었다. 20개 이상처럼 목표 RBER보다 훨씬 많은 defect에서는 exhaustive
optimum과 차이가 커지므로 결과에 이 제한을 명시한다.

## BCH/PBCH decoder

`bch_dec`은 세 계산 블록을 순서대로 사용한다.

1. `bch_syndrome`: odd syndrome `S1,S3,...,S(2t-1)`만 저장하고 even syndrome은
   GF square로 복원한다. full beat, selector, 마지막 parity fragment를 각각
   closed-form 선형망으로 만든다.
2. `bch_bm`: two-phase inversionless Berlekamp-Massey로 error-locator polynomial을
   구한다.
3. `bch_chien`: 외부 buffer에서 replay한 codeword와 병렬 Chien root mask를
   같은 cycle에 합쳐 corrected information을 출력한다.

`pbch_dec`은 동일한 `t=8` BCH decoder 출력을 받아 첫 `l` corrected bits를
selector로 저장하고, 나머지 4096 bits에 스트리밍 `dM`을 XOR한다.

현재 top은 이해와 단독 비교를 위해 한 frame을 syndrome→BM→replay 순서로 끝낸 뒤
다음 frame을 받는다. 세 stage의 inter-frame overlap은 구현하지 않았으므로 3.072
TB/s 정규화 수량은 이 보수적인 standalone engine의 measured initiation interval을
사용한다.

## 면적과 throughput 계산

- 공정: UMC 28nm 35HSL SVT, SS/0.9V/125°C
- clock uncertainty: 0.20 ns, input/output delay: 0.40 ns
- 합성: Design Compiler `compile_ultra -no_autoungroup`
- NAND2 기준: `STP_ND2_0P5 = 0.504 um^2`
- 한 engine throughput: `512 byte * frequency / verified cycles`
- 필요한 수: `ceil(3072 GB/s / one-engine GB/s)`
- 총 면적: `mapped cell area * 필요한 수`

PBCH encoder VCS 벡터는 solver stress를 위해 D1 12개, D2 32개의 defect를 넣었다.
목표 환경 throughput 계산에서는 제약 하나당 한 cycle인 구조를 이용해 각각
`4203*1e-4=0.4203`, `4215*1e-3=4.215` defects의 평균 cycle로 보정한다. Decoder는
각 profile의 최대 `t` 오류를 실제로 주입한 보수적 cycle을 사용한다.

HBF v0.7 Table 2의 정확한 목표인 `3072 GB/s` user bandwidth를 사용한다. 이 수량
정규화는 독립 engine을 필요한 만큼 복제했을 때의 codec core cell area이며, 공유
buffer·crossbar·clock tree·배선·pre-read latency/energy를 포함한 완성 chip 면적은 아니다.
