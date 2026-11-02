`timescale 1ns/1ps
`default_nettype none

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

module bch_pipeline_tb;
    localparam integer K = `K_BITS;
    localparam integer R = `R_BITS;
    localparam integer T = `T_BITS;
    localparam integer W = `W_BITS;
    localparam integer FRAMES = 5;
    localparam integer INFO_BEATS = (K+W-1)/W;
    localparam integer CW_BEATS = INFO_BEATS + (R+W-1)/W;
    localparam integer COUNT_W = $clog2(W+1);
    localparam integer DEG_W = $clog2(T+1);

    reg clk = 0;
    reg reset_n = 0;
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

    integer cycles;
    integer failures;
    integer zero_errors;
    integer mixed_errors;
    integer enc_started, enc_completed, enc_out_index;
    integer dec_started, dec_completed, dec_out_index;
    integer syn_done_count, bm_start_count, bm_done_count, chien_start_count;
    integer enc_start_cycle [0:FRAMES-1];
    integer enc_done_cycle [0:FRAMES-1];
    integer dec_start_cycle [0:FRAMES-1];
    integer dec_done_cycle [0:FRAMES-1];

    `ENC_TOP enc_u (
        .clk(clk),.reset_n(reset_n),.start_i(enc_start),.start_ready_o(enc_start_ready),
        .in_bits_i(enc_in_bits),.in_count_i(enc_in_count),.in_valid_i(enc_in_valid),
        .in_ready_o(enc_in_ready),.out_bits_o(enc_out_bits),.out_count_o(enc_out_count),
        .out_valid_o(enc_out_valid),.out_ready_i(enc_out_ready),.out_last_o(enc_out_last),
        .done_o(enc_done),.busy_o(enc_busy));

    `DEC_TOP dec_u (
        .clk(clk),.reset_n(reset_n),.start_i(dec_start),.start_ready_o(dec_start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),
        .code_ready_o(code_ready),.replay_req_o(replay_req),
        .replay_bits_i(replay_bits),.replay_count_i(replay_count),
        .replay_valid_i(replay_valid),.replay_ready_o(replay_ready),
        .info_bits_o(info_bits),.info_count_o(info_count),.info_valid_o(info_valid),
        .info_ready_i(info_ready),.done_o(dec_done),.success_o(dec_success),
        .error_count_o(error_count),.busy_o(dec_busy));

    function automatic integer code_count_at(input integer beat);
        integer parity_beat;
        begin
            if (beat < INFO_BEATS)
                code_count_at = (beat == INFO_BEATS-1) ? K-W*(INFO_BEATS-1) : W;
            else begin
                parity_beat = beat-INFO_BEATS;
                code_count_at = (parity_beat == (R+W-1)/W-1) ?
                                R-W*parity_beat : W;
            end
        end
    endfunction

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (reset_n && enc_start && enc_start_ready) begin
            enc_start_cycle[enc_started] = cycles;
            enc_started = enc_started + 1;
        end
        if (reset_n && dec_start && dec_start_ready) begin
            dec_start_cycle[dec_started] = cycles;
            dec_started = dec_started + 1;
        end
        if (reset_n && enc_out_valid && enc_out_ready) begin
            if (enc_out_bits !== codeword_mem[enc_out_index % CW_BEATS] ||
                enc_out_count !== code_count_at(enc_out_index % CW_BEATS)) begin
                $display("ERROR pipelined BCH encoder beat %0d", enc_out_index);
                failures = failures + 1;
            end
            enc_out_index = enc_out_index + 1;
        end
        if (reset_n && info_valid && info_ready) begin
            if (info_bits !== message_mem[dec_out_index % INFO_BEATS] || info_count != W) begin
                $display("ERROR pipelined BCH decoder beat %0d", dec_out_index);
                failures = failures + 1;
            end
            dec_out_index = dec_out_index + 1;
        end
        if (reset_n && enc_done) begin
            enc_done_cycle[enc_completed] = cycles;
            enc_completed = enc_completed + 1;
        end
        if (reset_n && dec_done) begin
            dec_done_cycle[dec_completed] = cycles;
            if (!dec_success || error_count !=
                (zero_errors ? 0 : ((mixed_errors && dec_completed[0]) ? 0 : T))) begin
                $display("ERROR pipelined BCH decoder status frame %0d", dec_completed);
                failures = failures + 1;
            end
            dec_completed = dec_completed + 1;
        end
        if (reset_n && dec_u.core.syndrome_done) begin
            syn_done_count=syn_done_count+1;
        end
        if (reset_n && dec_u.core.bm_start_q) begin
            bm_start_count=bm_start_count+1;
        end
        if (reset_n && dec_u.core.bm_done) bm_done_count=bm_done_count+1;
        if (reset_n && dec_u.core.chien_start_q) chien_start_count=chien_start_count+1;
    end

    task automatic drive_encoder_frames;
        integer frame, beat;
        begin
            for (frame = 0; frame < FRAMES; frame = frame + 1) begin
                while (!enc_start_ready) @(negedge clk);
                enc_start = 1'b1;
                @(negedge clk);
                enc_start = 1'b0;
                beat = 0;
                while (beat < INFO_BEATS) begin
                    enc_in_valid = 1'b1;
                    enc_in_bits = message_mem[beat];
                    enc_in_count = W;
                    if (enc_in_ready)
                        beat = beat + 1;
                    @(negedge clk);
                end
                enc_in_valid = 1'b0;
            end
        end
    endtask

    task automatic drive_scan_frames;
        integer frame, beat;
        begin
            for (frame = 0; frame < FRAMES; frame = frame + 1) begin
                while (!dec_start_ready) @(negedge clk);
                dec_start = 1'b1;
                @(negedge clk);
                dec_start = 1'b0;
                beat = 0;
                while (beat < CW_BEATS) begin
                    code_valid = 1'b1;
                    code_bits = (zero_errors || (mixed_errors && frame[0])) ?
                                codeword_mem[beat] : received_mem[beat];
                    code_count = code_count_at(beat);
                    if (code_ready)
                        beat = beat + 1;
                    @(negedge clk);
                end
                code_valid = 1'b0;
            end
        end
    endtask

    task automatic drive_replay_frames;
        integer frame, beat;
        begin
            for (frame = 0; frame < FRAMES; frame = frame + 1) begin
                wait (replay_req);
                @(negedge clk);
                beat = 0;
                while (beat < CW_BEATS) begin
                    replay_valid = 1'b1;
                    replay_bits = (zero_errors || (mixed_errors && frame[0])) ?
                                  codeword_mem[beat] : received_mem[beat];
                    replay_count = code_count_at(beat);
                    if (replay_ready)
                        beat = beat + 1;
                    @(negedge clk);
                end
                replay_valid = 1'b0;
            end
        end
    endtask

    initial begin
        cycles=0; failures=0;
        zero_errors=$test$plusargs("ZERO_ERRORS");
        mixed_errors=$test$plusargs("MIXED_ERRORS");
        enc_started=0; enc_completed=0; enc_out_index=0;
        dec_started=0; dec_completed=0; dec_out_index=0;
        syn_done_count=0; bm_start_count=0; bm_done_count=0; chien_start_count=0;
        enc_start=0; enc_in_bits=0; enc_in_count=0; enc_in_valid=0; enc_out_ready=1;
        dec_start=0; code_bits=0; code_count=0; code_valid=0;
        replay_bits=0; replay_count=0; replay_valid=0; info_ready=1;
        if (!$value$plusargs("VEC_DIR=%s",vec_dir)) begin
            $display("ERROR missing VEC_DIR"); $finish(2);
        end
        $readmemh({vec_dir,"/message.mem"},message_mem);
        $readmemh({vec_dir,"/codeword.mem"},codeword_mem);
        $readmemh({vec_dir,"/received.mem"},received_mem);
        repeat(4) @(negedge clk); reset_n=1;
        fork
            drive_encoder_frames();
            drive_scan_frames();
            drive_replay_frames();
        join
        wait(enc_completed == FRAMES && dec_completed == FRAMES);
        if (enc_out_index != FRAMES*CW_BEATS || dec_out_index != FRAMES*INFO_BEATS)
            failures = failures + 1;
        $display("METRIC encoder_latency=%0d",enc_done_cycle[0]-enc_start_cycle[0]);
        $display("METRIC encoder_ii=%0d",enc_start_cycle[FRAMES-1]-enc_start_cycle[FRAMES-2]);
        $display("METRIC decoder_latency=%0d",dec_done_cycle[0]-dec_start_cycle[0]);
        $display("METRIC decoder_ii=%0d",dec_start_cycle[FRAMES-1]-dec_start_cycle[FRAMES-2]);
        if (failures == 0)
            $display("PASS BCH PIPELINE frames=%0d W=%0d",FRAMES,W);
        else
            $display("FAIL BCH PIPELINE failures=%0d",failures);
        $finish(failures != 0);
    end

    initial begin
        #4000000;
        $display("ERROR timeout enc=%0d/%0d dec=%0d/%0d enc_out=%0d dec_out=%0d start_ready=%0d code_ready=%0d replay_req=%0d replay_ready=%0d syn=%0d bm_start=%0d bm_done=%0d chien_start=%0d syn_pending=%0d syn_busy=%0d bm_busy=%0d bm_pending=%0d chien_busy=%0d",
                 enc_started,enc_completed,dec_started,dec_completed,
                 enc_out_index,dec_out_index,dec_start_ready,code_ready,replay_req,replay_ready,
                 syn_done_count,bm_start_count,bm_done_count,chien_start_count,
                 dec_u.core.syndrome_pending_q,dec_u.core.syndrome_busy,
                 dec_u.core.bm_busy,dec_u.core.bm_result_pending_q,dec_u.core.chien_busy);
        $finish(3);
    end
endmodule

`default_nettype wire
