`timescale 1ns/1ps

// Minimal AXI4-Lite control/status register bank for the LoRa receiver wrapper.
//
// The metadata input is expected to come from lora_timestamp_metadata_join.
// Every metadata_valid pulse atomically snapshots the coarse and fractional
// timestamp fields and increments a sequence counter. The snapshot registers
// remain stable until the next complete metadata event, so software may read
// the three timestamp words without a torn update between fields by checking
// the sequence counter before/after the read if required.
//
// Register map (byte offsets):
//   0x00 CONTROL   RW  bit 0 receiver_enable
//                      bit 1 write-one-to-clear status flags
//   0x04 STATUS    RO  bit 0 snapshot_valid
//                      bit 1 metadata_overflow_sticky
//                      bit 2 receiver_enable
//   0x08 SEQUENCE  RO  increments on every metadata_valid pulse
//   0x0c COARSE_LO RO  timestamp_coarse[31:0]
//   0x10 COARSE_HI RO  timestamp_coarse[63:32]
//   0x14 FRACTION  RO  signed Q12 fractional ToA, raw 32-bit value
//   0x18 VERSION   RO  0x0001_0000 (register-map version 1.0)
module lora_axi_lite_status (
    input  wire         s_axi_aclk,
    input  wire         s_axi_aresetn,

    input  wire [5:0]   s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output reg  [1:0]   s_axi_bresp,
    output reg          s_axi_bvalid,
    input  wire         s_axi_bready,

    input  wire [5:0]   s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output reg  [31:0]  s_axi_rdata,
    output reg  [1:0]   s_axi_rresp,
    output reg          s_axi_rvalid,
    input  wire         s_axi_rready,

    input  wire [63:0]  metadata_coarse,
    input  wire [31:0]  metadata_fractional_q12,
    input  wire         metadata_valid,
    input  wire         metadata_overflow,

    output reg          receiver_enable
);

    localparam [5:0] ADDR_CONTROL   = 6'h00;
    localparam [5:0] ADDR_STATUS    = 6'h04;
    localparam [5:0] ADDR_SEQUENCE  = 6'h08;
    localparam [5:0] ADDR_COARSE_LO = 6'h0c;
    localparam [5:0] ADDR_COARSE_HI = 6'h10;
    localparam [5:0] ADDR_FRACTION  = 6'h14;
    localparam [5:0] ADDR_VERSION   = 6'h18;

    reg [5:0]  awaddr_hold;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;
    reg        aw_pending;
    reg        w_pending;

    reg [63:0] timestamp_coarse_snapshot;
    reg [31:0] timestamp_fractional_snapshot;
    reg [31:0] sequence_counter;
    reg        snapshot_valid;
    reg        metadata_overflow_sticky;

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            awaddr_hold                  <= 6'd0;
            wdata_hold                   <= 32'd0;
            wstrb_hold                   <= 4'd0;
            aw_pending                   <= 1'b0;
            w_pending                    <= 1'b0;
            s_axi_bresp                  <= 2'b00;
            s_axi_bvalid                 <= 1'b0;
            s_axi_rdata                  <= 32'd0;
            s_axi_rresp                  <= 2'b00;
            s_axi_rvalid                 <= 1'b0;
            receiver_enable              <= 1'b0;
            timestamp_coarse_snapshot    <= 64'd0;
            timestamp_fractional_snapshot<= 32'd0;
            sequence_counter             <= 32'd0;
            snapshot_valid               <= 1'b0;
            metadata_overflow_sticky     <= 1'b0;
        end else begin
            // AXI write-address and write-data channels are accepted
            // independently, as required by AXI4-Lite.
            if (s_axi_awready && s_axi_awvalid) begin
                awaddr_hold <= s_axi_awaddr;
                aw_pending  <= 1'b1;
            end

            if (s_axi_wready && s_axi_wvalid) begin
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
                w_pending  <= 1'b1;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            // Commit a write only after both channels have arrived.
            if (aw_pending && w_pending && !s_axi_bvalid) begin
                if (awaddr_hold == ADDR_CONTROL && wstrb_hold[0]) begin
                    receiver_enable <= wdata_hold[0];
                    if (wdata_hold[1]) begin
                        snapshot_valid           <= 1'b0;
                        metadata_overflow_sticky <= 1'b0;
                    end
                end
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bresp  <= 2'b00;
                s_axi_bvalid <= 1'b1;
            end

            // Metadata events are applied after W1C handling so a new event
            // arriving in the same cycle as a clear operation is retained.
            if (metadata_valid) begin
                timestamp_coarse_snapshot     <= metadata_coarse;
                timestamp_fractional_snapshot <= metadata_fractional_q12;
                sequence_counter              <= sequence_counter + 32'd1;
                snapshot_valid                <= 1'b1;
            end

            if (metadata_overflow)
                metadata_overflow_sticky <= 1'b1;

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (s_axi_arready && s_axi_arvalid) begin
                case (s_axi_araddr)
                    ADDR_CONTROL:
                        s_axi_rdata <= {31'd0, receiver_enable};
                    ADDR_STATUS:
                        s_axi_rdata <= {29'd0, receiver_enable,
                                        metadata_overflow_sticky,
                                        snapshot_valid};
                    ADDR_SEQUENCE:
                        s_axi_rdata <= sequence_counter;
                    ADDR_COARSE_LO:
                        s_axi_rdata <= timestamp_coarse_snapshot[31:0];
                    ADDR_COARSE_HI:
                        s_axi_rdata <= timestamp_coarse_snapshot[63:32];
                    ADDR_FRACTION:
                        s_axi_rdata <= timestamp_fractional_snapshot;
                    ADDR_VERSION:
                        s_axi_rdata <= 32'h0001_0000;
                    default:
                        s_axi_rdata <= 32'd0;
                endcase
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end
        end
    end

endmodule
