`timescale 1ns/1ps
`default_nettype none

// Compile-time settings make the same testbench exercise every generated
// profile/width wrapper.  The vector directory is supplied with +VEC_DIR=...
`ifndef ENC_TOP
  `define ENC_TOP bch_d1_enc_w64
`endif
`ifndef DEC_TOP
  `define DEC_TOP bch_d1_dec_w64
`endif
`ifndef K_BITS
  `define K_BITS 4096
`endif
`ifndef R_BITS
  `define R_BITS 156
`endif
`ifndef T_BITS
  `define T_BITS 12
`endif
`ifndef W_BITS
  `define W_BITS 64
`endif

module bch_profile_tb;
    localparam integer K = `K_BITS;
    localparam integer R = `R_BITS;
    localparam integer T = `T_BITS;
    localparam integer W = `W_BITS;
    localparam integer CW_BEATS = ((K + W - 1) / W) + ((R + W - 1) / W);
    localparam integer INFO_BEATS = (K + W - 1) / W;
    localparam integer COUNT_W = $clog2(W + 1);
    localparam integer DEG_W = $clog2(T + 1);

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    always #1 clk = ~clk;

    reg [W-1:0] message_mem [0:INFO_BEATS-1];
    reg [W-1:0] codeword_mem [0:CW_BEATS-1];
    reg [W-1:0] received_mem [0:CW_BEATS-1];
    string vec_dir;

    reg enc_start;
    wire enc_start_ready;
    reg [W-1:0] enc_in_bits;
    reg [COUNT_W-1:0] enc_in_count;
    reg enc_in_valid;
    wire enc_in_ready;
    wire [W-1:0] enc_out_bits;
    wire [COUNT_W-1:0] enc_out_count;
    wire enc_out_valid;
    reg enc_out_ready;
    wire enc_out_last;
    wire enc_done;
    wire enc_busy;

    reg dec_start;
    wire dec_start_ready;
    reg [W-1:0] code_bits;
    reg [COUNT_W-1:0] code_count;
    reg code_valid;
    wire code_ready;
    wire replay_req;
    reg [W-1:0] replay_bits;
    reg [COUNT_W-1:0] replay_count;
    reg replay_valid;
    wire replay_ready;
    wire [W-1:0] info_bits;
    wire [COUNT_W-1:0] info_count;
    wire info_valid;
    reg info_ready;
    wire dec_done;
    wire dec_success;
    wire [DEG_W-1:0] error_count;
    wire dec_busy;

    integer enc_out_index;
    integer dec_out_index;
    integer failures;
    integer cycles;
    integer enc_start_cycle;
    integer dec_start_cycle;

    `ENC_TOP enc_u (
        .clk(clk), .reset_n(reset_n), .start_i(enc_start),
        .start_ready_o(enc_start_ready),
        .in_bits_i(enc_in_bits), .in_count_i(enc_in_count),
        .in_valid_i(enc_in_valid), .in_ready_o(enc_in_ready),
        .out_bits_o(enc_out_bits), .out_count_o(enc_out_count),
        .out_valid_o(enc_out_valid), .out_ready_i(enc_out_ready),
        .out_last_o(enc_out_last), .done_o(enc_done), .busy_o(enc_busy)
    );

    `DEC_TOP dec_u (
        .clk(clk), .reset_n(reset_n), .start_i(dec_start),
        .start_ready_o(dec_start_ready),
        .code_bits_i(code_bits), .code_count_i(code_count),
        .code_valid_i(code_valid), .code_ready_o(code_ready),
        .replay_req_o(replay_req), .replay_bits_i(replay_bits),
        .replay_count_i(replay_count), .replay_valid_i(replay_valid),
        .replay_ready_o(replay_ready), .info_bits_o(info_bits),
        .info_count_o(info_count), .info_valid_o(info_valid),
        .info_ready_i(info_ready), .done_o(dec_done),
        .success_o(dec_success), .error_count_o(error_count), .busy_o(dec_busy)
    );

    function automatic integer code_count_at(input integer beat);
        integer parity_beat;
        begin
            if (beat < INFO_BEATS-1)
                code_count_at = W;
            else if (beat == INFO_BEATS-1)
                code_count_at = K - W*(INFO_BEATS-1);
            else begin
                parity_beat = beat - INFO_BEATS;
                if (parity_beat < (R+W-1)/W-1)
                    code_count_at = W;
                else
                    code_count_at = R - W*parity_beat;
            end
        end
    endfunction

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (reset_n && enc_out_valid && enc_out_ready) begin
            if (enc_out_index >= CW_BEATS) begin
                $display("ERROR encoder emitted an extra beat");
                failures = failures + 1;
            end else begin
                if (enc_out_bits !== codeword_mem[enc_out_index]) begin
                    $display("ERROR encoder beat %0d expected %h got %h",
                             enc_out_index, codeword_mem[enc_out_index], enc_out_bits);
                    failures = failures + 1;
                end
                if (enc_out_count !== code_count_at(enc_out_index)) begin
                    $display("ERROR encoder count beat %0d expected %0d got %0d",
                             enc_out_index, code_count_at(enc_out_index), enc_out_count);
                    failures = failures + 1;
                end
                enc_out_index = enc_out_index + 1;
            end
        end
        if (reset_n && info_valid && info_ready) begin
            if (dec_out_index >= INFO_BEATS) begin
                $display("ERROR decoder emitted an extra beat");
                failures = failures + 1;
            end else begin
                if (info_bits !== message_mem[dec_out_index]) begin
                    $display("ERROR decoder beat %0d expected %h got %h",
                             dec_out_index, message_mem[dec_out_index], info_bits);
                    failures = failures + 1;
                end
                dec_out_index = dec_out_index + 1;
            end
        end
    end

    task automatic pulse_encoder_start;
        begin
            @(negedge clk); enc_start = 1'b1;
            @(negedge clk); enc_start = 1'b0;
        end
    endtask

    task automatic drive_encoder;
        integer beat;
        begin
            beat = 0;
            while (beat < INFO_BEATS) begin
                @(negedge clk);
                enc_in_valid = 1'b1;
                enc_in_bits = message_mem[beat];
                enc_in_count = (beat == INFO_BEATS-1) ? K-W*(INFO_BEATS-1) : W;
                if (enc_in_ready)
                    beat = beat + 1;
            end
            @(negedge clk); enc_in_valid = 1'b0;
        end
    endtask

    task automatic pulse_decoder_start;
        begin
            @(negedge clk); dec_start = 1'b1;
            @(negedge clk); dec_start = 1'b0;
        end
    endtask

    task automatic drive_codeword(input bit replay_phase);
        integer beat;
        begin
            beat = 0;
            while (beat < CW_BEATS) begin
                @(negedge clk);
                if (!replay_phase) begin
                    code_valid = 1'b1;
                    code_bits = received_mem[beat];
                    code_count = code_count_at(beat);
                    if (code_ready)
                        beat = beat + 1;
                end else begin
                    replay_valid = 1'b1;
                    replay_bits = received_mem[beat];
                    replay_count = code_count_at(beat);
                    if (replay_ready)
                        beat = beat + 1;
                end
            end
            @(negedge clk);
            if (!replay_phase)
                code_valid = 1'b0;
            else
                replay_valid = 1'b0;
        end
    endtask

    initial begin
        failures = 0;
        cycles = 0;
        enc_out_index = 0;
        dec_out_index = 0;
        enc_start = 0; enc_in_bits = 0; enc_in_count = 0; enc_in_valid = 0;
        enc_out_ready = 1;
        dec_start = 0; code_bits = 0; code_count = 0; code_valid = 0;
        replay_bits = 0; replay_count = 0; replay_valid = 0; info_ready = 1;
        if (!$value$plusargs("VEC_DIR=%s", vec_dir)) begin
            $display("ERROR missing +VEC_DIR");
            $finish(2);
        end
        $readmemh({vec_dir, "/message.mem"}, message_mem);
        $readmemh({vec_dir, "/codeword.mem"}, codeword_mem);
        $readmemh({vec_dir, "/received.mem"}, received_mem);

        repeat (4) @(negedge clk);
        reset_n = 1'b1;

        enc_start_cycle = cycles;
        pulse_encoder_start();
        drive_encoder();
        wait (enc_done);
        $display("METRIC encoder_cycles=%0d", cycles-enc_start_cycle);
        if (enc_out_index != CW_BEATS) begin
            $display("ERROR encoder produced %0d/%0d beats", enc_out_index, CW_BEATS);
            failures = failures + 1;
        end

        dec_start_cycle = cycles;
        pulse_decoder_start();
        drive_codeword(1'b0);
        wait (replay_req);
        drive_codeword(1'b1);
        wait (dec_done);
        $display("METRIC decoder_cycles=%0d", cycles-dec_start_cycle);
        if (!dec_success || error_count != T) begin
            $display("ERROR decoder status success=%0d count=%0d expected=%0d",
                     dec_success, error_count, T);
            failures = failures + 1;
        end
        if (dec_out_index != INFO_BEATS) begin
            $display("ERROR decoder produced %0d/%0d info beats", dec_out_index, INFO_BEATS);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS BCH K=%0d R=%0d T=%0d W=%0d", K, R, T, W);
        else
            $display("FAIL BCH failures=%0d", failures);
        $finish(failures != 0);
    end

    initial begin
        #2000000;
        $display("ERROR timeout");
        $finish(3);
    end
endmodule

`default_nettype wire
