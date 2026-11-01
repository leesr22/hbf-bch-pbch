`default_nettype none

// Stores only the T odd syndromes.  Even syndromes are recovered by repeated
// squaring after the last codeword beat.
module bch_syndrome #(
    parameter integer M = 13,
    parameter integer T = 8,
    parameter integer N = 4200,
    parameter integer W = 64,
    parameter integer PARTIAL_A = 0,
    parameter integer PARTIAL_B = 0,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 14'h201b,
    parameter [(T*M)-1:0] FULL_STATE_FACTOR = '0,
    parameter [(T*W*M)-1:0] FULL_INPUT_FACTOR = '0,
    parameter [(T*M)-1:0] PARTIAL_A_STATE_FACTOR = '0,
    parameter [(T*W*M)-1:0] PARTIAL_A_INPUT_FACTOR = '0,
    parameter [(T*M)-1:0] PARTIAL_B_STATE_FACTOR = '0,
    parameter [(T*W*M)-1:0] PARTIAL_B_INPUT_FACTOR = '0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer TOTAL_W = $clog2(N + 1)
) (
    input  wire                   clk,
    input  wire                   reset_n,
    input  wire                   start_i,
    input  wire [W-1:0]           bits_i,
    input  wire [COUNT_W-1:0]     count_i,
    input  wire                   valid_i,
    output wire                   ready_o,
    output reg  [(2*T*M)-1:0]     syndromes_o,
    output reg                    done_o,
    output wire                   busy_o
);
    `include "rtl/common/gf.svh"

    // Keep the bank packed.  Besides being compact, this avoids a synthesis
    // tool corner case around nonblocking writes to unpacked arrays in loops.
    reg [(T*M)-1:0] odd_q;
    reg [(T*M)-1:0] odd_full;
    reg [(T*M)-1:0] odd_partial_a;
    reg [(T*M)-1:0] odd_partial_b;
    reg [M-1:0] full_work [1:2*T];
    reg [TOTAL_W-1:0] seen_q;
    reg busy_q;
    reg finish_q;
    integer update_odd;
    integer update_lane;
    integer index;

    assign ready_o = busy_q && !finish_q;
    assign busy_o = busy_q;

    // Only three transfer sizes exist in the four evaluated codecs: W, the
    // leading PBCH selector, and the final parity fragment.  Expressing those
    // as fixed transforms lets DC reduce each recurrence to a GF(2) network.
    always @* begin
        for (update_odd = 0; update_odd < T; update_odd = update_odd + 1) begin
            odd_full[update_odd*M +: M] = gf_mul(
                odd_q[update_odd*M +: M], FULL_STATE_FACTOR[update_odd*M +: M]);
            odd_partial_a[update_odd*M +: M] = gf_mul(
                odd_q[update_odd*M +: M], PARTIAL_A_STATE_FACTOR[update_odd*M +: M]);
            odd_partial_b[update_odd*M +: M] = gf_mul(
                odd_q[update_odd*M +: M], PARTIAL_B_STATE_FACTOR[update_odd*M +: M]);
            for (update_lane = 0; update_lane < W; update_lane = update_lane + 1) begin
                if (bits_i[W-1-update_lane]) begin
                    odd_full[update_odd*M +: M] = odd_full[update_odd*M +: M] ^
                        FULL_INPUT_FACTOR[(update_odd*W+update_lane)*M +: M];
                    odd_partial_a[update_odd*M +: M] = odd_partial_a[update_odd*M +: M] ^
                        PARTIAL_A_INPUT_FACTOR[(update_odd*W+update_lane)*M +: M];
                    odd_partial_b[update_odd*M +: M] = odd_partial_b[update_odd*M +: M] ^
                        PARTIAL_B_INPUT_FACTOR[(update_odd*W+update_lane)*M +: M];
                end
            end
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            seen_q <= '0;
            busy_q <= 1'b0;
            finish_q <= 1'b0;
            done_o <= 1'b0;
            syndromes_o <= '0;
            odd_q <= '0;
        end else begin
            done_o <= 1'b0;
            if (start_i && !busy_q) begin
                seen_q <= '0;
                busy_q <= 1'b1;
                finish_q <= 1'b0;
                odd_q <= '0;
            end else if (valid_i && ready_o) begin
                if (count_i == W)
                    odd_q <= odd_full;
                else if (count_i == PARTIAL_A)
                    odd_q <= odd_partial_a;
                else
                    odd_q <= odd_partial_b;
                seen_q <= seen_q + count_i;
                if (seen_q + count_i == N)
                    finish_q <= 1'b1;
            end else if (finish_q) begin
                for (index = 1; index <= 2*T; index = index + 1) begin
                    if (index[0])
                        full_work[index] = odd_q[((index-1)/2)*M +: M];
                    else
                        full_work[index] = gf_square(full_work[index/2]);
                    syndromes_o[(index-1)*M +: M] <= full_work[index];
                end
                busy_q <= 1'b0;
                finish_q <= 1'b0;
                done_o <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
