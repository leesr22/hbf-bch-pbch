#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <profile> <32|64|128|256|512> [max|zero|mixed]" >&2
    exit 2
fi
profile=$1
width=$2
mode=${3:-max}
case "$profile" in bch_d1|bch_d2|pbch_d1|pbch_d2|pbch_l*_exact|pbch_l*_gauss|pbch_l*_pipe) ;; *) exit 2;; esac
case "$width" in 32|64|128|256|512) ;; *) exit 2;; esac
case "$mode" in max|zero|mixed) ;; *) exit 2;; esac
vcs=${VCS_CMD:-vcs}
build="$root/build/vcs_${profile}_pipeline_w${width}"
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
    sources=("${common[@]}" "$root/rtl/generated/bch_wrappers.sv" "$root/tb/bch_pipeline_tb.sv")
    runtime=("+VEC_DIR=$root/vectors/$profile/w$width")
    top=bch_pipeline_tb
else
    if [[ $profile == pbch_d1 ]]; then
        l=3
        pbch_wrapper="$root/rtl/generated/pbch_wrappers.sv"
    elif [[ $profile == pbch_d2 ]]; then
        l=15
        pbch_wrapper="$root/rtl/generated/pbch_wrappers.sv"
    else
        l_text=${profile#pbch_l}
        l_text=${l_text%%_*}
        l=$((10#$l_text))
        pbch_wrapper="$root/rtl/generated/pbch_sweep_wrappers.sv"
    fi
    manifest="$root/vectors/$profile/w$width/manifest.json"
    selector=$(python3 -c 'import json,sys; print(format(json.load(open(sys.argv[1]))["selector"], "x"))' "$manifest")
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
        "$pbch_wrapper" "$root/tb/pbch_pipeline_tb.sv"
    )
    runtime=("+VEC_DIR=$root/vectors/$profile/w$width" "+EXPECT_SELECTOR=$selector" "+EXPECT_FAILURES=$failures")
    top=pbch_pipeline_tb
fi

case "$mode" in
    zero) runtime+=(+ZERO_ERRORS) ;;
    mixed)
        if [[ $profile != bch_d1 && $profile != bch_d2 ]]; then
            echo "mixed mode is currently defined only by bch_pipeline_tb" >&2
            exit 2
        fi
        runtime+=(+MIXED_ERRORS)
        ;;
esac

"$vcs" -full64 -sverilog +vcs+lic+wait +warn=noLNX_OS_VERUN +warn=noLINX_KRNL \
    -timescale=1ns/1ps "+incdir+$root" "${defines[@]}" "${sources[@]}" \
    -top "$top" -o "$build/simv" -Mdir="$build/csrc" \
    -LDFLAGS -Wl,--no-as-needed >"$build/compile.log" 2>&1
run_log="$build/run.log"
if [[ $mode != max ]]; then run_log="$build/run_${mode}.log"; fi
"$build/simv" "${runtime[@]}" | tee "$run_log"
