`timescale 1ns/1ps

// Compose the generated fixed-point FFT correlator with the generated blind
// detector and hand-written detector timestamp alignment path.
//
// The generated correlator remains behind fft_correlator_route_top so the
// historical generic DUT name and future ModulePrefix regeneration share one
// integration boundary. All symbol/timestamp sidebands remain cycle-aligned.
module lora_fft_detector_timestamp_path (
    input  wire               clk,
    input  wire               resetn,
    input  wire signed [15:0] iq_in_re,
    input  wire signed [15:0] iq_in_im,
    input  wire               valid_in,
    input  wire               reset_in,
    input  wire               resync_valid,
    input  wire [31:0]        resync_skip,
    input  wire [7:0]         sync_word,

    output wire [31:0]        symbol_index,
    output wire               symbol_valid,
    output wire [15:0]        confidence,
    output wire [63:0]        symbol_sample_count,
    output wire               timestamp_valid,

    output wire               detected,
    output wire               preamble_detected,
    output wire               sync_valid,
    output wire [15:0]        preamble_bin,
    output wire [15:0]        chips_to_boundary,
    output wire [7:0]         bins_seen,

    output wire [63:0]        preamble_start_count,
    output wire               preamble_start_valid,
    output wire [63:0]        packet_start_count,
    output wire               packet_start_valid,
    output wire               alignment_error,
    output wire               symbol_index_width_error
);

    wire fft_ce_out;
    wire [15:0] peak_magnitude_squared;
    wire [15:0] spectrum_sum;
    wire symbol_boundary;

    fft_correlator_route_top u_fft_correlator (
        .clk(clk),
        .reset(~resetn),
        .iqIn_re(iq_in_re),
        .iqIn_im(iq_in_im),
        .validIn(valid_in),
        .resetIn(reset_in),
        .resyncValid(resync_valid),
        .resyncSkip(resync_skip),
        .ce_out(fft_ce_out),
        .symbolIndex(symbol_index),
        .symbolValid(symbol_valid),
        .confidence(confidence),
        .peakMagnitudeSquared(peak_magnitude_squared),
        .spectrumSum(spectrum_sum),
        .symbolBoundary(symbol_boundary),
        .symbolSampleCount(symbol_sample_count),
        .timestampValid(timestamp_valid)
    );

    // symbol_valid is the actual transaction qualifier. Keeping the generated
    // detector enabled whenever the FFT path is enabled preserves HDL Coder's
    // state-update semantics while allowing arbitrary gaps in valid_in.
    lora_detector_timestamp_path u_detector_timestamp (
        .clk(clk),
        .resetn(resetn),
        .clk_enable(fft_ce_out),
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

endmodule
