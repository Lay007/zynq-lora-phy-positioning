`timescale 1ns/1ps

module tb_lora_detector_timestamp_path;
    reg         clk = 1'b0;
    reg         resetn = 1'b0;
    reg         clk_enable = 1'b1;
    reg         reset_in = 1'b0;
    reg  [31:0] symbol_index = 32'd0;
    reg         symbol_valid = 1'b0;
    reg  [63:0] symbol_sample_count = 64'd0;
    reg         timestamp_valid = 1'b0;
    reg  [7:0]  sync_word = 8'h12;

    wire        detected;
    wire        preamble_detected;
    wire        sync_valid;
    wire [15:0] preamble_bin;
    wire [15:0] chips_to_boundary;
    wire [7:0]  bins_seen;
    wire [63:0] preamble_start_count;
    wire        preamble_start_valid;
    wire [63:0] packet_start_count;
    wire        packet_start_valid;
    wire        alignment_error;
    wire        symbol_index_width_error;

    integer errors = 0;
    integer i;
    reg edge_preamble;
    reg edge_detected;
    reg edge_sync_valid;

    always #5 clk = ~clk;

    lora_detector_timestamp_path dut (
        .clk(clk),
        .resetn(resetn),
        .clk_enable(clk_enable),
        .reset_in(reset_in),
        .symbol_index(symbol_index),
        .symbol_valid(symbol_valid),
        .symbol_sample_count(symbol_sample_count),
        .timestamp_valid(timestamp_valid),
        .sync_word(sync_word),
        .detected(detected),
        .preamble_detected(preamble_detected),
        .sync_valid(sync_valid),
        .preamble_bin(preamble_bin),
        .chips_to_boundary(chips_to_boundary),
        .bins_seen(bins_seen),
        .preamble_start_count(preamble_start_count),
        .preamble_start_valid(preamble_start_valid),
        .packet_start_count(packet_start_count),
        .packet_start_valid(packet_start_valid),
        .alignment_error(alignment_error),
        .symbol_index_width_error(symbol_index_width_error)
    );

    task automatic expect_bit;
        input [8*64-1:0] name;
        input got;
        input expected;
        begin
            if (got !== expected) begin
                $display("FAIL %-56s got=%0d expected=%0d", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-56s value=%0d", name, got);
            end
        end
    endtask

    task automatic expect_u16;
        input [8*64-1:0] name;
        input [15:0] got;
        input [15:0] expected;
        begin
            if (got !== expected) begin
                $display("FAIL %-56s got=0x%04x expected=0x%04x", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-56s value=0x%04x", name, got);
            end
        end
    endtask

    task automatic expect_u64;
        input [8*64-1:0] name;
        input [63:0] got;
        input [63:0] expected;
        begin
            if (got !== expected) begin
                $display("FAIL %-56s got=0x%016x expected=0x%016x", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-56s value=0x%016x", name, got);
            end
        end
    endtask

    // Drive one correlator decision. The generated detector outputs are
    // combinational from the current symbol and its registered history, so
    // capture those pulses in the active region at the sampling edge. The
    // timestamp aligner registers the corresponding timestamp on that edge.
    task automatic send_symbol;
        input [31:0] index_value;
        input [63:0] timestamp_value;
        input timestamp_is_valid;
        begin
            @(negedge clk);
            symbol_index = index_value;
            symbol_sample_count = timestamp_value;
            symbol_valid = 1'b1;
            timestamp_valid = timestamp_is_valid;

            @(posedge clk);
            edge_preamble = preamble_detected;
            edge_detected = detected;
            edge_sync_valid = sync_valid;
            #1;
            symbol_valid = 1'b0;
            timestamp_valid = 1'b0;
        end
    endtask

    task automatic pulse_stream_reset;
        begin
            @(negedge clk);
            reset_in = 1'b1;
            symbol_valid = 1'b0;
            timestamp_valid = 1'b0;
            @(posedge clk);
            #1;
            reset_in = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;
        expect_bit("preamble timestamp valid reset", preamble_start_valid, 1'b0);
        expect_bit("packet timestamp valid reset", packet_start_valid, 1'b0);
        expect_bit("alignment error reset", alignment_error, 1'b0);
        resetn = 1'b1;

        // Standard private-network sync word 0x12. With preamble bin zero the
        // two expected sync bins are 8 and 16 for the generated SF7 detector.
        for (i = 0; i < 7; i = i + 1) begin
            send_symbol(32'd0, 64'd100 + i*64'd100, 1'b1);
            expect_bit("no early preamble timestamp", preamble_start_valid, 1'b0);
        end

        send_symbol(32'd0, 64'd800, 1'b1);
        expect_bit("generated detector sees 8-symbol preamble", edge_preamble, 1'b1);
        expect_bit("aligned preamble timestamp valid", preamble_start_valid, 1'b1);
        expect_u64("aligned preamble timestamp selects first symbol", preamble_start_count, 64'd100);
        expect_u16("generated detector preamble bin", preamble_bin, 16'd0);
        expect_u16("generated detector chips to boundary", chips_to_boundary, 16'd0);

        send_symbol(32'd8, 64'd900, 1'b1);
        expect_bit("no packet decision after first sync symbol", edge_detected, 1'b0);
        expect_bit("no packet timestamp after first sync symbol", packet_start_valid, 1'b0);

        send_symbol(32'd16, 64'd1000, 1'b1);
        expect_bit("generated detector confirms preamble plus sync", edge_detected, 1'b1);
        expect_bit("generated detector sync validation", edge_sync_valid, 1'b1);
        expect_bit("aligned packet timestamp valid", packet_start_valid, 1'b1);
        expect_u64("aligned packet timestamp selects first preamble symbol", packet_start_count, 64'd100);

        // reset_in is the generated streaming reset. The wrapper deliberately
        // clears timestamp history on the same edge, preventing stale metadata
        // from crossing a receiver resynchronization.
        pulse_stream_reset();
        expect_bit("stream reset clears preamble timestamp valid", preamble_start_valid, 1'b0);
        expect_bit("stream reset clears packet timestamp valid", packet_start_valid, 1'b0);
        expect_bit("stream reset clears alignment error", alignment_error, 1'b0);

        for (i = 0; i < 7; i = i + 1) begin
            send_symbol(32'd0, 64'd2000 + i*64'd100, 1'b1);
            expect_bit("no stale preamble after stream reset", preamble_start_valid, 1'b0);
        end
        send_symbol(32'd0, 64'd2700, 1'b1);
        expect_bit("fresh preamble detected after stream reset", edge_preamble, 1'b1);
        expect_bit("fresh preamble timestamp valid after reset", preamble_start_valid, 1'b1);
        expect_u64("fresh preamble uses post-reset history only", preamble_start_count, 64'd2000);

        // Missing timestamp sideband on a real detector event must be visible as
        // an integration error and must not emit a stale timestamp.
        pulse_stream_reset();
        for (i = 0; i < 7; i = i + 1)
            send_symbol(32'd0, 64'd3000 + i*64'd100, 1'b1);
        send_symbol(32'd0, 64'd3700, 1'b0);
        expect_bit("generated detector still sees preamble without timestamp", edge_preamble, 1'b1);
        expect_bit("missing timestamp raises alignment error", alignment_error, 1'b1);
        expect_bit("missing timestamp emits no preamble timestamp", preamble_start_valid, 1'b0);

        @(negedge clk);
        symbol_index = 32'h0001_0000;
        symbol_valid = 1'b1;
        #1;
        expect_bit("upper symbol-index bits are not silently truncated", symbol_index_width_error, 1'b1);
        symbol_valid = 1'b0;
        #1;
        expect_bit("symbol-index width error follows valid input", symbol_index_width_error, 1'b0);

        if (errors == 0)
            $display("PASS tb_lora_detector_timestamp_path");
        else begin
            $display("FAIL tb_lora_detector_timestamp_path errors=%0d", errors);
            $fatal(1);
        end

        $finish;
    end
endmodule
