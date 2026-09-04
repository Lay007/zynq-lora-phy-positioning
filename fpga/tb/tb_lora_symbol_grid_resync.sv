`timescale 1ns/1ps

module tb_lora_symbol_grid_resync;
    localparam integer SF = 7;
    localparam integer SAMPLES_PER_CHIP = 8;
    localparam integer SYMBOL_CHIPS = (1 << SF);

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg stream_reset = 1'b0;
    reg sample_valid = 1'b0;
    reg packet_detected = 1'b0;
    reg [15:0] chips_to_boundary = 16'd0;

    wire resync_valid;
    wire [31:0] resync_skip;
    wire resync_armed;
    wire [15:0] resync_chips;

    integer errors = 0;

    lora_symbol_grid_resync #(
        .SPREADING_FACTOR(SF),
        .SAMPLES_PER_CHIP(SAMPLES_PER_CHIP)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .stream_reset(stream_reset),
        .sample_valid(sample_valid),
        .packet_detected(packet_detected),
        .chips_to_boundary(chips_to_boundary),
        .resync_valid(resync_valid),
        .resync_skip(resync_skip),
        .resync_armed(resync_armed),
        .resync_chips(resync_chips)
    );

    task expect32(input [31:0] actual, input [31:0] expected, input [255:0] label);
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: expected 0x%08x got 0x%08x",
                         label, expected, actual);
                errors = errors + 1;
            end else begin
                $display("PASS %0s value=0x%08x", label, actual);
            end
        end
    endtask

    task expect1(input actual, input expected, input [255:0] label);
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: expected %0b got %0b", label, expected, actual);
                errors = errors + 1;
            end else begin
                $display("PASS %0s value=%0b", label, actual);
            end
        end
    endtask

    // One accepted sample every eight clocks, as the 1 MS/s stream looks
    // against the 62.5 MHz sample clock.
    task accepted_sample;
        begin
            @(negedge clk);
            sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
            repeat (6) @(negedge clk);
        end
    endtask

    task detect(input [15:0] chips);
        begin
            @(negedge clk);
            chips_to_boundary = chips;
            packet_detected = 1'b1;
            @(negedge clk);
            packet_detected = 1'b0;
            chips_to_boundary = 16'd0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        resetn = 1'b1;
        repeat (2) @(negedge clk);

        expect1(resync_armed, 1'b1, "armed after reset");
        expect1(resync_valid, 1'b0, "idle before detection");

        // The accepted 2026-09-03 capture had preamble bin 20, so
        // chipsToBoundary was 108. Adding the quarter symbol gives 140, and the
        // grid repeats every 128 chips, so the shortest advance is 12 chips.
        detect(16'd108);
        expect1(resync_valid, 1'b1, "request raised on detection");
        expect1(resync_armed, 1'b0, "disarmed after one request");
        expect32(resync_skip, 12 * SAMPLES_PER_CHIP,
                 "skip is chipsToBoundary plus a quarter symbol, wrapped");
        expect32({16'd0, resync_chips}, 32'd12, "held chip advance");

        // The request has to survive until an accepted sample arrives: the
        // correlator only latches it on one, and they are rare here.
        repeat (20) @(negedge clk);
        expect1(resync_valid, 1'b1, "request held while no sample is accepted");

        accepted_sample();
        expect1(resync_valid, 1'b0, "request dropped after one accepted sample");
        expect32(resync_skip, 12 * SAMPLES_PER_CHIP,
                 "skip value retained for inspection");

        // A second detection inside the same capture must not move the grid
        // again; only re-arming through a stream reset may.
        detect(16'd7);
        repeat (4) @(negedge clk);
        expect1(resync_valid, 1'b0, "second detection ignored while disarmed");
        expect32({16'd0, resync_chips}, 32'd12, "held advance unchanged");

        @(negedge clk);
        stream_reset = 1'b1;
        @(negedge clk);
        stream_reset = 1'b0;
        repeat (2) @(negedge clk);
        expect1(resync_armed, 1'b1, "re-armed by stream reset");
        expect32(resync_skip, 32'd0, "skip cleared by stream reset");

        // The quarter symbol wraps: chipsToBoundary 100 needs 132 chips, which
        // is one symbol plus four, so the request advances by four chips only.
        detect(16'd100);
        expect32(resync_skip, 4 * SAMPLES_PER_CHIP,
                 "quarter-symbol advance wraps within one symbol");

        @(negedge clk);
        stream_reset = 1'b1;
        @(negedge clk);
        stream_reset = 1'b0;
        repeat (2) @(negedge clk);

        // An already aligned preamble still needs the quarter symbol.
        detect(16'd0);
        expect32(resync_skip, (SYMBOL_CHIPS / 4) * SAMPLES_PER_CHIP,
                 "aligned preamble still advances a quarter symbol");

        if (errors != 0) begin
            $display("FAIL tb_lora_symbol_grid_resync (%0d errors)", errors);
            $fatal(1);
        end
        $display("PASS tb_lora_symbol_grid_resync");
        $finish;
    end
endmodule
