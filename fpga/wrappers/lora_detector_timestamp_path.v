`timescale 1ns/1ps

// Compose the generated blind detector with the hand-written timestamp
// alignment primitive. The inputs are exactly the sideband outputs produced by
// the generated FFT correlator: symbolIndex/symbolValid and
// symbolSampleCount/timestampValid.
//
// The currently committed HDL Coder snapshot predates ModulePrefix and names
// the generated detector implementation `BlindDetector`. After regenerating
// with run_hdl_generation.m the same implementation is expected to be named
// `lora_blind_BlindDetector`. Define LORA_NAMESPACED_GENERATED when compiling
// those regenerated sources. No generated Verilog is edited by hand.
`ifdef LORA_NAMESPACED_GENERATED
`define LORA_BLIND_DETECTOR_MODULE lora_blind_BlindDetector
`else
`define LORA_BLIND_DETECTOR_MODULE BlindDetector
`endif

module lora_detector_timestamp_path (
    input  wire        clk,
    input  wire        resetn,
    input  wire        clk_enable,
    input  wire        reset_in,

    input  wire [31:0] symbol_index,
    input  wire        symbol_valid,
    input  wire [63:0] symbol_sample_count,
    input  wire        timestamp_valid,
    input  wire [7:0]  sync_word,

    output wire         detected,
    output wire         preamble_detected,
    output wire         sync_valid,
    output wire [15:0]  preamble_bin,
    output wire [15:0]  chips_to_boundary,
    output wire [7:0]   bins_seen,

    output wire [63:0]  preamble_start_count,
    output wire         preamble_start_valid,
    output wire [63:0]  packet_start_count,
    output wire         packet_start_valid,
    output wire         alignment_error,
    output wire         symbol_index_width_error
);

    // HDL Coder currently emits a uint32 symbolIndex for the correlator and a
    // uint16 input for the detector. LoRa SF is at most 12, so valid symbol
    // indices fit comfortably in 16 bits. Keep the truncation explicit and
    // expose an error flag rather than silently hiding an integration mistake.
    wire [15:0] detector_symbol_index = symbol_index[15:0];
    assign symbol_index_width_error = symbol_valid && (|symbol_index[31:16]);

    `LORA_BLIND_DETECTOR_MODULE u_blind_detector (
        .clk(clk),
        .reset(~resetn),
        .enb(clk_enable),
        .symbolIndex(detector_symbol_index),
        .symbolValid(symbol_valid),
        .syncWord(sync_word),
        .resetIn(reset_in),
        .detected(detected),
        .preambleDetected(preamble_detected),
        .syncValid(sync_valid),
        .preambleBin(preamble_bin),
        .chipsToBoundary(chips_to_boundary),
        .binsSeen(bins_seen)
    );

    // reset_in clears the generated detector/correlator streaming state. Clear
    // timestamp history on the same clock edge so a post-reset detector event
    // can never be paired with a pre-reset symbol timestamp.
    wire align_resetn = resetn && !reset_in;

    lora_detector_timestamp_align u_timestamp_align (
        .clk(clk),
        .resetn(align_resetn),
        .symbol_sample_count(symbol_sample_count),
        .symbol_timestamp_valid(timestamp_valid),
        .preamble_detected(preamble_detected),
        .packet_detected(detected),
        .preamble_start_count(preamble_start_count),
        .preamble_start_valid(preamble_start_valid),
        .packet_start_count(packet_start_count),
        .packet_start_valid(packet_start_valid),
        .alignment_error(alignment_error)
    );

endmodule

`undef LORA_BLIND_DETECTOR_MODULE
