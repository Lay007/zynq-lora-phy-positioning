`timescale 1ns/1ps

module tb_lora_axi_lite_status;
    reg clk = 1'b0;
    reg resetn = 1'b0;

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

    reg  [63:0] metadata_coarse = 64'd0;
    reg  [31:0] metadata_fractional_q12 = 32'd0;
    reg         metadata_valid = 1'b0;
    reg         metadata_overflow = 1'b0;
    wire        receiver_enable;

    integer errors = 0;
    reg [31:0] read_value;

    always #5 clk = ~clk;

    lora_axi_lite_status dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(resetn),
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
        .metadata_coarse(metadata_coarse),
        .metadata_fractional_q12(metadata_fractional_q12),
        .metadata_valid(metadata_valid),
        .metadata_overflow(metadata_overflow),
        .receiver_enable(receiver_enable)
    );

    task automatic expect32(
        input [31:0] got,
        input [31:0] expected,
        input [8*48-1:0] label
    );
        begin
            if (got !== expected) begin
                $display("FAIL %-48s got=0x%08x expected=0x%08x", label, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-48s value=0x%08x", label, got);
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

    // Exercise the legal case where address and data channels do not arrive
    // together. This catches AXI-Lite slaves that incorrectly require both
    // VALID signals in the same cycle.
    task automatic axi_write_split(
        input [5:0] address,
        input [31:0] value
    );
        begin
            @(negedge clk);
            awaddr  = address;
            awvalid = 1'b1;
            while (!awready)
                @(negedge clk);
            @(negedge clk);
            awvalid = 1'b0;

            repeat (2) @(negedge clk);
            wdata  = value;
            wstrb  = 4'hf;
            wvalid = 1'b1;
            while (!wready)
                @(negedge clk);
            @(negedge clk);
            wvalid = 1'b0;
            wstrb  = 4'd0;

            while (!bvalid)
                @(negedge clk);
            if (bresp !== 2'b00) begin
                $display("FAIL split AXI write response at address 0x%02x", address);
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

    task automatic pulse_metadata(
        input [63:0] coarse,
        input [31:0] fractional
    );
        begin
            @(negedge clk);
            metadata_coarse = coarse;
            metadata_fractional_q12 = fractional;
            metadata_valid = 1'b1;
            @(negedge clk);
            metadata_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1'b1;
        repeat (2) @(negedge clk);

        axi_read(6'h18, read_value);
        expect32(read_value, 32'h0001_0000, "register map version");
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0000, "reset status");
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0000, "reset sequence");

        axi_write(6'h00, 32'h0000_0001);
        expect32({31'd0, receiver_enable}, 32'h0000_0001, "receiver enable output");
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0004, "enabled status");

        pulse_metadata(64'h1122_3344_5566_7788, 32'hffff_f800);
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0005, "first snapshot status");
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0001, "first snapshot sequence");
        axi_read(6'h0c, read_value);
        expect32(read_value, 32'h5566_7788, "first coarse low");
        axi_read(6'h10, read_value);
        expect32(read_value, 32'h1122_3344, "first coarse high");
        axi_read(6'h14, read_value);
        expect32(read_value, 32'hffff_f800, "first fractional Q12");

        @(negedge clk);
        metadata_overflow = 1'b1;
        @(negedge clk);
        metadata_overflow = 1'b0;
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0007, "overflow sticky status");

        pulse_metadata(64'hdead_beef_0123_4567, 32'h0000_0400);
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0002, "second snapshot sequence");
        axi_read(6'h0c, read_value);
        expect32(read_value, 32'h0123_4567, "second coarse low");
        axi_read(6'h10, read_value);
        expect32(read_value, 32'hdead_beef, "second coarse high");
        axi_read(6'h14, read_value);
        expect32(read_value, 32'h0000_0400, "second fractional Q12");

        // Clear sticky flags with address and data channels separated while
        // keeping the receiver enabled. Snapshot data and sequence remain.
        axi_write_split(6'h00, 32'h0000_0003);
        axi_read(6'h04, read_value);
        expect32(read_value, 32'h0000_0004, "status after W1C");
        axi_read(6'h08, read_value);
        expect32(read_value, 32'h0000_0002, "sequence survives W1C");
        axi_read(6'h10, read_value);
        expect32(read_value, 32'hdead_beef, "snapshot survives W1C");

        axi_read(6'h3c, read_value);
        expect32(read_value, 32'h0000_0000, "unmapped read returns zero");

        if (errors == 0) begin
            $display("PASS tb_lora_axi_lite_status");
            $finish;
        end

        $display("FAIL tb_lora_axi_lite_status errors=%0d", errors);
        $fatal(1);
    end

endmodule
