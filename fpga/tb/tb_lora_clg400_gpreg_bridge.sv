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
        force dut.toa_search_busy = 1'b0;
        force dut.metadata_coarse = 64'd0;
        force dut.metadata_fractional_q12 = 32'd0;
        force dut.toa_log_peak_q12 = 32'd0;

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

        $display("PASS tb_lora_clg400_gpreg_bridge");
        $finish;
    end

endmodule
