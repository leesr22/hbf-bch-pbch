`default_nettype none

// Applies dM to full-W beats of a 4096-bit message.  Every supported W divides
// 4096, so there is no partial data beat.  Keeping that fact explicit removes a
// variable-count mux chain from the mask datapath.  The LFSR describes constant
// columns of M, so the only state is L bits regardless of K.
module pbch_mask #(
    parameter integer L = 3,
    parameter integer W = 64,
    parameter [L:0] MASK_POLYNOMIAL = '0,
    parameter [L-1:0] MASK_SEED = {{(L-1){1'b0}},1'b1},
    parameter integer COUNT_W = $clog2(W + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    input  wire [L-1:0]         selector_i,
    input  wire [W-1:0]         in_bits_i,
    input  wire [COUNT_W-1:0]   in_count_i,
    input  wire                 in_valid_i,
    output wire                 in_ready_o,
    output reg  [W-1:0]         out_bits_o,
    output wire [COUNT_W-1:0]   out_count_o,
    output wire                 out_valid_o,
    input  wire                 out_ready_i
);
    reg [L-1:0] column_q;
    reg [L-1:0] column_work;
    reg mask_bit;
    integer lane;
    integer selector_bit;

    function automatic [L-1:0] mask_step(input [L-1:0] state);
        reg carry;
        begin
            carry = state[L-1];
            mask_step = {state[L-2:0], 1'b0};
            if (carry)
                mask_step = mask_step ^ MASK_POLYNOMIAL[L-1:0];
        end
    endfunction

    assign in_ready_o = out_ready_i;
    assign out_valid_o = in_valid_i;
    assign out_count_o = in_count_i;
    always @* begin
        out_bits_o = in_bits_i;
        column_work = column_q;
        for (lane = 0; lane < W; lane = lane + 1) begin
            mask_bit = 1'b0;
            for (selector_bit = 0; selector_bit < L; selector_bit = selector_bit + 1)
                mask_bit = mask_bit ^ (selector_i[selector_bit] & column_work[selector_bit]);
            out_bits_o[W-1-lane] = in_bits_i[W-1-lane] ^ mask_bit;
            column_work = mask_step(column_work);
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            column_q <= MASK_SEED;
        else if (start_i)
            column_q <= MASK_SEED;
        else if (in_valid_i && in_ready_o)
            column_q <= column_work;
    end

`ifndef SYNTHESIS
    always @(posedge clk)
        if (reset_n && in_valid_i && in_ready_o && in_count_i != W[COUNT_W-1:0])
            $error("pbch_mask expects full-W user-data beats");
`endif
endmodule

`default_nettype wire
