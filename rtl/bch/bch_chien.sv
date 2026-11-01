`default_nettype none

// Chien search runs in codeword-stream order and corrects the replayed word in
// the same pass.  INIT_FACTOR[j] initializes lambda_j*x^j at polynomial degree
// N-1; STEP_FACTOR[j]=alpha^j advances to the next transmitted bit.
module bch_chien #(
    parameter integer M = 13,
    parameter integer T = 8,
    parameter integer N = 4200,
    parameter integer K = 4096,
    parameter integer W = 32,
    parameter integer PARTIAL_A = 0,
    parameter integer PARTIAL_B = 0,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 14'h201b,
    parameter [((T+1)*M)-1:0] INIT_FACTOR = '0,
    parameter [((T+1)*W*M)-1:0] LANE_FACTOR = '0,
    parameter [((T+1)*M)-1:0] ADVANCE_FULL = '0,
    parameter [((T+1)*M)-1:0] ADVANCE_PARTIAL_A = '0,
    parameter [((T+1)*M)-1:0] ADVANCE_PARTIAL_B = '0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer TOTAL_W = $clog2(N + 1),
    parameter integer DEG_W = $clog2(T + 1)
) (
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire                    start_i,
    input  wire [((T+1)*M)-1:0]    locator_i,
    input  wire [DEG_W-1:0]        degree_i,
    input  wire [W-1:0]            replay_bits_i,
    input  wire [COUNT_W-1:0]      replay_count_i,
    input  wire                    replay_valid_i,
    output wire                    replay_ready_o,
    output reg  [W-1:0]            info_bits_o,
    output reg  [COUNT_W-1:0]      info_count_o,
    output wire                    info_valid_o,
    input  wire                    info_ready_i,
    output reg                     done_o,
    output reg                     success_o,
    output reg  [DEG_W-1:0]        error_count_o,
    output wire                    busy_o
);
    `include "rtl/common/gf.svh"

    reg [M-1:0] term_q [0:T];
    reg [M-1:0] term_full [0:T];
    reg [M-1:0] term_partial_a [0:T];
    reg [M-1:0] term_partial_b [0:T];
    reg [W-1:0] correction_work;
    reg [TOTAL_W-1:0] seen_q;
    reg [DEG_W:0] roots_q;
    reg busy_q;
    integer lane;
    integer coefficient;
    integer valid_info;
    integer roots_this_beat;
    integer roots_full;
    integer roots_partial_a;
    integer roots_partial_b;
    reg [M-1:0] value;

    assign busy_o = busy_q;
    assign info_valid_o = replay_valid_i && busy_q && (seen_q < K);
    assign replay_ready_o = busy_q && ((seen_q < K) ? info_ready_i : 1'b1);

    always @* begin
        correction_work = '0;
        roots_full = 0;
        roots_partial_a = 0;
        roots_partial_b = 0;
        for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1) begin
            term_full[coefficient] = gf_mul(
                term_q[coefficient], ADVANCE_FULL[coefficient*M +: M]);
            term_partial_a[coefficient] = gf_mul(
                term_q[coefficient], ADVANCE_PARTIAL_A[coefficient*M +: M]);
            term_partial_b[coefficient] = gf_mul(
                term_q[coefficient], ADVANCE_PARTIAL_B[coefficient*M +: M]);
        end
        for (lane = 0; lane < W; lane = lane + 1) begin
            value = '0;
            for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1)
                value = value ^ gf_mul(term_q[coefficient],
                    LANE_FACTOR[(lane*(T+1)+coefficient)*M +: M]);
            correction_work[W-1-lane] = (value == 0);
            if (value == 0) begin
                roots_full = roots_full + 1;
                if (lane < PARTIAL_A)
                    roots_partial_a = roots_partial_a + 1;
                if (lane < PARTIAL_B)
                    roots_partial_b = roots_partial_b + 1;
            end
        end

        if (replay_count_i == W)
            roots_this_beat = roots_full;
        else if (replay_count_i == PARTIAL_A)
            roots_this_beat = roots_partial_a;
        else
            roots_this_beat = roots_partial_b;

        info_bits_o = replay_bits_i ^ correction_work;
        valid_info = 0;
        if (seen_q < K)
            valid_info = ((K - seen_q) < replay_count_i) ? (K - seen_q) : replay_count_i;
        info_count_o = valid_info[COUNT_W-1:0];
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            seen_q <= '0;
            roots_q <= '0;
            busy_q <= 1'b0;
            done_o <= 1'b0;
            success_o <= 1'b0;
            error_count_o <= '0;
            for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1)
                term_q[coefficient] <= '0;
        end else begin
            done_o <= 1'b0;
            if (start_i && !busy_q) begin
                seen_q <= '0;
                roots_q <= '0;
                busy_q <= 1'b1;
                success_o <= 1'b0;
                error_count_o <= '0;
                for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1)
                    term_q[coefficient] <= gf_mul(
                        locator_i[coefficient*M +: M],
                        INIT_FACTOR[coefficient*M +: M]);
            end else if (replay_valid_i && replay_ready_o) begin
                for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1) begin
                    if (replay_count_i == W)
                        term_q[coefficient] <= term_full[coefficient];
                    else if (replay_count_i == PARTIAL_A)
                        term_q[coefficient] <= term_partial_a[coefficient];
                    else
                        term_q[coefficient] <= term_partial_b[coefficient];
                end
                roots_q <= roots_q + roots_this_beat;
                seen_q <= seen_q + replay_count_i;
                if (seen_q + replay_count_i == N) begin
                    busy_q <= 1'b0;
                    done_o <= 1'b1;
                    error_count_o <= roots_q + roots_this_beat;
                    success_o <= (roots_q + roots_this_beat) == degree_i;
                end
            end
        end
    end
endmodule

`default_nettype wire
