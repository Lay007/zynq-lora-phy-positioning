`timescale 1ns/1ps

// CLG400 board adapter for the portable LoRa timestamp receiver.
//
// The AD9361 FIFO already supplies signed, formatted complex samples in the
// divided sample clock domain. The course axi_gpreg control/status block lives
// on sys_cpu_clk, so this wrapper uses a request/acknowledge toggle to transfer
// each complete 128-bit timestamp record atomically. The payload is held stable
// from request until acknowledgement; only the toggles pass through ordinary
// two-flop synchronizers.
module lora_clg400_gpreg_bridge #(
    parameter REFERENCE_FILE = "fpga/rom/lora_sf7_l8_reference_q10.mem"
) (
    input  wire                    ctrl_clk,
    input  wire                    ctrl_resetn,
    input  wire                    sample_clk,
    input  wire                    sample_resetn,
    input  wire [31:0]             gp_ctrl,
    input  wire [32:0]             rx_sample_bus,

    output wire [31:0]             gp_status,
    output reg  [31:0]             gp_sequence,
    output reg  [31:0]             gp_coarse_lo,
    output reg  [31:0]             gp_coarse_hi,
    output reg  [31:0]             gp_fractional_q12,
    output reg  [31:0]             gp_log_peak_q12,
    output wire [31:0]             gp_debug,
    output wire [31:0]             gp_signature
);

    localparam [31:0] SIGNATURE = 32'h4c4f5241; // "LORA"

    wire                    rx_valid = rx_sample_bus[32];
    wire signed [15:0]      rx_i = rx_sample_bus[31:16];
    wire signed [15:0]      rx_q = rx_sample_bus[15:0];

    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sample_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sample_sync;

    wire receiver_requested = ctrl_sample_sync[0];
    wire stream_reset = !receiver_requested || ctrl_sample_sync[1];
    wire [7:0] configured_sync_word =
        (ctrl_sample_sync[15:8] == 8'h00) ? 8'h12 : ctrl_sample_sync[15:8];

    wire [63:0] metadata_coarse;
    wire signed [31:0] metadata_fractional_q12;
    wire metadata_valid;
    wire metadata_overflow;
    wire signed [31:0] toa_log_peak_q12;
    wire toa_search_busy;
    wire [63:0] packet_start_count;
    wire packet_start_valid;
    wire correlation_magnitude_valid;
    wire peak_triplet_valid;
    wire toa_offset_valid;
    wire alignment_error;
    wire symbol_index_width_error;
    wire toa_underflow_error;
    wire toa_search_restart_error;
    wire toa_mac_window_mismatch_error;
    wire toa_mac_read_miss_error;
    wire toa_mac_response_mismatch_error;
    wire toa_mac_restart_error;
    wire toa_peak_boundary_error;
    wire toa_peak_restart_error;
    wire internal_receiver_enable;

    wire unused_awready;
    wire unused_wready;
    wire [1:0] unused_bresp;
    wire unused_bvalid;
    wire unused_arready;
    wire [31:0] unused_rdata;
    wire [1:0] unused_rresp;
    wire unused_rvalid;

    lora_packet_toa_receiver_top #(
        .DEFAULT_RECEIVER_ENABLE(1'b1),
        .REFERENCE_FILE(REFERENCE_FILE)
    ) u_receiver (
        .clk(sample_clk),
        .resetn(sample_resetn),
        .iq_in_re(rx_i),
        .iq_in_im(rx_q),
        .valid_in(rx_valid && receiver_requested),
        .reset_in(stream_reset),
        .resync_valid(1'b0),
        .resync_skip(32'd0),
        .sync_word(configured_sync_word),

        .s_axi_awaddr(6'd0),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(unused_awready),
        .s_axi_wdata(32'd0),
        .s_axi_wstrb(4'd0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(unused_wready),
        .s_axi_bresp(unused_bresp),
        .s_axi_bvalid(unused_bvalid),
        .s_axi_bready(1'b1),
        .s_axi_araddr(6'd0),
        .s_axi_arvalid(1'b0),
        .s_axi_arready(unused_arready),
        .s_axi_rdata(unused_rdata),
        .s_axi_rresp(unused_rresp),
        .s_axi_rvalid(unused_rvalid),
        .s_axi_rready(1'b1),

        .receiver_enable(internal_receiver_enable),
        .symbol_index(),
        .symbol_valid(),
        .detected(),
        .preamble_detected(),
        .sync_valid(),
        .packet_start_count(packet_start_count),
        .packet_start_valid(packet_start_valid),
        .toa_search_busy(toa_search_busy),
        .toa_search_first_count(),
        .correlation_magnitude(),
        .correlation_magnitude_valid(correlation_magnitude_valid),
        .correlation_sample_count(),
        .peak_index(),
        .peak_sample_count(),
        .peak_triplet_valid(peak_triplet_valid),
        .toa_offset_q12(),
        .toa_offset_valid(toa_offset_valid),
        .toa_log_peak_q12(toa_log_peak_q12),
        .metadata_coarse(metadata_coarse),
        .metadata_fractional_q12(metadata_fractional_q12),
        .metadata_valid(metadata_valid),
        .history_next_sample_count(),
        .history_oldest_sample_count(),
        .history_samples_retained(),
        .alignment_error(alignment_error),
        .symbol_index_width_error(symbol_index_width_error),
        .metadata_overflow(metadata_overflow),
        .toa_underflow_error(toa_underflow_error),
        .toa_search_restart_error(toa_search_restart_error),
        .toa_mac_window_mismatch_error(toa_mac_window_mismatch_error),
        .toa_mac_read_miss_error(toa_mac_read_miss_error),
        .toa_mac_response_mismatch_error(toa_mac_response_mismatch_error),
        .toa_mac_restart_error(toa_mac_restart_error),
        .toa_peak_boundary_error(toa_peak_boundary_error),
        .toa_peak_restart_error(toa_peak_restart_error)
    );

    // Sample-domain event mailbox. A new record may replace the holding
    // register only after the control domain acknowledges the previous one.
    reg [127:0] event_hold_sample;
    reg event_request_toggle;
    reg bridge_overflow_sample;
    reg packet_seen_sample;
    reg sample_seen_sample;
    reg [15:0] packet_start_count_low_sample;
    reg [14:0] diagnostic_sticky_sample;
    (* ASYNC_REG = "TRUE" *) reg event_ack_meta;
    (* ASYNC_REG = "TRUE" *) reg event_ack_sync;

    // Control-domain mailbox receiver.
    (* ASYNC_REG = "TRUE" *) reg event_request_meta;
    (* ASYNC_REG = "TRUE" *) reg event_request_sync;
    reg event_ack_toggle;
    reg snapshot_valid_ctrl;

    // Low-rate diagnostic flags cross independently; they are status only and
    // do not form part of the atomic timestamp record.
    (* ASYNC_REG = "TRUE" *) reg [4:0] status_meta;
    (* ASYNC_REG = "TRUE" *) reg [4:0] status_sync;

    always @(posedge sample_clk) begin
        if (!sample_resetn) begin
            ctrl_sample_meta      <= 32'd0;
            ctrl_sample_sync      <= 32'd0;
            event_ack_meta        <= 1'b0;
            event_ack_sync        <= 1'b0;
            event_hold_sample     <= 128'd0;
            event_request_toggle  <= 1'b0;
            bridge_overflow_sample<= 1'b0;
            packet_seen_sample    <= 1'b0;
            sample_seen_sample    <= 1'b0;
            packet_start_count_low_sample <= 16'd0;
            diagnostic_sticky_sample <= 15'd0;
        end else begin
            ctrl_sample_meta <= gp_ctrl;
            ctrl_sample_sync <= ctrl_sample_meta;
            event_ack_meta   <= event_ack_toggle;
            event_ack_sync   <= event_ack_meta;

            if (stream_reset) begin
                packet_seen_sample <= 1'b0;
                sample_seen_sample <= 1'b0;
                packet_start_count_low_sample <= 16'd0;
                diagnostic_sticky_sample <= 15'd0;
            end else begin
                if (rx_valid)
                    sample_seen_sample <= 1'b1;
                if (packet_start_valid) begin
                    packet_seen_sample <= 1'b1;
                    packet_start_count_low_sample <= packet_start_count[15:0];
                end

                diagnostic_sticky_sample <= diagnostic_sticky_sample | {
                    alignment_error,
                    symbol_index_width_error,
                    toa_underflow_error,
                    toa_search_restart_error,
                    toa_mac_window_mismatch_error,
                    toa_mac_read_miss_error,
                    toa_mac_response_mismatch_error,
                    toa_mac_restart_error,
                    toa_peak_boundary_error,
                    toa_peak_restart_error,
                    toa_search_busy,
                    correlation_magnitude_valid,
                    peak_triplet_valid,
                    toa_offset_valid,
                    metadata_valid
                };
            end

            if (metadata_overflow)
                bridge_overflow_sample <= 1'b1;

            if (metadata_valid) begin
                if (event_request_toggle == event_ack_sync) begin
                    event_hold_sample <= {
                        toa_log_peak_q12,
                        metadata_fractional_q12,
                        metadata_coarse
                    };
                    event_request_toggle <= !event_request_toggle;
                end else begin
                    bridge_overflow_sample <= 1'b1;
                end
            end
        end
    end

    always @(posedge ctrl_clk) begin
        if (!ctrl_resetn) begin
            event_request_meta <= 1'b0;
            event_request_sync <= 1'b0;
            event_ack_toggle   <= 1'b0;
            status_meta        <= 5'd0;
            status_sync        <= 5'd0;
            gp_sequence        <= 32'd0;
            gp_coarse_lo       <= 32'd0;
            gp_coarse_hi       <= 32'd0;
            gp_fractional_q12  <= 32'd0;
            gp_log_peak_q12    <= 32'd0;
            snapshot_valid_ctrl<= 1'b0;
        end else begin
            event_request_meta <= event_request_toggle;
            event_request_sync <= event_request_meta;
            status_meta <= {
                sample_seen_sample,
                packet_seen_sample,
                toa_search_busy,
                bridge_overflow_sample,
                receiver_requested
            };
            status_sync <= status_meta;

            if (event_request_sync != event_ack_toggle) begin
                gp_coarse_lo       <= event_hold_sample[31:0];
                gp_coarse_hi       <= event_hold_sample[63:32];
                gp_fractional_q12  <= event_hold_sample[95:64];
                gp_log_peak_q12    <= event_hold_sample[127:96];
                gp_sequence        <= gp_sequence + 32'd1;
                snapshot_valid_ctrl<= 1'b1;
                event_ack_toggle   <= event_request_sync;
            end
        end
    end

    assign gp_status = {
        16'h0001,
        gp_ctrl[15:8],
        gp_ctrl[1],
        status_sync[4],
        status_sync[3],
        status_sync[2],
        status_sync[1],
        snapshot_valid_ctrl,
        status_sync[0],
        gp_ctrl[0]
    };
    assign gp_debug = {
        diagnostic_sticky_sample,
        internal_receiver_enable,
        packet_start_count_low_sample
    };
    assign gp_signature = SIGNATURE;

endmodule
