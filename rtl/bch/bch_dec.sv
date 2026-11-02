`default_nettype none

// Three-stage inter-frame decoder pipeline. Syndrome, BM, and Chien may work on
// different codewords concurrently. Only compact algebraic context crosses the
// stage boundaries; the original codeword stays in an external replay buffer.
module bch_dec #(
    parameter integer M = 13,
    parameter integer T = 8,
    parameter integer K = 4096,
    parameter integer N = 4200,
    parameter integer W = 32,
    parameter integer BM_LANES = 1,
    parameter integer PARTIAL_A = 0,
    parameter integer PARTIAL_B = 0,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 14'h201b,
    parameter [(T*M)-1:0] SYN_FULL_STATE = '0,
    parameter [(T*W*M)-1:0] SYN_FULL_INPUT = '0,
    parameter [(T*M)-1:0] SYN_PARTIAL_A_STATE = '0,
    parameter [(T*W*M)-1:0] SYN_PARTIAL_A_INPUT = '0,
    parameter [(T*M)-1:0] SYN_PARTIAL_B_STATE = '0,
    parameter [(T*W*M)-1:0] SYN_PARTIAL_B_INPUT = '0,
    parameter [((T+1)*M)-1:0] CHIEN_INIT = '0,
    parameter [((T+1)*W*M)-1:0] CHIEN_LANE = '0,
    parameter [((T+1)*M)-1:0] CHIEN_ADVANCE_FULL = '0,
    parameter [((T+1)*M)-1:0] CHIEN_ADVANCE_PARTIAL_A = '0,
    parameter [((T+1)*M)-1:0] CHIEN_ADVANCE_PARTIAL_B = '0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer DEG_W = $clog2(T + 1)
) (
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire                    start_i,
    output wire                    start_ready_o,
    input  wire [W-1:0]            code_bits_i,
    input  wire [COUNT_W-1:0]      code_count_i,
    input  wire                    code_valid_i,
    output wire                    code_ready_o,
    output wire                    replay_req_o,
    input  wire [W-1:0]            replay_bits_i,
    input  wire [COUNT_W-1:0]      replay_count_i,
    input  wire                    replay_valid_i,
    output wire                    replay_ready_o,
    output wire [W-1:0]            info_bits_o,
    output wire [COUNT_W-1:0]      info_count_o,
    output wire                    info_valid_o,
    input  wire                    info_ready_i,
    output wire                    done_o,
    output wire                    success_o,
    output wire [DEG_W-1:0]        error_count_o,
    output wire                    busy_o
);
    localparam integer LOC_W = (T+1)*M;
    localparam integer BM_SEL_W = (BM_LANES <= 1) ? 1 : $clog2(BM_LANES);

    wire [(2*T*M)-1:0] syndromes;
    wire syndrome_done;
    wire syndrome_busy;
    wire [(BM_LANES*LOC_W)-1:0] bm_locator;
    wire [(BM_LANES*DEG_W)-1:0] bm_degree;
    wire [BM_LANES-1:0] bm_done;
    wire [BM_LANES-1:0] bm_busy;
    wire chien_done;
    wire chien_success;
    wire [DEG_W-1:0] chien_error_count;
    wire chien_busy;

    reg syndrome_pending_q;
    reg [BM_LANES-1:0] bm_result_pending_q;
    reg [BM_LANES-1:0] bm_start_q;
    reg [BM_SEL_W-1:0] bm_issue_lane_q;
    reg [BM_SEL_W-1:0] bm_head_lane_q;
    reg chien_start_q;
    reg replay_req_q;
    reg [((T+1)*M)-1:0] chien_locator_q;
    reg [DEG_W-1:0] chien_degree_q;

    integer bm_index;

    function automatic [BM_SEL_W-1:0] next_bm_lane;
        input [BM_SEL_W-1:0] lane;
        begin
            if ((BM_LANES <= 1) || (lane == BM_LANES-1))
                next_bm_lane = '0;
            else
                next_bm_lane = lane + 1'b1;
        end
    endfunction

    wire bm_issue_ready = !bm_busy[bm_issue_lane_q] &&
                          !bm_done[bm_issue_lane_q] &&
                          !bm_start_q[bm_issue_lane_q] &&
                          !bm_result_pending_q[bm_issue_lane_q];
    wire bm_head_pending = bm_result_pending_q[bm_head_lane_q];
    wire bm_to_chien = bm_head_pending && !chien_busy && !chien_start_q;
    wire bm_any_active = (|bm_busy) || (|bm_done) || (|bm_start_q) ||
                         (|bm_result_pending_q);
    // The stage output registers themselves are the one-entry context buffers.
    // With two lanes, round-robin issue/head pointers preserve frame order while
    // the two unchanged BM cores interleave codewords.
    // Run zero syndromes through BM as well.  A direct zero-error bypass saves
    // latency in isolation, but needs another in-order result FIFO when mixed
    // with nonzero frames.  Uniform dispatch keeps the controller compact and
    // makes initiation interval independent of the error pattern.
    wire syndrome_to_bm = syndrome_pending_q && bm_issue_ready;
    wire syndrome_dispatch = syndrome_to_bm;
    wire completion_target_ready = bm_issue_ready;

    // A previous buffered syndrome may leave on the same edge that the next scan
    // starts.  At the completion edge itself, start another scan only if stage 2
    // can consume this new result before the one-entry context slot overflows.
    assign start_ready_o = !syndrome_busy &&
                           (syndrome_done ?
                            (!syndrome_pending_q && completion_target_ready) :
                            (!syndrome_pending_q || syndrome_dispatch));
    assign busy_o = syndrome_busy || syndrome_pending_q || bm_any_active || chien_busy;
    assign replay_req_o = replay_req_q;
    assign done_o = chien_done;
    assign success_o = chien_success;
    assign error_count_o = chien_error_count;

    bch_syndrome #(
        .M(M), .T(T), .N(N), .W(W), .PARTIAL_A(PARTIAL_A), .PARTIAL_B(PARTIAL_B),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL),
        .FULL_STATE_FACTOR(SYN_FULL_STATE), .FULL_INPUT_FACTOR(SYN_FULL_INPUT),
        .PARTIAL_A_STATE_FACTOR(SYN_PARTIAL_A_STATE),
        .PARTIAL_A_INPUT_FACTOR(SYN_PARTIAL_A_INPUT),
        .PARTIAL_B_STATE_FACTOR(SYN_PARTIAL_B_STATE),
        .PARTIAL_B_INPUT_FACTOR(SYN_PARTIAL_B_INPUT)
    ) syndrome_u (
        .clk(clk), .reset_n(reset_n), .start_i(start_i && start_ready_o),
        .bits_i(code_bits_i), .count_i(code_count_i), .valid_i(code_valid_i),
        .ready_o(code_ready_o), .syndromes_o(syndromes),
        .done_o(syndrome_done), .busy_o(syndrome_busy)
    );

    genvar bm_lane;
    generate
        for (bm_lane = 0; bm_lane < BM_LANES; bm_lane = bm_lane + 1) begin : bm_lanes
            bch_bm #(
                .M(M), .T(T), .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
            ) bm_u (
                .clk(clk), .reset_n(reset_n), .start_i(bm_start_q[bm_lane]),
                .syndromes_i(syndromes),
                .locator_o(bm_locator[bm_lane*LOC_W +: LOC_W]),
                .degree_o(bm_degree[bm_lane*DEG_W +: DEG_W]),
                .done_o(bm_done[bm_lane]), .busy_o(bm_busy[bm_lane])
            );
        end
    endgenerate

    bch_chien #(
        .M(M), .T(T), .N(N), .K(K), .W(W),
        .PARTIAL_A(PARTIAL_A), .PARTIAL_B(PARTIAL_B),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL),
        .INIT_FACTOR(CHIEN_INIT), .LANE_FACTOR(CHIEN_LANE),
        .ADVANCE_FULL(CHIEN_ADVANCE_FULL),
        .ADVANCE_PARTIAL_A(CHIEN_ADVANCE_PARTIAL_A),
        .ADVANCE_PARTIAL_B(CHIEN_ADVANCE_PARTIAL_B)
    ) chien_u (
        .clk(clk), .reset_n(reset_n), .start_i(chien_start_q),
        .locator_i(chien_locator_q), .degree_i(chien_degree_q),
        .replay_bits_i(replay_bits_i), .replay_count_i(replay_count_i),
        .replay_valid_i(replay_valid_i), .replay_ready_o(replay_ready_o),
        .info_bits_o(info_bits_o), .info_count_o(info_count_o),
        .info_valid_o(info_valid_o), .info_ready_i(info_ready_i),
        .done_o(chien_done), .success_o(chien_success),
        .error_count_o(chien_error_count), .busy_o(chien_busy)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            syndrome_pending_q <= 1'b0;
            bm_result_pending_q <= '0;
            bm_start_q <= '0;
            bm_issue_lane_q <= '0;
            bm_head_lane_q <= '0;
            chien_start_q <= 1'b0;
            replay_req_q <= 1'b0;
            chien_locator_q <= '0;
            chien_degree_q <= '0;
        end else begin
            bm_start_q <= '0;
            chien_start_q <= 1'b0;
            replay_req_q <= 1'b0;

            if (syndrome_done) begin
                syndrome_pending_q <= 1'b1;
            end

            if (syndrome_to_bm) begin
                bm_start_q[bm_issue_lane_q] <= 1'b1;
                bm_issue_lane_q <= next_bm_lane(bm_issue_lane_q);
                syndrome_pending_q <= 1'b0;
            end

            for (bm_index = 0; bm_index < BM_LANES; bm_index = bm_index + 1)
                if (bm_done[bm_index])
                    bm_result_pending_q[bm_index] <= 1'b1;

            if (bm_to_chien) begin
                chien_locator_q <= bm_locator[bm_head_lane_q*LOC_W +: LOC_W];
                chien_degree_q <= bm_degree[bm_head_lane_q*DEG_W +: DEG_W];
                chien_start_q <= 1'b1;
                replay_req_q <= 1'b1;
                bm_result_pending_q[bm_head_lane_q] <= 1'b0;
                bm_head_lane_q <= next_bm_lane(bm_head_lane_q);
            end
        end
    end
endmodule

`default_nettype wire
