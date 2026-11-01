`default_nettype none

// Joins the base codeword c(0) with the pre-read defect bitmap.  Empty beats
// pass at one beat/cycle; a beat containing defects is held while one compact
// equation h_i*d=c(0)_i is emitted per cycle.
module pbch_probe #(
    parameter integer L = 3,
    parameter integer K = 4096,
    parameter integer R = 104,
    parameter integer W = 64,
    parameter [L:0] MASK_POLYNOMIAL = '0,
    parameter [L-1:0] MASK_SEED = {{(L-1){1'b0}},1'b1},
    parameter [(R*L)-1:0] PARITY_COLUMNS = '0,
    parameter integer N = L + K + R,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer POS_W = $clog2(N + 1),
    parameter integer LANE_W = (W <= 1) ? 1 : $clog2(W)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    input  wire [W-1:0]         base_bits_i,
    input  wire [COUNT_W-1:0]   base_count_i,
    input  wire                 base_valid_i,
    output wire                 base_ready_o,
    input  wire [W-1:0]         probe_bits_i,
    input  wire [COUNT_W-1:0]   probe_count_i,
    input  wire                 probe_valid_i,
    output wire                 probe_ready_o,
    output wire [L-1:0]         row_h_o,
    output wire                 row_rhs_o,
    output wire                 row_valid_o,
    input  wire                 row_ready_i,
    output reg                  done_o
);
    reg [W-1:0] base_q;
    reg [W-1:0] defects_q;
    reg [POS_W-1:0] buffer_position_q;
    reg [L-1:0] buffer_mask_column_q;
    reg [POS_W-1:0] next_position_q;
    reg [L-1:0] next_mask_column_q;
    reg buffer_valid_q;
    reg last_buffer_q;
    reg [LANE_W-1:0] selected_lane;
    reg selected_found;
    reg [W-1:0] valid_mask;
    reg [L-1:0] advanced_column;
    integer lane;
    integer advance;

    function automatic [L-1:0] mask_step(input [L-1:0] state);
        reg carry;
        begin
            carry = state[L-1];
            mask_step = {state[L-2:0], 1'b0};
            if (carry)
                mask_step = mask_step ^ MASK_POLYNOMIAL[L-1:0];
        end
    endfunction

    always @* begin
        valid_mask = '0;
        for (lane = 0; lane < W; lane = lane + 1)
            if (lane < base_count_i)
                valid_mask[W-1-lane] = 1'b1;

        selected_found = 1'b0;
        selected_lane = '0;
        for (lane = 0; lane < W; lane = lane + 1) begin
            if (!selected_found && defects_q[W-1-lane]) begin
                selected_found = 1'b1;
                selected_lane = lane[LANE_W-1:0];
            end
        end

        advanced_column = next_mask_column_q;
        if ((next_position_q >= L) && (next_position_q < L + K)) begin
            for (advance = 0; advance < W; advance = advance + 1)
                if (advance < base_count_i)
                    advanced_column = mask_step(advanced_column);
        end
    end

    assign base_ready_o = !buffer_valid_q && probe_valid_i;
    assign probe_ready_o = !buffer_valid_q && base_valid_i;
    assign row_valid_o = buffer_valid_q && selected_found;
    assign row_rhs_o = base_q[W-1-selected_lane];

    pbch_g0 #(
        .L(L), .K(K), .R(R), .W(W), .MASK_POLYNOMIAL(MASK_POLYNOMIAL),
        .PARITY_COLUMNS(PARITY_COLUMNS)
    ) g0_u (
        .beat_position_i(buffer_position_q), .lane_i(selected_lane),
        .beat_mask_column_i(buffer_mask_column_q), .column_o(row_h_o)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            base_q <= '0;
            defects_q <= '0;
            buffer_position_q <= '0;
            buffer_mask_column_q <= MASK_SEED;
            next_position_q <= '0;
            next_mask_column_q <= MASK_SEED;
            buffer_valid_q <= 1'b0;
            last_buffer_q <= 1'b0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (start_i) begin
                next_position_q <= '0;
                next_mask_column_q <= MASK_SEED;
                buffer_valid_q <= 1'b0;
                last_buffer_q <= 1'b0;
            end else if (base_valid_i && base_ready_o) begin
                base_q <= base_bits_i;
                defects_q <= probe_bits_i & valid_mask;
                buffer_position_q <= next_position_q;
                buffer_mask_column_q <= next_mask_column_q;
                next_position_q <= next_position_q + base_count_i;
                next_mask_column_q <= advanced_column;
                if ((probe_bits_i & valid_mask) != 0) begin
                    buffer_valid_q <= 1'b1;
                    last_buffer_q <= (next_position_q + base_count_i) == N;
                end else if ((next_position_q + base_count_i) == N) begin
                    done_o <= 1'b1;
                end
            end else if (row_valid_o && row_ready_i) begin
                defects_q[W-1-selected_lane] <= 1'b0;
                if ((defects_q & ~( {{(W-1){1'b0}},1'b1} << (W-1-selected_lane))) == 0) begin
                    buffer_valid_q <= 1'b0;
                    if (last_buffer_q)
                        done_o <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // The two streams describe the same beat and therefore must agree.
    always @(posedge clk)
        if (reset_n && base_valid_i && probe_valid_i && !buffer_valid_q &&
            (base_count_i != probe_count_i))
            $error("PBCH base/probe count mismatch");
`endif
endmodule

`default_nettype wire
