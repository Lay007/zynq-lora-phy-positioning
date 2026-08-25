`timescale 1ns/1ps

// Capture a short sample-rate correlation-magnitude search window and emit
// the strongest interior peak together with its immediate neighbours.
//
// This block deliberately does not implement the matched filter itself. It is
// the hardware-shaped bridge between a future sample-rate correlation stream
// and the already-generated packet-rate ToA interpolator.
//
// Contract:
//   * search_start arms one SEARCH_SAMPLES-long window;
//   * search_base_count is the PL sample count of the first accepted magnitude;
//   * only magnitude_valid cycles advance the window;
//   * the first occurrence wins when equal maxima are present;
//   * an interior maximum emits before/peak/after and peak_sample_count;
//   * a maximum on either window boundary is rejected with boundary_error;
//   * a new search_start while busy/finalizing is ignored and pulses
//     restart_error.
//
// SEARCH_SAMPLES must be at least 3 and fit in the 16-bit sample index.
module lora_peak_triplet_capture #(
    parameter integer SEARCH_SAMPLES = 17
) (
    input  wire        clk,
    input  wire        resetn,

    input  wire        search_start,
    input  wire [63:0] search_base_count,
    input  wire [31:0] magnitude,
    input  wire        magnitude_valid,

    output reg  [31:0] magnitude_before,
    output reg  [31:0] magnitude_peak,
    output reg  [31:0] magnitude_after,
    output reg  [15:0] peak_index,
    output reg  [63:0] peak_sample_count,
    output reg         triplet_valid,
    output reg         busy,
    output reg         boundary_error,
    output reg         restart_error
);

    reg [15:0] sample_index;
    reg [63:0] base_count_reg;

    reg [31:0] previous_magnitude;
    reg        previous_valid;

    reg [31:0] max_magnitude;
    reg [15:0] max_index;
    reg [31:0] max_before;
    reg [31:0] max_after;
    reg        max_before_valid;
    reg        max_after_valid;

    reg finalize_pending;

    wire start_accepted = search_start && !busy && !finalize_pending;
    wire sample_accepted = magnitude_valid && (busy || start_accepted);

    always @(posedge clk) begin
        if (!resetn) begin
            sample_index       <= 16'd0;
            base_count_reg     <= 64'd0;
            previous_magnitude <= 32'd0;
            previous_valid     <= 1'b0;
            max_magnitude      <= 32'd0;
            max_index          <= 16'd0;
            max_before         <= 32'd0;
            max_after          <= 32'd0;
            max_before_valid   <= 1'b0;
            max_after_valid    <= 1'b0;
            finalize_pending   <= 1'b0;

            magnitude_before   <= 32'd0;
            magnitude_peak     <= 32'd0;
            magnitude_after    <= 32'd0;
            peak_index         <= 16'd0;
            peak_sample_count  <= 64'd0;
            triplet_valid      <= 1'b0;
            busy               <= 1'b0;
            boundary_error     <= 1'b0;
            restart_error      <= 1'b0;
        end else begin
            triplet_valid  <= 1'b0;
            boundary_error <= 1'b0;
            restart_error  <= 1'b0;

            // Finalize one clock after the last accepted sample so the stored
            // right neighbour from that final sample is already visible.
            if (finalize_pending) begin
                finalize_pending <= 1'b0;
                if (max_before_valid && max_after_valid &&
                    (max_index != 16'd0) &&
                    (max_index != SEARCH_SAMPLES-1)) begin
                    magnitude_before  <= max_before;
                    magnitude_peak    <= max_magnitude;
                    magnitude_after   <= max_after;
                    peak_index        <= max_index;
                    peak_sample_count <= base_count_reg + max_index;
                    triplet_valid     <= 1'b1;
                end else begin
                    boundary_error <= 1'b1;
                end
            end

            if (search_start && (busy || finalize_pending))
                restart_error <= 1'b1;

            if (start_accepted) begin
                busy               <= 1'b1;
                sample_index       <= 16'd0;
                base_count_reg     <= search_base_count;
                previous_magnitude <= 32'd0;
                previous_valid     <= 1'b0;
                max_magnitude      <= 32'd0;
                max_index          <= 16'd0;
                max_before         <= 32'd0;
                max_after          <= 32'd0;
                max_before_valid   <= 1'b0;
                max_after_valid    <= 1'b0;
            end

            if (sample_accepted) begin
                if ((busy ? sample_index : 16'd0) == 16'd0) begin
                    // First accepted sample establishes the initial maximum.
                    previous_magnitude <= magnitude;
                    previous_valid     <= 1'b1;
                    max_magnitude      <= magnitude;
                    max_index          <= 16'd0;
                    max_before_valid   <= 1'b0;
                    max_after_valid    <= 1'b0;
                end else begin
                    // If the current sample follows the current maximum, it is
                    // that maximum's right neighbour.
                    if ((max_index + 16'd1) == sample_index) begin
                        max_after       <= magnitude;
                        max_after_valid <= 1'b1;
                    end

                    // Strict greater-than retains the first of equal maxima.
                    if (magnitude > max_magnitude) begin
                        max_magnitude    <= magnitude;
                        max_index        <= sample_index;
                        max_before       <= previous_magnitude;
                        max_before_valid <= previous_valid;
                        max_after_valid  <= 1'b0;
                    end

                    previous_magnitude <= magnitude;
                    previous_valid     <= 1'b1;
                end

                if ((busy ? sample_index : 16'd0) == SEARCH_SAMPLES-1) begin
                    busy             <= 1'b0;
                    finalize_pending <= 1'b1;
                end else begin
                    sample_index <= (busy ? sample_index : 16'd0) + 16'd1;
                end
            end
        end
    end

endmodule
