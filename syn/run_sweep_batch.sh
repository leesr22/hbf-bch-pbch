#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -eq 0 ]]; then
    echo "usage: $0 <profile:enc|profile:dec> [...]" >&2
    exit 2
fi

for point in "$@"; do
    profile=${point%:*}
    kind=${point##*:}
    echo "BEGIN $profile $kind"
    "$root/syn/run_sweep_point.sh" "$profile" "$kind"
    echo "END $profile $kind"
done
