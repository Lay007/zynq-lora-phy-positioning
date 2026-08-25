`timescale 1ns/1ps

module tb_lora_packet_timestamp_axi_path;
    localparam integer SF = 7;
    localparam integer SAMPLES_PER_CHIP = 8;
    localparam integer SYMBOL_COUNT = (1 << SF);
    localparam integer SAMPLES_PER_SYMBOL = SYMBOL_COUNT * SAMPLES_PER_CHIP;
    localparam real PI = 3.14159265358979323846;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg signed [15:0] iq_in_re = 16'sd0;
    reg signed [15:0] iq_in_im = 16'sd0;
    reg valid_in = 1'b0;
    reg reset_in = 1'b0;
    reg resync_valid = 1'b0;
    reg [31:0] resync_skip = 32'd0;
    reg [7:0] sync_word = 8'h12;

    reg [31:0] magnitude_before = 32'd0;
    reg [31:0] magnitude_peak = 32'd0;
    reg [31:0] magnitude_after = 32'd0;
    reg triplet_valid = 1'b0;

    reg [5:0] awaddr = 6'd0;
    reg awvalid = 1'b0;
    wire awready;
    reg [31:0] wdata = 32'd0;
    reg [3:0] wstrb = 4'd0;
    reg wvalid = 1'b0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 1'b0;
    reg [5:0] araddr = 6'd0;
    reg arvalid = 1'b0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 1'b0;

    wire receiver_enable;
    wire [31:0] symbol_index;
    wire symbol_valid;
    wire detected;
    wire preamble_detected;
    wire sync_valid;
    wire [63:0] packet_start_count;
    wire packet_start_valid;
    wire signed [31:0] toa_offset_q12;
    wire toa_offset_valid;
    wire signed [31:0] toa_log_peak_q12;
    wire [63:0] metadata_coarse;
    wire signed [31:0] metadata_fractional_q12;
    wire metadata_valid;
    wire metadata_overflow;
    wire alignment_error;
    wire symbol_index_width_error;

    integer errors = 0;
    integer symbol_seen = 0;
    integer packet_start_seen = 0;
    integer toa_seen = 0;
    integer metadata_seen = 0;
    integer timeout_cycles = 0;
    reg [63:0] packet_start_captured = 64'd0;
    reg [31:0] expected_symbol [0:9];
    reg [31:0] read_value;

    lora_packet_timestamp_axi_path dut (
        .clk(clk), .resetn(resetn),
        .iq_in_re(iq_in_re), .iq_in_im(iq_in_im), .valid_in(valid_in),
        .reset_in(reset_in), .resync_valid(resync_valid), .resync_skip(resync_skip),
        .sync_word(sync_word),
        .magnitude_before(magnitude_before), .magnitude_peak(magnitude_peak),
        .magnitude_after(magnitude_after), .triplet_valid(triplet_valid),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
        .s_axi_bready(bready), .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .receiver_enable(receiver_enable), .symbol_index(symbol_index),
        .symbol_valid(symbol_valid), .detected(detected),
        .preamble_detected(preamble_detected), .sync_valid(sync_valid),
        .packet_start_count(packet_start_count), .packet_start_valid(packet_start_valid),
        .toa_offset_q12(toa_offset_q12), .toa_offset_valid(toa_offset_valid),
        .toa_log_peak_q12(toa_log_peak_q12), .metadata_coarse(metadata_coarse),
        .metadata_fractional_q12(metadata_fractional_q12),
        .metadata_valid(metadata_valid), .metadata_overflow(metadata_overflow),
        .alignment_error(alignment_error),
        .symbol_index_width_error(symbol_index_width_error)
    );

    function automatic integer quantize_q10(input real value);
        real scaled;
        begin
            scaled = value * 1024.0;
            if (scaled >= 0.0)
                quantize_q10 = $rtoi(scaled + 0.5);
            else
                quantize_q10 = $rtoi(scaled - 0.5);
        end
    endfunction

    task automatic drive_css_symbol(input integer symbol_value);
        integer n;
        integer source_n;
        integer q_re;
        integer q_im;
        real phase_cycles;
        real angle;
        begin
            for (n = 0; n < SAMPLES_PER_SYMBOL; n = n + 1) begin
                source_n = (n + symbol_value * SAMPLES_PER_CHIP) % SAMPLES_PER_SYMBOL;
                phase_cycles = (0.5 * source_n * source_n) /
                               (SYMBOL_COUNT * SAMPLES_PER_CHIP * SAMPLES_PER_CHIP) -
                               (0.5 * source_n) / SAMPLES_PER_CHIP;
                angle = 2.0 * PI * phase_cycles;
                q_re = quantize_q10($cos(angle));
                q_im = quantize_q10($sin(angle));
                @(negedge clk);
                iq_in_re <= q_re;
                iq_in_im <= q_im;
                valid_in <= 1'b1;
            end
        end
    endtask

    task automatic axi_write(input [5:0] address, input [31:0] value);
        begin
            @(negedge clk);
            awaddr = address; awvalid = 1'b1;
            wdata = value; wstrb = 4'hf; wvalid = 1'b1;
            while (!(awready && wready)) @(negedge clk);
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0; wstrb = 4'd0;
            while (!bvalid) @(negedge clk);
            if (bresp !== 2'b00) begin
                errors = errors + 1;
                $display("FAIL AXI write response address=0x%02x", address);
            end
            bready = 1'b1;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(input [5:0] address, output [31:0] value);
        begin
            @(negedge clk);
            araddr = address; arvalid = 1'b1;
            while (!arready) @(negedge clk);
            @(negedge clk);
            arvalid = 1'b0;
            while (!rvalid) @(negedge clk);
            value = rdata;
            if (rresp !== 2'b00) begin
                errors = errors + 1;
                $display("FAIL AXI read response address=0x%02x", address);
            end
            rready = 1'b1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task automatic expect32(input [31:0] got, input [31:0] expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-58s value=0x%08x", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-58s got=0x%08x expected=0x%08x", label_text, got, expected);
            end
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (resetn) begin
            if (symbol_valid) begin
                if (symbol_seen < 10 && symbol_index === expected_symbol[symbol_seen])
                    $display("PASS FFT symbol[%0d] through AXI path                            value=%0d", symbol_seen, symbol_index);
                else begin
                    errors = errors + 1;
                    $display("FAIL FFT symbol[%0d] through AXI path got=%0d", symbol_seen, symbol_index);
                end
                symbol_seen = symbol_seen + 1;
            end
            if (packet_start_valid) begin
                packet_start_seen = packet_start_seen + 1;
                packet_start_captured <= packet_start_count;
                $display("PASS coarse packet timestamp available before ToA                 value=0x%016h", packet_start_count);
            end
            if (toa_offset_valid) begin
                toa_seen = toa_seen + 1;
                if (toa_offset_q12 === 32'sd0)
                    $display("PASS generated ToA symmetric triplet returns zero               value=0x%08h", toa_offset_q12);
                else begin
                    errors = errors + 1;
                    $display("FAIL generated ToA symmetric triplet got=0x%08h expected=0", toa_offset_q12);
                end
            end
            if (metadata_valid) begin
                metadata_seen = metadata_seen + 1;
                if (metadata_coarse === packet_start_captured)
                    $display("PASS metadata keeps aligned coarse timestamp                    value=0x%016h", metadata_coarse);
                else begin
                    errors = errors + 1;
                    $display("FAIL metadata coarse got=0x%016h expected=0x%016h", metadata_coarse, packet_start_captured);
                end
                if (metadata_fractional_q12 === 32'sd0)
                    $display("PASS metadata joins generated fractional ToA                    value=0x%08h", metadata_fractional_q12);
                else begin
                    errors = errors + 1;
                    $display("FAIL metadata fractional got=0x%08h expected=0", metadata_fractional_q12);
                end
            end
            if (alignment_error || symbol_index_width_error || metadata_overflow) begin
                errors = errors + 1;
                $display("FAIL unexpected integration error align=%0b width=%0b overflow=%0b",
                         alignment_error, symbol_index_width_error, metadata_overflow);
            end
        end
    end

    initial begin
        expected_symbol[0]=0; expected_symbol[1]=0; expected_symbol[2]=0; expected_symbol[3]=0;
        expected_symbol[4]=0; expected_symbol[5]=0; expected_symbol[6]=0; expected_symbol[7]=0;
        expected_symbol[8]=8; expected_symbol[9]=16;

        repeat (6) @(posedge clk);
        resetn <= 1'b1;
        repeat (3) @(posedge clk);

        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0000, "AXI status reset before receiver enable");
        axi_write(6'h00, 32'h0000_0001);
        if (receiver_enable)
            $display("PASS AXI receiver_enable controls IQ acceptance");
        else begin
            errors = errors + 1;
            $display("FAIL AXI receiver_enable did not assert");
        end

        drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0);
        drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0);
        drive_css_symbol(8); drive_css_symbol(16);
        @(negedge clk);
        valid_in <= 1'b0; iq_in_re <= 16'sd0; iq_in_im <= 16'sd0;

        timeout_cycles = 0;
        while ((packet_start_seen == 0) && (timeout_cycles < 20000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (packet_start_seen != 1) begin
            errors = errors + 1;
            $display("FAIL expected one coarse packet timestamp before ToA request");
        end

        // Symmetric log-parabolic peak. The generated interpolator must return
        // exactly zero fractional samples; use comfortable integer magnitudes
        // so the test also exercises its real iterative datapath.
        @(negedge clk);
        magnitude_before <= 32'd1048576;
        magnitude_peak   <= 32'd4194304;
        magnitude_after  <= 32'd1048576;
        triplet_valid    <= 1'b1;
        @(negedge clk);
        triplet_valid    <= 1'b0;

        timeout_cycles = 0;
        while ((metadata_seen == 0) && (timeout_cycles < 200)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        repeat (4) @(posedge clk);

        if (toa_seen != 1) begin
            errors = errors + 1;
            $display("FAIL expected one generated ToA result, got=%0d", toa_seen);
        end
        if (metadata_seen != 1) begin
            errors = errors + 1;
            $display("FAIL expected one atomic metadata record, got=%0d", metadata_seen);
        end

        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0005, "AXI status has snapshot_valid plus receiver_enable");
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0001, "AXI sequence increments for complete packet timestamp");
        axi_read(6'h0c, read_value);
        expect32(read_value, packet_start_captured[31:0], "AXI coarse low matches aligned packet start");
        axi_read(6'h10, read_value);
        expect32(read_value, packet_start_captured[63:32], "AXI coarse high matches aligned packet start");
        axi_read(6'h14, read_value);
        expect32(read_value, 32'h0000_0000, "AXI fractional word comes from generated ToA");

        if (symbol_seen != 10) begin
            errors = errors + 1;
            $display("FAIL expected ten FFT decisions, got=%0d", symbol_seen);
        end

        if (errors == 0)
            $display("PASS tb_lora_packet_timestamp_axi_path");
        else begin
            $display("FAIL tb_lora_packet_timestamp_axi_path errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
