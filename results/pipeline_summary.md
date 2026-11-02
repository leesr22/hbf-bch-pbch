# Common W=64, 250-MHz pipeline result

Throughput uses steady-state initiation interval, not end-to-end latency. PBCH encoder II is adjusted from the stress vector to the target mean defect count.

| Profile | Block | Area (um2) | Latency | II | GB/s/engine | Engines | Total mm2 |
|---|---:|---:|---:|---:|---:|---:|---:|
| bch_d1 | enc | 2754.0 | 68 | 67.000 | 1.910 | 1608 | 4.428 |
| bch_d1 | dec | 39834.6 | 190 | 69.000 | 1.855 | 1656 | 65.966 |
| pbch_d1 | enc | 7385.3 | 153 | 71.420 | 1.792 | 1715 | 12.666 |
| pbch_d1 | dec | 27545.3 | 174 | 69.000 | 1.855 | 1656 | 45.615 |
| bch_d2 | enc | 5656.4 | 71 | 70.000 | 1.829 | 1680 | 9.503 |
| bch_d2 | dec | 121274.3 | 260 | 72.000 | 1.778 | 1728 | 209.562 |
| pbch_d2 | enc | 11163.8 | 188 | 90.215 | 1.419 | 2166 | 24.181 |
| pbch_d2 | dec | 29250.1 | 174 | 69.000 | 1.855 | 1656 | 48.438 |

## Reliability-matched comparison

| Point | Block | BCH mm2 | PBCH mm2 | PBCH change | Storage reduction |
|---|---:|---:|---:|---:|---:|
| D1 | enc | 4.428 | 12.666 | +186.0% | 31.4% |
| D1 | dec | 65.966 | 45.615 | -30.9% | 31.4% |
| D1 | enc+dec | 70.395 | 58.281 | -17.2% | 31.4% |
| D2 | enc | 9.503 | 24.181 | +154.5% | 67.3% |
| D2 | dec | 209.562 | 48.438 | -76.9% | 67.3% |
| D2 | enc+dec | 219.065 | 72.619 | -66.9% | 67.3% |

## BCH-D2 BM resource balancing

| Architecture | Area (um2) | II | GB/s/engine | Engines | Total mm2 |
|---|---:|---:|---:|---:|---:|
| single_bm | 92088.9 | 115 | 1.113 | 2760 | 254.165 |
| dual_bm | 121274.3 | 72 | 1.778 | 1728 | 209.562 |
