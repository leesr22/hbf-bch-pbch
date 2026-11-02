`default_nettype none

// Two-stage inter-frame PBCH encoder.
//
// PREP streams c(0) with the pre-read bitmap and solves for d. EMIT replays the
// user data, applies dM, and emits BCH([d | message XOR dM]). Separate BCH cores
// let PREP(frame i+1) overlap EMIT(frame i). The page data remains external.
module pbch_enc #(
    parameter integer L = 3,
    parameter integer K = 4096,
    parameter integer R = 104,
    parameter integer W = 64,
    parameter [R:0] BCH_GENERATOR = '0,
    parameter [L:0] MASK_POLYNOMIAL = '0,
    parameter [L-1:0] MASK_SEED = {{(L-1){1'b0}},1'b1},
    parameter [(R*L)-1:0] PARITY_COLUMNS = '0,
    parameter integer EXACT_SOLVER = (L <= 3),
    parameter integer PIPELINED_SOLVER = 0,
    parameter integer PIVOTS_PER_STAGE = 2,
    parameter integer N = L + K + R,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer DATA_W = $clog2(K + 1),
    parameter integer FAIL_W = $clog2(N + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    output wire                 start_ready_o,
    input  wire [W-1:0]         data_bits_i,
    input  wire [COUNT_W-1:0]   data_count_i,
    input  wire                 data_valid_i,
    output wire                 data_ready_o,
    output reg                  replay_req_o,
    input  wire [W-1:0]         replay_bits_i,
    input  wire [COUNT_W-1:0]   replay_count_i,
    input  wire                 replay_valid_i,
    output wire                 replay_ready_o,
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
    localparam [2:0] PREP_IDLE = 3'd0, PREP_START = 3'd1,
                     PREP_SELECTOR = 3'd2, PREP_DATA = 3'd3,
                     PREP_WAIT = 3'd4;
    localparam [2:0] EMIT_IDLE = 3'd0, EMIT_START = 3'd1,
                     EMIT_SELECTOR = 3'd2, EMIT_DATA = 3'd3,
                     EMIT_WAIT = 3'd4;

    reg [2:0] prep_state_q;
    reg [2:0] emit_state_q;
    reg base_start_q;
    reg final_start_q;
    reg probe_start_q;
    reg solve_start_q;
    reg mask_start_q;
    reg [DATA_W-1:0] prep_seen_q;
    reg [DATA_W-1:0] emit_seen_q;

    reg result_valid_q;
    reg [L-1:0] result_selector_q;
    reg [FAIL_W-1:0] result_failures_q;

    reg [W-1:0] base_in_bits;
    reg [COUNT_W-1:0] base_in_count;
    reg base_in_valid;
    wire base_in_ready;
    wire [W-1:0] base_out_bits;
    wire [COUNT_W-1:0] base_out_count;
    wire base_out_valid;
    reg base_out_ready;
    wire base_done;
    wire base_start_ready;

    reg [W-1:0] final_in_bits;
    reg [COUNT_W-1:0] final_in_count;
    reg final_in_valid;
    wire final_in_ready;
    wire final_done;
    wire final_start_ready;

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

    wire emit_pop = (emit_state_q == EMIT_IDLE) && result_valid_q;
    assign start_ready_o = (prep_state_q == PREP_IDLE) &&
                           (!result_valid_q || emit_pop);
    assign busy_o = (prep_state_q != PREP_IDLE) ||
                    (emit_state_q != EMIT_IDLE) || result_valid_q;
    assign data_ready_o = (prep_state_q == PREP_DATA) ? base_in_ready : 1'b0;
    assign replay_ready_o = (emit_state_q == EMIT_DATA) ? mask_data_ready : 1'b0;
    assign probe_ready_o = (prep_state_q >= PREP_SELECTOR &&
                            prep_state_q <= PREP_WAIT) ? probe_stream_ready : 1'b0;

    always @* begin
        base_in_bits = '0;
        base_in_count = '0;
        base_in_valid = 1'b0;
        base_out_ready = 1'b0;
        case (prep_state_q)
            PREP_SELECTOR: begin
                base_in_count = L;
                base_in_valid = 1'b1;
                base_out_ready = probe_base_ready;
            end
            PREP_DATA: begin
                base_in_bits = data_bits_i;
                base_in_count = data_count_i;
                base_in_valid = data_valid_i;
                base_out_ready = probe_base_ready;
            end
            PREP_WAIT: base_out_ready = probe_base_ready;
            default: begin end
        endcase
    end

    always @* begin
        final_in_bits = '0;
        final_in_count = '0;
        final_in_valid = 1'b0;
        mask_out_ready = 1'b0;
        case (emit_state_q)
            EMIT_SELECTOR: begin
                final_in_bits = {{(W-L){1'b0}}, selector_o} << (W-L);
                final_in_count = L;
                final_in_valid = 1'b1;
            end
            EMIT_DATA: begin
                final_in_bits = masked_bits;
                final_in_count = masked_count;
                final_in_valid = masked_valid;
                mask_out_ready = final_in_ready;
            end
            default: begin end
        endcase
    end

    bch_enc #(
        .K(K+L), .R(R), .W(W), .SPECIAL_COUNT(L), .GENERATOR(BCH_GENERATOR)
    ) base_enc_u (
        .clk(clk), .reset_n(reset_n), .start_i(base_start_q),
        .start_ready_o(base_start_ready),
        .in_bits_i(base_in_bits), .in_count_i(base_in_count),
        .in_valid_i(base_in_valid), .in_ready_o(base_in_ready),
        .out_bits_o(base_out_bits), .out_count_o(base_out_count),
        .out_valid_o(base_out_valid), .out_ready_i(base_out_ready),
        .out_last_o(), .done_o(base_done), .busy_o()
    );

    bch_enc #(
        .K(K+L), .R(R), .W(W), .SPECIAL_COUNT(L), .GENERATOR(BCH_GENERATOR)
    ) final_enc_u (
        .clk(clk), .reset_n(reset_n), .start_i(final_start_q),
        .start_ready_o(final_start_ready),
        .in_bits_i(final_in_bits), .in_count_i(final_in_count),
        .in_valid_i(final_in_valid), .in_ready_o(final_in_ready),
        .out_bits_o(out_bits_o), .out_count_o(out_count_o),
        .out_valid_o(out_valid_o), .out_ready_i(out_ready_i),
        .out_last_o(out_last_o), .done_o(final_done), .busy_o()
    );

    pbch_probe #(
        .L(L), .K(K), .R(R), .W(W),
        .MASK_POLYNOMIAL(MASK_POLYNOMIAL), .MASK_SEED(MASK_SEED),
        .PARITY_COLUMNS(PARITY_COLUMNS)
    ) probe_u (
        .clk(clk), .reset_n(reset_n), .start_i(probe_start_q),
        .base_bits_i(base_out_bits), .base_count_i(base_out_count),
        .base_valid_i(base_out_valid && prep_state_q <= PREP_WAIT),
        .base_ready_o(probe_base_ready), .probe_bits_i(probe_bits_i),
        .probe_count_i(probe_count_i), .probe_valid_i(probe_valid_i),
        .probe_ready_o(probe_stream_ready), .row_h_o(row_h), .row_rhs_o(row_rhs),
        .row_valid_o(row_valid), .row_ready_i(row_ready), .done_o(probe_done)
    );

    pbch_solve #(
        .L(L), .N(N), .EXACT_SOLVER(EXACT_SOLVER),
        .PIPELINED_SOLVER(PIPELINED_SOLVER),
        .PIVOTS_PER_STAGE(PIVOTS_PER_STAGE)
    ) solve_u (
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
        .selector_i(selector_o), .in_bits_i(replay_bits_i),
        .in_count_i(replay_count_i),
        .in_valid_i(replay_valid_i && emit_state_q == EMIT_DATA),
        .in_ready_o(mask_data_ready), .out_bits_o(masked_bits),
        .out_count_o(masked_count), .out_valid_o(masked_valid),
        .out_ready_i(mask_out_ready)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            prep_state_q <= PREP_IDLE;
            emit_state_q <= EMIT_IDLE;
            base_start_q <= 1'b0;
            final_start_q <= 1'b0;
            probe_start_q <= 1'b0;
            solve_start_q <= 1'b0;
            mask_start_q <= 1'b0;
            prep_seen_q <= '0;
            emit_seen_q <= '0;
            result_valid_q <= 1'b0;
            result_selector_q <= '0;
            result_failures_q <= '0;
            replay_req_o <= 1'b0;
            selector_o <= '0;
            mask_failures_o <= '0;
            done_o <= 1'b0;
        end else begin
            base_start_q <= 1'b0;
            final_start_q <= 1'b0;
            probe_start_q <= 1'b0;
            solve_start_q <= 1'b0;
            mask_start_q <= 1'b0;
            replay_req_o <= 1'b0;
            done_o <= 1'b0;

            if (start_i && start_ready_o) begin
                base_start_q <= 1'b1;
                probe_start_q <= 1'b1;
                solve_start_q <= 1'b1;
                prep_seen_q <= '0;
                prep_state_q <= PREP_START;
            end else begin
                case (prep_state_q)
                    PREP_START: prep_state_q <= PREP_SELECTOR;
                    PREP_SELECTOR: if (base_in_valid && base_in_ready) begin
                        prep_seen_q <= '0;
                        prep_state_q <= PREP_DATA;
                    end
                    PREP_DATA: if (data_valid_i && data_ready_o) begin
                        prep_seen_q <= prep_seen_q + data_count_i;
                        if (prep_seen_q + data_count_i == K)
                            prep_state_q <= PREP_WAIT;
                    end
                    PREP_WAIT: if (solve_done) begin
                        result_selector_q <= solved_selector;
                        result_failures_q <= solved_failures;
                        result_valid_q <= 1'b1;
                        prep_state_q <= PREP_IDLE;
                    end
                    default: begin end
                endcase
            end

            if (emit_pop) begin
                selector_o <= result_selector_q;
                mask_failures_o <= result_failures_q;
                result_valid_q <= 1'b0;
                final_start_q <= 1'b1;
                mask_start_q <= 1'b1;
                replay_req_o <= 1'b1;
                emit_seen_q <= '0;
                emit_state_q <= EMIT_START;
            end else begin
                case (emit_state_q)
                    EMIT_START: emit_state_q <= EMIT_SELECTOR;
                    EMIT_SELECTOR: if (final_in_valid && final_in_ready) begin
                        emit_seen_q <= '0;
                        emit_state_q <= EMIT_DATA;
                    end
                    EMIT_DATA: if (replay_valid_i && replay_ready_o) begin
                        emit_seen_q <= emit_seen_q + replay_count_i;
                        if (emit_seen_q + replay_count_i == K)
                            emit_state_q <= EMIT_WAIT;
                    end
                    EMIT_WAIT: if (final_done) begin
                        done_o <= 1'b1;
                        emit_state_q <= EMIT_IDLE;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
