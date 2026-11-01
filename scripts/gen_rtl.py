#!/usr/bin/env python3
"""Generate profile wrappers and compact simulation vectors."""

from pathlib import Path
import json
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.ecc import M, PRIMITIVE_POLY, PROFILES, gf_pow


WIDTHS = (32, 64, 128, 256, 512)


def literal(width, value):
    digits = (width + 3) // 4
    return "%d'h%0*x" % (width, digits, value)


def pack(values, width):
    result = 0
    for index, value in enumerate(values):
        result |= value << (index * width)
    return result


def syndrome_factors(t, width, count):
    state = [gf_pow(2, (2*odd+1)*count) for odd in range(t)]
    inputs = []
    for odd in range(t):
        exponent = 2*odd + 1
        for lane in range(width):
            inputs.append(gf_pow(2, exponent*(count-1-lane)) if lane < count else 0)
    return state, inputs


def chien_factors(t, width, count):
    return [gf_pow(2, coefficient*count) for coefficient in range(t+1)]


def encoder_wrapper(name, k, r, generator, width):
    top = "%s_enc_w%d" % (name, width)
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,
    input wire [{width-1}:0] in_bits_i,input wire [$clog2({width}+1)-1:0] in_count_i,
    input wire in_valid_i,output wire in_ready_o,
    output wire [{width-1}:0] out_bits_o,output wire [$clog2({width}+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire done_o,output wire busy_o
);
    bch_enc #(.K({k}),.R({r}),.W({width}),.GENERATOR({literal(r+1,generator)})) core (
        .clk(clk),.reset_n(reset_n),.start_i(start_i),
        .in_bits_i(in_bits_i),.in_count_i(in_count_i),.in_valid_i(in_valid_i),.in_ready_o(in_ready_o),
        .out_bits_o(out_bits_o),.out_count_o(out_count_o),.out_valid_o(out_valid_o),
        .out_ready_i(out_ready_i),.out_last_o(out_last_o),.done_o(done_o),.busy_o(busy_o));
endmodule
"""


def decoder_wrapper(name, k, n, t, width):
    partial_a = (n-k) % width
    full_state, full_input = syndrome_factors(t, width, width)
    a_state, a_input = syndrome_factors(t, width, partial_a)
    b_state, b_input = syndrome_factors(t, width, 0)
    init = [gf_pow(2, (-(n-1)*j) % ((1<<M)-1)) for j in range(t+1)]
    lane = [gf_pow(2, coefficient*lane_index)
            for lane_index in range(width) for coefficient in range(t+1)]
    advance_full = chien_factors(t, width, width)
    advance_a = chien_factors(t, width, partial_a)
    advance_b = chien_factors(t, width, 0)
    top = "%s_dec_w%d" % (name, width)
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,
    input wire [{width-1}:0] code_bits_i,input wire [$clog2({width}+1)-1:0] code_count_i,
    input wire code_valid_i,output wire code_ready_o,output wire replay_req_o,
    input wire [{width-1}:0] replay_bits_i,input wire [$clog2({width}+1)-1:0] replay_count_i,
    input wire replay_valid_i,output wire replay_ready_o,
    output wire [{width-1}:0] info_bits_o,output wire [$clog2({width}+1)-1:0] info_count_o,
    output wire info_valid_o,input wire info_ready_i,output wire done_o,
    output wire success_o,output wire [$clog2({t}+1)-1:0] error_count_o,output wire busy_o
);
    bch_dec #(.M(13),.T({t}),.K({k}),.N({n}),.W({width}),
        .PARTIAL_A({partial_a}),.PARTIAL_B(0),
        .PRIMITIVE_POLYNOMIAL(14'h201b),
        .SYN_FULL_STATE({literal(t*M,pack(full_state,M))}),
        .SYN_FULL_INPUT({literal(t*width*M,pack(full_input,M))}),
        .SYN_PARTIAL_A_STATE({literal(t*M,pack(a_state,M))}),
        .SYN_PARTIAL_A_INPUT({literal(t*width*M,pack(a_input,M))}),
        .SYN_PARTIAL_B_STATE({literal(t*M,pack(b_state,M))}),
        .SYN_PARTIAL_B_INPUT({literal(t*width*M,pack(b_input,M))}),
        .CHIEN_INIT({literal((t+1)*M,pack(init,M))}),
        .CHIEN_LANE({literal((t+1)*width*M,pack(lane,M))}),
        .CHIEN_ADVANCE_FULL({literal((t+1)*M,pack(advance_full,M))}),
        .CHIEN_ADVANCE_PARTIAL_A({literal((t+1)*M,pack(advance_a,M))}),
        .CHIEN_ADVANCE_PARTIAL_B({literal((t+1)*M,pack(advance_b,M))})) core (
        .clk(clk),.reset_n(reset_n),.start_i(start_i),
        .code_bits_i(code_bits_i),.code_count_i(code_count_i),.code_valid_i(code_valid_i),.code_ready_o(code_ready_o),
        .replay_req_o(replay_req_o),.replay_bits_i(replay_bits_i),.replay_count_i(replay_count_i),
        .replay_valid_i(replay_valid_i),.replay_ready_o(replay_ready_o),
        .info_bits_o(info_bits_o),.info_count_o(info_count_o),.info_valid_o(info_valid_o),
        .info_ready_i(info_ready_i),.done_o(done_o),.success_o(success_o),
        .error_count_o(error_count_o),.busy_o(busy_o));
endmodule
"""


def pbch_encoder_wrapper(name, profile, width):
    parity_columns = profile.influence_columns()[profile.l + profile.k:]
    parity_packed = pack(parity_columns, profile.l)
    top = "%s_enc_w%d" % (name, width)
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,
    input wire [{width-1}:0] data_bits_i,input wire [$clog2({width}+1)-1:0] data_count_i,
    input wire data_valid_i,output wire data_ready_o,output wire replay_req_o,
    input wire [{width-1}:0] probe_bits_i,input wire [$clog2({width}+1)-1:0] probe_count_i,
    input wire probe_valid_i,output wire probe_ready_o,
    output wire [{width-1}:0] out_bits_o,output wire [$clog2({width}+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire [{profile.l-1}:0] selector_o,
    output wire [$clog2({profile.n}+1)-1:0] mask_failures_o,
    output wire done_o,output wire busy_o
);
    pbch_enc #(.L({profile.l}),.K({profile.k}),.R({profile.parent.r}),.W({width}),
        .BCH_GENERATOR({literal(profile.parent.r+1,profile.parent.generator)}),
        .MASK_POLYNOMIAL({literal(profile.l+1,profile.mask_primitive)}),
        .MASK_SEED({literal(profile.l,profile.mask_seed)}),
        .PARITY_COLUMNS({literal(profile.parent.r*profile.l,parity_packed)})) core (
        .clk(clk),.reset_n(reset_n),.start_i(start_i),
        .data_bits_i(data_bits_i),.data_count_i(data_count_i),.data_valid_i(data_valid_i),
        .data_ready_o(data_ready_o),.replay_req_o(replay_req_o),
        .probe_bits_i(probe_bits_i),.probe_count_i(probe_count_i),
        .probe_valid_i(probe_valid_i),.probe_ready_o(probe_ready_o),
        .out_bits_o(out_bits_o),.out_count_o(out_count_o),.out_valid_o(out_valid_o),
        .out_ready_i(out_ready_i),.out_last_o(out_last_o),.selector_o(selector_o),
        .mask_failures_o(mask_failures_o),.done_o(done_o),.busy_o(busy_o));
endmodule
"""


def pbch_decoder_wrapper(name, profile, width):
    t = profile.t
    n = profile.n
    full_state, full_input = syndrome_factors(t, width, width)
    a_state, a_input = syndrome_factors(t, width, profile.l)
    partial_b = profile.parent.r % width
    b_state, b_input = syndrome_factors(t, width, partial_b)
    init = [gf_pow(2, (-(n-1)*j) % ((1<<M)-1)) for j in range(t+1)]
    lane = [gf_pow(2, coefficient*lane_index)
            for lane_index in range(width) for coefficient in range(t+1)]
    advance_full = chien_factors(t, width, width)
    advance_a = chien_factors(t, width, profile.l)
    advance_b = chien_factors(t, width, partial_b)
    top = "%s_dec_w%d" % (name, width)
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,
    input wire [{width-1}:0] code_bits_i,input wire [$clog2({width}+1)-1:0] code_count_i,
    input wire code_valid_i,output wire code_ready_o,output wire replay_req_o,
    input wire [{width-1}:0] replay_bits_i,input wire [$clog2({width}+1)-1:0] replay_count_i,
    input wire replay_valid_i,output wire replay_ready_o,
    output wire [{width-1}:0] info_bits_o,output wire [$clog2({width}+1)-1:0] info_count_o,
    output wire info_valid_o,input wire info_ready_i,output wire [{profile.l-1}:0] selector_o,
    output wire done_o,output wire success_o,output wire [$clog2({t}+1)-1:0] error_count_o,
    output wire busy_o
);
    pbch_dec #(.M(13),.T({t}),.L({profile.l}),.K({profile.k}),.R({profile.parent.r}),.W({width}),
        .PRIMITIVE_POLYNOMIAL(14'h201b),
        .SYN_FULL_STATE({literal(t*M,pack(full_state,M))}),
        .SYN_FULL_INPUT({literal(t*width*M,pack(full_input,M))}),
        .SYN_PARTIAL_A_STATE({literal(t*M,pack(a_state,M))}),
        .SYN_PARTIAL_A_INPUT({literal(t*width*M,pack(a_input,M))}),
        .SYN_PARTIAL_B_STATE({literal(t*M,pack(b_state,M))}),
        .SYN_PARTIAL_B_INPUT({literal(t*width*M,pack(b_input,M))}),
        .CHIEN_INIT({literal((t+1)*M,pack(init,M))}),
        .CHIEN_LANE({literal((t+1)*width*M,pack(lane,M))}),
        .CHIEN_ADVANCE_FULL({literal((t+1)*M,pack(advance_full,M))}),
        .CHIEN_ADVANCE_PARTIAL_A({literal((t+1)*M,pack(advance_a,M))}),
        .CHIEN_ADVANCE_PARTIAL_B({literal((t+1)*M,pack(advance_b,M))}),
        .MASK_POLYNOMIAL({literal(profile.l+1,profile.mask_primitive)}),
        .MASK_SEED({literal(profile.l,profile.mask_seed)})) core (
        .clk(clk),.reset_n(reset_n),.start_i(start_i),
        .code_bits_i(code_bits_i),.code_count_i(code_count_i),.code_valid_i(code_valid_i),
        .code_ready_o(code_ready_o),.replay_req_o(replay_req_o),
        .replay_bits_i(replay_bits_i),.replay_count_i(replay_count_i),
        .replay_valid_i(replay_valid_i),.replay_ready_o(replay_ready_o),
        .info_bits_o(info_bits_o),.info_count_o(info_count_o),.info_valid_o(info_valid_o),
        .info_ready_i(info_ready_i),.selector_o(selector_o),.done_o(done_o),
        .success_o(success_o),.error_count_o(error_count_o),.busy_o(busy_o));
endmodule
"""


def chunk(value, total_bits, segments, width):
    chunks = []
    consumed = 0
    for segment in segments:
        left = segment
        while left:
            count = min(width, left)
            shift = total_bits - consumed - count
            bits = (value >> shift) & ((1 << count) - 1)
            chunks.append((bits << (width-count), count))
            consumed += count
            left -= count
    assert consumed == total_bits
    return chunks


def write_vectors(name, profile, width):
    out = ROOT / "vectors" / name / ("w%d" % width)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0xB0C000 + width + profile.t)
    message = rng.getrandbits(profile.k)
    word = profile.encode(message)
    errors = sorted(rng.sample(range(profile.n), profile.t))
    received = word
    for position in errors:
        received ^= 1 << position
    segments = (profile.k, profile.r)
    entries = {
        "message": chunk(message, profile.k, (profile.k,), width),
        "codeword": chunk(word, profile.n, segments, width),
        "received": chunk(received, profile.n, segments, width),
    }
    for kind, beats in entries.items():
        (out / (kind + ".mem")).write_text("\n".join("%0*x" % ((width+3)//4,b) for b,_ in beats)+"\n")
        (out / (kind + "_count.mem")).write_text("\n".join(str(c) for _,c in beats)+"\n")
    (out / "manifest.json").write_text(json.dumps({
        "profile": name, "width": width, "k": profile.k, "r": profile.r,
        "n": profile.n, "t": profile.t, "errors_polynomial_positions": errors,
        "message_beats": len(entries["message"]), "codeword_beats": len(entries["codeword"]),
    }, indent=2)+"\n")


def write_pbch_vectors(name, profile, width):
    out = ROOT / "vectors" / name / ("w%d" % width)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0xB0C100 + width + profile.l)
    message = rng.getrandbits(profile.k)
    defect_count = 12 if profile.l == 3 else 32
    probe_positions = sorted(rng.sample(range(profile.n), defect_count))
    if profile.l == 3:
        selector, failures = profile.exact_selector(message, probe_positions)
    else:
        selector, failures = profile.greedy_selector(message, probe_positions)
    word = profile.encode(message, selector)
    received = word
    errors = sorted(rng.sample(range(profile.n), profile.t))
    for position in errors:
        received ^= 1 << position
    probe_word = 0
    for position in probe_positions:
        probe_word |= 1 << (profile.n - 1 - position)
    segments = (profile.l, profile.k, profile.parent.r)
    entries = {
        "message": chunk(message, profile.k, (profile.k,), width),
        "probe": chunk(probe_word, profile.n, segments, width),
        "codeword": chunk(word, profile.n, segments, width),
        "received": chunk(received, profile.n, segments, width),
    }
    for kind, beats in entries.items():
        (out / (kind + ".mem")).write_text(
            "\n".join("%0*x" % ((width+3)//4,b) for b,_ in beats)+"\n")
        (out / (kind + "_count.mem")).write_text(
            "\n".join(str(c) for _,c in beats)+"\n")
    (out / "manifest.json").write_text(json.dumps({
        "profile": name, "width": width, "k": profile.k, "l": profile.l,
        "r": profile.parent.r, "n": profile.n, "t": profile.t,
        "selector": selector, "mask_failures": failures,
        "probe_positions_stream": probe_positions,
        "errors_polynomial_positions": errors,
        "message_beats": len(entries["message"]),
        "codeword_beats": len(entries["codeword"]),
    }, indent=2)+"\n")


def main():
    generated = ROOT / "rtl" / "generated"
    generated.mkdir(parents=True, exist_ok=True)
    text = ["`default_nettype none\n"]
    for name in ("bch_d1", "bch_d2"):
        profile = PROFILES[name]
        for width in WIDTHS:
            text.append(encoder_wrapper(name, profile.k, profile.r, profile.generator, width))
            text.append(decoder_wrapper(name, profile.k, profile.n, profile.t, width))
            write_vectors(name, profile, width)
    text.append("\n`default_nettype wire\n")
    (generated / "bch_wrappers.sv").write_text("".join(text))

    pbch_text = ["`default_nettype none\n"]
    for name in ("pbch_d1", "pbch_d2"):
        profile = PROFILES[name]
        for width in WIDTHS:
            pbch_text.append(pbch_encoder_wrapper(name, profile, width))
            pbch_text.append(pbch_decoder_wrapper(name, profile, width))
            write_pbch_vectors(name, profile, width)
    pbch_text.append("\n`default_nettype wire\n")
    (generated / "pbch_wrappers.sv").write_text("".join(pbch_text))

    manifest = {}
    for name, profile in PROFILES.items():
        if name.startswith("pbch"):
            influence = profile.influence_columns()
            manifest[name] = {
                "k": profile.k, "l": profile.l, "r": profile.parent.r,
                "n": profile.n, "t": profile.t,
                "mask_primitive": hex(profile.mask_primitive), "mask_seed": hex(profile.mask_seed),
                "zero_influence_columns": sum(v == 0 for v in influence),
                "unique_influence_columns": len(set(influence)),
            }
        else:
            manifest[name] = {
                "k": profile.k, "r": profile.r, "n": profile.n, "t": profile.t,
                "generator": hex(profile.generator),
            }
    (generated / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")


if __name__ == "__main__":
    main()
