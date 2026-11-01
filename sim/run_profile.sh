#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -ne 2 ]]; then
    echo "usage: $0 <bch_d1|bch_d2|pbch_d1|pbch_d2> <32|64|128|256|512>" >&2
    exit 2
fi
profile=$1
width=$2
case "$profile" in bch_d1|bch_d2|pbch_d1|pbch_d2) ;; *) exit 2;; esac
case "$width" in 32|64|128|256|512) ;; *) exit 2;; esac
vcs=${VCS_CMD:-vcs}
build="$root/build/vcs_${profile}_w${width}"
mkdir -p "$build"

common=(
    "$root/rtl/bch/bch_enc.sv"
    "$root/rtl/bch/bch_syndrome.sv"
    "$root/rtl/bch/bch_bm.sv"
    "$root/rtl/bch/bch_chien.sv"
    "$root/rtl/bch/bch_dec.sv"
)

if [[ $profile == bch_d1 || $profile == bch_d2 ]]; then
    if [[ $profile == bch_d1 ]]; then r=156; t=12; else r=364; t=28; fi
    defines=(
        "+define+ENC_TOP=${profile}_enc_w${width}"
        "+define+DEC_TOP=${profile}_dec_w${width}"
        +define+K_BITS=4096 "+define+R_BITS=$r" "+define+T_BITS=$t"
        "+define+W_BITS=$width"
    )
    sources=("${common[@]}" "$root/rtl/generated/bch_wrappers.sv" "$root/tb/bch_profile_tb.sv")
    runtime=("+VEC_DIR=$root/vectors/$profile/w$width")
else
    if [[ $profile == pbch_d1 ]]; then l=3; else l=15; fi
    manifest="$root/vectors/$profile/w$width/manifest.json"
    selector=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["selector"])' "$manifest")
    failures=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mask_failures"])' "$manifest")
    defines=(
        "+define+ENC_TOP=${profile}_enc_w${width}"
        "+define+DEC_TOP=${profile}_dec_w${width}"
        "+define+L_BITS=$l" "+define+W_BITS=$width"
    )
    sources=(
        "${common[@]}"
        "$root/rtl/pbch/pbch_g0.sv" "$root/rtl/pbch/pbch_probe.sv"
        "$root/rtl/pbch/pbch_solve.sv" "$root/rtl/pbch/pbch_mask.sv"
        "$root/rtl/pbch/pbch_enc.sv" "$root/rtl/pbch/pbch_dec.sv"
        "$root/rtl/generated/pbch_wrappers.sv" "$root/tb/pbch_profile_tb.sv"
    )
    runtime=("+VEC_DIR=$root/vectors/$profile/w$width" "+EXPECT_SELECTOR=$selector" "+EXPECT_FAILURES=$failures")
fi

"$vcs" -full64 -sverilog +vcs+lic+wait +warn=noLNX_OS_VERUN +warn=noLINX_KRNL \
    -timescale=1ns/1ps "+incdir+$root" "${defines[@]}" "${sources[@]}" \
    -top "${profile%%_*}_profile_tb" -o "$build/simv" -Mdir="$build/csrc" \
    -LDFLAGS -Wl,--no-as-needed >"$build/compile.log" 2>&1
"$build/simv" "${runtime[@]}" | tee "$build/run.log"
