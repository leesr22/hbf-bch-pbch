#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -ne 4 ]]; then
    echo "usage: $0 <profile> <enc|dec> <32|64|128|256|512> <MHz>" >&2
    exit 2
fi
case "$1" in bch_d1|bch_d2|pbch_d1|pbch_d2|pbch_l*_exact|pbch_l*_gauss|pbch_l*_pipe) ;; *) exit 2;; esac
case "$2" in enc|dec) ;; *) exit 2;; esac
case "$3" in 32|64|128|256|512) ;; *) exit 2;; esac
if ! [[ "$4" =~ ^[0-9]+$ ]]; then exit 2; fi

export HBF_ECC_ROOT="$root"
export ECC_PROFILE="$1" ECC_KIND="$2" ECC_WIDTH="$3" ECC_CLOCK_MHZ="$4"
: "${HBF_ECC_TARGET_LIBRARY:?Set HBF_ECC_TARGET_LIBRARY to an authorized Liberty .db file}"
dc_cmd="${DC_CMD:-dc_shell-xg-t}"
run="${1}_${2}_w${3}_${4}mhz"
mkdir -p "$root/syn/reports/$run" "$root/syn/results/$run" "$root/syn/work/$run"
exec 9>/tmp/hbf_umc28_dc.global.lock
flock 9
(cd "$root/syn/work/$run" && "$dc_cmd" -64bit -f "$root/syn/synth.tcl") \
    >"$root/syn/reports/$run/compile.log" 2>&1
test -s "$root/syn/results/$run/status.txt"
cat "$root/syn/results/$run/status.txt"
