`timescale 1ns/1ps

// Sequence one full-resolution preamble/SFD matched-filter pair and turn the
// two integer peaks into a sample-grid correction.
//
// A timing error moves the upchirp and downchirp peaks in the same direction;
// CFO moves them in opposite directions. Therefore
//
//   timingSamples = round_away_from_zero((upOffset + downOffset) / 2).
//
// The coarse packet timestamp is the first of the eight preamble decisions
// retained by the detector's ten-symbol [8 preamble + 2 sync] window. Adding
// chips_to_boundary*L places the search on that preamble chirp. The first full
// SFD downchirp is ten symbols later.
//
// fine_skip includes FINE_GUARD_SAMPLES. The coarse grid-resync policy must
// withhold the same guard from its first skip, so both requests together equal
// the original coarse advance plus the signed joint timing correction. Keeping
// the late request non-negative matters because the generated correlator can
// advance its grid by dropping samples but cannot move it backwards.
module lora_joint_chirp_grid_controller #(
    parameter integer SAMPLES_PER_CHIP = 8,
    parameter integer SYMBOL_SAMPLES = 1024,
    parameter integer SEARCH_RADIUS = 16,
    parameter integer FINE_GUARD_SAMPLES = 16,
    parameter integer PREAMBLE_TO_SFD_SYMBOLS = 10
) (
    input  wire               clk,
    input  wire               resetn,
    input  wire               stream_reset,

    input  wire               packet_start_valid,
    input  wire [63:0]        packet_start_count,
    input  wire [15:0]        chips_to_boundary,
    input  wire [63:0]        history_next_sample_count,

    input  wire               search_busy,
    input  wire               search_failed,
    input  wire               search_triplet_valid,
    input  wire [63:0]        search_peak_sample_count,

    output reg                search_start,
    output reg  [63:0]        search_coarse_start,
    output reg                reference_down,
    output reg                busy,

    output reg  signed [31:0] timing_correction_samples,
    output reg  [31:0]        fine_skip,
    output reg                fine_resync_valid,
    output reg                timing_valid,

    output reg                restart_error,
    output reg                timing_range_error,
    // Asserted for one cycle when a search abort forced the
    // correction to be declined. Without it a trace cannot tell
    // "the estimator never ran" from "it ran and was rejected".
    output reg                search_abort_error
);

    localparam [2:0] STATE_IDLE           = 3'd0;
    localparam [2:0] STATE_LAUNCH_UP      = 3'd1;
    localparam [2:0] STATE_WAIT_UP        = 3'd2;
    localparam [2:0] STATE_WAIT_DOWN_DATA = 3'd3;
    localparam [2:0] STATE_LAUNCH_DOWN    = 3'd4;
    localparam [2:0] STATE_WAIT_DOWN      = 3'd5;

    localparam [63:0] SYMBOL_SAMPLES_U64 = SYMBOL_SAMPLES;
    localparam [63:0] SEARCH_RADIUS_U64 = SEARCH_RADIUS;
    localparam [63:0] FINE_GUARD_U64 = FINE_GUARD_SAMPLES;

    reg [2:0] state;
    reg [63:0] up_coarse_start;
    reg [63:0] down_coarse_start;
    reg signed [64:0] up_offset;

    wire [63:0] coarse_chip_advance = chips_to_boundary * SAMPLES_PER_CHIP;
    wire [63:0] down_ready_count = down_coarse_start
        + SYMBOL_SAMPLES_U64 + SEARCH_RADIUS_U64;
    wire signed [64:0] peak_signed = {1'b0, search_peak_sample_count};
    wire signed [64:0] down_coarse_signed = {1'b0, down_coarse_start};
    wire signed [64:0] down_offset_now = peak_signed - down_coarse_signed;
    wire signed [65:0] offset_sum =
        {{1{up_offset[64]}}, up_offset}
        + {{1{down_offset_now[64]}}, down_offset_now};
    wire signed [65:0] offset_sum_abs =
        offset_sum < 0 ? -offset_sum : offset_sum;
    wire signed [65:0] rounded_abs = (offset_sum_abs + 1) >>> 1;
    wire signed [65:0] rounded_timing =
        offset_sum < 0 ? -rounded_abs : rounded_abs;
    wire timing_in_range =
        (rounded_timing >= -$signed(FINE_GUARD_U64))
        && (rounded_timing <= $signed(FINE_GUARD_U64));
    wire signed [65:0] guarded_skip =
        $signed({2'b00, FINE_GUARD_U64}) + rounded_timing;

    initial begin
        if (SAMPLES_PER_CHIP < 1)
            $error("SAMPLES_PER_CHIP must be positive");
        if (SYMBOL_SAMPLES < 2)
            $error("SYMBOL_SAMPLES must be at least two");
        if (SEARCH_RADIUS < 1)
            $error("SEARCH_RADIUS must be positive");
        if (FINE_GUARD_SAMPLES < SEARCH_RADIUS)
            $error("FINE_GUARD_SAMPLES must cover SEARCH_RADIUS");
    end

    always @(posedge clk) begin
        if (!resetn || stream_reset) begin
            state                     <= STATE_IDLE;
            up_coarse_start           <= 64'd0;
            down_coarse_start         <= 64'd0;
            up_offset                 <= 65'sd0;
            search_start              <= 1'b0;
            search_coarse_start       <= 64'd0;
            reference_down            <= 1'b0;
            busy                      <= 1'b0;
            timing_correction_samples <= 32'sd0;
            fine_skip                 <= 32'd0;
            fine_resync_valid         <= 1'b0;
            timing_valid              <= 1'b0;
            restart_error             <= 1'b0;
            timing_range_error        <= 1'b0;
            search_abort_error        <= 1'b0;
        end else begin
            search_start       <= 1'b0;
            fine_resync_valid  <= 1'b0;
            timing_valid       <= 1'b0;
            restart_error      <= 1'b0;
            timing_range_error <= 1'b0;
            search_abort_error <= 1'b0;

            if (packet_start_valid && busy)
                restart_error <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (packet_start_valid) begin
                        up_coarse_start <= packet_start_count + coarse_chip_advance;
                        down_coarse_start <= packet_start_count
                            + coarse_chip_advance
                            + PREAMBLE_TO_SFD_SYMBOLS * SYMBOL_SAMPLES_U64;
                        search_coarse_start <= packet_start_count
                            + coarse_chip_advance;
                        reference_down <= 1'b0;
                        busy <= 1'b1;
                        state <= STATE_LAUNCH_UP;
                    end
                end

                STATE_LAUNCH_UP: begin
                    if (!search_busy) begin
                        search_start <= 1'b1;
                        state <= STATE_WAIT_UP;
                    end
                end

                STATE_WAIT_UP: begin
                    if (search_failed) begin
                        // Withholding the guard is unconditional, so returning
                        // it must be too. Abandoning the request here leaves
                        // the grid permanently FINE_GUARD_SAMPLES short, which
                        // is strictly worse than never attempting the
                        // correction. Give the guard back with a zero
                        // correction and degrade to the coarse-only grid.
                        fine_skip <= FINE_GUARD_U64[31:0];
                        fine_resync_valid <= 1'b1;
                        search_abort_error <= 1'b1;
                        busy <= 1'b0;
                        state <= STATE_IDLE;
                    end else if (search_triplet_valid) begin
                        up_offset <= peak_signed - $signed({1'b0, up_coarse_start});
                        state <= STATE_WAIT_DOWN_DATA;
                    end
                end

                STATE_WAIT_DOWN_DATA: begin
                    if (history_next_sample_count >= down_ready_count) begin
                        search_coarse_start <= down_coarse_start;
                        reference_down <= 1'b1;
                        state <= STATE_LAUNCH_DOWN;
                    end
                end

                STATE_LAUNCH_DOWN: begin
                    if (!search_busy) begin
                        search_start <= 1'b1;
                        state <= STATE_WAIT_DOWN;
                    end
                end

                STATE_WAIT_DOWN: begin
                    if (search_failed) begin
                        fine_skip <= FINE_GUARD_U64[31:0];
                        fine_resync_valid <= 1'b1;
                        search_abort_error <= 1'b1;
                        busy <= 1'b0;
                        state <= STATE_IDLE;
                    end else if (search_triplet_valid) begin
                        timing_correction_samples <= rounded_timing[31:0];
                        timing_valid <= 1'b1;
                        busy <= 1'b0;
                        state <= STATE_IDLE;
                        if (timing_in_range) begin
                            fine_skip <= guarded_skip[31:0];
                            fine_resync_valid <= 1'b1;
                        end else begin
                            // Same rule for a rejected out-of-range estimate:
                            // decline the correction, but still hand back the
                            // guard the coarse resync withheld.
                            fine_skip <= FINE_GUARD_U64[31:0];
                            fine_resync_valid <= 1'b1;
                            timing_range_error <= 1'b1;
                        end
                    end
                end

                default: begin
                    busy <= 1'b0;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
