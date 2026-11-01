#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
for width in 32 64 128 256 512; do
    for profile in bch_d1 bch_d2 pbch_d1 pbch_d2; do
        "$root/sim/run_profile.sh" "$profile" "$width"
    done
done
