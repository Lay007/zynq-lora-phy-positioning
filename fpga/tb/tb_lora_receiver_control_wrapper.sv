`timescale 1ns/1ps

module tb_lora_receiver_control_wrapper;
    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg sample_valid = 1'b0;
    reg coarse_capture = 1'b0;
    reg signed [31:0] fractional_toa_q12 = 32'sd0;
    reg fractional_valid = 1'b0;

    reg  [5:0]  awaddr = 6'd0;
    reg         awvalid = 1'b0;
    wire        awready;
    reg  [31:0] wdata = 32'd0;
    reg  [3:0]  wstrb = 4'd0;
    reg         wvalid = 1'b0;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready = 1'b0;

    reg  [5:0]  araddr = 6'd0;
    reg         arvalid = 1'b0;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready = 1'b0;

    wire receiver_enable;

    integer errors = 0;
    reg [31:0] read_value;

    always #5 clk = ~clk;

    lora_receiver_control_wrapper dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(resetn),
        .sample_valid(sample_valid),
        .coarse_capture(coarse_capture),
        .fractional_toa_q12(fractional_toa_q12),
        .fractional_valid(fractional_valid),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .receiver_enable(receiver_enable)
    );

    task automatic expect32(
        input [31:0] got,
        input [31:0] expected,
        input [8*64-1:0] label
    );
        begin
            if (got !== expected) begin
                $display("FAIL %-64s got=0x%08x expected=0x%08x", label, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-64s value=0x%08x", label, got);
            end
        end
    endtask

    task automatic axi_write(
        input [5:0] address,
        input [31:0] value
    );
        begin
            @(negedge clk);
            awaddr  = address;
            awvalid = 1'b1;
            wdata   = value;
            wstrb   = 4'hf;
            wvalid  = 1'b1;

            while (!(awready && wready))
                @(negedge clk);

            @(negedge clk);
            awvalid = 1'b0;
            wvalid  = 1'b0;
            wstrb   = 4'd0;

            while (!bvalid)
                @(negedge clk);
            if (bresp !== 2'b00) begin
                $display("FAIL AXI write response at address 0x%02x", address);
                errors = errors + 1;
            end
            bready = 1'b1;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input [5:0] address,
        output [31:0] value
    );
        begin
            @(negedge clk);
            araddr  = address;
            arvalid = 1'b1;
            while (!arready)
                @(negedge clk);
            @(negedge clk);
            arvalid = 1'b0;

            while (!rvalid)
                @(negedge clk);
            value = rdata;
            if (rresp !== 2'b00) begin
                $display("FAIL AXI read response at address 0x%02x", address);
                errors = errors + 1;
            end
            rready = 1'b1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task automatic accept_samples(input integer count);
        integer i;
        begin
            @(negedge clk);
            sample_valid = 1'b1;
            for (i = 0; i < count; i = i + 1)
                @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task automatic pulse_capture;
        begin
            @(negedge clk);
            coarse_capture = 1'b1;
            @(negedge clk);
            coarse_capture = 1'b0;
        end
    endtask

    task automatic pulse_fractional(input signed [31:0] value);
        begin
            @(negedge clk);
            fractional_toa_q12 = value;
            fractional_valid = 1'b1;
            @(negedge clk);
            fractional_valid = 1'b0;
        end
    endtask

    task automatic pulse_sample_capture_fractional(
        input signed [31:0] fractional
    );
        begin
            @(negedge clk);
            sample_valid = 1'b1;
            coarse_capture = 1'b1;
            fractional_toa_q12 = fractional;
            fractional_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
            coarse_capture = 1'b0;
            fractional_valid = 1'b0;
        end
    endtask

    task automatic pulse_capture_and_fractional(
        input signed [31:0] fractional
    );
        begin
            @(negedge clk);
            coarse_capture = 1'b1;
            fractional_toa_q12 = fractional;
            fractional_valid = 1'b1;
            @(negedge clk);
            coarse_capture = 1'b0;
            fractional_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1'b1;
        repeat (2) @(negedge clk);

        axi_read(6'h18, read_value);
        expect32(read_value, 32'h0001_0000, "register-map version through composed wrapper");

        axi_write(6'h00, 32'h0000_0001);
        expect32({31'd0, receiver_enable}, 32'h0000_0001, "receiver enable reaches wrapper output");

        // Coarse-first metadata pair. Five accepted samples establish a coarse
        // count of 5 before the capture event.
        accept_samples(5);
        pulse_capture();
        pulse_fractional(-32'sd2048);
        repeat (4) @(negedge clk);
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0001, "coarse-first sequence");
        axi_read(6'h0c, read_value);
        expect32(read_value, 32'h0000_0005, "coarse-first PL sample count");
        axi_read(6'h10, read_value);
        expect32(read_value, 32'h0000_0000, "coarse-first high word");
        axi_read(6'h14, read_value);
        expect32(read_value, 32'hffff_f800, "coarse-first fractional Q12");

        // Fraction-first metadata pair. Three more accepted samples move the
        // live PL sample count to 8 before the second coarse capture.
        pulse_fractional(32'sd1024);
        accept_samples(3);
        pulse_capture();
        repeat (4) @(negedge clk);
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0002, "fraction-first sequence");
        axi_read(6'h0c, read_value);
        expect32(read_value, 32'h0000_0008, "fraction-first PL sample count");
        axi_read(6'h14, read_value);
        expect32(read_value, 32'h0000_0400, "fraction-first fractional Q12");

        // Duplicate unmatched coarse captures must not replace the first
        // fragment and must set the sticky overflow bit in the AXI status.
        pulse_capture();
        pulse_capture();
        pulse_fractional(32'sd256);
        repeat (4) @(negedge clk);
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0007, "sticky overflow propagated through composition");
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0003, "duplicate coarse capture still emits one record");
        axi_read(6'h0c, read_value);
        expect32(read_value, 32'h0000_0008, "first coarse capture retained after duplicate");

        // Clear sticky flags while keeping the receiver enabled.
        axi_write(6'h00, 32'h0000_0003);
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0004, "W1C clears composed metadata status");

        // Reset must discard a captured coarse fragment and clear the PL
        // sample counter as part of the same control-domain reset contract.
        accept_samples(2);
        pulse_capture();
        @(negedge clk);
        resetn = 1'b0;
        repeat (2) @(negedge clk);
        resetn = 1'b1;
        repeat (2) @(negedge clk);

        pulse_fractional(32'sd512);
        repeat (3) @(negedge clk);
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0000, "captured coarse fragment discarded by reset");
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0000, "status reset across composed wrapper");
        expect32({31'd0, receiver_enable}, 32'h0000_0000, "receiver enable reset");

        // Clear the intentionally orphaned post-reset fractional fragment so
        // the next scenario is independent.
        @(negedge clk);
        resetn = 1'b0;
        repeat (2) @(negedge clk);
        resetn = 1'b1;
        repeat (2) @(negedge clk);

        // Four samples are accepted after reset. On the next edge sample_valid,
        // coarse_capture and fractional_valid are asserted together. By
        // definition the coarse timestamp is the pre-increment count (4), and
        // the same edge advances the live counter to 5.
        axi_write(6'h00, 32'h0000_0001);
        accept_samples(4);
        pulse_sample_capture_fractional(-32'sd1);
        repeat (5) @(negedge clk);
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0001, "same-edge sample/capture sequence after reset");
        axi_read(6'h0c, read_value);
        expect32(read_value, 32'h0000_0004, "same-edge capture uses pre-increment sample count");
        axi_read(6'h14, read_value);
        expect32(read_value, 32'hffff_ffff, "same-edge signed fractional Q12");

        // A subsequent capture with no accepted sample must observe 5,
        // proving that the previous simultaneous sample advanced the timebase.
        pulse_capture_and_fractional(32'sd0);
        repeat (5) @(negedge clk);
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0002, "post-increment capture sequence");
        axi_read(6'h0c, read_value);
        expect32(read_value, 32'h0000_0005, "sample counter advances after same-edge capture");

        if (errors == 0) begin
            $display("PASS tb_lora_receiver_control_wrapper");
            $finish;
        end

        $display("FAIL tb_lora_receiver_control_wrapper errors=%0d", errors);
        $fatal(1);
    end

endmodule
