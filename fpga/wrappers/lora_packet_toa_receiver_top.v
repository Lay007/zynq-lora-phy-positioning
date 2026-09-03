`timescale 1ns/1ps

// Complete portable SF7/L=8 packet timestamp path.
//
// Accepted IQ samples feed both the generated symbol/acquisition path and a
// circular sample history. A confirmed packet timestamp automatically starts a
// short, packet-rate matched-filter search around that coarse sample. The
// strongest integer lag and the generated log-parabolic fractional estimate
// are joined atomically and exposed through AXI4-Lite.
//
// This top is intentionally single-clock. The board adapter must cross AD936x
// samples into this domain and cross the joined metadata record into the PS AXI
// domain if those clocks differ. It must not synchronize the multiword record
// with unrelated two-flop synchronizers.
`ifdef LORA_NAMESPACED_GENERATED
`define LORA_TOA_INTERPOLATOR_MODULE lora_toa_ToaInterpolator
`else
`define LORA_TOA_INTERPOLATOR_MODULE ToaInterpolator
`endif

module lora_packet_toa_receiver_top #(
    parameter integer HISTORY_DEPTH = 65536,
    parameter integer REF_SAMPLES = 1024,
    parameter integer SEARCH_RADIUS = 8,
    parameter integer MATCH_ACC_WIDTH = 48,
    parameter integer MATCH_POWER_SHIFT = 30,
    parameter DEFAULT_RECEIVER_ENABLE = 1'b0,
    parameter REFERENCE_FILE = "fpga/rom/lora_sf7_l8_reference_q10.mem"
) (
    input  wire               clk,
    input  wire               resetn,

    input  wire signed [15:0] iq_in_re,
    input  wire signed [15:0] iq_in_im,
    input  wire               valid_in,
    input  wire               reset_in,
    input  wire               resync_valid,
    input  wire [31:0]        resync_skip,
    input  wire [7:0]         sync_word,

    input  wire [5:0]         s_axi_awaddr,
    input  wire               s_axi_awvalid,
    output wire               s_axi_awready,
    input  wire [31:0]        s_axi_wdata,
    input  wire [3:0]         s_axi_wstrb,
    input  wire               s_axi_wvalid,
    output wire               s_axi_wready,
    output wire [1:0]         s_axi_bresp,
    output wire               s_axi_bvalid,
    input  wire               s_axi_bready,

    input  wire [5:0]         s_axi_araddr,
    input  wire               s_axi_arvalid,
    output wire               s_axi_arready,
    output wire [31:0]        s_axi_rdata,
    output wire [1:0]         s_axi_rresp,
    output wire               s_axi_rvalid,
    input  wire               s_axi_rready,

    output wire               receiver_enable,

    output wire [31:0]        symbol_index,
    output wire               symbol_valid,
    output wire [15:0]        symbol_confidence,
    output wire [63:0]        symbol_sample_count,
    output wire               symbol_timestamp_valid,
    output wire               detected,
    output wire               preamble_detected,
    output wire               sync_valid,
    output wire [15:0]        preamble_bin,
    output wire [63:0]        packet_start_count,
    output wire               packet_start_valid,

    output wire               toa_search_busy,
    output wire [63:0]        toa_search_first_count,
    output wire [31:0]        correlation_magnitude,
    output wire               correlation_magnitude_valid,
    output wire [63:0]        correlation_sample_count,
    output wire [15:0]        peak_index,
    output wire [63:0]        peak_sample_count,
    output wire               peak_triplet_valid,
    output wire signed [31:0] toa_offset_q12,
    output wire               toa_offset_valid,
    output wire signed [31:0] toa_log_peak_q12,

    output wire [63:0]        metadata_coarse,
    output wire signed [31:0] metadata_fractional_q12,
    output wire               metadata_valid,

    output wire [63:0]        history_next_sample_count,
    output wire [63:0]        history_oldest_sample_count,
    output wire [31:0]        history_samples_retained,

    output wire               alignment_error,
    output wire               symbol_index_width_error,
    output wire               metadata_overflow,
    output wire               toa_underflow_error,
    output wire               toa_search_restart_error,
    output wire               toa_mac_window_mismatch_error,
    output wire               toa_mac_read_miss_error,
    output wire               toa_mac_response_mismatch_error,
    output wire               toa_mac_restart_error,
    output wire               toa_peak_boundary_error,
    output wire               toa_peak_restart_error
);

    wire gated_valid_in = valid_in && receiver_enable;
    wire datapath_resetn = resetn && !reset_in;

    // HDL Coder implements the active-high reset of the generated ToA block as
    // an asynchronous clear. Do not drive those clear pins from the
    // combinational resetn/reset_in expression: that creates a LUT-controlled
    // asynchronous reset which can glitch. Register the stream-reset request;
    // global reset still asserts this register asynchronously and all release
    // paths are clocked.
    reg toa_reset_reg;
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            toa_reset_reg <= 1'b1;
        else
            toa_reset_reg <= reset_in;
    end

    wire [15:0] chips_to_boundary_unused;
    wire [7:0] bins_seen_unused;
    wire [63:0] preamble_start_count_unused;
    wire preamble_start_valid_unused;

    lora_fft_detector_timestamp_path u_fft_detector_timestamp (
        .clk(clk),
        .resetn(resetn),
        .iq_in_re(iq_in_re),
        .iq_in_im(iq_in_im),
        .valid_in(gated_valid_in),
        .reset_in(reset_in),
        .resync_valid(resync_valid),
        .resync_skip(resync_skip),
        .sync_word(sync_word),
        .symbol_index(symbol_index),
        .symbol_valid(symbol_valid),
        .confidence(symbol_confidence),
        .symbol_sample_count(symbol_sample_count),
        .timestamp_valid(symbol_timestamp_valid),
        .detected(detected),
        .preamble_detected(preamble_detected),
        .sync_valid(sync_valid),
        .preamble_bin(preamble_bin),
        .chips_to_boundary(chips_to_boundary_unused),
        .bins_seen(bins_seen_unused),
        .preamble_start_count(preamble_start_count_unused),
        .preamble_start_valid(preamble_start_valid_unused),
        .packet_start_count(packet_start_count),
        .packet_start_valid(packet_start_valid),
        .alignment_error(alignment_error),
        .symbol_index_width_error(symbol_index_width_error)
    );

    wire history_read_req;
    wire [63:0] history_read_sample_count;
    wire signed [15:0] history_read_iq_re;
    wire signed [15:0] history_read_iq_im;
    wire [63:0] history_read_sample_count_out;
    wire history_read_valid;
    wire history_read_miss;

    lora_iq_history_buffer #(
        .DEPTH(HISTORY_DEPTH)
    ) u_iq_history (
        .clk(clk),
        .resetn(resetn),
        .stream_reset(reset_in),
        .iq_in_re(iq_in_re),
        .iq_in_im(iq_in_im),
        .sample_valid(gated_valid_in),
        .read_req(history_read_req),
        .read_sample_count(history_read_sample_count),
        .read_iq_re(history_read_iq_re),
        .read_iq_im(history_read_iq_im),
        .read_sample_count_out(history_read_sample_count_out),
        .read_valid(history_read_valid),
        .read_miss(history_read_miss),
        .next_sample_count(history_next_sample_count),
        .oldest_sample_count(history_oldest_sample_count),
        .samples_retained(history_samples_retained)
    );

    wire [15:0] reference_index;
    wire signed [15:0] reference_re;
    wire signed [15:0] reference_im;

    lora_reference_chirp_rom #(
        .REF_SAMPLES(REF_SAMPLES),
        .INIT_FILE(REFERENCE_FILE)
    ) u_reference_rom (
        .reference_index(reference_index),
        .reference_re(reference_re),
        .reference_im(reference_im)
    );

    wire [31:0] magnitude_before;
    wire [31:0] magnitude_peak;
    wire [31:0] magnitude_after;

    lora_matched_filter_search #(
        .REF_SAMPLES(REF_SAMPLES),
        .SEARCH_RADIUS(SEARCH_RADIUS),
        .ACC_WIDTH(MATCH_ACC_WIDTH),
        .POWER_SHIFT(MATCH_POWER_SHIFT)
    ) u_toa_search (
        .clk(clk),
        .resetn(resetn),
        .stream_reset(reset_in),
        .start(packet_start_valid && receiver_enable),
        .coarse_start_count(packet_start_count),
        .iq_read_req(history_read_req),
        .iq_read_sample_count(history_read_sample_count),
        .iq_read_re(history_read_iq_re),
        .iq_read_im(history_read_iq_im),
        .iq_read_sample_count_out(history_read_sample_count_out),
        .iq_read_valid(history_read_valid),
        .iq_read_miss(history_read_miss),
        .reference_index(reference_index),
        .reference_re(reference_re),
        .reference_im(reference_im),
        .busy(toa_search_busy),
        .search_first_count(toa_search_first_count),
        .correlation_magnitude(correlation_magnitude),
        .correlation_magnitude_valid(correlation_magnitude_valid),
        .correlation_sample_count(correlation_sample_count),
        .magnitude_before(magnitude_before),
        .magnitude_peak(magnitude_peak),
        .magnitude_after(magnitude_after),
        .peak_index(peak_index),
        .peak_sample_count(peak_sample_count),
        .triplet_valid(peak_triplet_valid),
        .underflow_error(toa_underflow_error),
        .search_restart_error(toa_search_restart_error),
        .mac_window_mismatch_error(toa_mac_window_mismatch_error),
        .mac_read_miss_error(toa_mac_read_miss_error),
        .mac_response_mismatch_error(toa_mac_response_mismatch_error),
        .mac_restart_error(toa_mac_restart_error),
        .peak_boundary_error(toa_peak_boundary_error),
        .peak_restart_error(toa_peak_restart_error)
    );

    `LORA_TOA_INTERPOLATOR_MODULE u_toa_interpolator (
        .clk(clk),
        .reset(toa_reset_reg),
        .enb(1'b1),
        .magnitudeBefore(magnitude_before),
        .magnitudePeak(magnitude_peak),
        .magnitudeAfter(magnitude_after),
        .tripletValid(peak_triplet_valid),
        .offsetSamples(toa_offset_q12),
        .offsetValid(toa_offset_valid),
        .logPeak(toa_log_peak_q12)
    );

    lora_timestamp_metadata_join u_metadata_join (
        .clk(clk),
        .resetn(datapath_resetn),
        .coarse_sample_count(peak_sample_count),
        .coarse_valid(peak_triplet_valid),
        .fractional_toa_q12(toa_offset_q12),
        .fractional_valid(toa_offset_valid),
        .timestamp_coarse(metadata_coarse),
        .timestamp_fractional_q12(metadata_fractional_q12),
        .timestamp_valid(metadata_valid),
        .metadata_overflow(metadata_overflow)
    );

    lora_axi_lite_status #(
        .DEFAULT_RECEIVER_ENABLE(DEFAULT_RECEIVER_ENABLE)
    ) u_axi_status (
        .s_axi_aclk(clk),
        .s_axi_aresetn(resetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .metadata_coarse(metadata_coarse),
        .metadata_fractional_q12(metadata_fractional_q12),
        .metadata_valid(metadata_valid),
        .metadata_overflow(metadata_overflow),
        .receiver_enable(receiver_enable)
    );

endmodule

`undef LORA_TOA_INTERPOLATOR_MODULE
