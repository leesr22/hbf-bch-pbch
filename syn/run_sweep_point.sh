#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -ne 2 ]]; then
    echo "usage: $0 <pbch_lNN_exact|pbch_lNN_gauss|pbch_lNN_pipe> <enc|dec>" >&2
    exit 2
fi
case "$1" in pbch_l*_exact|pbch_l*_gauss|pbch_l*_pipe) ;; *) exit 2;; esac
case "$2" in enc|dec) ;; *) exit 2;; esac

if [[ -z ${HBF_ECC_TARGET_LIBRARY:-} ]]; then
    status="$root/syn/results/pbch_d1_enc_w64_250mhz/status.txt"
    HBF_ECC_TARGET_LIBRARY=$(sed -n 's/^library=//p' "$status")
    export HBF_ECC_TARGET_LIBRARY
fi

summary=$(mktemp)
trap 'rm -f "$summary"' EXIT
"$root/syn/run.sh" "$1" "$2" 64 250 >"$summary"
sed -n '/^result=/p; /^slack_ns=/p; /^area_um2=/p; /^top=/p' "$summary"
