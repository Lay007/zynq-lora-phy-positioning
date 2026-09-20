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
    // Correlator peak magnitude of the decision on symbol_index, in the same
    // cycle. Zero exactly when there is no signal (see the straddle guard).
    input  wire [15:0] symbol_peak,
    input  wire [7:0]  sync_word,

    output wire         detected,
    // High in the same cycle as `detected` when only the straddle-tolerant
    // path (see below) accepted the sync word, not the generated rule.
    output wire         straddle_detected,
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

    wire detected_generated;

    `LORA_BLIND_DETECTOR_MODULE u_blind_detector (
        .clk(clk),
        .reset(~resetn),
        .enb(clk_enable),
        .symbolIndex(detector_symbol_index),
        .symbolValid(symbol_valid),
        .syncWord(sync_word),
        .resetIn(reset_in),
        .detected(detected_generated),
        .preambleDetected(preamble_detected),
        .syncValid(sync_valid),
        .preambleBin(preamble_bin),
        .chipsToBoundary(chips_to_boundary),
        .binsSeen(bins_seen)
    );

    // Straddle-tolerant sync acceptance (M7).
    //
    // On the free-running symbol grid the correlator window straddles two
    // symbols. Deep inside the preamble that costs nothing, but where the
    // preamble meets the first sync symbol the window holds half of each and
    // the N-point spectrum has two comparable peaks; the peak tracker returns
    // whichever is larger. For arrivals a little past half a symbol (about
    // 9% of arrival phases, measured by replaying board IQ through this RTL
    // at every phase) it returns the preamble half: the first sync symbol
    // shows up as one extra preamble bin, and the second sync symbol is read
    // correctly. The generated detector needs preamble+8*highNibble at that
    // position and so never fires, and the packet is lost for good: the sync
    // word cannot be seen again on this grid.
    //
    // The pattern is [8 x ref][ref][ref + 8*lowNibble] instead of
    // [8 x ref][ref + 8*highNibble][ref + 8*lowNibble]. Accepting it as well,
    // with the same +/-1 bin tolerance and the same ten-symbol window, adds
    // no detection where the generated rule already fires: the two sync
    // patterns differ in the ninth symbol by 8*highNibble bins, so at most
    // one of them can match (a sync word with highNibble 0 makes them
    // identical and this path adds nothing). No generated file is edited;
    // this is combinational in the same cycle as symbol_valid, like the
    // generated detected, because lora_detector_timestamp_align requires the
    // decision on the matching timestamp cycle.
    //
    // Two guards, both found the hard way on the first board run of this
    // path (5 of its 12 rescued packets were false detections):
    //
    //  * Every decision in the window must have come from a correlator that
    //    saw a signal. In silence the correlator's spectrum is exactly zero
    //    and its argmax is bin 0, so eight "equal" bins and a ninth equal
    //    bin cost nothing, and the decision for the first, partial window of
    //    the next packet then needs only ONE coincidence (16 +/- 1 bins,
    //    about 2.3%) instead of the generated rule's two. peak, spectrum sum
    //    and confidence were all exactly 0 on every silent decision of
    //    board recordings from 25 dB to the 50 dB set, and non-zero on every
    //    decision of a real preamble or sync window, so "peak != 0" is a
    //    clean test. A false detection there arms the trace and the grid
    //    resync on the wrong instant and garbles the joint estimate.
    //  * The reference bin must lie near half a symbol (N/4 .. 3N/4). The
    //    straddle happens only when the packet's arrival is about half a
    //    symbol from the correlator window, which is what the bin measures;
    //    on the board it was 55..66 and the seven rescued packets that
    //    decoded were 58..64. Silence's bin 0 is far outside.
    localparam [15:0] BIN_MASK = 16'd127; // 2^SF - 1 for the SF7 build

    reg [15:0] prev_bin [0:8]; // [0] oldest ... [8] newest previous symbol
    reg [8:0]  prev_present;   // matching 'correlator saw a signal' bits
    reg [3:0]  prev_filled;
    integer    alt_i;
    integer    alt_j;

    wire [15:0] alt_low  = {12'd0, sync_word[3:0]};
    wire [15:0] alt_ref  = prev_bin[0];
    // N/4 .. 3N/4: the reference bin has to be near half a symbol.
    localparam [15:0] BAND_LOW  = (BIN_MASK + 16'd1) >> 2;
    localparam [15:0] BAND_HIGH = ((BIN_MASK + 16'd1) >> 2) * 16'd3;
    wire alt_ref_in_band = (alt_ref >= BAND_LOW) && (alt_ref <= BAND_HIGH);
    wire alt_signal_present = (&prev_present) && (symbol_peak != 16'd0);
    wire [15:0] alt_s2_target = (alt_ref + ((alt_low << 3) & BIN_MASK)) & BIN_MASK;

    function automatic bin_within(input [15:0] bin, input [15:0] target);
        reg [15:0] delta;
        begin
            delta = (bin - target) & BIN_MASK;
            bin_within = (delta == 16'd0) || (delta == 16'd1) ||
                         (delta == BIN_MASK);
        end
    endfunction

    reg alt_run_ok;
    always @* begin
        alt_run_ok = 1'b1;
        for (alt_i = 0; alt_i < 8; alt_i = alt_i + 1)
            alt_run_ok = alt_run_ok && bin_within(prev_bin[alt_i], alt_ref);
    end

    wire alt_step = clk_enable && symbol_valid && !reset_in;
    wire detected_straddle = alt_step && (prev_filled == 4'd9) &&
        alt_run_ok && alt_signal_present && alt_ref_in_band &&
        bin_within(prev_bin[8], alt_ref) &&
        bin_within(detector_symbol_index, alt_s2_target);

    assign detected = detected_generated || detected_straddle;
    assign straddle_detected = detected_straddle && !detected_generated;

    always @(posedge clk) begin
        if (!resetn || reset_in) begin
            prev_filled <= 4'd0;
            prev_present <= 9'd0;
            for (alt_j = 0; alt_j < 9; alt_j = alt_j + 1)
                prev_bin[alt_j] <= 16'd0;
        end else if (clk_enable && symbol_valid) begin
            for (alt_j = 0; alt_j < 8; alt_j = alt_j + 1)
                prev_bin[alt_j] <= prev_bin[alt_j + 1];
            prev_bin[8] <= detector_symbol_index;
            prev_present <= {prev_present[7:0], symbol_peak != 16'd0};
            if (prev_filled < 4'd9)
                prev_filled <= prev_filled + 4'd1;
        end
    end

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
        .packet_detected(detected),  // generated OR straddle-tolerant
        .preamble_start_count(preamble_start_count),
        .preamble_start_valid(preamble_start_valid),
        .packet_start_count(packet_start_count),
        .packet_start_valid(packet_start_valid),
        .alignment_error(alignment_error)
    );

endmodule

`undef LORA_BLIND_DETECTOR_MODULE
