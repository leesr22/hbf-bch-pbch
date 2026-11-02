`default_nettype none

// Parent t=8 BCH correction followed by selector capture and streaming dM
// removal.  The corrected selector is the first L information bits, so user
// data can be returned immediately without a 4096-bit temporary register.
module pbch_dec #(
    parameter integer M = 13,
    parameter integer T = 8,
    parameter integer L = 3,
    parameter integer K = 4096,
    parameter integer R = 104,
    parameter integer W = 64,
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
    parameter [L:0] MASK_POLYNOMIAL = '0,
    parameter [L-1:0] MASK_SEED = {{(L-1){1'b0}},1'b1},
    parameter integer N = L + K + R,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer DEG_W = $clog2(T + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    output wire                 start_ready_o,
    input  wire [W-1:0]         code_bits_i,
    input  wire [COUNT_W-1:0]   code_count_i,
    input  wire                 code_valid_i,
    output wire                 code_ready_o,
    output wire                 replay_req_o,
    input  wire [W-1:0]         replay_bits_i,
    input  wire [COUNT_W-1:0]   replay_count_i,
    input  wire                 replay_valid_i,
    output wire                 replay_ready_o,
    output wire [W-1:0]         info_bits_o,
    output wire [COUNT_W-1:0]   info_count_o,
    output wire                 info_valid_o,
    input  wire                 info_ready_i,
    output reg  [L-1:0]         selector_o,
    output wire                 done_o,
    output wire                 success_o,
    output wire [DEG_W-1:0]     error_count_o,
    output wire                 busy_o
);
    reg expect_selector_q;
    wire [W-1:0] parent_info_bits;
    wire [COUNT_W-1:0] parent_info_count;
    wire parent_info_valid;
    wire parent_info_ready;
    wire [W-1:0] unmasked_bits;
    wire [COUNT_W-1:0] unmasked_count;
    wire unmasked_valid;
    wire mask_in_ready;

    assign parent_info_ready = expect_selector_q ? 1'b1 : mask_in_ready;
    assign info_bits_o = unmasked_bits;
    assign info_count_o = unmasked_count;
    assign info_valid_o = unmasked_valid && !expect_selector_q;

    bch_dec #(
        .M(M), .T(T), .K(K+L), .N(N), .W(W),
        .PARTIAL_A(L), .PARTIAL_B(R % W),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL),
        .SYN_FULL_STATE(SYN_FULL_STATE), .SYN_FULL_INPUT(SYN_FULL_INPUT),
        .SYN_PARTIAL_A_STATE(SYN_PARTIAL_A_STATE),
        .SYN_PARTIAL_A_INPUT(SYN_PARTIAL_A_INPUT),
        .SYN_PARTIAL_B_STATE(SYN_PARTIAL_B_STATE),
        .SYN_PARTIAL_B_INPUT(SYN_PARTIAL_B_INPUT),
        .CHIEN_INIT(CHIEN_INIT), .CHIEN_LANE(CHIEN_LANE),
        .CHIEN_ADVANCE_FULL(CHIEN_ADVANCE_FULL),
        .CHIEN_ADVANCE_PARTIAL_A(CHIEN_ADVANCE_PARTIAL_A),
        .CHIEN_ADVANCE_PARTIAL_B(CHIEN_ADVANCE_PARTIAL_B)
    ) bch_dec_u (
        .clk(clk), .reset_n(reset_n), .start_i(start_i),
        .start_ready_o(start_ready_o),
        .code_bits_i(code_bits_i), .code_count_i(code_count_i),
        .code_valid_i(code_valid_i), .code_ready_o(code_ready_o),
        .replay_req_o(replay_req_o), .replay_bits_i(replay_bits_i),
        .replay_count_i(replay_count_i), .replay_valid_i(replay_valid_i),
        .replay_ready_o(replay_ready_o), .info_bits_o(parent_info_bits),
        .info_count_o(parent_info_count), .info_valid_o(parent_info_valid),
        .info_ready_i(parent_info_ready), .done_o(done_o),
        .success_o(success_o), .error_count_o(error_count_o), .busy_o(busy_o)
    );

    pbch_mask #(
        .L(L), .W(W), .MASK_POLYNOMIAL(MASK_POLYNOMIAL), .MASK_SEED(MASK_SEED)
    ) unmask_u (
        .clk(clk), .reset_n(reset_n), .start_i(replay_req_o),
        .selector_i(selector_o), .in_bits_i(parent_info_bits),
        .in_count_i(parent_info_count),
        .in_valid_i(parent_info_valid && !expect_selector_q),
        .in_ready_o(mask_in_ready), .out_bits_o(unmasked_bits),
        .out_count_o(unmasked_count), .out_valid_o(unmasked_valid),
        .out_ready_i(info_ready_i)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            expect_selector_q <= 1'b1;
            selector_o <= '0;
        end else if (replay_req_o) begin
            expect_selector_q <= 1'b1;
            selector_o <= '0;
        end else if (expect_selector_q && parent_info_valid && parent_info_ready) begin
            selector_o <= parent_info_bits[W-1 -: L];
            expect_selector_q <= 1'b0;
`ifndef SYNTHESIS
            if (parent_info_count != L)
                $error("PBCH selector must be a separate L-bit segment");
`endif
        end
    end
endmodule

`default_nettype wire
