`default_nettype none

// Streaming decoder with an external replay contract.  The original codeword
// remains in the HBF page/cache buffer; after syndrome/BM, replay_req_o asks the
// source to stream it again for Chien correction.  No N-bit register is used.
module bch_dec #(
    parameter integer M = 13,
    parameter integer T = 8,
    parameter integer K = 4096,
    parameter integer N = 4200,
    parameter integer W = 32,
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
    input  wire [W-1:0]            code_bits_i,
    input  wire [COUNT_W-1:0]      code_count_i,
    input  wire                    code_valid_i,
    output wire                    code_ready_o,
    output reg                     replay_req_o,
    input  wire [W-1:0]            replay_bits_i,
    input  wire [COUNT_W-1:0]      replay_count_i,
    input  wire                    replay_valid_i,
    output wire                    replay_ready_o,
    output wire [W-1:0]            info_bits_o,
    output wire [COUNT_W-1:0]      info_count_o,
    output wire                    info_valid_o,
    input  wire                    info_ready_i,
    output reg                     done_o,
    output reg                     success_o,
    output reg  [DEG_W-1:0]        error_count_o,
    output wire                    busy_o
);
    localparam [2:0] IDLE = 3'd0, SCAN = 3'd1, WAIT_BM = 3'd2,
                     WAIT_REPLAY = 3'd3, REPLAY = 3'd4;
    reg [2:0] state_q;
    wire [(2*T*M)-1:0] syndromes;
    wire syndrome_done;
    wire syndrome_busy;
    wire syndrome_zero = syndromes == 0;
    reg bm_start;
    wire [((T+1)*M)-1:0] bm_locator;
    wire [DEG_W-1:0] bm_degree;
    wire bm_done;
    reg [((T+1)*M)-1:0] locator_q;
    reg [DEG_W-1:0] degree_q;
    reg chien_start;
    wire chien_done;
    wire chien_success;
    wire [DEG_W-1:0] chien_error_count;
    wire chien_busy;

    assign busy_o = state_q != IDLE;

    bch_syndrome #(
        .M(M), .T(T), .N(N), .W(W), .PARTIAL_A(PARTIAL_A), .PARTIAL_B(PARTIAL_B),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL),
        .FULL_STATE_FACTOR(SYN_FULL_STATE), .FULL_INPUT_FACTOR(SYN_FULL_INPUT),
        .PARTIAL_A_STATE_FACTOR(SYN_PARTIAL_A_STATE),
        .PARTIAL_A_INPUT_FACTOR(SYN_PARTIAL_A_INPUT),
        .PARTIAL_B_STATE_FACTOR(SYN_PARTIAL_B_STATE),
        .PARTIAL_B_INPUT_FACTOR(SYN_PARTIAL_B_INPUT)
    ) syndrome_u (
        .clk(clk), .reset_n(reset_n), .start_i(start_i && state_q == IDLE),
        .bits_i(code_bits_i), .count_i(code_count_i), .valid_i(code_valid_i),
        .ready_o(code_ready_o), .syndromes_o(syndromes),
        .done_o(syndrome_done), .busy_o(syndrome_busy)
    );

    bch_bm #(
        .M(M), .T(T), .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
    ) bm_u (
        .clk(clk), .reset_n(reset_n), .start_i(bm_start),
        .syndromes_i(syndromes), .locator_o(bm_locator), .degree_o(bm_degree),
        .done_o(bm_done), .busy_o()
    );

    bch_chien #(
        .M(M), .T(T), .N(N), .K(K), .W(W),
        .PARTIAL_A(PARTIAL_A), .PARTIAL_B(PARTIAL_B),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL),
        .INIT_FACTOR(CHIEN_INIT), .LANE_FACTOR(CHIEN_LANE),
        .ADVANCE_FULL(CHIEN_ADVANCE_FULL),
        .ADVANCE_PARTIAL_A(CHIEN_ADVANCE_PARTIAL_A),
        .ADVANCE_PARTIAL_B(CHIEN_ADVANCE_PARTIAL_B)
    ) chien_u (
        .clk(clk), .reset_n(reset_n), .start_i(chien_start),
        .locator_i(locator_q), .degree_i(degree_q),
        .replay_bits_i(replay_bits_i), .replay_count_i(replay_count_i),
        .replay_valid_i(replay_valid_i), .replay_ready_o(replay_ready_o),
        .info_bits_o(info_bits_o), .info_count_o(info_count_o),
        .info_valid_o(info_valid_o), .info_ready_i(info_ready_i),
        .done_o(chien_done), .success_o(chien_success),
        .error_count_o(chien_error_count), .busy_o(chien_busy)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            bm_start <= 1'b0;
            chien_start <= 1'b0;
            replay_req_o <= 1'b0;
            locator_q <= '0;
            degree_q <= '0;
            done_o <= 1'b0;
            success_o <= 1'b0;
            error_count_o <= '0;
        end else begin
            bm_start <= 1'b0;
            chien_start <= 1'b0;
            replay_req_o <= 1'b0;
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) state_q <= SCAN;
                SCAN: if (syndrome_done) begin
                    if (syndrome_zero) begin
                        locator_q <= {{(T*M){1'b0}}, {{(M-1){1'b0}},1'b1}};
                        degree_q <= '0;
                        state_q <= WAIT_REPLAY;
                    end else begin
                        bm_start <= 1'b1;
                        state_q <= WAIT_BM;
                    end
                end
                WAIT_BM: if (bm_done) begin
                    locator_q <= bm_locator;
                    degree_q <= bm_degree;
                    state_q <= WAIT_REPLAY;
                end
                WAIT_REPLAY: begin
                    replay_req_o <= 1'b1;
                    chien_start <= 1'b1;
                    state_q <= REPLAY;
                end
                REPLAY: if (chien_done) begin
                    success_o <= chien_success;
                    error_count_o <= chien_error_count;
                    done_o <= 1'b1;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
