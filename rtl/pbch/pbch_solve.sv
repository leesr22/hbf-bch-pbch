`default_nettype none

// L=3: exact eight-candidate scoring.  L>3: a compact incremental GF(2)
// pivot basis.  Inconsistent new equations are dropped and counted; all kept
// equations are satisfied by the returned selector.
module pbch_solve #(
    parameter integer L = 3,
    parameter integer N = 4203,
    parameter integer FAIL_W = $clog2(N + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    input  wire [L-1:0]         row_h_i,
    input  wire                 row_rhs_i,
    input  wire                 row_valid_i,
    output wire                 row_ready_o,
    input  wire                 finish_i,
    output reg  [L-1:0]         selector_o,
    output reg  [FAIL_W-1:0]    failures_o,
    output reg                  done_o
);
    generate if (L <= 3) begin : exact_g
        localparam integer CANDIDATES = 1 << L;
        reg [FAIL_W-1:0] score_q [0:CANDIDATES-1];
        integer candidate;
        integer bit_index;
        integer mismatches;
        reg parity_value;
        reg [FAIL_W-1:0] best_score;
        reg [L-1:0] best_selector;

        assign row_ready_o = 1'b1;
        always @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                selector_o <= '0;
                failures_o <= '0;
                done_o <= 1'b0;
                for (candidate = 0; candidate < CANDIDATES; candidate = candidate + 1)
                    score_q[candidate] <= '0;
            end else begin
                done_o <= 1'b0;
                if (start_i) begin
                    for (candidate = 0; candidate < CANDIDATES; candidate = candidate + 1)
                        score_q[candidate] <= '0;
                end else if (row_valid_i) begin
                    for (candidate = 0; candidate < CANDIDATES; candidate = candidate + 1) begin
                        parity_value = 1'b0;
                        for (bit_index = 0; bit_index < L; bit_index = bit_index + 1)
                            parity_value = parity_value ^ (candidate[bit_index] & row_h_i[bit_index]);
                        if (parity_value != row_rhs_i)
                            score_q[candidate] <= score_q[candidate] + 1'b1;
                    end
                end
                if (finish_i) begin
                    best_score = score_q[0];
                    best_selector = '0;
                    for (mismatches = 1; mismatches < CANDIDATES; mismatches = mismatches + 1)
                        if (score_q[mismatches] < best_score) begin
                            best_score = score_q[mismatches];
                            best_selector = mismatches[L-1:0];
                        end
                    selector_o <= best_selector;
                    failures_o <= best_score;
                    done_o <= 1'b1;
                end
            end
        end
    end else begin : gaussian_g
        localparam integer INDEX_W = $clog2(L);
        reg [L:0] pivot_q [0:L-1];
        reg [L-1:0] valid_q;
        reg [L:0] reduced_row;
        reg insert_found;
        reg conflict;
        reg solving_q;
        reg [INDEX_W-1:0] solve_index_q;
        reg [L-1:0] selector_q;
        reg solve_bit;
        reg solve_parity;
        integer pivot;
        integer lower;

        assign row_ready_o = !solving_q;
        always @* begin
            reduced_row = {row_rhs_i, row_h_i};
            insert_found = 1'b0;
            for (pivot = L-1; pivot >= 0; pivot = pivot - 1)
                if (!insert_found && reduced_row[pivot]) begin
                    if (valid_q[pivot])
                        reduced_row = reduced_row ^ pivot_q[pivot];
                    else
                        insert_found = 1'b1;
                end
            conflict = !insert_found && (reduced_row[L-1:0] == 0) && reduced_row[L];

            solve_parity = 1'b0;
            for (lower = 0; lower < L; lower = lower + 1)
                if (lower < solve_index_q)
                    solve_parity = solve_parity ^
                                   (pivot_q[solve_index_q][lower] & selector_q[lower]);
            solve_bit = valid_q[solve_index_q] ?
                        (pivot_q[solve_index_q][L] ^ solve_parity) : 1'b0;
        end

        always @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                valid_q <= '0;
                solving_q <= 1'b0;
                solve_index_q <= '0;
                selector_q <= '0;
                selector_o <= '0;
                failures_o <= '0;
                done_o <= 1'b0;
                for (pivot = 0; pivot < L; pivot = pivot + 1)
                    pivot_q[pivot] <= '0;
            end else begin
                done_o <= 1'b0;
                if (start_i) begin
                    valid_q <= '0;
                    solving_q <= 1'b0;
                    selector_q <= '0;
                    failures_o <= '0;
                    for (pivot = 0; pivot < L; pivot = pivot + 1)
                        pivot_q[pivot] <= '0;
                end else if (row_valid_i && row_ready_o) begin
                    if (insert_found) begin
                        for (pivot = 0; pivot < L; pivot = pivot + 1)
                            if (!valid_q[pivot] && reduced_row[pivot] &&
                                ((reduced_row & (((1 << L)-1) & ~((1 << (pivot+1))-1))) == 0)) begin
                                pivot_q[pivot] <= reduced_row;
                                valid_q[pivot] <= 1'b1;
                            end
                    end else if (conflict) begin
                        failures_o <= failures_o + 1'b1;
                    end
                end

                if (finish_i) begin
                    solving_q <= 1'b1;
                    solve_index_q <= '0;
                    selector_q <= '0;
                end else if (solving_q) begin
                    selector_q[solve_index_q] <= solve_bit;
                    if (solve_index_q == L-1) begin
                        selector_o <= selector_q;
                        selector_o[solve_index_q] <= solve_bit;
                        solving_q <= 1'b0;
                        done_o <= 1'b1;
                    end else begin
                        solve_index_q <= solve_index_q + 1'b1;
                    end
                end
            end
        end
    end endgenerate
endmodule

`default_nettype wire
