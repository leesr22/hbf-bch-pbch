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

module pbch_pipeline_tb;
    localparam integer K = 4096;
    localparam integer L = `L_BITS;
    localparam integer R = 104;
    localparam integer T = 8;
    localparam integer W = `W_BITS;
    localparam integer FRAMES = 5;
    localparam integer INFO_BEATS = K/W;
    localparam integer CW_BEATS = 1 + INFO_BEATS + (R+W-1)/W;
    localparam integer COUNT_W = $clog2(W+1);
    localparam integer FAIL_W = $clog2(L+K+R+1);

    reg clk=0;
    reg reset_n=0;
    always #1 clk=~clk;

    reg [W-1:0] message_mem [0:INFO_BEATS-1];
    reg [W-1:0] probe_mem [0:CW_BEATS-1];
    reg [W-1:0] codeword_mem [0:CW_BEATS-1];
    reg [W-1:0] received_mem [0:CW_BEATS-1];
    string vec_dir;
    reg [L-1:0] expected_selector;
    integer expected_failures;

    reg enc_start;
    wire enc_start_ready;
    reg [W-1:0] data_bits;
    reg [COUNT_W-1:0] data_count;
    reg data_valid;
    wire data_ready;
    wire enc_replay_req;
    reg [W-1:0] enc_replay_bits;
    reg [COUNT_W-1:0] enc_replay_count;
    reg enc_replay_valid;
    wire enc_replay_ready;
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
    wire dec_start_ready;
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

    integer cycles, failures;
    integer zero_errors;
    integer enc_started, enc_completed, enc_out_index;
    integer dec_started, dec_completed, dec_out_index;
    integer enc_start_cycle [0:FRAMES-1];
    integer enc_done_cycle [0:FRAMES-1];
    integer dec_start_cycle [0:FRAMES-1];
    integer dec_done_cycle [0:FRAMES-1];

    `ENC_TOP enc_u (
        .clk(clk),.reset_n(reset_n),.start_i(enc_start),.start_ready_o(enc_start_ready),
        .data_bits_i(data_bits),.data_count_i(data_count),.data_valid_i(data_valid),
        .data_ready_o(data_ready),.replay_req_o(enc_replay_req),
        .replay_bits_i(enc_replay_bits),.replay_count_i(enc_replay_count),
        .replay_valid_i(enc_replay_valid),.replay_ready_o(enc_replay_ready),
        .probe_bits_i(probe_bits),.probe_count_i(probe_count),.probe_valid_i(probe_valid),
        .probe_ready_o(probe_ready),.out_bits_o(enc_out_bits),.out_count_o(enc_out_count),
        .out_valid_o(enc_out_valid),.out_ready_i(enc_out_ready),.out_last_o(enc_out_last),
        .selector_o(selected),.mask_failures_o(mask_failures),.done_o(enc_done),.busy_o(enc_busy));

    `DEC_TOP dec_u (
        .clk(clk),.reset_n(reset_n),.start_i(dec_start),.start_ready_o(dec_start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),
        .code_ready_o(code_ready),.replay_req_o(dec_replay_req),
        .replay_bits_i(replay_bits),.replay_count_i(replay_count),
        .replay_valid_i(replay_valid),.replay_ready_o(replay_ready),
        .info_bits_o(info_bits),.info_count_o(info_count),.info_valid_o(info_valid),
        .info_ready_i(info_ready),.selector_o(decoded_selector),.done_o(dec_done),
        .success_o(dec_success),.error_count_o(error_count),.busy_o(dec_busy));

    function automatic integer code_count_at(input integer beat);
        integer parity_beat;
        begin
            if (beat == 0)
                code_count_at = L;
            else if (beat <= INFO_BEATS)
                code_count_at = W;
            else begin
                parity_beat = beat-INFO_BEATS-1;
                code_count_at = (parity_beat == (R+W-1)/W-1) ?
                                R-W*parity_beat : W;
            end
        end
    endfunction

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (reset_n && enc_start && enc_start_ready) begin
            enc_start_cycle[enc_started]=cycles;
            enc_started=enc_started+1;
        end
        if (reset_n && dec_start && dec_start_ready) begin
            dec_start_cycle[dec_started]=cycles;
            dec_started=dec_started+1;
        end
        if (reset_n && enc_out_valid && enc_out_ready) begin
            if (enc_out_bits !== codeword_mem[enc_out_index % CW_BEATS] ||
                enc_out_count !== code_count_at(enc_out_index % CW_BEATS)) begin
                $display("ERROR pipelined PBCH encoder beat %0d",enc_out_index);
                failures=failures+1;
            end
            enc_out_index=enc_out_index+1;
        end
        if (reset_n && info_valid && info_ready) begin
            if (info_bits !== message_mem[dec_out_index % INFO_BEATS] || info_count != W) begin
                $display("ERROR pipelined PBCH decoder beat %0d",dec_out_index);
                failures=failures+1;
            end
            dec_out_index=dec_out_index+1;
        end
        if (reset_n && enc_done) begin
            enc_done_cycle[enc_completed]=cycles;
            if (selected != expected_selector || mask_failures != expected_failures) begin
                $display("ERROR pipelined PBCH encoder status frame %0d",enc_completed);
                failures=failures+1;
            end
            enc_completed=enc_completed+1;
        end
        if (reset_n && dec_done) begin
            dec_done_cycle[dec_completed]=cycles;
            if (!dec_success || error_count != (zero_errors ? 0 : T) ||
                decoded_selector != expected_selector) begin
                $display("ERROR pipelined PBCH decoder status frame %0d",dec_completed);
                failures=failures+1;
            end
            dec_completed=dec_completed+1;
        end
    end

    task automatic drive_data_one;
        integer beat;
        begin
            beat=0;
            while (beat < INFO_BEATS) begin
                data_valid=1; data_bits=message_mem[beat]; data_count=W;
                if (data_ready) beat=beat+1;
                @(negedge clk);
            end
            data_valid=0;
        end
    endtask

    task automatic drive_probe_one;
        integer beat;
        begin
            beat=0;
            while (beat < CW_BEATS) begin
                probe_valid=1; probe_bits=probe_mem[beat]; probe_count=code_count_at(beat);
                if (probe_ready) beat=beat+1;
                @(negedge clk);
            end
            probe_valid=0;
        end
    endtask

    task automatic drive_prepare_frames;
        integer frame;
        begin
            for (frame=0; frame<FRAMES; frame=frame+1) begin
                while (!enc_start_ready) @(negedge clk);
                enc_start=1;
                @(negedge clk);
                enc_start=0;
                fork
                    drive_data_one();
                    drive_probe_one();
                join
            end
        end
    endtask

    task automatic drive_encoder_replays;
        integer frame, beat;
        begin
            for (frame=0; frame<FRAMES; frame=frame+1) begin
                wait(enc_replay_req);
                @(negedge clk);
                beat=0;
                while (beat < INFO_BEATS) begin
                    enc_replay_valid=1; enc_replay_bits=message_mem[beat]; enc_replay_count=W;
                    if (enc_replay_ready) beat=beat+1;
                    @(negedge clk);
                end
                enc_replay_valid=0;
            end
        end
    endtask

    task automatic drive_scan_frames;
        integer frame, beat;
        begin
            for (frame=0; frame<FRAMES; frame=frame+1) begin
                while (!dec_start_ready) @(negedge clk);
                dec_start=1;
                @(negedge clk);
                dec_start=0;
                beat=0;
                while (beat < CW_BEATS) begin
                    code_valid=1;
                    code_bits=zero_errors ? codeword_mem[beat] : received_mem[beat];
                    code_count=code_count_at(beat);
                    if (code_ready) beat=beat+1;
                    @(negedge clk);
                end
                code_valid=0;
            end
        end
    endtask

    task automatic drive_decoder_replays;
        integer frame, beat;
        begin
            for (frame=0; frame<FRAMES; frame=frame+1) begin
                wait(dec_replay_req);
                @(negedge clk);
                beat=0;
                while (beat < CW_BEATS) begin
                    replay_valid=1;
                    replay_bits=zero_errors ? codeword_mem[beat] : received_mem[beat];
                    replay_count=code_count_at(beat);
                    if (replay_ready) beat=beat+1;
                    @(negedge clk);
                end
                replay_valid=0;
            end
        end
    endtask

    initial begin
        cycles=0; failures=0;
        zero_errors=$test$plusargs("ZERO_ERRORS");
        enc_started=0; enc_completed=0; enc_out_index=0;
        dec_started=0; dec_completed=0; dec_out_index=0;
        enc_start=0; data_bits=0; data_count=0; data_valid=0;
        enc_replay_bits=0; enc_replay_count=0; enc_replay_valid=0;
        probe_bits=0; probe_count=0; probe_valid=0; enc_out_ready=1;
        dec_start=0; code_bits=0; code_count=0; code_valid=0;
        replay_bits=0; replay_count=0; replay_valid=0; info_ready=1;
        if (!$value$plusargs("VEC_DIR=%s",vec_dir) ||
            !$value$plusargs("EXPECT_SELECTOR=%h",expected_selector) ||
            !$value$plusargs("EXPECT_FAILURES=%d",expected_failures)) begin
            $display("ERROR missing plusargs"); $finish(2);
        end
        $readmemh({vec_dir,"/message.mem"},message_mem);
        $readmemh({vec_dir,"/probe.mem"},probe_mem);
        $readmemh({vec_dir,"/codeword.mem"},codeword_mem);
        $readmemh({vec_dir,"/received.mem"},received_mem);
        repeat(4) @(negedge clk); reset_n=1;
        fork
            drive_prepare_frames();
            drive_encoder_replays();
            drive_scan_frames();
            drive_decoder_replays();
        join
        wait(enc_completed == FRAMES && dec_completed == FRAMES);
        if (enc_out_index != FRAMES*CW_BEATS || dec_out_index != FRAMES*INFO_BEATS)
            failures=failures+1;
        $display("METRIC encoder_latency=%0d",enc_done_cycle[0]-enc_start_cycle[0]);
        $display("METRIC encoder_ii=%0d",enc_start_cycle[FRAMES-1]-enc_start_cycle[FRAMES-2]);
        $display("METRIC decoder_latency=%0d",dec_done_cycle[0]-dec_start_cycle[0]);
        $display("METRIC decoder_ii=%0d",dec_start_cycle[FRAMES-1]-dec_start_cycle[FRAMES-2]);
        if (failures == 0)
            $display("PASS PBCH PIPELINE frames=%0d W=%0d",FRAMES,W);
        else
            $display("FAIL PBCH PIPELINE failures=%0d",failures);
        $finish(failures != 0);
    end

    initial begin
        #5000000; $display("ERROR timeout"); $finish(3);
    end
endmodule

`default_nettype wire
