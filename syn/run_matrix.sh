#!/usr/bin/env bash
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -lt 3 ]]; then
    echo "usage: $0 <enc|dec> <MHz> <width> [width ...]" >&2
    exit 2
fi
kind=$1
frequency=$2
shift 2
failures=0
for width in "$@"; do
    for profile in bch_d1 bch_d2 pbch_d1 pbch_d2; do
        status="$root/syn/results/${profile}_${kind}_w${width}_${frequency}mhz/status.txt"
        if [[ -s $status ]]; then
            echo "SKIP $profile $kind W=$width F=$frequency"
        elif ! "$root/syn/run.sh" "$profile" "$kind" "$width" "$frequency"; then
            echo "FAILED $profile $kind W=$width F=$frequency" >&2
            failures=$((failures+1))
        fi
    done
done
exit "$failures"
