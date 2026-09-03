`timescale 1ns/1ps

module tb_lora_clg400_gpreg_bridge;

    reg ctrl_clk = 1'b0;
    reg sample_clk = 1'b0;
    always #25 ctrl_clk = ~ctrl_clk;
    always #5 sample_clk = ~sample_clk;

    reg ctrl_resetn = 1'b0;
    reg sample_resetn = 1'b0;
    reg [31:0] gp_ctrl = 32'd0;
    reg [32:0] rx_sample_bus = 33'd0;

    wire [31:0] gp_status;
    wire [31:0] gp_sequence;
    wire [31:0] gp_coarse_lo;
    wire [31:0] gp_coarse_hi;
    wire [31:0] gp_fractional_q12;
    wire [31:0] gp_log_peak_q12;
    wire [31:0] gp_debug;
    wire [31:0] gp_signature;
    integer i;

    lora_clg400_gpreg_bridge dut (
        .ctrl_clk(ctrl_clk),
        .ctrl_resetn(ctrl_resetn),
        .sample_clk(sample_clk),
        .sample_resetn(sample_resetn),
        .gp_ctrl(gp_ctrl),
        .rx_sample_bus(rx_sample_bus),
        .gp_status(gp_status),
        .gp_sequence(gp_sequence),
        .gp_coarse_lo(gp_coarse_lo),
        .gp_coarse_hi(gp_coarse_hi),
        .gp_fractional_q12(gp_fractional_q12),
        .gp_log_peak_q12(gp_log_peak_q12),
        .gp_debug(gp_debug),
        .gp_signature(gp_signature)
    );

    task automatic expect32(
        input [31:0] actual,
        input [31:0] expected,
        input [8*64-1:0] label
    );
        begin
            if (actual !== expected) begin
                $display("FAIL %0s actual=0x%08x expected=0x%08x",
                         label, actual, expected);
                $fatal(1);
            end
            $display("PASS %0s value=0x%08x", label, actual);
        end
    endtask

    task pulse_metadata(
        input [63:0] coarse,
        input [31:0] fractional,
        input [31:0] log_peak
    );
        begin
            @(negedge sample_clk);
            force dut.metadata_coarse = coarse;
            force dut.metadata_fractional_q12 = fractional;
            force dut.toa_log_peak_q12 = log_peak;
            force dut.metadata_valid = 1'b1;
            @(negedge sample_clk);
            force dut.metadata_valid = 1'b0;
        end
    endtask

    initial begin
        force dut.metadata_valid = 1'b0;
        force dut.metadata_overflow = 1'b0;
        force dut.packet_start_valid = 1'b0;
        force dut.packet_start_count = 64'd0;
        force dut.toa_search_busy = 1'b0;
        force dut.correlation_magnitude_valid = 1'b0;
        force dut.peak_triplet_valid = 1'b0;
        force dut.toa_offset_valid = 1'b0;
        force dut.alignment_error = 1'b0;
        force dut.symbol_index_width_error = 1'b0;
        force dut.toa_underflow_error = 1'b0;
        force dut.toa_search_restart_error = 1'b0;
        force dut.toa_mac_window_mismatch_error = 1'b0;
        force dut.toa_mac_read_miss_error = 1'b0;
        force dut.toa_mac_response_mismatch_error = 1'b0;
        force dut.toa_mac_restart_error = 1'b0;
        force dut.toa_peak_boundary_error = 1'b0;
        force dut.toa_peak_restart_error = 1'b0;
        force dut.metadata_coarse = 64'd0;
        force dut.metadata_fractional_q12 = 32'd0;
        force dut.toa_log_peak_q12 = 32'd0;
        force dut.packet_detected = 1'b0;
        force dut.preamble_bin = 16'd0;
        force dut.symbol_index = 32'd0;
        force dut.symbol_valid = 1'b0;
        force dut.symbol_confidence = 16'd0;
        force dut.symbol_sample_count = 64'd0;
        force dut.symbol_timestamp_valid = 1'b0;

        repeat (4) @(posedge ctrl_clk);
        ctrl_resetn = 1'b1;
        sample_resetn = 1'b1;
        gp_ctrl = 32'h0000_1201;

        repeat (8) @(posedge ctrl_clk);
        expect32(gp_signature, 32'h4c4f5241, "signature");
        if (!gp_status[0] || !gp_status[1]) begin
            $display("FAIL receiver request/active status=0x%08x", gp_status);
            $fatal(1);
        end

        // Diagnostic stage/error pulses are sticky until stream reset, while
        // packet-start count is captured from the same sample-domain event.
        @(negedge sample_clk);
        force dut.packet_start_count = 64'h0000_0000_1234_abcd;
        force dut.packet_start_valid = 1'b1;
        force dut.toa_search_busy = 1'b1;
        force dut.correlation_magnitude_valid = 1'b1;
        force dut.toa_peak_boundary_error = 1'b1;
        @(negedge sample_clk);
        force dut.packet_start_valid = 1'b0;
        force dut.toa_search_busy = 1'b0;
        force dut.correlation_magnitude_valid = 1'b0;
        force dut.toa_peak_boundary_error = 1'b0;
        repeat (2) @(posedge sample_clk);
        repeat (3) @(posedge ctrl_clk);
        expect32(gp_debug, 32'h00b1_abcd,
                 "sticky diagnostic and packet-start count");

        // The control clock is deliberately slower than the sample clock. The
        // second event arrives while the first mailbox entry is pending and
        // must set overflow without tearing the first payload.
        pulse_metadata(64'h0123_4567_89ab_cdef, 32'hffff_f800,
                       32'h0001_2345);
        pulse_metadata(64'hdead_beef_0000_0002, 32'h0000_0100,
                       32'h0002_0000);

        wait (gp_sequence == 32'd1);
        repeat (3) @(posedge ctrl_clk);
        expect32(gp_coarse_lo, 32'h89ab_cdef, "atomic coarse low");
        expect32(gp_coarse_hi, 32'h0123_4567, "atomic coarse high");
        expect32(gp_fractional_q12, 32'hffff_f800, "atomic fractional");
        expect32(gp_log_peak_q12, 32'h0001_2345, "atomic log peak");
        if (!gp_status[2] || !gp_status[3]) begin
            $display("FAIL snapshot/overflow status=0x%08x", gp_status);
            $fatal(1);
        end

        // Once acknowledged, a later event transfers normally and increments
        // exactly once.
        repeat (5) @(posedge sample_clk);
        pulse_metadata(64'h1020_3040_5060_7080, 32'h0000_0400,
                       32'h0003_0000);
        wait (gp_sequence == 32'd2);
        repeat (2) @(posedge ctrl_clk);
        expect32(gp_coarse_lo, 32'h5060_7080, "second coarse low");
        expect32(gp_coarse_hi, 32'h1020_3040, "second coarse high");
        expect32(gp_fractional_q12, 32'h0000_0400, "second fractional");
        expect32(gp_log_peak_q12, 32'h0003_0000, "second log peak");

        // Re-arm the symbol trace, trigger on the packet decision, and then
        // provide the 128 following symbol decisions. The detector-cycle
        // symbol itself must not occupy entry zero.
        gp_ctrl = 32'h0000_1203;
        repeat (3) @(posedge sample_clk);
        gp_ctrl = 32'h0000_1201;
        repeat (3) @(posedge sample_clk);

        @(negedge sample_clk);
        force dut.packet_detected = 1'b1;
        force dut.preamble_bin = 16'd7;
        force dut.symbol_index = 32'h0000_007f;
        force dut.symbol_valid = 1'b1;
        force dut.symbol_confidence = 16'h7fff;
        force dut.symbol_sample_count = 64'd100;
        force dut.symbol_timestamp_valid = 1'b1;
        @(negedge sample_clk);
        force dut.packet_detected = 1'b0;

        for (i = 0; i < 128; i = i + 1) begin
            force dut.symbol_index = 32'h0000_0040 + i;
            force dut.symbol_confidence = 16'h0200 + i;
            force dut.symbol_sample_count = 64'd1000 + i*1024;
            @(negedge sample_clk);
        end
        force dut.symbol_valid = 1'b0;
        force dut.symbol_timestamp_valid = 1'b0;

        repeat (6) @(posedge ctrl_clk);
        // Page one, trace index five, receiver remains enabled with sync 0x12.
        gp_ctrl = 32'h0501_1201;
        repeat (5) @(posedge ctrl_clk);
        expect32(gp_status, 32'h5359_0280, "symbol trace complete status");
        expect32(gp_sequence, 32'd1, "symbol trace sequence");
        expect32(gp_coarse_lo, 32'h0000_0045, "symbol trace index");
        expect32(gp_coarse_hi, 32'd6120, "symbol trace sample count low");
        expect32(gp_fractional_q12, 32'd0, "symbol trace sample count high");
        expect32(gp_log_peak_q12, 32'h0002_0205,
                 "symbol trace flags and confidence");
        expect32(gp_debug, 32'h0007_0a80,
                 "symbol trace preamble bin, index, and count");

        // Returning to page zero must preserve the timestamp snapshot ABI.
        gp_ctrl = 32'h0000_1201;
        repeat (2) @(posedge ctrl_clk);
        expect32(gp_sequence, 32'd2, "timestamp sequence after trace read");
        expect32(gp_coarse_lo, 32'h5060_7080,
                 "timestamp snapshot after trace read");

        $display("PASS tb_lora_clg400_gpreg_bridge");
        $finish;
    end

endmodule
