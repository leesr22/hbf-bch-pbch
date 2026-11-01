`default_nettype none

// Returns the selector influence h_i for one codeword position.  Selector and
// message columns are generated structurally; only the 104 parity signatures
// are constants.  No N-by-L matrix is stored in flops.
module pbch_g0 #(
    parameter integer L = 3,
    parameter integer K = 4096,
    parameter integer R = 104,
    parameter integer W = 64,
    parameter [L:0] MASK_POLYNOMIAL = '0,
    parameter [(R*L)-1:0] PARITY_COLUMNS = '0,
    parameter integer POS_W = $clog2(L + K + R + 1),
    parameter integer LANE_W = (W <= 1) ? 1 : $clog2(W)
) (
    input  wire [POS_W-1:0]  beat_position_i,
    input  wire [LANE_W-1:0] lane_i,
    input  wire [L-1:0]       beat_mask_column_i,
    output reg  [L-1:0]       column_o
);
    function automatic [L-1:0] mask_step(input [L-1:0] state);
        reg carry;
        begin
            carry = state[L-1];
            mask_step = {state[L-2:0], 1'b0};
            if (carry)
                mask_step = mask_step ^ MASK_POLYNOMIAL[L-1:0];
        end
    endfunction

    integer position;
    integer parity_position;
    integer step;
    always @* begin
        position = beat_position_i + lane_i;
        column_o = '0;
        if (position < L) begin
            column_o[L-1-position] = 1'b1;
        end else if (position < L + K) begin
            column_o = beat_mask_column_i;
            for (step = 0; step < W; step = step + 1)
                if (step < lane_i)
                    column_o = mask_step(column_o);
        end else begin
            parity_position = position - L - K;
            if (parity_position < R)
                column_o = PARITY_COLUMNS[parity_position*L +: L];
        end
    end
endmodule

`default_nettype wire
