`timescale 1ns/1ps

// Align the correlator symbol grid to an acquired packet.
//
// The streaming FFT frames on its own count of accepted samples, so its window
// grid sits wherever the receive stream started and stays there. The preamble
// hides that: consecutive preamble upchirps are identical, so a window
// straddling two of them is still a clean chirp and the common preamble bin
// reports the grid phase exactly. Payload symbols are all different, so a
// window that straddles two of them mixes both and the decision drifts to a
// neighbouring bin.
//
// The generated correlator realigns by withholding samples rather than by
// loading a phase, and states the policy it expects: for a preamble at bin d
// the advance that lands the grid on the preamble boundary is
// chipsToBoundary*L = mod(-d, N)*L. That is not where the payload starts. The
// SFD is 2.25 downchirps, so the payload boundary is a further quarter symbol
// on, and a quarter symbol is exactly N/4 chips. This module adds that quarter
// symbol and issues the request.
//
// The request is raised on the detector pulse, once sync has been confirmed,
// and not on the earlier preamble pulse. The generated detector checks the
// sync word against a preamble bin it captured on the old grid; moving the grid
// between the two would compare bins measured on different grids and the packet
// would never be detected at all. Waiting costs nothing: the skip is under one
// and a quarter symbols and the SFD still has 2.25 symbols to run, so the
// realignment always completes before the first payload symbol.
//
// One realignment per armed capture. A second one inside the same packet would
// move the grid straight back off the payload, and re-arming through a receive
// stream reset is the contract the rest of the capture path already uses.
module lora_symbol_grid_resync #(
    parameter integer SPREADING_FACTOR = 7,
    parameter integer SAMPLES_PER_CHIP = 8
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        stream_reset,
    input  wire        sample_valid,
    input  wire        packet_detected,
    input  wire [15:0] chips_to_boundary,

    output wire        resync_valid,
    output wire [31:0] resync_skip,
    output wire        resync_armed,
    output wire [15:0] resync_chips
);

    localparam integer SYMBOL_CHIPS = 1 << SPREADING_FACTOR;
    localparam integer QUARTER_CHIPS = SYMBOL_CHIPS / 4;
    localparam integer CHIP_MASK = SYMBOL_CHIPS - 1;

    // Plain integer constants, no part-selects: this file is compiled as
    // Verilog-2001 by the vendor flow, where selecting bits out of a parameter
    // is not legal even though the simulator accepts it in SystemVerilog mode.
    wire [15:0] advance_sum = chips_to_boundary + QUARTER_CHIPS;
    wire [15:0] payload_chips = advance_sum & CHIP_MASK;

    reg armed;
    reg request;
    reg [15:0] chips_held;
    reg [31:0] skip_held;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            armed      <= 1'b1;
            request    <= 1'b0;
            chips_held <= 16'd0;
            skip_held  <= 32'd0;
        end else if (stream_reset) begin
            armed      <= 1'b1;
            request    <= 1'b0;
            chips_held <= 16'd0;
            skip_held  <= 32'd0;
        end else if (armed && packet_detected) begin
            armed      <= 1'b0;
            request    <= 1'b1;
            chips_held <= payload_chips;
            skip_held  <= payload_chips * SAMPLES_PER_CHIP;
        end else if (request && sample_valid) begin
            // The correlator only latches a request on an accepted sample, and
            // accepted samples are rare against this clock. Hold the request
            // across exactly one of them: any longer and a second window of the
            // same packet could take it again.
            request <= 1'b0;
        end
    end

    assign resync_valid = request;
    assign resync_skip  = skip_held;
    assign resync_armed = armed;
    assign resync_chips = chips_held;

endmodule
