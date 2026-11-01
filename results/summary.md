# PPA summary

Target throughput is 3,072 GB/s of 4096-bit user payload.  PBCH encoder cycles are adjusted from the stress vectors to the mean target defect count (0.4203 for D1 and 4.215 for D2). Decoder cycles use the verified maximum-t error vectors.

| Profile | Block | W | MHz | Area (um2) | NAND2 GE | Cycles | GB/s/engine | Engines | Total mm2 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| bch_d1 | dec | 128 | 325 | 56020.6 | 111152 | 125.000 | 1.331 | 2308 | 129.296 |
| bch_d1 | enc | 256 | 500 | 7131.9 | 14151 | 20.000 | 12.800 | 240 | 1.712 |
| bch_d2 | dec | 64 | 300 | 92090.2 | 182719 | 261.000 | 0.589 | 5220 | 480.711 |
| bch_d2 | enc | 256 | 450 | 15124.5 | 30009 | 21.000 | 10.971 | 280 | 4.235 |
| pbch_d1 | dec | 64 | 350 | 27589.1 | 54740 | 175.000 | 1.024 | 3000 | 82.767 |
| pbch_d1 | enc | 64 | 250 | 5102.0 | 10123 | 141.420 | 0.905 | 3395 | 17.321 |
| pbch_d2 | dec | 64 | 350 | 29345.4 | 58225 | 175.000 | 1.024 | 3000 | 88.036 |
| pbch_d2 | enc | 64 | 250 | 8621.6 | 17106 | 160.215 | 0.799 | 3846 | 33.159 |

## Reliability-matched comparison

Positive logic overhead means PBCH occupies more normalized codec area; negative means less.
Storage reduction compares total ECC redundancy bits per 4096-bit user word.

| Point | Block | BCH mm2 | PBCH mm2 | PBCH logic overhead | BCH redundancy | PBCH redundancy | Storage reduction |
|---|---:|---:|---:|---:|---:|---:|---:|
| D1 | enc | 1.712 | 17.321 | +912.0% | 156 | 107 | 31.4% |
| D1 | dec | 129.296 | 82.767 | -36.0% | 156 | 107 | 31.4% |
| D1 | enc+dec | 131.007 | 100.089 | -23.6% | 156 | 107 | 31.4% |
| D2 | enc | 4.235 | 33.159 | +683.0% | 364 | 119 | 67.3% |
| D2 | dec | 480.711 | 88.036 | -81.7% | 364 | 119 | 67.3% |
| D2 | enc+dec | 484.946 | 121.195 | -75.0% | 364 | 119 | 67.3% |
