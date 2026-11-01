`timescale 1ns/1ps
`default_nettype none

`ifndef ENC_TOP
  `define ENC_TOP pbch_d1_enc_w64
`endif
`ifndef DEC_TOP
  `define DEC_TOP pbch_d1_dec_w64
`endif
`ifndef L_BITS
  `define L_BITS 3
`endif
`ifndef W_BITS
  `define W_BITS 64
`endif

module pbch_profile_tb;
    localparam integer K = 4096;
    localparam integer L = `L_BITS;
    localparam integer R = 104;
    localparam integer T = 8;
    localparam integer W = `W_BITS;
    localparam integer INFO_BEATS = (K+W-1)/W;
    localparam integer CW_BEATS = 1 + INFO_BEATS + (R+W-1)/W;
    localparam integer COUNT_W = $clog2(W+1);
    localparam integer FAIL_W = $clog2(L+K+R+1);

    reg clk = 0;
    reg reset_n = 0;
    always #1 clk = ~clk;

    reg [W-1:0] message_mem [0:INFO_BEATS-1];
    reg [W-1:0] probe_mem [0:CW_BEATS-1];
    reg [W-1:0] codeword_mem [0:CW_BEATS-1];
    reg [W-1:0] received_mem [0:CW_BEATS-1];
    string vec_dir;
    integer expected_selector;
    integer expected_failures;
    integer failures;
    integer enc_out_index;
    integer dec_out_index;
    integer cycles;
    integer enc_start_cycle;
    integer dec_start_cycle;

    reg enc_start;
    reg [W-1:0] data_bits;
    reg [COUNT_W-1:0] data_count;
    reg data_valid;
    wire data_ready;
    wire enc_replay_req;
    reg [W-1:0] probe_bits;
    reg [COUNT_W-1:0] probe_count;
    reg probe_valid;
    wire probe_ready;
    wire [W-1:0] enc_out_bits;
    wire [COUNT_W-1:0] enc_out_count;
    wire enc_out_valid;
    reg enc_out_ready;
    wire enc_out_last;
    wire [L-1:0] selected;
    wire [FAIL_W-1:0] mask_failures;
    wire enc_done;
    wire enc_busy;

    reg dec_start;
    reg [W-1:0] code_bits;
    reg [COUNT_W-1:0] code_count;
    reg code_valid;
    wire code_ready;
    wire dec_replay_req;
    reg [W-1:0] replay_bits;
    reg [COUNT_W-1:0] replay_count;
    reg replay_valid;
    wire replay_ready;
    wire [W-1:0] info_bits;
    wire [COUNT_W-1:0] info_count;
    wire info_valid;
    reg info_ready;
    wire [L-1:0] decoded_selector;
    wire dec_done;
    wire dec_success;
    wire [$clog2(T+1)-1:0] error_count;
    wire dec_busy;

    `ENC_TOP enc_u (
        .clk(clk),.reset_n(reset_n),.start_i(enc_start),
        .data_bits_i(data_bits),.data_count_i(data_count),.data_valid_i(data_valid),
        .data_ready_o(data_ready),.replay_req_o(enc_replay_req),
        .probe_bits_i(probe_bits),.probe_count_i(probe_count),.probe_valid_i(probe_valid),
        .probe_ready_o(probe_ready),.out_bits_o(enc_out_bits),.out_count_o(enc_out_count),
        .out_valid_o(enc_out_valid),.out_ready_i(enc_out_ready),.out_last_o(enc_out_last),
        .selector_o(selected),.mask_failures_o(mask_failures),.done_o(enc_done),.busy_o(enc_busy)
    );

    `DEC_TOP dec_u (
        .clk(clk),.reset_n(reset_n),.start_i(dec_start),
        .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),
        .code_ready_o(code_ready),.replay_req_o(dec_replay_req),
        .replay_bits_i(replay_bits),.replay_count_i(replay_count),
        .replay_valid_i(replay_valid),.replay_ready_o(replay_ready),
        .info_bits_o(info_bits),.info_count_o(info_count),.info_valid_o(info_valid),
        .info_ready_i(info_ready),.selector_o(decoded_selector),.done_o(dec_done),
        .success_o(dec_success),.error_count_o(error_count),.busy_o(dec_busy)
    );

    function automatic integer code_count_at(input integer beat);
        integer parity_beat;
        begin
            if (beat == 0)
                code_count_at = L;
            else if (beat <= INFO_BEATS)
                code_count_at = (beat == INFO_BEATS) ? K-W*(INFO_BEATS-1) : W;
            else begin
                parity_beat = beat - INFO_BEATS - 1;
                code_count_at = (parity_beat == (R+W-1)/W-1) ?
                                R-W*parity_beat : W;
            end
        end
    endfunction

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (reset_n && enc_out_valid && enc_out_ready) begin
            if (enc_out_index >= CW_BEATS || enc_out_bits !== codeword_mem[enc_out_index]) begin
                $display("ERROR PBCH encoder beat %0d expected %h got %h",
                         enc_out_index, codeword_mem[enc_out_index], enc_out_bits);
                failures = failures + 1;
            end
            if (enc_out_count !== code_count_at(enc_out_index)) begin
                $display("ERROR PBCH encoder count beat %0d", enc_out_index);
                failures = failures + 1;
            end
            enc_out_index = enc_out_index + 1;
        end
        if (reset_n && info_valid && info_ready) begin
            if (dec_out_index >= INFO_BEATS || info_bits !== message_mem[dec_out_index]) begin
                $display("ERROR PBCH decoder beat %0d expected %h got %h",
                         dec_out_index, message_mem[dec_out_index], info_bits);
                failures = failures + 1;
            end
            dec_out_index = dec_out_index + 1;
        end
    end

    task automatic pulse_enc_start;
        begin
            @(negedge clk); enc_start = 1;
            @(negedge clk); enc_start = 0;
        end
    endtask

    task automatic drive_data_pass;
        integer beat;
        begin
            beat = 0;
            while (beat < INFO_BEATS) begin
                @(negedge clk);
                data_valid = 1;
                data_bits = message_mem[beat];
                data_count = (beat == INFO_BEATS-1) ? K-W*(INFO_BEATS-1) : W;
                if (data_ready)
                    beat = beat + 1;
            end
            @(negedge clk); data_valid = 0;
        end
    endtask

    task automatic drive_probe_pass;
        integer beat;
        begin
            beat = 0;
            while (beat < CW_BEATS) begin
                @(negedge clk);
                probe_valid = 1;
                probe_bits = probe_mem[beat];
                probe_count = code_count_at(beat);
                if (probe_ready)
                    beat = beat + 1;
            end
            @(negedge clk); probe_valid = 0;
        end
    endtask

    task automatic pulse_dec_start;
        begin
            @(negedge clk); dec_start = 1;
            @(negedge clk); dec_start = 0;
        end
    endtask

    task automatic drive_codeword(input bit replay_phase);
        integer beat;
        begin
            beat = 0;
            while (beat < CW_BEATS) begin
                @(negedge clk);
                if (!replay_phase) begin
                    code_valid = 1;
                    code_bits = received_mem[beat];
                    code_count = code_count_at(beat);
                    if (code_ready) beat = beat + 1;
                end else begin
                    replay_valid = 1;
                    replay_bits = received_mem[beat];
                    replay_count = code_count_at(beat);
                    if (replay_ready) beat = beat + 1;
                end
            end
            @(negedge clk);
            if (!replay_phase) code_valid = 0;
            else replay_valid = 0;
        end
    endtask

    initial begin
        failures = 0; enc_out_index = 0; dec_out_index = 0; cycles = 0;
        enc_start=0; data_bits=0; data_count=0; data_valid=0;
        probe_bits=0; probe_count=0; probe_valid=0; enc_out_ready=1;
        dec_start=0; code_bits=0; code_count=0; code_valid=0;
        replay_bits=0; replay_count=0; replay_valid=0; info_ready=1;
        if (!$value$plusargs("VEC_DIR=%s", vec_dir) ||
            !$value$plusargs("EXPECT_SELECTOR=%d", expected_selector) ||
            !$value$plusargs("EXPECT_FAILURES=%d", expected_failures)) begin
            $display("ERROR missing plusargs"); $finish(2);
        end
        $readmemh({vec_dir,"/message.mem"},message_mem);
        $readmemh({vec_dir,"/probe.mem"},probe_mem);
        $readmemh({vec_dir,"/codeword.mem"},codeword_mem);
        $readmemh({vec_dir,"/received.mem"},received_mem);
        repeat(4) @(negedge clk); reset_n=1;

        enc_start_cycle = cycles;
        pulse_enc_start();
        fork
            drive_probe_pass();
            begin
                drive_data_pass();
                wait(enc_replay_req);
                drive_data_pass();
            end
        join
        wait(enc_done);
        $display("METRIC encoder_cycles=%0d",cycles-enc_start_cycle);
        if (selected != expected_selector || mask_failures != expected_failures) begin
            $display("ERROR selector/failures expected %0d/%0d got %0d/%0d",
                     expected_selector, expected_failures, selected, mask_failures);
            failures = failures + 1;
        end
        if (enc_out_index != CW_BEATS) begin
            $display("ERROR encoder produced %0d/%0d beats",enc_out_index,CW_BEATS);
            failures = failures + 1;
        end

        dec_start_cycle = cycles;
        pulse_dec_start();
        drive_codeword(0);
        wait(dec_replay_req);
        drive_codeword(1);
        wait(dec_done);
        $display("METRIC decoder_cycles=%0d",cycles-dec_start_cycle);
        if (!dec_success || error_count != T || decoded_selector != expected_selector) begin
            $display("ERROR decoder status success=%0d errors=%0d selector=%0d",
                     dec_success,error_count,decoded_selector);
            failures = failures + 1;
        end
        if (dec_out_index != INFO_BEATS) begin
            $display("ERROR decoder produced %0d/%0d beats",dec_out_index,INFO_BEATS);
            failures = failures + 1;
        end
        if (failures == 0)
            $display("PASS PBCH K=%0d L=%0d T=%0d W=%0d",K,L,T,W);
        else
            $display("FAIL PBCH failures=%0d",failures);
        $finish(failures != 0);
    end

    initial begin
        #4000000; $display("ERROR timeout"); $finish(3);
    end
endmodule

`default_nettype wire
