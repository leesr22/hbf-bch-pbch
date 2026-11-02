`default_nettype none

// Systematic shortened-BCH encoder.  Valid bits occupy the MSB lanes and are
// processed from MSB to LSB.  The source may split information at any boundary;
// in_count_i states how many lanes are valid in the current beat.
module bch_enc #(
    parameter integer K = 4096,
    parameter integer R = 104,
    parameter integer W = 64,
    // Information beats are full W bits, except PBCH's leading selector beat.
    // Keeping that second size constant lets synthesis collapse both updates
    // into fixed GF(2) linear transforms instead of a W-way variable shifter.
    parameter integer SPECIAL_COUNT = 0,
    parameter [R:0] GENERATOR = '0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer TOTAL_W = $clog2(K + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    output wire                 start_ready_o,
    input  wire [W-1:0]         in_bits_i,
    input  wire [COUNT_W-1:0]   in_count_i,
    input  wire                 in_valid_i,
    output wire                 in_ready_o,
    output reg  [W-1:0]         out_bits_o,
    output reg  [COUNT_W-1:0]   out_count_o,
    output wire                 out_valid_o,
    input  wire                 out_ready_i,
    output reg                  out_last_o,
    output reg                  done_o,
    output wire                 busy_o
);
    localparam [1:0] IDLE = 2'd0, INFO = 2'd1, PARITY = 2'd2;
    localparam integer PARITY_COUNT_W = $clog2(R + 1);

    reg [1:0] state_q;
    reg [R-1:0] remainder_q;
    reg [TOTAL_W-1:0] info_seen_q;
    reg [PARITY_COUNT_W-1:0] parity_seen_q;
    reg [R-1:0] remainder_full;
    reg [R-1:0] remainder_special;
    integer update_lane;
    integer output_lane;
    integer valid_now;

    // The next frame may be announced while the final parity beat is accepted.
    // Its first information beat follows on the next cycle, so the output has
    // no inter-frame idle bubble.
    assign start_ready_o = (state_q == IDLE) ||
                           ((state_q == PARITY) && out_ready_i && out_last_o);
    assign busy_o = state_q != IDLE;
    assign in_ready_o = (state_q == INFO) && out_ready_i;
    assign out_valid_o = (state_q == INFO) ? in_valid_i : (state_q == PARITY);

    always @* begin
        remainder_full = remainder_q;
        for (update_lane = 0; update_lane < W; update_lane = update_lane + 1) begin
            if (in_bits_i[W-1-update_lane] ^ remainder_full[R-1])
                remainder_full = {remainder_full[R-2:0], 1'b0} ^ GENERATOR[R-1:0];
            else
                remainder_full = {remainder_full[R-2:0], 1'b0};
        end

        remainder_special = remainder_q;
        for (update_lane = 0; update_lane < W; update_lane = update_lane + 1) begin
            if (update_lane < SPECIAL_COUNT) begin
                if (in_bits_i[W-1-update_lane] ^ remainder_special[R-1])
                    remainder_special = {remainder_special[R-2:0], 1'b0} ^ GENERATOR[R-1:0];
                else
                    remainder_special = {remainder_special[R-2:0], 1'b0};
            end
        end
    end

    always @* begin
        out_bits_o = '0;
        out_count_o = '0;
        out_last_o = 1'b0;
        if (state_q == INFO) begin
            out_bits_o = in_bits_i;
            out_count_o = in_count_i;
        end else if (state_q == PARITY) begin
            valid_now = ((R - parity_seen_q) > W) ? W : (R - parity_seen_q);
            out_count_o = valid_now[COUNT_W-1:0];
            for (output_lane = 0; output_lane < W; output_lane = output_lane + 1)
                if (output_lane < valid_now)
                    out_bits_o[W-1-output_lane] = remainder_q[R-1-parity_seen_q-output_lane];
            out_last_o = (parity_seen_q + valid_now) == R;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            remainder_q <= '0;
            info_seen_q <= '0;
            parity_seen_q <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (start_i && state_q == IDLE) begin
                state_q <= INFO;
                remainder_q <= '0;
                info_seen_q <= '0;
                parity_seen_q <= '0;
            end else if (state_q == INFO && in_valid_i && in_ready_o) begin
                remainder_q <= (in_count_i == W) ? remainder_full : remainder_special;
                info_seen_q <= info_seen_q + in_count_i;
                if (info_seen_q + in_count_i == K) begin
                    state_q <= PARITY;
                    parity_seen_q <= '0;
                end
            end else if (state_q == PARITY && out_ready_i) begin
                valid_now = ((R - parity_seen_q) > W) ? W : (R - parity_seen_q);
                if (parity_seen_q + valid_now == R) begin
                    done_o <= 1'b1;
                    if (start_i) begin
                        state_q <= INFO;
                        remainder_q <= '0;
                        info_seen_q <= '0;
                        parity_seen_q <= '0;
                    end else begin
                        state_q <= IDLE;
                    end
                end else begin
                    parity_seen_q <= parity_seen_q + valid_now;
                end
            end
        end
    end
endmodule

`default_nettype wire
