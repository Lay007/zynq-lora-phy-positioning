`timescale 1ns/1ps

// Compose the current receiver timestamp datapath into the PS-facing AXI-Lite
// boundary:
//
//   fixed-point IQ -> generated FFT correlator -> generated blind detector
//       -> aligned coarse packet timestamp
//       + generated packet-rate ToA interpolator
//       -> atomic coarse/fractional metadata join
//       -> AXI4-Lite snapshot registers
//
// The matched-filter peak triplet is still an explicit integration input. It
// belongs to the future board-facing matched-filter/peak-search path; keeping
// it visible here avoids pretending that hardware block already exists.
//
// All logic in this wrapper is intentionally single-clock. CDC belongs at the
// AD936x/board boundary once the actual clock plan is fixed.
`ifdef LORA_NAMESPACED_GENERATED
`define LORA_TOA_INTERPOLATOR_MODULE lora_toa_ToaInterpolator
`else
`define LORA_TOA_INTERPOLATOR_MODULE ToaInterpolator
`endif

module lora_packet_timestamp_axi_path (
    input  wire               clk,
    input  wire               resetn,

    input  wire signed [15:0] iq_in_re,
    input  wire signed [15:0] iq_in_im,
    input  wire               valid_in,
    input  wire               reset_in,
    input  wire               resync_valid,
    input  wire [31:0]        resync_skip,
    input  wire [7:0]         sync_word,

    input  wire [31:0]        magnitude_before,
    input  wire [31:0]        magnitude_peak,
    input  wire [31:0]        magnitude_after,
    input  wire               triplet_valid,

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
    output wire               detected,
    output wire               preamble_detected,
    output wire               sync_valid,
    output wire [63:0]        packet_start_count,
    output wire               packet_start_valid,

    output wire signed [31:0] toa_offset_q12,
    output wire               toa_offset_valid,
    output wire signed [31:0] toa_log_peak_q12,

    output wire [63:0]        metadata_coarse,
    output wire signed [31:0] metadata_fractional_q12,
    output wire               metadata_valid,
    output wire               metadata_overflow,

    output wire               alignment_error,
    output wire               symbol_index_width_error
);

    wire [15:0] confidence_unused;
    wire [63:0] symbol_sample_count_unused;
    wire timestamp_valid_unused;
    wire [15:0] preamble_bin_unused;
    wire [15:0] chips_to_boundary_unused;
    wire [7:0]  bins_seen_unused;
    wire [63:0] preamble_start_count_unused;
    wire preamble_start_valid_unused;

    // AXI control is now functional: disabled receivers do not advance the
    // generated correlator's valid-sample framing state.
    wire gated_valid_in = valid_in && receiver_enable;

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
        .confidence(confidence_unused),
        .symbol_sample_count(symbol_sample_count_unused),
        .timestamp_valid(timestamp_valid_unused),
        .detected(detected),
        .preamble_detected(preamble_detected),
        .sync_valid(sync_valid),
        .preamble_bin(preamble_bin_unused),
        .chips_to_boundary(chips_to_boundary_unused),
        .bins_seen(bins_seen_unused),
        .preamble_start_count(preamble_start_count_unused),
        .preamble_start_valid(preamble_start_valid_unused),
        .packet_start_count(packet_start_count),
        .packet_start_valid(packet_start_valid),
        .alignment_error(alignment_error),
        .symbol_index_width_error(symbol_index_width_error)
    );

    // A streaming reset must discard an in-flight interpolation request and a
    // partially assembled metadata record. The AXI register bank uses only the
    // global reset so software can still read the last complete snapshot after
    // a receiver resync.
    wire datapath_resetn = resetn && !reset_in;

    `LORA_TOA_INTERPOLATOR_MODULE u_toa_interpolator (
        .clk(clk),
        .reset(~datapath_resetn),
        .enb(1'b1),
        .magnitudeBefore(magnitude_before),
        .magnitudePeak(magnitude_peak),
        .magnitudeAfter(magnitude_after),
        .tripletValid(triplet_valid),
        .offsetSamples(toa_offset_q12),
        .offsetValid(toa_offset_valid),
        .logPeak(toa_log_peak_q12)
    );

    lora_timestamp_metadata_join u_metadata_join (
        .clk(clk),
        .resetn(datapath_resetn),
        .coarse_sample_count(packet_start_count),
        .coarse_valid(packet_start_valid),
        .fractional_toa_q12(toa_offset_q12),
        .fractional_valid(toa_offset_valid),
        .timestamp_coarse(metadata_coarse),
        .timestamp_fractional_q12(metadata_fractional_q12),
        .timestamp_valid(metadata_valid),
        .metadata_overflow(metadata_overflow)
    );

    lora_axi_lite_status u_axi_status (
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
