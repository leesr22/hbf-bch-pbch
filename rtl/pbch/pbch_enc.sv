`default_nettype none

// Two-pass PBCH encoder.  Pass 1 streams c(0) against the pre-read bitmap and
// solves for d.  The source is then asked to replay only the 4096 user bits;
// pass 2 emits BCH([d | message XOR dM]).  The page/codeword stays external.
module pbch_enc #(
    parameter integer L = 3,
    parameter integer K = 4096,
    parameter integer R = 104,
    parameter integer W = 64,
    parameter [R:0] BCH_GENERATOR = '0,
    parameter [L:0] MASK_POLYNOMIAL = '0,
    parameter [L-1:0] MASK_SEED = {{(L-1){1'b0}},1'b1},
    parameter [(R*L)-1:0] PARITY_COLUMNS = '0,
    parameter integer N = L + K + R,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer DATA_W = $clog2(K + 1),
    parameter integer FAIL_W = $clog2(N + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    input  wire [W-1:0]         data_bits_i,
    input  wire [COUNT_W-1:0]   data_count_i,
    input  wire                 data_valid_i,
    output wire                 data_ready_o,
    output reg                  replay_req_o,
    input  wire [W-1:0]         probe_bits_i,
    input  wire [COUNT_W-1:0]   probe_count_i,
    input  wire                 probe_valid_i,
    output wire                 probe_ready_o,
    output wire [W-1:0]         out_bits_o,
    output wire [COUNT_W-1:0]   out_count_o,
    output wire                 out_valid_o,
    input  wire                 out_ready_i,
    output wire                 out_last_o,
    output reg  [L-1:0]         selector_o,
    output reg  [FAIL_W-1:0]    mask_failures_o,
    output reg                  done_o,
    output wire                 busy_o
);
    localparam [3:0] IDLE = 4'd0, BASE_START = 4'd1, BASE_SELECTOR = 4'd2,
                     BASE_DATA = 4'd3, BASE_WAIT = 4'd4, FINAL_START = 4'd5,
                     FINAL_SELECTOR = 4'd6, FINAL_DATA = 4'd7,
                     FINAL_WAIT = 4'd8;
    reg [3:0] state_q;
    reg parent_start_q;
    reg probe_start_q;
    reg solve_start_q;
    reg mask_start_q;
    reg [DATA_W-1:0] data_seen_q;

    reg [W-1:0] parent_in_bits;
    reg [COUNT_W-1:0] parent_in_count;
    reg parent_in_valid;
    wire parent_in_ready;
    wire [W-1:0] parent_out_bits;
    wire [COUNT_W-1:0] parent_out_count;
    wire parent_out_valid;
    reg parent_out_ready;
    wire parent_out_last;
    wire parent_done;

    wire [W-1:0] masked_bits;
    wire [COUNT_W-1:0] masked_count;
    wire masked_valid;
    wire mask_data_ready;
    reg mask_out_ready;

    wire probe_base_ready;
    wire probe_stream_ready;
    wire [L-1:0] row_h;
    wire row_rhs;
    wire row_valid;
    wire row_ready;
    wire probe_done;
    wire [L-1:0] solved_selector;
    wire [FAIL_W-1:0] solved_failures;
    wire solve_done;

    assign busy_o = state_q != IDLE;
    assign data_ready_o = (state_q == BASE_DATA) ? parent_in_ready :
                          (state_q == FINAL_DATA) ? mask_data_ready : 1'b0;
    assign probe_ready_o = (state_q >= BASE_SELECTOR && state_q <= BASE_WAIT) ?
                           probe_stream_ready : 1'b0;
    assign out_bits_o = parent_out_bits;
    assign out_count_o = parent_out_count;
    assign out_valid_o = (state_q >= FINAL_SELECTOR && state_q <= FINAL_WAIT) ?
                         parent_out_valid : 1'b0;
    assign out_last_o = parent_out_last && out_valid_o;

    always @* begin
        parent_in_bits = '0;
        parent_in_count = '0;
        parent_in_valid = 1'b0;
        parent_out_ready = 1'b0;
        mask_out_ready = 1'b0;
        case (state_q)
            BASE_SELECTOR: begin
                parent_in_count = L;
                parent_in_valid = 1'b1;
                parent_out_ready = probe_base_ready;
            end
            BASE_DATA: begin
                parent_in_bits = data_bits_i;
                parent_in_count = data_count_i;
                parent_in_valid = data_valid_i;
                parent_out_ready = probe_base_ready;
            end
            BASE_WAIT: parent_out_ready = probe_base_ready;
            FINAL_SELECTOR: begin
                parent_in_bits = {{(W-L){1'b0}}, selector_o} << (W-L);
                parent_in_count = L;
                parent_in_valid = 1'b1;
                parent_out_ready = out_ready_i;
            end
            FINAL_DATA: begin
                parent_in_bits = masked_bits;
                parent_in_count = masked_count;
                parent_in_valid = masked_valid;
                mask_out_ready = parent_in_ready;
                parent_out_ready = out_ready_i;
            end
            FINAL_WAIT: parent_out_ready = out_ready_i;
            default: begin end
        endcase
    end

    bch_enc #(
        .K(K+L), .R(R), .W(W), .SPECIAL_COUNT(L), .GENERATOR(BCH_GENERATOR)
    ) bch_enc_u (
        .clk(clk), .reset_n(reset_n), .start_i(parent_start_q),
        .in_bits_i(parent_in_bits), .in_count_i(parent_in_count),
        .in_valid_i(parent_in_valid), .in_ready_o(parent_in_ready),
        .out_bits_o(parent_out_bits), .out_count_o(parent_out_count),
        .out_valid_o(parent_out_valid), .out_ready_i(parent_out_ready),
        .out_last_o(parent_out_last), .done_o(parent_done), .busy_o()
    );

    pbch_probe #(
        .L(L), .K(K), .R(R), .W(W),
        .MASK_POLYNOMIAL(MASK_POLYNOMIAL), .MASK_SEED(MASK_SEED),
        .PARITY_COLUMNS(PARITY_COLUMNS)
    ) probe_u (
        .clk(clk), .reset_n(reset_n), .start_i(probe_start_q),
        .base_bits_i(parent_out_bits), .base_count_i(parent_out_count),
        .base_valid_i(parent_out_valid && state_q <= BASE_WAIT),
        .base_ready_o(probe_base_ready), .probe_bits_i(probe_bits_i),
        .probe_count_i(probe_count_i), .probe_valid_i(probe_valid_i),
        .probe_ready_o(probe_stream_ready), .row_h_o(row_h), .row_rhs_o(row_rhs),
        .row_valid_o(row_valid), .row_ready_i(row_ready), .done_o(probe_done)
    );

    pbch_solve #(.L(L), .N(N)) solve_u (
        .clk(clk), .reset_n(reset_n), .start_i(solve_start_q),
        .row_h_i(row_h), .row_rhs_i(row_rhs), .row_valid_i(row_valid),
        .row_ready_o(row_ready), .finish_i(probe_done),
        .selector_o(solved_selector), .failures_o(solved_failures),
        .done_o(solve_done)
    );

    pbch_mask #(
        .L(L), .W(W), .MASK_POLYNOMIAL(MASK_POLYNOMIAL), .MASK_SEED(MASK_SEED)
    ) mask_u (
        .clk(clk), .reset_n(reset_n), .start_i(mask_start_q),
        .selector_i(selector_o), .in_bits_i(data_bits_i),
        .in_count_i(data_count_i), .in_valid_i(data_valid_i && state_q == FINAL_DATA),
        .in_ready_o(mask_data_ready), .out_bits_o(masked_bits),
        .out_count_o(masked_count), .out_valid_o(masked_valid),
        .out_ready_i(mask_out_ready)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            parent_start_q <= 1'b0;
            probe_start_q <= 1'b0;
            solve_start_q <= 1'b0;
            mask_start_q <= 1'b0;
            data_seen_q <= '0;
            replay_req_o <= 1'b0;
            selector_o <= '0;
            mask_failures_o <= '0;
            done_o <= 1'b0;
        end else begin
            parent_start_q <= 1'b0;
            probe_start_q <= 1'b0;
            solve_start_q <= 1'b0;
            mask_start_q <= 1'b0;
            replay_req_o <= 1'b0;
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    parent_start_q <= 1'b1;
                    probe_start_q <= 1'b1;
                    solve_start_q <= 1'b1;
                    data_seen_q <= '0;
                    state_q <= BASE_START;
                end
                BASE_START: state_q <= BASE_SELECTOR;
                BASE_SELECTOR: if (parent_in_valid && parent_in_ready) begin
                    data_seen_q <= '0;
                    state_q <= BASE_DATA;
                end
                BASE_DATA: if (data_valid_i && data_ready_o) begin
                    data_seen_q <= data_seen_q + data_count_i;
                    if (data_seen_q + data_count_i == K)
                        state_q <= BASE_WAIT;
                end
                BASE_WAIT: if (solve_done) begin
                    selector_o <= solved_selector;
                    mask_failures_o <= solved_failures;
                    replay_req_o <= 1'b1;
                    parent_start_q <= 1'b1;
                    mask_start_q <= 1'b1;
                    state_q <= FINAL_START;
                end
                FINAL_START: state_q <= FINAL_SELECTOR;
                FINAL_SELECTOR: if (parent_in_valid && parent_in_ready) begin
                    data_seen_q <= '0;
                    state_q <= FINAL_DATA;
                end
                FINAL_DATA: if (data_valid_i && data_ready_o) begin
                    data_seen_q <= data_seen_q + data_count_i;
                    if (data_seen_q + data_count_i == K)
                        state_q <= FINAL_WAIT;
                end
                FINAL_WAIT: if (parent_done) begin
                    done_o <= 1'b1;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
